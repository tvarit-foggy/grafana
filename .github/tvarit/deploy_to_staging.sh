#!/usr/bin/env bash

set -e

PREFIX=$1
if [ -z "${PREFIX}" ]; then
    echo "Usage .github/tvarit/deploy_to_staging.sh <PREFIX>"
    exit 1
fi

aws lightsail get-certificates --certificate-name ${PREFIX}-tvarit-com > /dev/null

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
AWS_ACCESS_KEY=$(aws secretsmanager get-secret-value --secret-id /credentials/grafana-user/access-key --output text --query SecretString)
AWS_SECRET_KEY=$(aws secretsmanager get-secret-value --secret-id /credentials/grafana-user/secret-key --output text --query SecretString)

echo "Create Lightsail container service if not exists..."
(aws lightsail create-container-service \
  --service-name  "${PREFIX}-next-grafana" \
  --power nano \
  --scale 1 \
  --region "${AWS_DEFAULT_REGION}" \
  --public-domain-names ${PREFIX}-tvarit-com=next-${PREFIX}.tvarit.com \
  --environmentVariables tls_version=1.2,tls_reject_versions=1.0 && sleep 10) || :

echo "Building docker image..."
docker build --tag grafana/grafana:next-${PREFIX} .

cd .github/tvarit/conf/prod/
echo "Downloading plugins..."
rm -rf plugins
aws s3 sync s3://com.tvarit.grafana.artifacts/grafana-plugins plugins
find plugins/ -type f -name *.tar.gz -exec bash -c 'cd $(dirname $1) && tar -xf $(basename $1) && rm $(basename $1); cd -' bash {} \;

echo "Finalising docker image..."
cp grafana.ini.template grafana.ini
sed -i "s#<DOMAIN/>#next-${PREFIX}.tvarit.com#g" grafana.ini
sed -i "s#<ROOT_URL/>#https://next-${PREFIX}.tvarit.com/#g" grafana.ini
sed -i "s#<SIGNING_SECRET/>#${SIGNING_SECRET}#g" grafana.ini
sed -i "s#<DB_ENDPOINT/>#${DB_ENDPOINT}#g" grafana.ini
sed -i "s#<DB_PASSWORD/>#$(echo ${DB_PASSWORD} | sed 's/#/\\#/g' | sed 's/&/\\&/g')#g" grafana.ini
sed -i "s#<OAUTH_CLIENT_ID/>#${OAUTH_CLIENT_ID}#g" grafana.ini
sed -i "s#<OAUTH_CLIENT_SECRET/>#${OAUTH_CLIENT_SECRET}#g" grafana.ini
sed -i "s#<SMTP_HOST/>#${SMTP_HOST}#g" grafana.ini
sed -i "s#<SMTP_USER/>#${SMTP_USER}#g" grafana.ini
sed -i "s#<SMTP_PASSWORD/>#${SMTP_PASSWORD}#g" grafana.ini
sed -i "s#<SMTP_FROM/>#[BETA] Tvarit AI Platform#g" grafana.ini

if [ "${PREFIX}" == "maxion" ]; then
sed -i "s#<AD_LOGIN_FLAG/>#true#g" grafana.ini
sed -i "s#<MAXION_CLIENT_ID/>#${MAXION_CLIENT_ID}#g" grafana.ini
sed -i "s#<MAXION_CLIENT_SECRET/>#${MAXION_CLIENT_SECRET}#g" grafana.ini
else
sed -i "s#<AD_LOGIN_FLAG>#false#g" grafana.ini
fi

echo "${MAXION_CLIENT_ID}"
cat "grafana.ini"

cp cloudwatch.json.template cloudwatch.json
sed -i "s#<DOMAIN/>#next-${PREFIX}.tvarit.com#g" cloudwatch.json

cp Dockerfile.template Dockerfile
sed -i "s#<BASE_IMAGE/>#grafana/grafana:next-${PREFIX}#g" Dockerfile
sed -i "s#<AWS_ACCESS_KEY/>#${AWS_ACCESS_KEY}#g" Dockerfile
sed -i "s#<AWS_SECRET_KEY/>#${AWS_SECRET_KEY}#g" Dockerfile
sed -i "s#<AWS_REGION/>#${AWS_DEFAULT_REGION}#g" Dockerfile
docker build --tag grafana/grafana:next-${PREFIX} .
sleep 300
echo "Upload docker image to lightsail container service and get image etag..."
IMAGE=$(aws lightsail push-container-image \
  --service-name  "${PREFIX}-next-grafana" \
  --label "${PREFIX}-next-grafana" \
  --image "grafana/grafana:next-${PREFIX}" \
  --region "${AWS_DEFAULT_REGION}" | grep "Refer to this image as")
IMAGE=${IMAGE:24:-17}

echo "Create Lightsail container service deployment..."
cp lightsail.json.template lightsail.json
sed -i "s#<PREFIX/>#${PREFIX}-next#g" lightsail.json
sed -i "s#<IMAGE/>#${IMAGE}#g" lightsail.json
aws lightsail create-container-service-deployment --cli-input-json file://lightsail.json
