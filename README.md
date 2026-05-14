# Self-Hosted Cloud Agents Lab

This repository demonstrates how to run Cursor Cloud Agents on customer-managed infrastructure with self-hosted worker pools.

Cursor still handles orchestration, model inference, and the Cloud Agents experience. The worker runs inside your environment and executes the operational work: cloning repos, running shell commands, editing files, running builds/tests, and reaching internal services that are not available from Cursor-hosted infrastructure.

## What This Shows

- A shared Docker image that installs the Cursor `agent` CLI and starts a pool worker.
- A direct EC2 deployment that provisions AWS infrastructure with Terraform.
- A Helm/Kubernetes path for customers that already run Kubernetes.
- An ECS/Fargate scaffold for customers that prefer managed container scheduling.

Workers connect outbound to Cursor over HTTPS. No inbound access to the worker is required.

## Prerequisites

- Docker
- A Cursor Enterprise workspace with Self-Hosted Cloud Agents enabled
- A Cursor service account API key for pool workers
- The Cursor GitHub App installed with access to target repositories
- `kubectl` and `helm` for the Helm/Kubernetes approach
- AWS CLI and Terraform for the EC2 and ECS approaches

Pool workers require a **service account API key**. Personal, user, team, member, and general organization API keys are rejected by the worker CLI.

## Repo Layout

```text
.
├── config/              # Shared worker labels and local config examples
├── docker/              # Shared worker image and entrypoint
├── ec2/terraform/       # EC2-focused Terraform deployment
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

4. For Kubernetes, install the controller, create the API key secret, and apply the worker deployment:

   ```bash
   make helm-install-controller
   make helm-create-api-key-secret
   make helm-apply
   ```

## Deployment Approaches

- `ec2/` provisions a single long-lived EC2 host that runs the worker container directly with Docker. This is the simplest customer demo path.
- `helm/` installs the official Kubernetes controller and applies a `WorkerDeployment`. This is the best fit for teams that already operate Kubernetes.
- `ecs/` is a starting point for a Fargate or ECS service deployment.

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
