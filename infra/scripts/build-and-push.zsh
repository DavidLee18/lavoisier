#!/usr/bin/env zsh
# Build the arm64 `lavoisier` image with nerdctl and push it to the stack's ECR repo.
# (§9 M10 / §10: arm64, colima + nerdctl, not Docker.)
#
# Prereqs: the ECR repo exists (terraform apply -target=aws_ecr_repository.app), a running
# colima VM (`colima start --arch aarch64`) with nerdctl, + AWS CLI configured for us-west-2.
#
# Usage: ./infra/scripts/build-and-push.zsh [tag]   # tag defaults to "dev"
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
REPO_NAME="${REPO_NAME:-lavoisier}"
TAG="${1:-dev}"

ROOT="${0:A:h}/../.."

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${REPO_NAME}:${TAG}"

print "Building ${IMAGE} (linux/arm64)…"
nerdctl build --platform linux/arm64 -f "${ROOT}/Containerfile" -t "${IMAGE}" "${ROOT}"

print "Logging in to ECR ${REGISTRY}…"
aws ecr get-login-password --region "${REGION}" \
  | nerdctl login --username AWS --password-stdin "${REGISTRY}"

print "Pushing ${IMAGE}…"
nerdctl push "${IMAGE}"
print "Done: ${IMAGE}"
