#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="${DEPLOYMENT_MODE:-standalone}"
VAR_FILES=()
PLAN_ONLY="${PLAN_ONLY:-false}"
AUTO_APPROVE="${AUTO_APPROVE:-true}"
AWS_STACK_NAME="${AWS_STACK_NAME:-}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
AWS_PROFILE_VALUE="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-}}"
PROVIDER_DOMAIN_MAP="${PROVIDER_DOMAIN_MAP:-}"

usage() {
  cat <<'EOF'
Usage: deploy.sh [options]

Options:
  --mode <standalone|aws_attached>   Deployment mode (default: standalone)
  --var-file <path>                  Terraform var-file (repeatable; default: terraform.tfvars)
  --plan-only                        Run init+plan only
  --no-auto-approve                  Require interactive approval on apply
  --aws-stack-name <name>            AWS CloudFormation stack name (required for aws_attached)
  --aws-region <region>              AWS region for CloudFormation output lookup
  --aws-profile <profile>            AWS CLI profile for CloudFormation output lookup
  --provider-domain-map <mapping>    Host->provider mapping (e.g. gemini.example.com:google,bedrock.example.com:aws)
  --help                             Show this message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --var-file)
      VAR_FILES+=("$2")
      shift 2
      ;;
    --plan-only)
      PLAN_ONLY="true"
      shift
      ;;
    --no-auto-approve)
      AUTO_APPROVE="false"
      shift
      ;;
    --aws-stack-name)
      AWS_STACK_NAME="$2"
      shift 2
      ;;
    --aws-region)
      AWS_REGION="$2"
      shift 2
      ;;
    --aws-profile)
      AWS_PROFILE_VALUE="$2"
      shift 2
      ;;
    --provider-domain-map)
      PROVIDER_DOMAIN_MAP="$2"
      shift 2
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

if [[ "$MODE" != "standalone" && "$MODE" != "aws_attached" ]]; then
  echo "Invalid --mode '$MODE'. Use standalone or aws_attached." >&2
  exit 1
fi

TF_ARGS=(-var "deployment_mode=${MODE}")
if [[ ${#VAR_FILES[@]} -eq 0 ]]; then
  VAR_FILES=("${TF_VAR_FILE:-terraform.tfvars}")
fi

# Drop duplicates while preserving first-seen order of explicit args.
dedup=()
seen=""
for vf in "${VAR_FILES[@]}"; do
  if [[ ",$seen," != *",$vf,"* ]]; then
    dedup+=("$vf")
    seen+="${seen:+,}$vf"
  fi
done
VAR_FILES=("${dedup[@]}")
for vf in "${VAR_FILES[@]}"; do
  [[ -n "$vf" ]] && TF_ARGS+=(-var-file="$vf")
done
if [[ -n "${PROVIDER_DOMAIN_MAP}" ]]; then
  TF_ARGS+=(-var "provider_domain_map=${PROVIDER_DOMAIN_MAP}")
fi

if [[ "$MODE" == "aws_attached" ]]; then
  if [[ -z "$AWS_STACK_NAME" ]]; then
    echo "--aws-stack-name is required when --mode aws_attached" >&2
    exit 1
  fi

  AWS_CMD=(aws --region "$AWS_REGION")
  if [[ -n "$AWS_PROFILE_VALUE" ]]; then
    AWS_CMD+=(--profile "$AWS_PROFILE_VALUE")
  fi

  cf_output() {
    local key="$1"
    "${AWS_CMD[@]}" cloudformation describe-stacks \
      --stack-name "$AWS_STACK_NAME" \
      --query "Stacks[0].Outputs[?OutputKey=='${key}'].OutputValue | [0]" \
      --output text
  }

  require_output() {
    local key="$1"
    local value
    value="$(cf_output "$key")"
    if [[ -z "$value" || "$value" == "None" || "$value" == "null" ]]; then
      echo "Missing CloudFormation output '${key}' on stack '${AWS_STACK_NAME}'" >&2
      exit 1
    fi
    echo "$value"
  }

  DB_HOST="$(require_output "DatabaseHost")"
  DB_NAME="$(require_output "DatabaseName")"
  DB_PORT="$(require_output "DatabasePort")"
  DB_USER="$(require_output "DatabaseUsername")"
  REDIS_HOST="$(require_output "RedisHost")"
  REDIS_PORT="$(require_output "RedisPort")"
  ASSETS_BUCKET="$(require_output "AssetsBucketName")"
  OPENSEARCH_HOST="$(require_output "OpenSearchHost")"
  OPENSEARCH_PORT="$(require_output "OpenSearchPort")"

  TF_ARGS+=(
    -var "aws_database_host=${DB_HOST}"
    -var "aws_database_name=${DB_NAME}"
    -var "aws_database_port=${DB_PORT}"
    -var "aws_database_username=${DB_USER}"
    -var "aws_redis_host=${REDIS_HOST}"
    -var "aws_redis_port=${REDIS_PORT}"
    -var "aws_assets_bucket_name=${ASSETS_BUCKET}"
    -var "opensearch_host=${OPENSEARCH_HOST}"
    -var "opensearch_port=${OPENSEARCH_PORT}"
    -var "opensearch_protocol=https"
  )

  echo "AWS attachment mode enabled using stack: ${AWS_STACK_NAME} (${AWS_REGION})"
fi

cd "$SCRIPT_DIR"

terraform init
terraform plan "${TF_ARGS[@]}" -out=tfplan

if [[ "$PLAN_ONLY" == "true" ]]; then
  echo "Plan-only mode complete."
  exit 0
fi

if [[ "$AUTO_APPROVE" == "true" ]]; then
  terraform apply -auto-approve tfplan
else
  terraform apply tfplan
fi
