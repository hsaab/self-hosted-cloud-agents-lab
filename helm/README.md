# Helm Approach

Use this approach when you already have a Kubernetes cluster and want to run Cursor self-hosted workers through the official worker-set controller.

This path mirrors the EC2 demo but uses the Cursor controller Helm chart from the docs to manage Kubernetes `WorkerDeployment` resources.

## What Gets Installed

The workflow installs:

- The official Cursor worker-set controller Helm chart.
- A `cursord` namespace by default.
- A Kubernetes secret containing the Cursor service account API key.
- A labels ConfigMap mounted into the worker container.
- One example `WorkerDeployment` that runs the shared worker image.

The controller chart is configured by `values.yaml`. The default chart reference is:

```text
oci://public.ecr.aws/j6w0t2f5/cursor/worker-set-controller-chart
```

## End-To-End Flow

Set `.env` values first. For a remote cluster, `K8S_WORKER_IMAGE` must point at an image the cluster can pull, such as an ECR, GHCR, or other registry image.

```bash
make docker-build
make helm-install-controller
make helm-create-api-key-secret
make helm-render
make helm-apply
```

For an EKS-style demo using the same ECR image as the EC2 path:

```bash
make ecr-build-push
K8S_WORKER_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY_NAME:$WORKER_IMAGE_TAG" make helm-apply
```

`helm-render` prints the generated `WorkerDeployment` so you can review the exact Kubernetes object before applying it.

## Local Kind Smoke Test

This repo was validated locally with `kind` using the official Cursor controller chart and the local worker image.

If `helm` or `kind` are missing:

```bash
brew install helm kind
```

Create a local cluster, build the image, and load it into the kind node:

```bash
kind create cluster --name cursor-helm-lab
make docker-build
kind load docker-image cursor-self-hosted-worker:local --name cursor-helm-lab
```

Then deploy the controller and worker:

```bash
make helm-install-controller
make helm-create-api-key-secret
make helm-apply
```

The live validation used:

```bash
kubectl get pods -n "$K8S_NAMESPACE"
kubectl get workerdeployments -n "$K8S_NAMESPACE"
kubectl logs -n "$K8S_NAMESPACE" -l app=cursor-self-hosted-worker -c worker --since=5m
```

Expected healthy output:

```text
Worker is now running
Registering to worker pool
Repo: hsaab/self-hosted-cloud-agents-lab
Pool: hsaab-worker-pool
```

## How The Worker Starts

`make helm-install-controller` runs `helm upgrade --install` against the official controller chart and enables auth management through `values.yaml`.

`make helm-create-api-key-secret` creates the API key secret from `CURSOR_API_KEY` and labels it for the `WorkerDeployment`. This keeps the secret value out of checked-in YAML.

`make helm-apply` creates the namespace, applies the labels ConfigMap from `helm/labels.json`, and applies a generated `WorkerDeployment`. The pod has:

1. An init container that initializes `/workspace` as a git repo and sets `origin` to `WORKER_REPOSITORY_URL`.
2. A worker container that starts `agent worker --pool --pool-name "$CURSOR_WORKER_POOL_NAME"`.
3. A management port on `0.0.0.0:8080` for the controller.
4. A token file at `/var/run/cursor/token` that is managed by the controller from the API key secret.

The checked-in `manifests/worker-deployment.yaml` is a static example. The Make target uses `scripts/render-worker-deployment.sh` so local `.env` values are reflected without editing YAML by hand.

## Validation

Check the controller:

```bash
kubectl get pods -n "$K8S_NAMESPACE"
kubectl get deploy -n "$K8S_NAMESPACE"
kubectl logs -n "$K8S_NAMESPACE" -l app.kubernetes.io/name=worker-set-controller --since=5m
```

Check the worker deployment:

```bash
kubectl get workerdeployments -n "$K8S_NAMESPACE"
kubectl get pods -n "$K8S_NAMESPACE" -l app=cursor-self-hosted-worker
kubectl logs -n "$K8S_NAMESPACE" -l app=cursor-self-hosted-worker -c worker -f
```

A healthy worker log includes:

```text
Worker is now running
Registering to worker pool
Repo: <owner>/<repo>
Pool: <pool-name>
```

## Updating The Worker

After changing Docker files or the entrypoint, build and push a new image, then apply the generated worker deployment again:

```bash
make ecr-build-push
K8S_WORKER_IMAGE="<registry>/<repo>:<tag>" make helm-apply
```

After rotating the service account key:

```bash
make helm-create-api-key-secret
kubectl delete pod -n "$K8S_NAMESPACE" -l app=cursor-self-hosted-worker
```

If the controller recreates pods automatically after the secret update, a manual restart is not needed.

## Common Blockers

### Helm Or Kind Is Missing

The live local run initially failed because `helm` was not installed, and there was no local cluster helper installed. Install both with:

```bash
brew install helm kind
```

For an existing remote cluster, `kind` is optional, but `helm` is required for `make helm-install-controller`.

### No Kubernetes Context Is Set

If `kubectl config current-context` fails or `kubectl cluster-info` tries `localhost:8080`, kubeconfig is not pointed at a cluster. For local validation, create a kind cluster:

```bash
kind create cluster --name cursor-helm-lab
kubectl config current-context
```

For EKS or another remote cluster, update kubeconfig before running the Helm targets.

### Cluster Cannot Pull The Image

The default `cursor-self-hosted-worker:local` image only works when your local Kubernetes runtime can see that image, such as a local kind/minikube setup after loading it into the cluster. Remote clusters need `K8S_WORKER_IMAGE` set to a registry image.

For kind:

```bash
make docker-build
kind load docker-image cursor-self-hosted-worker:local --name cursor-helm-lab
```

### Worker Directory Is Not A Git Repo

Cursor derives the repo label from the worker directory's git remote. The generated Helm example handles this with an init container that runs `git init` in `/workspace` and sets the remote from `WORKER_REPOSITORY_URL`.

### API Key Is Invalid

Pool workers require a Cursor **service account API key**. Normal user, member, team, personal, or organization API keys are rejected.

Create the key from Cursor's Service Accounts settings, update `.env`, and rerun `make helm-create-api-key-secret`.

### CRD Is Missing

If `kubectl apply` reports that `WorkerDeployment` is not recognized, the controller chart did not finish installing its CRDs. Rerun:

```bash
make helm-install-controller
kubectl get crd | rg workers.cursor.com
```

### Initial Kind Scheduling Warning

On a single-node kind cluster, events may briefly show `FailedScheduling` for the controller because the control-plane taint has not been tolerated yet. In the live run this resolved within a few seconds and the controller rolled out normally.

## Cleanup

Remove the example worker deployment and labels ConfigMap:

```bash
make helm-delete
```

Remove the controller release and namespace:

```bash
helm uninstall "$CURSOR_CONTROLLER_RELEASE_NAME" -n "$K8S_NAMESPACE"
kubectl delete namespace "$K8S_NAMESPACE"
kind delete cluster --name cursor-helm-lab
```
