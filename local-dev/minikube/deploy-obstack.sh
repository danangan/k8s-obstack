#!/usr/bin/env bash

set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$1" >&2; exit 1; }

RELEASE="obstack"
# The chart creates the `obstack` namespace itself, so Helm's release record must live in
# another, existing namespace.
RELEASE_NAMESPACE="default"
NAMESPACE="obstack"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The chart is the repository root.
CHART="$(cd "${SCRIPT_DIR}/../.." && pwd)"

context="$(kubectl config current-context 2>/dev/null || true)"
[[ "$context" == minikube* ]] || die "kubectl context is '${context}', not minikube. Run local-dev/minikube/minikube-setup.sh or switch context first."

log "Deploying ${RELEASE} to namespace ${NAMESPACE} (context ${context})..."
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$RELEASE_NAMESPACE" \
  --values "${SCRIPT_DIR}/values-minikube.yaml" \
  --wait --timeout 6m \
  "$@"

kubectl get pods -n "$NAMESPACE"
log "Done! Grafana: http://grafana.localtest.me (run 'minikube tunnel' if it isn't running)"
