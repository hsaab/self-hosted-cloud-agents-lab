# EC2 Terraform Scaffold

This folder is intentionally non-provisioning for the first pass. Use it to design the direct EC2 worker-host approach before creating live resources.

## Likely AWS Pieces

- ECR repository for the worker image
- EC2 instance profile with the minimum permissions needed for image pulls, logs, and optional SSM access
- Security group with restricted inbound access and outbound HTTPS access to Cursor APIs and artifact hosts
- User data or a bootstrap script that installs Docker and starts the worker container
- Network egress that allows outbound HTTPS to Cursor APIs and artifact hosts
- Secrets Manager or SSM Parameter Store for the Cursor service account API key

## Local Setup Later

1. Install and configure the AWS CLI.
2. Confirm the target AWS account and region.
3. Decide whether the worker host should live in an existing VPC or a lab VPC.
4. Replace the TODO-only resources with reviewed modules.
5. Run `terraform init` and `terraform plan` before applying anything.

## Safety

Do not put real service account API keys in Terraform variables or state unless the state backend and access model are intentionally designed for secrets.
