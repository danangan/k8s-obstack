#!/usr/bin/env bash
# Build the sample app image inside minikube and deploy it with its Helm chart.
# Env overrides: MINIKUBE_PROFILE

set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

PROFILE="${MINIKUBE_PROFILE:-minikube}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The script lives in the sample app directory.
APP_DIR="${SCRIPT_DIR}"

log "Building container image..."
# Building via minikube would make the image instantly accessible from within the cluster
minikube image build -t sample-app:latest -p "$PROFILE" "$APP_DIR"

log "Deploying application to k8s cluster via helm..."
helm upgrade --install sample-app "${APP_DIR}/k8s"

# The tag is always :latest, so helm sees no spec change; restart to pick up the new image.
log "Restarting pods to pick up the new image..."
kubectl rollout restart deployment/sample-app
kubectl rollout status deployment/sample-app --timeout=3m

log "Done!"
