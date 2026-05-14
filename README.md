# Self-Hosted Cloud Agents Lab

This repo is a sandbox for trying Cursor Self-Hosted Pool workers with a shared worker image and three deployment approaches: EC2, Helm/Kubernetes, and ECS.

## What This Is

Cursor Self-Hosted Pool workers run the agent workspace, shell commands, tool calls, builds, and tests inside your infrastructure while Cursor still handles orchestration and inference. Workers require a Cursor service account API key; user, team, or org API keys are not enough for pool workers.

## Prerequisites

- Docker
- Cursor `agent` CLI support inside the image
- A Cursor service account API key
- `kubectl` and `helm` for the Helm/Kubernetes approach
- AWS CLI configured locally for the EC2 and ECS approaches
- Terraform for the EC2 scaffold

## Repo Layout

```text
.
├── config/              # Shared worker labels and local config examples
├── docker/              # Shared worker image and entrypoint
├── ec2/terraform/       # EC2-focused Terraform scaffold
├── ecs/                 # ECS/Fargate approach notes and examples
└── helm/                # Helm values, Kubernetes manifests, and helper scripts
```

## Suggested Workflow

1. Copy `.env.example` to `.env` and fill in local values.
2. Build the Docker worker image:

   ```bash
   make docker-build
   ```

3. Run a single Docker worker locally:

   ```bash
   make docker-run
   ```

4. When a Kubernetes cluster is available, install the controller:

   ```bash
   make helm-install-controller
   ```

5. Create the service account API key secret:

   ```bash
   make helm-create-api-key-secret
   ```

6. Apply the worker deployment:

   ```bash
   make helm-apply
   ```

7. For AWS alternatives, use `ec2/` and `ecs/` as separate starting points. Both are scaffolds until reviewed and wired to real AWS resources.

## Secrets

Do not commit real API keys, kubeconfigs, Terraform state, or `.env` files. The helper scripts read values from environment variables so secrets can stay in your shell, secret manager, or CI environment.

## Notes

- The default namespace is `cursord`.
- The example Kubernetes secret is named `my-workers-api-key`.
- The example worker deployment is named `my-workers`.
- Reserved worker labels include `repo` and `pool`; avoid setting those manually in shared or approach-specific label files.
- Workers need outbound HTTPS access to Cursor APIs, Cursor downloads, and Cursor cloud-agent artifacts.

## Approach Status

- `helm/` is the most complete path today. It installs the official controller and applies a `WorkerDeployment`.
- `ec2/terraform/` is a non-provisioning scaffold for a direct EC2 worker host approach.
- `ecs/` is a scaffold for a Fargate or ECS service approach and includes a task definition example.
