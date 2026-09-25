#!/usr/bin/env bash

set -euo pipefail

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

CLUSTER="platform-cluster"
REGION="us-east-1"
HELM_RELEASE="obstack"
HELM_RELEASE_NAMESPACE="default"
K8S_NAMESPACE="obstack"
CHART="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log "Checking access to EKS cluster ${CLUSTER} (${REGION})..."
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl get nodes

log "Deploying ${HELM_RELEASE}"
helm upgrade --install "$HELM_RELEASE" "$CHART" \
  --namespace "$HELM_RELEASE_NAMESPACE" \
  --values "${CHART}/examples/aws-eks/values.yaml" \
  --wait --timeout 10m

kubectl get pods -n "$K8S_NAMESPACE"

log "Done!"
