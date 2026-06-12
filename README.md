# Osirus AI GCP DevOps

Terraform-based GCP deployment package for Osirus AI services.

## Architecture

This stack deploys a production-style, serverless-first GCP architecture:

1. Global HTTP(S) load balancing routes traffic to Cloud Run services (`app` and `api`).
2. The API runs on Cloud Run with a `searxng` sidecar.
3. Data plane services:
   - Cloud SQL (MySQL)
   - Memorystore (Redis)
   - Cloud Storage assets bucket
4. Optional domain + managed certificate for HTTPS.
5. Cloud Run Job executes database migrations.
6. Secret Manager + IAM secure runtime secrets and access.

`aws_attached` mode is also supported. In that mode, Cloud Run and the load balancer stay on GCP while data service endpoints come from AWS stack outputs.

## Architecture Diagram

```text
Custom Domain (osirus.ai)
        |
        v
Global External HTTP(S) Load Balancer
        |
        +------------------------------+
        |                              |
        v                              v
Cloud Run: app                    Cloud Run: api (+ searxng sidecar)
                                         |
                                         +--> Secret Manager (runtime/API keys)
                                         +--> Cloud SQL (MySQL)
                                         +--> Memorystore (Redis)
                                         +--> Cloud Storage (assets)
                                         +--> OpenSearch endpoint (configured)

Ops path:
- Cloud Run Job: <stack>-api-migrations -> Cloud SQL
- IAM roles/policies control service-to-service access
- Cloud Logging/Monitoring via Cloud Run + GCP platform services
```

## API Connectivity

In `standalone` mode, `osirus.ai` traffic reaches the GCP load balancer and is routed to the `api` Cloud Run service. The API then connects to Cloud SQL, Memorystore, Cloud Storage, and the configured OpenSearch endpoint using runtime environment values and secrets.

In `aws_attached` mode, routing and runtime remain on GCP. `gcp.sh` resolves AWS CloudFormation outputs and injects those endpoints into Terraform variables, so the same API container connects to AWS-hosted DB, Redis, S3, and OpenSearch services instead of GCP-managed equivalents.

## Repo Layout

- `terraform/` Terraform modules, providers, and example variables
- `gcp.sh` wrapper for init, plan, apply, destroy, bootstrap, and migration workflows

## Prerequisites

- Google Cloud project with billing enabled
- `gcloud` CLI authenticated for the target project
- Terraform installed locally

## Quickstart

1. Create local tfvars from examples:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp terraform/terraform.launch.tfvars.example terraform/terraform.launch.tfvars
```

2. Edit local tfvars with your project, image, and secret values.

3. Run the standalone deploy workflow:

```bash
./gcp.sh init
./gcp.sh plan standalone
./gcp.sh up standalone
```

## AWS-Attached Mode

Use this mode when Cloud Run should stay on GCP but the data plane should use an existing AWS stack.

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
- Remove temporary CI or code-review test files before opening production PRs.

## LLM Request Flow Diagram (Vertex Search + Vertex AI)

```text
User UI
  |
  | 1) Prompt / task request
  v
Osirus API (Cloud Run)
  |
  | 2) Prefetch context (RAG/search grounding)
  v
Vertex AI Search (Vertex Search)
  |
  | 3) Ranked docs/snippets returned
  v
Osirus API (context assembly + prompt building)
  |
  | 4) Model invocation
  v
Vertex AI Model Endpoint
  |\
  | \-- Gemini (text/multimodal)
  | \-- Nano Banana (configured model route)
  |
  | 5) Model output
  v
Osirus API (post-processing, policy/formatting)
  |
  | 6) API response / stream
  v
User UI
```

Notes:
- The API orchestrates both retrieval (Vertex Search) and generation (Vertex AI).
- Provider/model choice is controlled by API routing/config (for example Gemini vs Nano Banana).
- The same response path returns to the UI regardless of chosen model.
