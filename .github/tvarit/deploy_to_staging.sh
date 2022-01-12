#!/usr/bin/env bash

set -e

echo "Creating production database..."
aws lightsail create-relational-database \
  --relational-database-name grafana-db \
  --availability-zone eu-central-1a \
  --relational-database-blueprint-id mysql_8_0 \
  --relational-database-bundle-id micro_1_0 \
  --preferred-backup-window 00:00-00:30 \
  --preferred-maintenance-window Sun:01:00-Sun:01:30 \
  --master-database-name grafana \
  --master-username grafana \
  --no-publicly-accessible || :

echo "Waiting for database to be available..."
for run in {1..60}; do
  state=$(aws lightsail get-relational-database --relational-database-name grafana-db --output text --query 'relationalDatabase.state')
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
  --relational-database-name stage-grafana-db \
  --source-relational-database-name grafana-db \
  --use-latest-restorable-time || :

echo "Waiting for database to be available..."
for run in {1..60}; do
  state=$(aws lightsail get-relational-database --relational-database-name stage-grafana-db --output text --query 'relationalDatabase.state')
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

DB_ENDPOINT=$(aws lightsail get-relational-database --relational-database-name stage-grafana-db --output text --query 'relationalDatabase.masterEndpoint.address')
DB_PASSWORD=$(aws lightsail get-relational-database-master-user-password --relational-database-name stage-grafana-db --output text --query masterUserPassword)

echo "Create Lightsail container service if not exists..."
(aws lightsail create-container-service \
  --service-name  "stage-grafana" \
  --power nano \
  --scale 1 \
  --region "${AWS_DEFAULT_REGION}" \
  --public-domain-names cloud-tvarit-com=next-cloud.tvarit.com && sleep 10) || :

echo "Building docker image..."
docker build --tag grafana/grafana:next .

cd .github/tvarit/conf/prod/
cp grafana.ini.template grafana.ini
sed -i "s#<DOMAIN/>#next-cloud.tvarit.com#g" grafana.ini
sed -i "s#<ROOT_URL/>#https://next-cloud.tvarit.com/#g" grafana.ini
sed -i "s#<SIGNING_SECRET/>#$(aws secretsmanager get-random-password --exclude-characters ';#' --output text)#g" grafana.ini
sed -i "s#<DB_ENDPOINT/>#${DB_ENDPOINT}#g" grafana.ini
sed -i "s#<DB_PASSWORD/>#$(echo ${DB_PASSWORD} | sed 's/#/\\#/g')#g" grafana.ini
sed -i "s#<SMTP_HOST/>#${SMTP_HOST}#g" grafana.ini
sed -i "s#<SMTP_USER/>#${SMTP_USER}#g" grafana.ini
sed -i "s#<SMTP_PASSWORD/>#${SMTP_PASSWORD}#g" grafana.ini
sed -i "s#<SMTP_FROM/>#[BETA] Tvarit AI Platform#g" grafana.ini

cp Dockerfile.template Dockerfile
sed -i "s#<BASE_IMAGE/>#grafana/grafana:next#g" Dockerfile
docker build --tag grafana/grafana:next .

echo "Upload docker image to lightsail container service and get image etag..."
IMAGE=$(aws lightsail push-container-image \
  --service-name  "stage-grafana" \
  --label "stage-grafana" \
  --image "grafana/grafana:next" \
  --region "${AWS_DEFAULT_REGION}" | grep "Refer to this image as")
IMAGE=${IMAGE:24:-17}

echo "Create Lightsail container service deployment..."
cp lightsail.json.template lightsail.json
sed -i "s#<PREFIX/>#stage#g" lightsail.json
sed -i "s#<IMAGE/>#${IMAGE}#g" lightsail.json
aws lightsail create-container-service-deployment --cli-input-json file://lightsail.json
