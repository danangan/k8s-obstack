#!/usr/bin/env bash

set -euo pipefail

# Env overrides: MINIKUBE_PROFILE, MINIKUBE_CPUS,
#                MINIKUBE_MEMORY, POD_CIDR

PROFILE="${MINIKUBE_PROFILE:-minikube}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
OS="$(uname -s)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$1" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# minikube and kubectl are assumed to be installed already
# ---------------------------------------------------------------------------

require_tools() {
  has minikube || die "minikube not found on PATH. Install it first: https://minikube.sigs.k8s.io/docs/start/"
  has kubectl || die "kubectl not found on PATH. Install it first: https://kubernetes.io/docs/tasks/tools/"
  log "minikube found ($(minikube version --short 2>/dev/null || echo present))"
}

# ---------------------------------------------------------------------------
# Driver selection: prefer Docker, fall back to Podman
# ---------------------------------------------------------------------------

docker_ready() {
  has docker && docker info >/dev/null 2>&1
}

podman_ready() {
  has podman && podman info >/dev/null 2>&1
}

select_driver() {
  if docker_ready; then
    echo docker
  elif podman_ready; then
    echo podman
  else
    die "Neither Docker nor Podman is available and running. Start Docker Desktop or Podman, or install one of them, then re-run."
  fi
}

# ---------------------------------------------------------------------------
# Start the cluster
# ---------------------------------------------------------------------------

start_cluster() {
  local driver="$1"

  # if minikube profile list -o json 2>/dev/null | grep -q "\"Name\":\"${PROFILE}\""; then
  #   die "Profile '${PROFILE}' already exists. Run 'minikube delete -p ${PROFILE}' first, then re-run this script."
  # fi

  log "Starting minikube (profile=${PROFILE}, driver=${driver})..."

  minikube start -p "$PROFILE" --driver="$driver" --cpus=4 --memory=8192
}

# ---------------------------------------------------------------------------
# Networking fix: some Docker/Podman versions set the host's iptables
# FORWARD policy to DROP, which silently breaks pod-to-pod traffic (timeouts,
# DNS failures) inside the minikube node. Explicitly ACCEPT the pod CIDR.
# Not persistent across node restarts, so this is re-applied every run.
# ---------------------------------------------------------------------------

fix_networking() {
  log "Applying pod network FORWARD rules for ${POD_CIDR} (fixes pod-to-pod timeouts/DNS failures)..."
  minikube ssh -p "$PROFILE" -- "
    sudo iptables -C FORWARD -s ${POD_CIDR} -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD 1 -s ${POD_CIDR} -j ACCEPT
    sudo iptables -C FORWARD -d ${POD_CIDR} -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD 1 -d ${POD_CIDR} -j ACCEPT
  "
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  require_tools

  local driver
  driver="$(select_driver)"
  log "Using driver: ${driver}"

  start_cluster "$driver"
  fix_networking

  log "minikube is up. kubectl context: $(kubectl config current-context 2>/dev/null || echo "${PROFILE}")"
  minikube status -p "$PROFILE"

  log "setting up ingress and metrics-server addons..."

  minikube addons enable ingress
  minikube addons enable metrics-server

  # Enabling returns before the controller is serving; until then its admission webhook
  # rejects Ingress objects, which would fail an immediate deploy.
  log "waiting for the ingress controller to be ready..."
  kubectl wait -n ingress-nginx --for=condition=Ready pod \
    -l app.kubernetes.io/component=controller --timeout=180s

  log "Done!"
}

main "$@"
