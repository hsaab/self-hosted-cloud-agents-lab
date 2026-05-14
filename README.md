# Self-Hosted Cloud Agents Lab

This repository demonstrates how to run Cursor Cloud Agents on customer-managed infrastructure with self-hosted worker pools. Cursor still handles orchestration, model inference, and the Cloud Agents experience, while workers run inside your environment to clone repos, run commands, edit files, execute builds/tests, and reach internal services.

Workers connect outbound to Cursor over HTTPS. No inbound access to the worker is required.

## Infrastructure Guides

| Infrastructure | General README | Implementation README |
| --- | --- | --- |
| EC2 + Docker | [`ec2/README.md`](ec2/README.md) | [`ec2/terraform/README.md`](ec2/terraform/README.md) |
| ECS/Fargate | [`ecs/README.md`](ecs/README.md) | [`ecs/terraform/README.md`](ecs/terraform/README.md) |
| EKS + Helm | [`eks/README.md`](eks/README.md) | [`eks/helm/README.md`](eks/helm/README.md) |

For EC2 + Docker, start with the general README to understand the architecture, operating model, validation expectations, and troubleshooting. Use the implementation README when you want customer-facing setup commands for Terraform, Secrets Manager, ECR, validation, worker updates, key rotation, and cleanup.

For ECS/Fargate, start with the general README to understand the architecture, autoscaling model, operational trade-offs, and troubleshooting. Use the implementation README when you want copy-paste setup commands for Terraform, Secrets Manager, ECR, validation, key rotation, and cleanup.

The EKS guide covers the customer-facing flow. The Helm implementation assets live under `eks/helm/` so the Kubernetes controller, worker deployment, labels, and metrics autoscaling stay with the EKS approach.
