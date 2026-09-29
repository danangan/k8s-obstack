#!/usr/bin/env bash
# Build the sample app, push it to ECR and deploy it. Run deploy.sh first: it points kubectl
# at the cluster.

set -euo pipefail

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

REGION="us-east-1"
REPOSITORY="sample-app"
PLATFORM="linux/amd64,linux/arm64"
APP_DIR="$(dirname "$0")/../sample-app"
CONTAINER_CLI="$(command -v docker || command -v podman)"

REGISTRY="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com"
IMAGE_REPOSITORY="${REGISTRY}/${REPOSITORY}"
TAG="$(date +%Y%m%d%H%M%S)"

aws ecr describe-repositories --repository-names "$REPOSITORY" --region "$REGION" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name "$REPOSITORY" --region "$REGION" >/dev/null
aws ecr get-login-password --region "$REGION" \
  | "$CONTAINER_CLI" login --username AWS --password-stdin "$REGISTRY"

# A multi-platform image is a manifest list, which Docker and Podman build and push differently.
log "Building and pushing ${IMAGE_REPOSITORY}:${TAG} (${PLATFORM})..."
if [[ "$CONTAINER_CLI" == *podman ]]; then
  podman build --platform "$PLATFORM" --manifest "${IMAGE_REPOSITORY}:${TAG}" "$APP_DIR"
  podman manifest push --all "${IMAGE_REPOSITORY}:${TAG}"
else
  docker buildx build --platform "$PLATFORM" -t "${IMAGE_REPOSITORY}:${TAG}" --push "$APP_DIR"
fi

log "Deploying sample-app..."
helm upgrade --install sample-app "${APP_DIR}/k8s" \
  --set image.repository="$IMAGE_REPOSITORY" \
  --set image.tag="$TAG" \
  --set image.pullPolicy=IfNotPresent \
  --set ingress.enabled=false \
  --wait --timeout 5m

kubectl get pods -l app=sample-app
log "Done!"
