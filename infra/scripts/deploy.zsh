#!/usr/bin/env zsh
# Apply the Terraform gateway stack and roll the ECS service to pick up a re-pushed image.
# Usage: ./infra/scripts/deploy.zsh
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
NAME="${NAME:-lavoisier}"
TF_DIR="${0:A:h}/../terraform"

terraform -chdir="${TF_DIR}" init -input=false
terraform -chdir="${TF_DIR}" apply -input=false

# Force a fresh deployment so a re-pushed :tag is pulled (no-op on the first apply).
aws ecs update-service \
  --cluster "${NAME}" --service "${NAME}" \
  --force-new-deployment --region "${REGION}" >/dev/null

print "Deployed. ALB: http://$(terraform -chdir="${TF_DIR}" output -raw alb_dns_name)"
