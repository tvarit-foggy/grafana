#!/usr/bin/env bash
#test commit
set -e

PREFIX=$1
if [ -z "${PREFIX}" ]; then
    echo "Usage .github/tvarit/deploy_to_dev_sk.sh <PREFIX>"
    exit 1
fi

validate_lightsail_instance() {
    instance_name="$1"

    # Get the instance information
    instance_info=$(aws lightsail get-instance --instance-name "$instance_name" 2>/dev/null)

    local exit_code=$?
    echo $exit_code

}

delete_lightsail_instance() {
  instance_name="$1"

  aws lightsail delete-instance --instance-name $instance_name

}

function add_instance_to_load_balancer() {
    local instance_name="$1"
    local load_balancer_name="$2"

    aws lightsail attach-instances-to-load-balancer --load-balancer-name "$2" --instance-names "$1"

}

function check_load_balancer_existence() {
    local load_balancer_name="$1"
    
    aws lightsail get-load-balancer --load-balancer-name "$load_balancer_name" >/dev/null 2>&1

    local exit_code=$?
    echo $exit_code

}

function create_load_balancer() {
    local load_balancer_name="$1"
    local instance_port="$2"
    
    #aws lightsail create-load-balancer-tls-certificate --load-balancer-name "$load_balancer_name" >/dev/null 2>&1
    
    aws lightsail create-load-balancer \
        --load-balancer-name "$load_balancer_name" \
        --instance-port "$instance_port"
    
}

# aws lightsail get-certificates --certificate-name ${PREFIX}-tvarit-com > /dev/null

echo "Creating production database..."
aws lightsail create-relational-database \
  --relational-database-name ${PREFIX}-grafana-db \
  --availability-zone ${AWS_DEFAULT_REGION}a \
  --relational-database-blueprint-id mysql_8_0 \
  --relational-database-bundle-id micro_1_0 \
  --preferred-backup-window 00:00-00:30 \
  --preferred-maintenance-window Sun:01:00-Sun:01:30 \
  --master-database-name grafana \
  --master-username grafana \
  --no-publicly-accessible || :

echo "Waiting for database to be available..."
for run in {1..60}; do
  state=$(aws lightsail get-relational-database --relational-database-name ${PREFIX}-grafana-db --output text --query 'relationalDatabase.state')
  if [ "${state}" == "available" ]; then
    break
  fi
  echo "Waiting for database to be available..."
  sleep 60
done

if [ "${state}" != "available" ]; then
  echo "Database not created in 60 mins"
  exit 1
fi

echo "Creating staging database..."
aws lightsail create-relational-database-from-snapshot \
  --relational-database-name ${PREFIX}-next-grafana-db \
  --source-relational-database-name ${PREFIX}-grafana-db \
  --use-latest-restorable-time || :

echo "Waiting for database to be available..."
for run in {1..60}; do
  state=$(aws lightsail get-relational-database --relational-database-name ${PREFIX}-next-grafana-db --output text --query 'relationalDatabase.state')
  if [ "${state}" == "available" ]; then
    break
  fi
  echo "Waiting for database to be available..."
  sleep 60
done

if [ "${state}" != "available" ]; then
  echo "Database not created in 60 mins"
  exit 1
fi

DB_ENDPOINT=$(aws lightsail get-relational-database --relational-database-name ${PREFIX}-next-grafana-db --output text --query 'relationalDatabase.masterEndpoint.address')
DB_PASSWORD=$(aws lightsail get-relational-database-master-user-password --relational-database-name ${PREFIX}-next-grafana-db --output text --query masterUserPassword)
SIGNING_SECRET=$(aws secretsmanager get-secret-value --secret-id grafana-signing-secret --output text --query SecretString)

#AWS-016
AWS_ACCESS_KEY=$(aws secretsmanager get-secret-value --secret-id /credentials/grafana-user/access-key --output text --query SecretString)
AWS_SECRET_KEY=$(aws secretsmanager get-secret-value --secret-id /credentials/grafana-user/secret-key --output text --query SecretString)

echo "Building docker image..."
docker build --tag grafana/grafana:next-${PREFIX} .

cd .github/tvarit/conf/prod/
echo "Downloading plugins..."
rm -rf plugins
aws s3 sync s3://com.tvarit.grafana.artifacts/grafana-plugins plugins
find plugins/ -type f -name *.tar.gz -exec bash -c 'cd $(dirname $1) && tar -xf $(basename $1) && rm $(basename $1); cd -' bash {} \;

echo "Finalising docker image..."
cp grafana.ini.template grafana.ini
sed -i "s#<DOMAIN/>#${PREFIX}.tvarit.com#g" grafana.ini
sed -i "s#<ROOT_URL/>#https://${PREFIX}.tvarit.com/#g" grafana.ini
sed -i "s#<SIGNING_SECRET/>#${SIGNING_SECRET}#g" grafana.ini
sed -i "s#<DB_ENDPOINT/>#${DB_ENDPOINT}#g" grafana.ini
sed -i "s#<DB_PASSWORD/>#$(echo ${DB_PASSWORD} | sed 's/#/\\#/g' | sed 's/&/\\&/g')#g" grafana.ini
sed -i "s#<OAUTH_CLIENT_ID/>#${OAUTH_CLIENT_ID}#g" grafana.ini
sed -i "s#<OAUTH_CLIENT_SECRET/>#${OAUTH_CLIENT_SECRET}#g" grafana.ini
sed -i "s#<SMTP_HOST/>#${SMTP_HOST}#g" grafana.ini
sed -i "s#<SMTP_USER/>#${SMTP_USER}#g" grafana.ini
sed -i "s#<SMTP_PASSWORD/>#${SMTP_PASSWORD}#g" grafana.ini
sed -i "s#<SMTP_FROM/>#[BETA] Tvarit AI Platform#g" grafana.ini

cp cloudwatch.json.template cloudwatch.json
sed -i "s#<DOMAIN/>#next-${PREFIX}.tvarit.com#g" cloudwatch.json

cp Dockerfile.template Dockerfile
sed -i "s#<BASE_IMAGE/>#grafana/grafana:next-${PREFIX}#g" Dockerfile
sed -i "s#<AWS_ACCESS_KEY/>#${AWS_ACCESS_KEY}#g" Dockerfile
sed -i "s#<AWS_SECRET_KEY/>#${AWS_SECRET_KEY}#g" Dockerfile
sed -i "s#<AWS_REGION/>#${AWS_DEFAULT_REGION}#g" Dockerfile
docker build --tag grafana/grafana:next-${PREFIX} .

#push Docker image to ECR
echo "push docker image to ECR........."
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin 250373516626.dkr.ecr.eu-central-1.amazonaws.com
docker tag grafana/grafana:next-${PREFIX} 250373516626.dkr.ecr.eu-central-1.amazonaws.com/lightsailinstance:latest
docker push 250373516626.dkr.ecr.eu-central-1.amazonaws.com/lightsailinstance:latest

instance_name=grafana-${PREFIX}
static_ip_name=grafana-ip-${PREFIX}

return_value_instance=$(validate_lightsail_instance $instance_name)

if [ $return_value_instance -eq 0 ]; then
    echo "instance already exist"
    echo "deleting existing lightsail instance"
    delete_lightsail_instance $instance_name
fi

echo "Creating lightsail instance!!!!!!"
cp lightsail.sh userdata.sh
sed -i "s#<AWS_ACCESS_KEY/>#${AWS_ACCESS_KEY}#g" userdata.sh
sed -i "s#<AWS_SECRET_KEY/>#${AWS_SECRET_KEY}#g" userdata.sh

aws lightsail create-instances --instance-names grafana-${PREFIX} --availability-zone eu-central-1a --blueprint-id ubuntu_22_04 --bundle-id nano_2_0 --user-data file://userdata.sh
echo "waiting for user data to be executed in the instance"
sleep 300

#check if load balancer exist
return_value=$(check_load_balancer_existence "grafana-lb")
echo $return_value
  if [[ $return_value -eq 0 ]]; then
    echo "load balancer exist"
  else
    echo "creating Load Balancer"
    create_load_balancer "grafana-lb" 80
  fi

echo "waiting for server to up and running!!!!!!!!!!!"
sleep 180
echo "adding instance to load balancer"
add_instance_to_load_balancer grafana-${PREFIX} grafana-lb

aws lightsail open-instance-public-ports --port-info fromPort=3000,toPort=3000,protocol=TCP --instance-name grafana-${PREFIX}

echo "waiting for instance to be attach with load balancer"
sleep 120
