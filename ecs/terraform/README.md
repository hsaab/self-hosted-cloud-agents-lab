# ECS Terraform Scaffold

This Terraform root provisions the Fargate-first ECS worker path.

## What Gets Created

- ECS cluster, unless `create_ecs_cluster=false`.
- ECR repository, unless `create_ecr_repository=false`.
- Secrets Manager secret container for the Cursor service account key.
- ECS task execution role and task role.
- Fargate task definition and ECS service.
- Security group with no inbound rules and outbound HTTPS/DNS.
- CloudWatch log groups for worker and metrics publisher logs.
- Scheduled Lambda metrics publisher for Cursor fleet utilization.
- Application Auto Scaling target and target-tracking policy.

## Secret Handling

Terraform creates the Secrets Manager secret container, but it does not store the Cursor service account API key value in Terraform state. Upload the value separately:

```bash
make ecs-put-api-key-secret
```

## Autoscaling Signal

The metrics publisher calls Cursor's fleet summary API and publishes these CloudWatch metrics under `Cursor/SelfHostedWorkers`:

- `Connected`
- `InUse`
- `Idle`
- `UtilizationPercent`

ECS Service Auto Scaling target-tracks `UtilizationPercent`. Keep `min_capacity` above zero unless you add a separate scale-from-zero signal.

## Safety

Run `make ecs-terraform-plan` before applying. The initial apply can start tasks before the worker image or secret value exists; if that happens, upload the secret, push the image, and force a new ECS deployment.
