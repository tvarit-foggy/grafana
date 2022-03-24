#!/usr/bin/env bash

set -e

echo "Deleting staging deployment..."
aws lightsail delete-container-service --service-name stage-grafana || :
aws lightsail delete-relational-database --relational-database-name stage-grafana-db --skip-final-snapshot || :
