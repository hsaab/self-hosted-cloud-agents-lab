# EC2 Approach

Use this approach to run one or more long-lived Cursor self-hosted worker containers directly on EC2 instances.

## Current Status

This is a scaffold only. The Terraform in `terraform/` documents the intended AWS shape but does not create resources yet.

## Intended Shape

- Build and publish the shared worker image from `docker/`.
- Store the Cursor service account API key in Secrets Manager or SSM Parameter Store.
- Launch EC2 workers with an instance profile, restricted inbound access, and outbound HTTPS.
- Bootstrap Docker on instance startup and run the worker container against the target pool.

## Terraform

```bash
make ec2-terraform-init
make ec2-terraform-plan
```
