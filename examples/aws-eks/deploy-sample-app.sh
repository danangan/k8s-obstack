#!/usr/bin/env bash
# Build the sample app, push it to ECR and deploy it. Run deploy.sh first: it points kubectl
# at the cluster.

set -euo pipefail

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

REGION="us-east-1"
REPOSITORY="sample-app"
# The cluster's nodes are Graviton (arm64).
PLATFORM="linux/arm64"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../local-dev/sample-app" && pwd)"
CONTAINER_CLI="$(command -v docker || command -v podman)"

REGISTRY="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com"
IMAGE_REPOSITORY="${REGISTRY}/${REPOSITORY}"
# A new tag per build, so helm rolls out the new image.
TAG="$(date +%Y%m%d%H%M%S)"

log "Building ${IMAGE_REPOSITORY}:${TAG}..."
"$CONTAINER_CLI" build --platform "$PLATFORM" -t "${IMAGE_REPOSITORY}:${TAG}" "$APP_DIR"

log "Pushing to ECR..."
aws ecr describe-repositories --repository-names "$REPOSITORY" --region "$REGION" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name "$REPOSITORY" --region "$REGION" >/dev/null
aws ecr get-login-password --region "$REGION" \
  | "$CONTAINER_CLI" login --username AWS --password-stdin "$REGISTRY"
"$CONTAINER_CLI" push "${IMAGE_REPOSITORY}:${TAG}"

log "Deploying sample-app..."
helm upgrade --install sample-app "${APP_DIR}/k8s" \
  --set image.repository="$IMAGE_REPOSITORY" \
  --set image.tag="$TAG" \
  --set image.pullPolicy=IfNotPresent \
  --set ingress.enabled=false \
  --wait --timeout 5m

kubectl get pods -l app=sample-app
log "Done!"
