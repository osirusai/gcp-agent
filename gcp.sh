#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
MODE="${GCP_MODE:-standalone}"
VAR_FILE="${GCP_VAR_FILE:-${TF_DIR}/terraform.tfvars}"
LAUNCH_VAR_FILE="${GCP_LAUNCH_VAR_FILE:-${TF_DIR}/terraform.launch.tfvars}"

usage() {
  cat <<'USAGE'
Usage: ./gcp.sh <command> [mode]

Commands:
  init [mode]          terraform init + validate
  plan [mode]          terraform plan
  up [mode]            terraform apply
  down [mode]          terraform destroy
  bootstrap-role       run terraform/bootstrap-iam.sh
  migrations           run Cloud Run migrations job

Modes:
  standalone (default)
  aws_attached

Environment:
  GCP_MODE             default mode override
  GCP_VAR_FILE         base tfvars path (default: terraform/terraform.tfvars)
  GCP_LAUNCH_VAR_FILE  launch override tfvars (default: terraform/terraform.launch.tfvars)
  GOOGLE_PROJECT_ID    required for migrations/bootstrap-role
  REGION               Cloud Run/Job region (default: us-central1)
  STACK_NAME           stack prefix (default: osirus-ai)
  AWS_STACK_NAME       required for aws_attached mode
  AWS_REGION           default us-east-1 for aws_attached output lookup
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

tf_common_args() {
  local mode="$1"
  local args=("-var=deployment_mode=${mode}")
  [[ -f "$VAR_FILE" ]] && args+=("-var-file=${VAR_FILE}")
  [[ -f "$LAUNCH_VAR_FILE" ]] && args+=("-var-file=${LAUNCH_VAR_FILE}")
  echo "${args[*]}"
}

attach_aws_args() {
  local aws_stack="${AWS_STACK_NAME:-}"
  local aws_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
  if [[ -z "$aws_stack" ]]; then
    echo "AWS_STACK_NAME is required for aws_attached mode" >&2
    exit 1
  fi

  local profile_args=()
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    profile_args=(--profile "$AWS_PROFILE")
  elif [[ -n "${AWS_DEFAULT_PROFILE:-}" ]]; then
    profile_args=(--profile "$AWS_DEFAULT_PROFILE")
  fi

  cf_out() {
    aws "${profile_args[@]}" --region "$aws_region" cloudformation describe-stacks \
      --stack-name "$aws_stack" \
      --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" \
      --output text
  }

  echo "-var=aws_database_host=$(cf_out DatabaseHost)"
  echo "-var=aws_database_name=$(cf_out DatabaseName)"
  echo "-var=aws_database_port=$(cf_out DatabasePort)"
  echo "-var=aws_database_username=$(cf_out DatabaseUsername)"
  echo "-var=aws_redis_host=$(cf_out RedisHost)"
  echo "-var=aws_redis_port=$(cf_out RedisPort)"
  echo "-var=aws_assets_bucket_name=$(cf_out AssetsBucketName)"
  echo "-var=opensearch_host=$(cf_out OpenSearchHost)"
  echo "-var=opensearch_port=$(cf_out OpenSearchPort)"
  echo "-var=opensearch_protocol=https"
}

run_tf() {
  local subcmd="$1"
  local mode="$2"
  require_cmd terraform
  cd "$TF_DIR"
  terraform init -input=false >/dev/null

  local args=()
  read -r -a args <<< "$(tf_common_args "$mode")"

  if [[ "$mode" == "aws_attached" ]]; then
    require_cmd aws
    mapfile -t aws_args < <(attach_aws_args)
    args+=("${aws_args[@]}")
  fi

  case "$subcmd" in
    plan) terraform plan "${args[@]}" ;;
    apply) terraform apply -auto-approve "${args[@]}" ;;
    destroy) terraform destroy -auto-approve "${args[@]}" ;;
    *) echo "Unknown terraform subcmd: $subcmd" >&2; exit 1 ;;
  esac
}

bootstrap_role() {
  require_cmd gcloud
  local project_id="${GOOGLE_PROJECT_ID:-}"
  if [[ -z "$project_id" ]]; then
    echo "Set GOOGLE_PROJECT_ID first." >&2
    exit 1
  fi
  local stack_name="${STACK_NAME:-osirus-ai}"
  "${TF_DIR}/bootstrap-iam.sh" --project-id "$project_id" --stack-name "$stack_name"
}

migrations() {
  require_cmd gcloud
  local project_id="${GOOGLE_PROJECT_ID:-}"
  local region="${REGION:-us-central1}"
  local stack_name="${STACK_NAME:-osirus-ai}"
  if [[ -z "$project_id" ]]; then
    echo "Set GOOGLE_PROJECT_ID first." >&2
    exit 1
  fi
  gcloud run jobs execute "${stack_name}-api-migrations" --region "$region" --project "$project_id" --wait
}

cmd="${1:-help}"
mode="${2:-$MODE}"

case "$cmd" in
  init)
    require_cmd terraform
    cd "$TF_DIR"
    terraform init
    terraform validate
    ;;
  plan) run_tf plan "$mode" ;;
  up) run_tf apply "$mode" ;;
  down) run_tf destroy "$mode" ;;
  bootstrap-role) bootstrap_role ;;
  migrations) migrations ;;
  help|-h|--help|"") usage ;;
  *) echo "Unknown command: $cmd" >&2; usage; exit 1 ;;
esac
