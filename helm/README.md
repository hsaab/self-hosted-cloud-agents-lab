# Helm Approach

Use this approach when you already have a Kubernetes cluster and want to run Cursor self-hosted workers through the official worker-set controller.

## Contents

- `values.yaml` configures the controller Helm chart.
- `manifests/namespace.yaml` creates the default `cursord` namespace.
- `manifests/worker-deployment.yaml` defines an example `WorkerDeployment` and labels ConfigMap.
- `scripts/` contains helpers for installing the controller and creating the API key secret.

## Workflow

```bash
make helm-install-controller
make helm-create-api-key-secret
make helm-apply
```

Set `CURSOR_API_KEY` in your shell or `.env` before creating the secret.
