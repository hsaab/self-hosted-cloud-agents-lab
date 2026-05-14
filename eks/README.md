# EKS Customer Implementation Guide

Use this guide to stand up Cursor self-hosted Cloud Agent workers on Amazon EKS from scratch.

This path uses the shared worker image in `docker/`, pushes that image to ECR, installs the official Cursor worker-set controller Helm chart, and applies a generated `WorkerDeployment`.

## Architecture

The deployed flow is:

1. Cursor Cloud Agents schedules work for a repo and self-hosted pool.
2. The Cursor worker-set controller runs in EKS and keeps the requested number of worker pods ready.
3. Each worker pod runs the shared Cursor worker image from ECR.
4. The controller manages the worker auth token from a Kubernetes secret backed by the Cursor service account API key.
5. Workers connect outbound to Cursor over HTTPS. No inbound access to worker pods is required.

## Prerequisites

Install local tools:

```bash
brew install awscli eksctl kubectl helm
```

You also need:

- Docker running locally.
- An AWS account with permission to create EKS, IAM, VPC, node groups, and ECR resources.
- A Cursor Enterprise workspace with Self-Hosted Cloud Agents enabled.
- A Cursor **service account API key** for pool workers.
- The Cursor GitHub App installed with access to the target repository.

Pool workers reject personal, member, team, and general organization API keys.

## Step 1: Configure Local Environment

Copy the example environment file:

```bash
cp .env.example .env
```

Set these values in `.env`:

```bash
AWS_PROFILE=default
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=<your-aws-account-id>
ECR_REPOSITORY_NAME=cursor-self-hosted-worker

CURSOR_API_KEY=<cursor-service-account-api-key>
CURSOR_WORKER_POOL_NAME=<cursor-worker-pool-name>
CURSOR_WORKER_IDLE_RELEASE_TIMEOUT=600

K8S_NAMESPACE=cursord
WORKER_DEPLOYMENT_NAME=my-workers
WORKER_READY_REPLICAS=1
CURSOR_API_KEY_SECRET_NAME=my-workers-api-key
K8S_WORKER_LABELS_FILE=helm/labels.json
```

Set `WORKER_REPOSITORY_URL` if the local repo remote is not the customer repo that Cloud Agents should work on:

```bash
WORKER_REPOSITORY_URL=https://github.com/<owner>/<repo>.git
```

## Step 2: Authenticate AWS

Authenticate the AWS CLI:

```bash
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity --profile "$AWS_PROFILE"
```

If you do not use AWS IAM Identity Center, configure credentials with your normal AWS process and confirm `aws sts get-caller-identity` works. If your environment supports `aws login`, that is fine too.

## Step 3: Create An EKS Cluster

Set a cluster name in your shell:

```bash
export EKS_CLUSTER_NAME=cursor-agents-lab
```

Create a managed-node EKS cluster:

```bash
eksctl create cluster \
  --name "$EKS_CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --nodes 2 \
  --node-type t3.large \
  --managed
```

This command creates the VPC, EKS control plane, managed node group, and node IAM role. For private clusters, make sure worker nodes have outbound HTTPS through NAT or another approved egress path.

Update kubeconfig and verify access:

```bash
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$EKS_CLUSTER_NAME" \
  --profile "$AWS_PROFILE"

kubectl config current-context
kubectl get nodes
```

## Step 4: Create Or Reuse The ECR Repository

Create the ECR repository if it does not already exist:

```bash
aws ecr describe-repositories \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --repository-names "$ECR_REPOSITORY_NAME" >/dev/null 2>&1 \
  || aws ecr create-repository \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --repository-name "$ECR_REPOSITORY_NAME"
```

Build and push the worker image:

```bash
make ecr-build-push
```

The default `WORKER_PLATFORM=linux/amd64` matches the `t3.large` node type above. If you use Graviton nodes, set `WORKER_PLATFORM=linux/arm64` before building and pushing.

Set the Kubernetes image to the ECR image in `.env`:

```bash
K8S_WORKER_IMAGE=<aws-account-id>.dkr.ecr.<region>.amazonaws.com/cursor-self-hosted-worker:latest
```

Values loaded from `.env` are exported by the Makefile. You can also pass the image per command with `K8S_WORKER_IMAGE="..." make helm-apply`.

## Step 5: Install The Cursor Controller

Install the official Cursor worker-set controller Helm chart:

```bash
make helm-install-controller
```

Confirm the controller rolled out:

```bash
kubectl rollout status deployment/worker-set-controller -n "$K8S_NAMESPACE" --timeout=120s
kubectl get pods -n "$K8S_NAMESPACE"
```

## Step 6: Create The API Key Secret

Create or update the Kubernetes secret from `CURSOR_API_KEY`:

```bash
make helm-create-api-key-secret
```

Confirm the secret exists without printing the secret value:

```bash
kubectl get secret "$CURSOR_API_KEY_SECRET_NAME" -n "$K8S_NAMESPACE"
```

## Step 7: Render And Apply The WorkerDeployment

Review the generated deployment:

```bash
make helm-render
```

Apply it:

```bash
make helm-apply
```

Wait for the worker deployment:

```bash
kubectl get workerdeployments -n "$K8S_NAMESPACE"
kubectl get pods -n "$K8S_NAMESPACE" -l app=cursor-self-hosted-worker
```

## Step 8: Validate Worker Registration

Inspect worker logs:

```bash
kubectl logs -n "$K8S_NAMESPACE" -l app=cursor-self-hosted-worker -c worker --since=5m
```

A healthy worker log includes:

```text
Worker is now running
Registering to worker pool
Repo: <owner>/<repo>
Pool: <pool-name>
```

Then open Cursor Cloud Agents, choose **Self Hosted**, and start a test job against the repo that matches `WORKER_REPOSITORY_URL`.

## Step 9: Update Or Scale Workers

To change the worker image:

```bash
make ecr-build-push
make helm-apply
```

To change the number of ready workers:

```bash
WORKER_READY_REPLICAS=2 make helm-apply
kubectl get workerdeployments -n "$K8S_NAMESPACE"
```

To rotate the Cursor service account key:

```bash
make helm-create-api-key-secret
kubectl delete pod -n "$K8S_NAMESPACE" -l app=cursor-self-hosted-worker
```

The controller recreates the worker pod and mounts fresh auth material.

## Troubleshooting

### `helm` Or `kubectl` Is Missing

Install the required tools:

```bash
brew install awscli eksctl kubectl helm
```

Then rerun `helm version --short` and `kubectl version --client=true`.

### `kubectl` Has No Cluster Context

If `kubectl config current-context` fails or `kubectl cluster-info` tries `localhost:8080`, update kubeconfig:

```bash
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$EKS_CLUSTER_NAME" \
  --profile "$AWS_PROFILE"
```

### Worker Pods Show `ImagePullBackOff`

Confirm `K8S_WORKER_IMAGE` points at the pushed ECR image:

```bash
echo "$K8S_WORKER_IMAGE"
aws ecr describe-images \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --repository-name "$ECR_REPOSITORY_NAME"
```

Also confirm the node IAM role can pull from ECR. Managed node groups created by `eksctl` usually include ECR read permissions.

### Pod Fails With `exec format error`

The worker image architecture does not match the node architecture. Use `WORKER_PLATFORM=linux/amd64` for x86 nodes or `WORKER_PLATFORM=linux/arm64` for Graviton nodes, then rerun `make ecr-build-push` and `make helm-apply`.

### WorkerDeployment Kind Is Not Recognized

The controller chart did not install its CRD, or `helm-install-controller` did not finish successfully:

```bash
make helm-install-controller
kubectl get crd | rg workers.cursor.com
```

### Worker Logs Say The API Key Is Invalid

Create a Cursor service account API key from Cursor's Service Accounts settings. Update `CURSOR_API_KEY` in `.env`, then rerun:

```bash
make helm-create-api-key-secret
kubectl delete pod -n "$K8S_NAMESPACE" -l app=cursor-self-hosted-worker
```

### Worker Is Running But Jobs Do Not Start

Check that the pool name in Cursor matches `CURSOR_WORKER_POOL_NAME`, the repo in the worker logs matches the intended repo, and the Cursor GitHub App has access to that repo.

### Worker Cannot Reach Cursor

Workers need outbound HTTPS access to Cursor APIs, Cursor downloads, and Cursor cloud-agent artifacts. For private EKS nodes, verify NAT, firewall, proxy, and DNS settings.

### Pods Are Pending

Inspect scheduling events:

```bash
kubectl describe pods -n "$K8S_NAMESPACE" -l app=cursor-self-hosted-worker
kubectl get events -n "$K8S_NAMESPACE" --sort-by=.lastTimestamp
```

Common causes are insufficient CPU or memory, node taints, missing tolerations, or cluster autoscaler limits.

## Cleanup

Delete the example worker and labels ConfigMap:

```bash
make helm-delete
```

Remove the controller:

```bash
helm uninstall "$CURSOR_CONTROLLER_RELEASE_NAME" -n "$K8S_NAMESPACE"
kubectl delete namespace "$K8S_NAMESPACE"
```

Delete the EKS cluster when the demo is complete:

```bash
eksctl delete cluster \
  --name "$EKS_CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"
```

Delete the ECR repository if it was created only for the demo:

```bash
aws ecr delete-repository \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --repository-name "$ECR_REPOSITORY_NAME" \
  --force
```
