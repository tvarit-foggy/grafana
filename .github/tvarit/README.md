# Setup CI/CD for Grafana

## Prerequisites

### Configure GitHub

#### Configure Github Environment

Configure 3 environments with protection rules and secrets. [Learn more](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment).

1. development
  * Add required reviewers
  * Add following secrets
    * AWS_ACCESS_KEY_ID
    * AWS_SECRET_ACCESS_KEY
    * SMTP_HOST
    * SMTP_PASSWORD
    * SMTP_USER
    * OAUTH_CLIENT_ID
    * OAUTH_CLIENT_SECRET
2. staging
  * Add required reviewers
  * Allow deployment only on `main` branch
  * Add following secrets
    * AWS_ACCESS_KEY_ID
    * AWS_SECRET_ACCESS_KEY
    * SMTP_HOST
    * SMTP_PASSWORD
    * SMTP_USER
    * OAUTH_CLIENT_ID
    * OAUTH_CLIENT_SECRET
3. production
  * Add required reviewers
  * Allow deployment only on `main` branch
  * Add following secrets
    * AWS_ACCESS_KEY_ID
    * AWS_SECRET_ACCESS_KEY
    * SMTP_HOST
    * SMTP_PASSWORD
    * SMTP_USER
    * OAUTH_CLIENT_ID
    * OAUTH_CLIENT_SECRET

#### Create Github Runner

Host a runner and customize the environment used to run jobs in GitHub Actions workflows. [Learn more]https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners).

1. Add Github Actions runner with name self-hosted
2. Install AWS CLIv2 and LightsailCtl on the runner

### Configure AWS

1. Create certificate on AWS for *.tvarit.com in us-east-1
2. Create SES identity for tvarit.com and no-reply@tvarit.com in eu-central-1
3. Update the ARNs in main-stack.yaml
4. Run `bash prerequisites.sh`

## Process Flow

### On commit to a PR to main

```
See .github/workflows/pr-deploy.yml
```

1. Run tests
2. Approve deploy to development
3. Deploy to development

### On close PR to main

```
See .github/workflows/pr-commands-close.yml
```

1. Approve tear down development deployment
2. Tear down development deployment

### On push to main

```
See .github/workflows/deploy.yml
```

1. Run tests
2. Approve deploy to staging
3. Deploy to staging
4. Approve deploy to production
5. Deploy to production
