# Osirus AI on Google Cloud (Terraform)

This directory is the Google Cloud equivalent of `devops/cloudformation`.

It maps the current AWS stack to GCP as follows:

- CloudFormation -> Terraform
- ECS/Fargate (app/api) -> Cloud Run services
- ECS task for migrations -> Cloud Run Job
- RDS MySQL -> Cloud SQL for MySQL
- ElastiCache Redis -> Memorystore for Redis
- S3 assets bucket -> Cloud Storage bucket (public object read)
- ALB + path routing -> Global External HTTP(S) Load Balancer with URL map
- CloudFront `/ms-content/*` origin -> Backend bucket path route with optional Cloud CDN
- OpenSearch domain -> external OpenSearch endpoint (Elastic/OpenSearch on GCP)

## What this stack creates

In `standalone` mode:

- VPC + subnet + private service networking
- Serverless VPC Access connector
- Cloud SQL MySQL instance, DB, and DB user
- Memorystore Redis instance
- Public Cloud Storage assets bucket
- Cloud Run `app` service
- Cloud Run `api` service with `searxng` sidecar
- Cloud Run `api-migrations` job
- Global load balancer with routes:
  - `/api/*` -> API Cloud Run service
  - `/ms-content/*` -> assets bucket
  - default (`/`) -> app Cloud Run service
- Optional managed TLS certificate when `domain_name` is set
- OpenSearch endpoint wiring through env vars (`OPENSEARCH_*`) only; no first-party OpenSearch cluster is created

In `aws_attached` mode:

- VPC + subnet + Serverless VPC Access connector
- Cloud Run `app` service
- Cloud Run `api` service with `searxng` sidecar
- Cloud Run `api-migrations` job
- Global load balancer + optional managed TLS certificate
- Runtime is configured to use AWS RDS/Redis/S3/OpenSearch endpoints

## Prerequisites

- Terraform >= 1.5
- `gcloud` authenticated for the target project
- Container images already built and available (Docker Hub public images or Artifact Registry paths)

## Deploy

Two deployment modes are supported:

- `standalone` (default): full GCP stack (Cloud SQL + Memorystore + GCS + Cloud Run + LB)
- `aws_attached`: GCP Cloud Run/LB attached to AWS primary data services (RDS/Redis/S3/OpenSearch)

1. Copy example variables:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Edit `terraform.tfvars` and set at least:

- `project_id`
- `app_container_image`
- `api_container_image`
- `migration_container_image`
- `database_password`
- `opensearch_node_url` or `opensearch_host`/`opensearch_port`
- Optional: `provider_domain_map` for domain-based provider filtering (for example `gemini.example.com:google,bedrock.example.com:aws`)
- Optional (private Docker Hub): `dockerhub_use_remote_repository`, `dockerhub_remote_repository_id`, `dockerhub_username`, `dockerhub_password_secret_id`, `dockerhub_password_secret_version`
- Optional (restricted IAM environments):
  - `manage_project_services=false` (skip Service Usage API management in Terraform)
  - `runtime_service_account_email=<existing-sa@project.iam.gserviceaccount.com>`
  - `manage_runtime_service_account_roles=false` (if role grants are managed by admins outside Terraform)
  - `cloud_run_deletion_protection=false` for easy test cleanup (`true` to protect Cloud Run service/job deletes)

3. Apply:

```bash
terraform init
terraform plan
terraform apply
```

Or use the helper script:

```bash
# Standalone GCP
./deploy.sh --mode standalone --var-file terraform.tfvars

# Attach GCP runtime to an existing AWS CloudFormation stack
./deploy.sh --mode aws_attached --var-file terraform.tfvars --aws-stack-name <aws-stack-name> --aws-region <aws-region>

# Optional domain-based provider filtering
./deploy.sh --mode standalone --var-file terraform.tfvars --provider-domain-map "gemini.example.com:google,bedrock.example.com:aws"
```

From repo root, use the unified deploy wrapper:

```bash
# Standalone GCP
devops/bin/deploy.sh --target gcp --gcp-mode standalone --gcp-var-file terraform.tfvars

# AWS-attached GCP
devops/bin/deploy.sh --target gcp --gcp-mode aws_attached --aws-stack-name <aws-stack-name> --aws-region <aws-region> --gcp-var-file terraform.tfvars

# Optional domain-based provider filtering
devops/bin/deploy.sh --target gcp --gcp-mode standalone --gcp-var-file terraform.tfvars --provider-domain-map "gemini.example.com:google,bedrock.example.com:aws"
```

From repo root, prefer `gcp.sh` for GCP workflows (`cmd.sh gcp-*` remains a passthrough):

```bash
# Optional once-per-project/stack IAM bootstrap (grants deploy + runtime roles)
./gcp.sh bootstrap-role osirus-ai

# 1) Auth + validate launch tfvars file
./gcp.sh init

# 2) Plan/apply standalone
./gcp.sh plan standalone
./gcp.sh up standalone
./gcp.sh down standalone
# fallback manual cleanup for orphaned resources
./gcp.sh clean osirus-ai us-east1 osirus-ai

# 3) Run DB migrations
./gcp.sh migrations
```

`gcp.sh plan/up/down` passes both:
- `terraform.tfvars`
- `terraform.launch.tfvars` (git-excluded launch config, applied last to override base defaults)

`gcp.sh init` does not write tfvars from `.env`. Keep launch/runtime values in `terraform.launch.tfvars` (git-excluded), and keep Docker Hub secret references there.

AWS-attached mode via `gcp.sh`:

```bash
AWS_STACK_NAME=<aws-stack-name> AWS_REGION=<aws-region> ./gcp.sh plan aws_attached
AWS_STACK_NAME=<aws-stack-name> AWS_REGION=<aws-region> ./gcp.sh up aws_attached
AWS_STACK_NAME=<aws-stack-name> AWS_REGION=<aws-region> ./gcp.sh down aws_attached
```

Use `CFT_AWS_PROFILE` (or `AWS_PROFILE`) for CloudFormation output lookup in aws_attached mode.

## Update Existing Stack (Recommended)

Use this flow when you changed config/image/env and want to roll the update:

```bash
# repo root
./gcp.sh init
./gcp.sh plan standalone
./gcp.sh up standalone
```

AWS-attached update:

```bash
AWS_STACK_NAME=<aws-stack-name> AWS_REGION=<aws-region> ./gcp.sh plan aws_attached
AWS_STACK_NAME=<aws-stack-name> AWS_REGION=<aws-region> ./gcp.sh up aws_attached
```

Cleanup/rollback after failed tests:

```bash
./gcp.sh down standalone
```

Notes:
- `gcp.sh` uses your active `gcloud` account by default (no browser ADC flow in Terraform). Set `GCP_USE_SERVICE_ACCOUNT_AUTH=true` to auto-activate `GOOGLE_SERVICE_ACCOUNT` from `.env`.
- `gcp.sh plan/up/down` apply both var files: `terraform.tfvars` and `terraform.launch.tfvars` (or `GCP_TFVARS_LAUNCH_FILE`).
- `gcp.sh down` performs a best-effort `gcloud run ... --no-deletion-protection` for `app`, `api`, and `api-migrations` before Terraform destroy.
- `gcp.sh down` also performs a best-effort `gcloud sql instances patch --no-deletion-protection` for `<stack>-db` before Terraform destroy.
- `gcp.sh down` now also runs a targeted Terraform apply on `google_sql_database_instance.db[0]` with `deletion_protection=false` before full destroy.
- `gcp.sh` no longer auto-creates Docker Hub secrets by default; use pre-created Secret Manager IDs in `terraform.launch.tfvars`.
- Set `GCP_USE_SERVICE_ACCOUNT_AUTH=false` explicitly if you want to enforce user-token auth in scripts/environment where the variable may already be set.

You can also run the bootstrap script directly:

```bash
devops/gcp/terraform/bootstrap-iam.sh \
  --project-id <project-id> \
  --stack-name <stack-name> \
  --deployer-member serviceAccount:<deployer-sa@project.iam.gserviceaccount.com>
```

Optional automation:
- Set `GCP_BOOTSTRAP_IAM_ON_INIT=true` to run IAM bootstrap automatically during `./gcp.sh init`.
- Control bootstrap behavior with:
  - `GCP_DEPLOYER_MEMBER`
  - `GCP_RUNTIME_SERVICE_ACCOUNT_EMAIL`
  - `GCP_BOOTSTRAP_USE_SERVICE_ACCOUNT` (default `false`; uses active `gcloud` account unless set `true`)
  - `GCP_BOOTSTRAP_ENABLE_APIS`
  - `GCP_BOOTSTRAP_GRANT_DEPLOYER_ROLES`
  - `GCP_BOOTSTRAP_GRANT_RUNTIME_ROLES`
  - `GCP_BOOTSTRAP_CREATE_RUNTIME_SA`

`gcp-bootstrap-role` now also creates the Artifact Registry service identity (one-time) so Docker Hub remote repository secret IAM binding can succeed.

4. Run migrations after apply:

```bash
gcloud run jobs execute <stack-name>-api-migrations --region <region> --project <project-id> --wait
```

## Docker Hub images (public vs private)

- This stack now defaults to Docker Hub images:
  - `docker.io/mediacoin/osirus-ai:latest`
  - `docker.io/mediacoin/osirus-ai-api:latest`
  - `docker.io/mediacoin/osirus-ai-api-migrations:latest`
- Public Docker Hub images can be used directly as `app_container_image`, `api_container_image`, and `migration_container_image`.
- For private Docker Hub repos, Terraform can create an Artifact Registry remote repository and wire it automatically.

Private Docker Hub setup:

```bash
# 1) Create Docker Hub PAT secret (one-time)
echo -n '<dockerhub_pat>' | gcloud secrets create dockerhub-pat --data-file=- --replication-policy=automatic

# 2) Set terraform.tfvars values
# dockerhub_use_remote_repository = true
# dockerhub_remote_repository_id  = "dockerhub-remote"
# dockerhub_username              = "<dockerhub_username>"
# dockerhub_password_secret_id    = "projects/<project-id>/secrets/dockerhub-pat"
# dockerhub_password_secret_version = "projects/<project-id>/secrets/dockerhub-pat/versions/1"
```

When `dockerhub_use_remote_repository=true`:
- Terraform grants Artifact Registry service agent access to your secret.
- Terraform creates the remote repository (`DOCKER_HUB` upstream).
- Terraform rewrites `app_container_image`, `api_container_image`, and `migration_container_image` to the remote path automatically.

Optional Docker Hub secret management via env (disabled by default):
- Username: `DOCKERHUB_USERNAME` (aliases: `DOCKER_HUB_USERNAME`, `DOCKERHUB_USER`)
- Password/PAT: `DOCKERHUB_PASSWORD` (aliases: `DOCKER_HUB_PASSWORD`, `DOCKERHUB_TOKEN`, `DOCKERHUB_PAT`)
- Enable explicit management:
  - `GCP_MANAGE_DOCKERHUB_SECRET=true`
- Optional pre-created secret mode (without creation):
  - `DOCKERHUB_USE_REMOTE_REPOSITORY=true`
  - `DOCKERHUB_PASSWORD_SECRET_ID=projects/<project>/secrets/<secret>`
  - `DOCKERHUB_PASSWORD_SECRET_VERSION=projects/<project>/secrets/<secret>/versions/<n>`

Use `terraform.launch.tfvars` for test sizing overrides (memory/tiers/deletion protection) and secrets.

Troubleshooting image pull errors:
- If Cloud Run shows `Image 'mirror.gcr.io/... not found'`, your image is either private or missing at that tag.
- For private repos, set Docker Hub credentials and rerun:
  - `./gcp.sh init`
  - `./gcp.sh up standalone`
- Preferred for clean commits: pre-create secret(s) once and reference them in `terraform.launch.tfvars` instead of passing PATs in env.
- If Terraform fails with `gcp-sa-artifactregistry ... does not exist`, rerun `./gcp.sh init` using a project-admin account. The script now ensures the Artifact Registry service agent exists before apply.
- On older gcloud versions, service identity creation is under beta:
  - `gcloud beta services identity create --service=artifactregistry.googleapis.com --project <project-id>`
- If you previously ran `terraform plan -out=tfplan`, do not reuse that old plan after changing launch settings. Run `./gcp.sh up ...` to generate a fresh plan and apply.

## Test Sizing

`terraform.tfvars` now uses a small test profile by default:

- `instance_count = 0` (scale-to-zero baseline)
- `app_service_memory = "512Mi"`
- `api_service_memory = "512Mi"`
- `searxng_sidecar_memory = "512Mi"`
- `database_tier = "db-custom-1-3840"`
- `database_disk_size_gb = 10`
- `redis_memory_size_gb = 1`
- `deletion_protection = false` (faster teardown in test environments)

Increase these for production capacity and safety.

## DNS and HTTPS

- If `domain_name` is empty, the stack serves traffic on HTTP using the load balancer IP output.
- If `domain_name` is set, the stack creates a managed certificate and HTTPS load balancer.
- Point your DNS A record to `load_balancer_ip` output.
- Managed certificate provisioning can take several minutes after DNS propagates.

## Notes

- OpenSearch is not a first-party managed GCP service in this stack; pass an external endpoint.
- In `aws_attached` mode, Terraform skips Cloud SQL, Memorystore, and GCS bucket creation and uses AWS endpoints instead.
- `database_password` and API keys are Terraform variables and can appear in state; use secured state storage and access controls.
- For production, consider moving sensitive values to Secret Manager and injecting them as secret refs in Cloud Run.
- If you see `AUTH_PERMISSION_DENIED` for `google_project_service.required`, either grant Service Usage permissions or set `manage_project_services=false` and have an admin pre-enable APIs.
