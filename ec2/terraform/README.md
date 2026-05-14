# EC2 Terraform

This folder contains the Terraform used by the EC2 Docker approach documented in [`../README.md`](../README.md).

## What It Provisions

- ECR repository for the worker image
- Secrets Manager secret metadata for the Cursor service account API key
- EC2 instance profile with permissions for ECR pulls, Secrets Manager reads, and SSM access
- Security group with no inbound access and outbound HTTPS/DNS
- EC2 instance that runs Docker and starts the Cursor worker container from ECR
- User data bootstrap script that prepares the worker workspace and container environment

## Customer Flow

From the repository root:

```bash
make ec2-terraform-init
make ec2-terraform-plan
make ec2-terraform-apply
make ec2-put-api-key-secret
make ecr-build-push
```

See [`../README.md`](../README.md) for the full step-by-step walkthrough, validation commands, and common blockers.

## Safety

Do not put real service account API keys in Terraform variables or state. Terraform creates the secret container only; `make ec2-put-api-key-secret` uploads the value separately from `.env`.
