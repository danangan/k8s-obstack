# Local development guideline

This guideline covers how to spin up Kubernetes locally with minikube, and how to deploy obstack
and the sample app into it.

## Prerequisites

> [!CAUTION]
> These instructions only cover macOS. Linux and Windows haven't been tested yet.

- [minikube](https://minikube.sigs.k8s.io/), [kubectl](https://kubernetes.io/docs/tasks/tools/) and [Helm](https://helm.sh/)
- Docker or Podman, running
- Python and [uv](https://docs.astral.sh/uv/), only needed to run `sample-app` outside the cluster.
  `sample-app` is a small Python HTTP API that generates logs, metrics and traces for local
  development.

[minikube/minikube-setup.sh](minikube/minikube-setup.sh) creates a minikube node with 4 CPUs and
8 GB of memory. On macOS, Docker and Podman both run containers inside a VM, and that VM needs at
least **4 CPUs and 9 GB of memory**: the node's 8 GB plus headroom.

- **Docker Desktop:** Settings → Resources.
- **Podman:** stop the machine, then run `podman machine set --cpus 4 --memory 9216`.

The stack itself is much lighter: with the sample app running, the node uses about 0.3 CPU cores and
1.8 GB of memory.

## Starting obstack locally with minikube

From the repository root:

```sh
# 1. Start minikube (Docker, falling back to Podman; 4 CPUs / 8 GB) and enable ingress + metrics-server
./local-dev/minikube/minikube-setup.sh

# 2. Deploy the stack into the `obstack` namespace, with the minikube overrides
#    (local-dev/minikube/values-minikube.yaml) on top of the chart's AWS production defaults
./local-dev/minikube/deploy-obstack.sh

# 3. Build the sample app image inside minikube and deploy it
./local-dev/sample-app/build-and-deploy.sh

# 4. Expose the ingress to the host machine (leave this running; it asks for sudo)
minikube tunnel

# 5. Generate some traffic
for i in $(seq 20); do curl -s -XPOST "http://app.localtest.me/orders?item=book&quantity=2"; echo; done
```

Then open **Grafana** at <http://grafana.localtest.me>. Locally there's no login screen.

> [!NOTE]
> `*.localtest.me` is a public domain that resolves to `127.0.0.1`, so no `/etc/hosts` edits are needed.

## Layout

| Path | Description |
| --- | --- |
| [minikube/](minikube/) | Start the minikube cluster, and deploy the stack with the local overrides |
| [sample-app/](sample-app/) | FastAPI app (managed with [uv](https://docs.astral.sh/uv/)) instrumented with OpenTelemetry, and its build-and-deploy script |
| [sample-app/k8s/](sample-app/k8s/) | Helm chart for the sample app |
