#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GOOGLE_PROJECT_ID:-}"
STACK_NAME="${GCP_STACK_NAME:-osirus-ai}"
DEPLOYER_MEMBER="${GCP_DEPLOYER_MEMBER:-}"
RUNTIME_SERVICE_ACCOUNT_EMAIL="${GCP_RUNTIME_SERVICE_ACCOUNT_EMAIL:-}"
ENABLE_APIS="true"
GRANT_DEPLOYER_ROLES="true"
GRANT_RUNTIME_ROLES="true"
CREATE_RUNTIME_SA="true"

usage() {
  cat <<'EOF'
Usage: bootstrap-iam.sh [options]

Options:
  --project-id <id>                    GCP project id (required)
  --stack-name <name>                  Stack name used for runtime SA default (default: osirus-ai)
  --deployer-member <member>           IAM member to grant deployer roles (user:... or serviceAccount:...)
  --runtime-service-account <email>    Runtime service account email to use/grant
  --skip-enable-apis                   Do not enable required project APIs
  --skip-deployer-roles                Do not grant deployer roles
  --skip-runtime-roles                 Do not grant runtime roles
  --skip-runtime-sa-create             Do not create runtime SA when it does not exist
  --help                               Show this help
EOF
}

normalize_bool() {
  local value
  value="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on) echo "true" ;;
    0|false|no|off) echo "false" ;;
    *) echo "false" ;;
  esac
}

detect_active_member() {
  local account
  account="$(gcloud config get-value account 2>/dev/null || true)"
  account="$(printf '%s' "$account" | tr -d '\r' | xargs)"
  if [[ -z "$account" || "$account" == "(unset)" ]]; then
    echo ""
    return 0
  fi

  if [[ "$account" == *".gserviceaccount.com" ]]; then
    echo "serviceAccount:${account}"
  else
    echo "user:${account}"
  fi
}

normalize_member() {
  local member="${1:-}"
  if [[ "$member" == *":"* ]]; then
    echo "$member"
  elif [[ "$member" == *".gserviceaccount.com" ]]; then
    echo "serviceAccount:${member}"
  else
    echo "user:${member}"
  fi
}

runtime_sa_account_id_from_stack() {
  local stack="$1"
  local normalized
  normalized="$(printf '%s' "$stack" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ -z "$normalized" ]]; then
    normalized="osirus-ai"
  fi
  normalized="${normalized}-runtime"
  printf '%s' "${normalized:0:30}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --stack-name)
      STACK_NAME="$2"
      shift 2
      ;;
    --deployer-member)
      DEPLOYER_MEMBER="$2"
      shift 2
      ;;
    --runtime-service-account)
      RUNTIME_SERVICE_ACCOUNT_EMAIL="$2"
      shift 2
      ;;
    --skip-enable-apis)
      ENABLE_APIS="false"
      shift
      ;;
    --skip-deployer-roles)
      GRANT_DEPLOYER_ROLES="false"
      shift
      ;;
    --skip-runtime-roles)
      GRANT_RUNTIME_ROLES="false"
      shift
      ;;
    --skip-runtime-sa-create)
      CREATE_RUNTIME_SA="false"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ID" ]]; then
  echo "--project-id is required (or set GOOGLE_PROJECT_ID)." >&2
  exit 1
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "Missing required command: gcloud" >&2
  exit 1
fi

if [[ -z "$DEPLOYER_MEMBER" ]]; then
  DEPLOYER_MEMBER="$(detect_active_member)"
fi
if [[ -n "$DEPLOYER_MEMBER" ]]; then
  DEPLOYER_MEMBER="$(normalize_member "$DEPLOYER_MEMBER")"
fi

if [[ -z "$RUNTIME_SERVICE_ACCOUNT_EMAIL" ]]; then
  RUNTIME_ACCOUNT_ID="$(runtime_sa_account_id_from_stack "$STACK_NAME")"
  RUNTIME_SERVICE_ACCOUNT_EMAIL="${RUNTIME_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
else
  RUNTIME_ACCOUNT_ID="${RUNTIME_SERVICE_ACCOUNT_EMAIL%@*}"
fi

APIS=(
  compute.googleapis.com
  run.googleapis.com
  sqladmin.googleapis.com
  redis.googleapis.com
  vpcaccess.googleapis.com
  servicenetworking.googleapis.com
  storage.googleapis.com
  iam.googleapis.com
  artifactregistry.googleapis.com
  secretmanager.googleapis.com
)

DEPLOYER_ROLES=(
  roles/serviceusage.serviceUsageAdmin
  roles/compute.admin
  roles/compute.loadBalancerAdmin
  roles/servicenetworking.networksAdmin
  roles/run.admin
  roles/vpcaccess.admin
  roles/cloudsql.admin
  roles/redis.admin
  roles/storage.admin
  roles/secretmanager.admin
  roles/artifactregistry.admin
  roles/iam.serviceAccountAdmin
  roles/iam.serviceAccountUser
  roles/resourcemanager.projectIamAdmin
)

RUNTIME_ROLES=(
  roles/cloudsql.client
  roles/storage.objectAdmin
  roles/logging.logWriter
  roles/monitoring.metricWriter
)

echo "Project: ${PROJECT_ID}"
echo "Stack: ${STACK_NAME}"
echo "Deployer member: ${DEPLOYER_MEMBER:-<none>}"
echo "Runtime SA: ${RUNTIME_SERVICE_ACCOUNT_EMAIL}"

if [[ "$(normalize_bool "$ENABLE_APIS")" == "true" ]]; then
  echo "Enabling required APIs..."
  gcloud services enable "${APIS[@]}" --project "$PROJECT_ID"

  echo "Ensuring Artifact Registry service identity..."
  gcloud services identity create \
    --service=artifactregistry.googleapis.com \
    --project "$PROJECT_ID" >/dev/null 2>&1 \
    || gcloud beta services identity create \
      --service=artifactregistry.googleapis.com \
      --project "$PROJECT_ID" >/dev/null
fi

if [[ "$(normalize_bool "$CREATE_RUNTIME_SA")" == "true" ]]; then
  if ! gcloud iam service-accounts describe "$RUNTIME_SERVICE_ACCOUNT_EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
    echo "Creating runtime service account ${RUNTIME_ACCOUNT_ID}..."
    gcloud iam service-accounts create "$RUNTIME_ACCOUNT_ID" \
      --project "$PROJECT_ID" \
      --display-name "${STACK_NAME} runtime"
  else
    echo "Runtime service account already exists."
  fi
fi

if [[ "$(normalize_bool "$GRANT_DEPLOYER_ROLES")" == "true" ]]; then
  if [[ -z "$DEPLOYER_MEMBER" ]]; then
    echo "No deployer member provided and no active gcloud account detected." >&2
    exit 1
  fi
  echo "Granting deployer roles to ${DEPLOYER_MEMBER}..."
  for role in "${DEPLOYER_ROLES[@]}"; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member "$DEPLOYER_MEMBER" \
      --role "$role" >/dev/null
  done
fi

if [[ "$(normalize_bool "$GRANT_RUNTIME_ROLES")" == "true" ]]; then
  echo "Granting runtime roles to serviceAccount:${RUNTIME_SERVICE_ACCOUNT_EMAIL}..."
  for role in "${RUNTIME_ROLES[@]}"; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member "serviceAccount:${RUNTIME_SERVICE_ACCOUNT_EMAIL}" \
      --role "$role" >/dev/null
  done
fi

echo "IAM bootstrap complete."
echo "RUNTIME_SERVICE_ACCOUNT_EMAIL=${RUNTIME_SERVICE_ACCOUNT_EMAIL}"
echo "Recommended Terraform flags:"
echo "  manage_project_services = false"
echo "  runtime_service_account_email = \"${RUNTIME_SERVICE_ACCOUNT_EMAIL}\""
echo "  manage_runtime_service_account_roles = false"
