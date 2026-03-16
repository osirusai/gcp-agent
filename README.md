# Osirus AI GCP DevOps

Terraform-based GCP deployment package for Osirus AI.

## Architecture

This stack deploys a production-style, serverless-first GCP architecture:

1. Global HTTP(S) load balancing routes traffic to Cloud Run services (`app`, `api`).
2. API runs with a sidecar (`searxng`) on Cloud Run.
3. Data plane services:
- Cloud SQL (MySQL)
- Memorystore (Redis)
- Cloud Storage assets bucket
4. Optional domain + managed certificate for HTTPS.
5. Cloud Run Job executes database migrations.
6. Secret Manager + IAM secure runtime secrets and access.

`aws_attached` mode is also supported, where Cloud Run/LB stays on GCP while data services come from AWS stack outputs.

## Repo Layout

- `terraform/` Terraform modules, providers, and examples
- `gcp.sh` clean wrapper for init/plan/apply/destroy/bootstrap/migrations

## Quickstart

1. Create local tfvars from examples:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp terraform/terraform.launch.tfvars.example terraform/terraform.launch.tfvars
```

2. Edit local tfvars with your project/images/secrets.

3. Run deploy workflow:

```bash
./gcp.sh init
./gcp.sh plan standalone
./gcp.sh up standalone
```

## AWS-Attached Mode

```bash
AWS_STACK_NAME=<aws-stack-name> AWS_REGION=us-east-1 ./gcp.sh plan aws_attached
AWS_STACK_NAME=<aws-stack-name> AWS_REGION=us-east-1 ./gcp.sh up aws_attached
```

## IAM Bootstrap and Migrations

```bash
GOOGLE_PROJECT_ID=<project-id> STACK_NAME=osirus-ai ./gcp.sh bootstrap-role
GOOGLE_PROJECT_ID=<project-id> REGION=us-central1 STACK_NAME=osirus-ai ./gcp.sh migrations
```

## Security

- Keep `terraform/*.tfvars` local and untracked.
- Never commit real API keys, tokens, or service account secrets.
