#!/usr/bin/env bash

set -e

echo "Create Lightsail container service if not exists..."
(aws lightsail create-container-service --service-name  "dev-grafana-${PR_NUMBER}" --power nano --scale 1 --region "${AWS_DEFAULT_REGION}" && sleep 10) || :
ROOT_URL=$(aws lightsail get-container-services --service-name  "dev-grafana-${PR_NUMBER}" --output text --query "containerServices[0].url")

echo "Building docker image..."
docker build --tag grafana/grafana:${PR_NUMBER} .

cd .github/tvarit/conf/dev/
cp grafana.ini.template grafana.ini
sed -i "s#<ROOT_URL/>#${ROOT_URL}#g" grafana.ini
sed -i "s#<SMTP_HOST/>#${SMTP_HOST}#g" grafana.ini
sed -i "s#<SMTP_USER/>#${SMTP_USER}#g" grafana.ini
sed -i "s#<SMTP_PASSWORD/>#${SMTP_PASSWORD}#g" grafana.ini
sed -i "s#<SMTP_FROM/>#[dev-${PR_NUMBER}] Tvarit AI Platform#g" grafana.ini

cp Dockerfile.template Dockerfile
sed -i "s#<BASE_IMAGE/>#grafana/grafana:${PR_NUMBER}#g" Dockerfile
docker build --tag grafana/grafana:${PR_NUMBER} .

echo "Upload docker image to lightsail container service and get image etag..."
IMAGE=$(aws lightsail push-container-image \
  --service-name  "dev-grafana-${PR_NUMBER}" \
  --label "dev-grafana-${PR_NUMBER}" \
  --image "grafana/grafana:${PR_NUMBER}" \
  --region "${AWS_DEFAULT_REGION}" | grep "Refer to this image as")
IMAGE=${IMAGE:24:-17}

echo "Create Lightsail container service deployment..."
cp lightsail.json.template lightsail.json
sed -i "s#<PR_NUMBER/>#${PR_NUMBER}#g" lightsail.json
sed -i "s#<IMAGE/>#${IMAGE}#g" lightsail.json
aws lightsail create-container-service-deployment --cli-input-json file://lightsail.json