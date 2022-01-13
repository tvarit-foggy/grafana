#!/usr/bin/env bash

# Create S3 bucket for plugins
# Create service user for grafana deployment (TODO)
# Create service user for landing zone access (TODO)
# Create certificate for hosting (TODO)

set -e

aws cloudformation deploy \
  --stack-name grafana-stack \
  --template-file main-stack.yaml \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --no-fail-on-empty-changeset \
  --tags Key=Environment,Value=prod \
    Key=Owner,Value=kamal.galrani \
    Key=Developer,Value=mayank.pathela \
    Key=Service,Value=grafana
