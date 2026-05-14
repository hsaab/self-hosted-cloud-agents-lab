# Self-Hosted Cloud Agents Lab

This repository demonstrates how to run Cursor Cloud Agents on customer-managed infrastructure with self-hosted worker pools.

Cursor still handles orchestration, model inference, and the Cloud Agents experience. The worker runs inside your environment and executes the operational work: cloning repos, running shell commands, editing files, running builds/tests, and reaching internal services that are not available from Cursor-hosted infrastructure.

## What This Shows

- A shared Docker image that installs the Cursor `agent` CLI and starts a pool worker.
- A direct EC2 deployment that provisions AWS infrastructure with Terraform.
- A Helm/Kubernetes path for customers that already run Kubernetes.
- A from-scratch EKS customer implementation guide.
- An ECS/Fargate scaffold for customers that prefer managed container scheduling.

Workers connect outbound to Cursor over HTTPS. No inbound access to the worker is required.

## Prerequisites

- Docker
- A Cursor Enterprise workspace with Self-Hosted Cloud Agents enabled
- A Cursor service account API key for pool workers
- The Cursor GitHub App installed with access to target repositories
- `kubectl` and `helm` for the Helm/Kubernetes approach
- `kind` for the local Helm smoke test
- AWS CLI and Terraform for the EC2 and ECS approaches

Pool workers require a **service account API key**. Personal, user, team, member, and general organization API keys are rejected by the worker CLI.

## Repo Layout

```text
.
├── config/              # Shared worker labels and local config examples
├── docker/              # Shared worker image and entrypoint
├── ec2/terraform/       # EC2-focused Terraform deployment
├── eks/                 # EKS customer implementation guide
├── ecs/                 # ECS/Fargate approach notes and examples
└── helm/                # Helm values, Kubernetes manifests, and helper scripts
```

## Quick Start

1. Copy `.env.example` to `.env` and fill in local values.
2. Build and smoke-test the worker image locally:

   ```bash
   make docker-build
   make docker-run
   ```

3. For an EC2 demo, provision AWS, upload the service account key, and push the image:

   ```bash
   make ec2-terraform-init
   make ec2-terraform-plan
   make ec2-terraform-apply
   make ec2-put-api-key-secret
   make ecr-build-push
   ```

4. For Kubernetes, install the controller chart from the Cursor docs, create the API key secret, and apply the worker deployment:

   ```bash
   # Set K8S_WORKER_IMAGE to an image your cluster can pull.
   make helm-install-controller
   make helm-create-api-key-secret
   make helm-render
   make helm-apply
   ```

   For a local kind smoke test, create a cluster and load the local image first:

   ```bash
   kind create cluster --name cursor-helm-lab
   make docker-build
   kind load docker-image cursor-self-hosted-worker:local --name cursor-helm-lab
   ```

5. For ECS/Fargate, provision AWS, upload the service account key, and push the image:

   ```bash
   make ecs-terraform-init
   make ecs-terraform-plan
   make ecs-terraform-apply
   make ecs-put-api-key-secret
   make ecr-build-push
   ```

## Deployment Approaches

- `ec2/` provisions a single long-lived EC2 host that runs the worker container directly with Docker. This is the simplest customer demo path.
- `eks/` walks a customer from AWS setup through EKS, ECR, Helm, validation, troubleshooting, and cleanup.
- `helm/` installs the official Kubernetes controller chart and applies a generated `WorkerDeployment`. This is the best fit for teams that already operate Kubernetes.
- `ecs/` provisions a Fargate service with Cursor utilization metrics published to CloudWatch for ECS Service Auto Scaling.

## Operational Model

For the EC2 path, Terraform creates the infrastructure but does not store the Cursor API key value in Terraform state. The secret value is uploaded separately from `.env` into Secrets Manager. On boot, EC2 user data fetches that value, writes an env file on the host, and starts the worker container with Docker `--env-file`.

The worker registers itself with Cursor using:

- The repo derived from the worker directory's git remote.
- The pool name from `CURSOR_WORKER_POOL_NAME`.
- Optional labels from `config/labels.json`.

## Verification

For EC2, use SSM to inspect the host without opening SSH:

```bash
aws ssm start-session --region "$AWS_REGION" --target "<instance-id>"
sudo docker logs -f cursor-worker
```

For Helm/Kubernetes, inspect the controller and worker pod:

```bash
kubectl get pods -n "$K8S_NAMESPACE"
kubectl logs -n "$K8S_NAMESPACE" -l app=cursor-self-hosted-worker -c worker -f
```

A healthy worker log includes:

```text
Worker is now running
Registering to worker pool
Repo: <owner>/<repo>
Pool: <pool-name>
```

## Secrets

Do not commit real API keys, kubeconfigs, Terraform state, or `.env` files. The helper scripts read values from environment variables so secrets can stay in your shell, secret manager, or CI environment.

If a service account key is exposed in logs or command history, rotate it.

## Notes

- The default namespace is `cursord`.
- The example Kubernetes secret is named `my-workers-api-key`.
- The example worker deployment is named `my-workers`.
- Reserved worker labels include `repo` and `pool`; avoid setting those manually in shared or approach-specific label files.
- Workers need outbound HTTPS access to Cursor APIs, Cursor downloads, and Cursor cloud-agent artifacts.
