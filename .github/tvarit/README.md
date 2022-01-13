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
2. staging
  * Add required reviewers
  * Allow deployment only on `main` branch
  * Add following secrets
    * AWS_ACCESS_KEY_ID
    * AWS_SECRET_ACCESS_KEY
    * SMTP_HOST
    * SMTP_PASSWORD
    * SMTP_USER
3. production
  * Add required reviewers
  * Allow deployment only on `main` branch
  * Add following secrets
    * AWS_ACCESS_KEY_ID
    * AWS_SECRET_ACCESS_KEY
    * SMTP_HOST
    * SMTP_PASSWORD
    * SMTP_USER

#### Create Github Runner

Host a runner and customize the environment used to run jobs in GitHub Actions workflows. [Learn more]https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners).

1. Add Github Actions runner with name self-hosted
2. Install AWS CLIv2 and LightsailCtl on the runner

### Process Flow


#### On commit to a PR to main

```
See .github/workflows/pr-deploy.yml
```

1. Setup AWS prerequisites (TODO)
2. Run tests
3. Approve deploy to development
4. Deploy to development

#### On close PR to main

```
See .github/workflows/pr-commands-close.yml
```

1. Approve tear down development deployment
2. Tear down development deployment

#### On push to main

```
See .github/workflows/deploy.yml
```

1. Setup AWS prerequisites (TODO)
2. Run tests
3. Approve deploy to staging
4. Deploy to staging
5. Approve deploy to production
6. Deploy to production
