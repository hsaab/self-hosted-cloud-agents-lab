# ECS Approach

Use this approach to run Cursor self-hosted workers as ECS tasks, either on Fargate or on an ECS cluster backed by EC2 capacity.

## Current Status

This folder includes a Fargate-first Terraform deployment and a task definition example. The Terraform path creates an ECS service, ECR repository, Secrets Manager secret container, CloudWatch logs, and an autoscaling signal path for Cursor worker utilization.

## Intended Shape

- Build and publish the shared worker image from `docker/` to ECR.
- Store the Cursor service account API key in Secrets Manager.
- Run the worker as an ECS service where each task is one Cursor worker.
- Give the task outbound HTTPS access to Cursor APIs, Cursor downloads, and Cursor cloud-agent artifacts.
- Publish Cursor fleet utilization into CloudWatch and let ECS Service Auto Scaling adjust the service desired count.

Fargate is the default recommendation for teams that do not need privileged Docker, host-mounted caches, GPUs, or custom AMIs. Use ECS on EC2 when agents need CI-runner-style host control or specialized hardware. ECS on EC2 adds a second scaling loop because you must scale both the ECS service desired count and the underlying EC2 capacity provider.

## Autoscaling Model

Do not autoscale the worker service directly on CPU or memory. Idle workers can have low CPU while still representing useful warm capacity, and busy workers may be blocked on network or build steps rather than CPU.

The Cursor metrics that matter are:

- `cursor_self_hosted_worker_connected`: `1` when a worker has an active outbound connection to Cursor. Treat this as connected capacity and health.
- `cursor_self_hosted_worker_session_active`: `1` when a worker is claimed by a Cloud Agent session. Treat this as used capacity and demand.
- `cursor_self_hosted_worker_last_activity_unix_seconds`: useful for stale connection alerts.
- `cursor_self_hosted_worker_session_ends_total{reason=...}`: useful for reliability alerts, especially `session_error`, `connection_timeout`, and `session_aborted`.

For autoscaling, use worker occupancy:

```text
idle_workers = connected_workers - active_sessions
utilization_percent = active_sessions / connected_workers * 100
```

Do not scale out on `connected` alone. More connected workers means more capacity, so scaling up when `connected` increases creates a feedback loop. Use `connected` as the denominator for utilization and as an alert when ECS tasks are running but workers are not connected.

This lab uses a scheduled Lambda metrics publisher instead of scraping every Fargate task. The publisher calls Cursor's fleet management API, writes `Connected`, `InUse`, `Idle`, and `UtilizationPercent` to CloudWatch, and ECS Service Auto Scaling target-tracks `UtilizationPercent`.

Good starting defaults:

- `min_capacity`: `1` for demos, `2` for teams that need less cold-start latency.
- `max_capacity`: `10` by default, bounded by the Cursor team worker limit and cost policy.
- `target_utilization_percent`: `75`.
- Scale out cooldown: `60` seconds.
- Scale in cooldown: `600` to `900` seconds.
- `CURSOR_WORKER_IDLE_RELEASE_TIMEOUT`: `600`; ECS desired count is still the source of truth for fleet size.

The per-worker `/metrics` endpoint remains useful for dashboards and debugging. Scraping it from Fargate requires service discovery plus Prometheus, ADOT, or CloudWatch Agent plumbing, so it is a secondary path for this lab.

## End-To-End Flow

```bash
make ecs-terraform-init
make ecs-terraform-plan
make ecs-terraform-apply
make ecs-put-api-key-secret
make ecr-build-push
```

The ECS service may start before the secret value or first image exists. If tasks fail during the first boot, push the image, upload the secret, and force a new deployment:

```bash
aws ecs update-service \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER_NAME" \
  --service "$ECS_SERVICE_NAME" \
  --force-new-deployment
```

## Validation

Check the ECS service:

```bash
aws ecs describe-services \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER_NAME" \
  --services "$ECS_SERVICE_NAME"
```

Check logs:

```bash
aws logs tail "${ECS_WORKER_LOG_GROUP_NAME:-/ecs/$ECS_SERVICE_NAME}" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --follow
```

A healthy worker log includes:

```text
Worker is now running
Registering to worker pool
Repo: <owner>/<repo>
Pool: <pool-name>
```

Check the autoscaling metric:

```bash
aws cloudwatch get-metric-statistics \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --namespace "Cursor/SelfHostedWorkers" \
  --metric-name "UtilizationPercent" \
  --dimensions Name=PoolName,Value="${ECS_WORKER_POOL_NAME:-ecs-$CURSOR_WORKER_POOL_NAME}" Name=ClusterName,Value="$ECS_CLUSTER_NAME" Name=ServiceName,Value="$ECS_SERVICE_NAME" \
  --start-time "$(date -u -v-15M +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 \
  --statistics Average
```

## Cleanup

To stop AWS spend after a demo:

```bash
make ecs-terraform-destroy
```

Because this lab sets the ECR repository to force-delete, Terraform can remove the repository even if it contains demo images.

## Common Blockers

### Fargate Tasks Start Before The Image Or Secret Exists

The ECS service pulls the configured image and injects the Secrets Manager value at task startup. If either is missing, tasks stop quickly. Upload the secret with `make ecs-put-api-key-secret`, push the image with `make ecr-build-push`, then force a new service deployment.

### Worker Directory Is Not A Git Repo

Cursor derives the repo label from the worker directory's git remote. Fargate tasks start with empty ephemeral storage, so the shared Docker entrypoint initializes `/workspace` as a minimal git repo when `WORKER_REPOSITORY_URL` is set.

### Fleet API Metrics Are Team-Wide

The summary endpoint returns user and team counts. For a single lab pool, team utilization is fine. For production with multiple pools, use one service account and pool per ECS service or switch the metrics publisher to list workers and filter by labels when the API exposes enough pool detail for your routing model.

### Scaling From Zero Has No Connected Denominator

If `min_capacity` is `0`, there may be no connected worker count to divide by. Keep at least one warm worker unless you add a separate scheduled or queue-based scale-from-zero signal.

### Service Auto Scaling Changes Desired Count

Terraform creates the initial ECS service desired count, then ignores later desired count drift so Application Auto Scaling can manage it. Change `min_capacity`, `max_capacity`, or the scaling policy instead of repeatedly forcing `desired_count` back with Terraform.

## Customer Implementation Guide

Use this sequence when helping a customer implement the ECS/Fargate path from scratch.

### 1. Confirm Prerequisites

Confirm the customer has:

- Cursor Enterprise with Self-Hosted Cloud Agents enabled.
- A Cursor service account API key for pool workers.
- The Cursor GitHub App installed for the target repo owner and repository.
- AWS CLI, Docker, Terraform, and permissions to create ECS, ECR, IAM, Lambda, EventBridge, CloudWatch, Secrets Manager, and security group resources.
- A VPC with outbound internet access. The default lab path uses public subnets with `ECS_ASSIGN_PUBLIC_IP=true`; private subnets need NAT or equivalent egress.

### 2. Configure Environment

Copy the example environment file and fill in customer-specific values:

```bash
cp .env.example .env
```

Set at least:

```bash
AWS_PROFILE=customer-profile
AWS_REGION=us-east-1
CURSOR_API_KEY=replace-with-service-account-api-key
CURSOR_WORKER_POOL_NAME=customer-pool
ECS_WORKER_POOL_NAME=ecs-customer-pool
WORKER_ENVIRONMENT_LABEL=production
WORKER_OWNER_LABEL=platform-team
ECS_WORKER_INFRASTRUCTURE_LABEL=ecs
CURSOR_API_KEY_SECRET_NAME=customer/cursor-service-account-key
ECS_CLUSTER_NAME=cursor-agents
ECS_SERVICE_NAME=cursor-worker-service
ECS_TASK_FAMILY=cursor-self-hosted-worker
WORKER_REPOSITORY_URL=https://github.com/OWNER/REPO.git
```

Size the worker like a CI runner for the repository:

```bash
ECS_TASK_CPU=1024
ECS_TASK_MEMORY=2048
ECS_MIN_CAPACITY=1
ECS_MAX_CAPACITY=10
ECS_TARGET_UTILIZATION_PERCENT=75
```

Use an ECS-specific pool name, such as `ecs-customer-pool`, so the worker is easy to identify in the Cursor Cloud Agents dashboard. The Makefile defaults `ECS_WORKER_POOL_NAME` to `ecs-$(CURSOR_WORKER_POOL_NAME)` when it is not set explicitly. The ECS task also passes custom labels through `CURSOR_WORKER_LABELS_JSON`, so Cursor should show labels like `infrastructure=ecs`, `runtime=ecs-fargate`, `environment=production`, and `owner=platform-team`.

If using Graviton/Fargate ARM, also set:

```bash
WORKER_PLATFORM=linux/arm64
ECS_TASK_CPU_ARCHITECTURE=ARM64
```

### 3. Review The Terraform Plan

Initialize and plan without applying:

```bash
make ecs-terraform-init
make ecs-terraform-plan
```

Confirm the plan creates only the expected lab resources: ECS cluster/service/task definition, ECR repository, Secrets Manager secret container, IAM roles and policies, CloudWatch log groups, Lambda metrics publisher, EventBridge schedule, security group, and Application Auto Scaling target/policy.

### 4. Apply Infrastructure

Apply once the customer approves the plan:

```bash
make ecs-terraform-apply
```

Terraform creates the secret container but not the API key value. That keeps the service account key out of Terraform state.

### 5. Upload Secret And Push Image

Upload the service account key:

```bash
make ecs-put-api-key-secret
```

Build and push the worker image:

```bash
make ecr-build-push
```

If the ECS service started before the secret or image existed, force a new deployment:

```bash
aws ecs update-service \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER_NAME" \
  --service "$ECS_SERVICE_NAME" \
  --force-new-deployment
```

### 6. Verify Worker Health

Check service state:

```bash
aws ecs describe-services \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER_NAME" \
  --services "$ECS_SERVICE_NAME" \
  --query "services[0].{desired:desiredCount,running:runningCount,pending:pendingCount,events:events[0:5]}"
```

Tail worker logs:

```bash
aws logs tail "${ECS_WORKER_LOG_GROUP_NAME:-/ecs/$ECS_SERVICE_NAME}" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --follow
```

Confirm the worker appears in the Cursor Cloud Agents dashboard under the configured pool. Start a test Cloud Agent run with the pool selected.

### 7. Verify Autoscaling Metrics

Confirm the metrics publisher is running:

```bash
aws logs tail "/aws/lambda/${ECS_METRICS_PUBLISHER_NAME:-$ECS_SERVICE_NAME-metrics-publisher}" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --since 15m
```

Check CloudWatch for utilization:

```bash
aws cloudwatch get-metric-statistics \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --namespace "${ECS_METRICS_NAMESPACE:-Cursor/SelfHostedWorkers}" \
  --metric-name "UtilizationPercent" \
  --dimensions Name=PoolName,Value="${ECS_WORKER_POOL_NAME:-ecs-$CURSOR_WORKER_POOL_NAME}" Name=ClusterName,Value="$ECS_CLUSTER_NAME" Name=ServiceName,Value="$ECS_SERVICE_NAME" \
  --start-time "$(date -u -v-15M +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 \
  --statistics Average
```

Autoscaling should add capacity when `UtilizationPercent` stays above the target and remove capacity slowly after sustained lower utilization.

### 8. Production Hardening Checklist

Before production rollout, decide:

- Whether to use private subnets with NAT or VPC endpoints instead of public task ENIs.
- Whether each repo, team, or environment should get a separate pool and ECS service.
- Whether `ECS_MIN_CAPACITY` should be `2` or higher for warm standby capacity.
- Whether workers need ECS on EC2 instead of Fargate for privileged Docker, host caches, GPUs, larger local disks, or custom AMIs.
- Whether to add customer-standard alarms for failed ECS deployments, stopped tasks, Lambda errors, missing metrics, high utilization, and worker connection failures.

### 9. Troubleshooting

If tasks are stopped with image pull errors, run `make ecr-build-push` and confirm `ECR_REPOSITORY_NAME`, `WORKER_IMAGE_TAG`, `WORKER_PLATFORM`, and `ECS_TASK_CPU_ARCHITECTURE` match.

If tasks are stopped with secret injection errors, run `make ecs-put-api-key-secret` and confirm `CURSOR_API_KEY_SECRET_NAME` matches the Terraform output.

If worker logs say the worker directory is not a git repo, confirm `WORKER_REPOSITORY_URL` is set. The container entrypoint initializes `/workspace` using that remote.

If the worker connects but no jobs arrive, confirm the Cursor dashboard is selecting the ECS-specific pool from `ECS_WORKER_POOL_NAME`, and confirm the GitHub App has access to the target repo.

If metrics are missing, inspect the Lambda logs and confirm the service account key is valid. The metrics publisher uses the Cursor fleet summary API and writes CloudWatch metrics with `PoolName`, `ClusterName`, and `ServiceName` dimensions.

If autoscaling does not change desired count, check the Application Auto Scaling target and target-tracking policy, then confirm `UtilizationPercent` has recent CloudWatch datapoints. Target tracking does not act on missing data.

### 10. Teardown

For demos and proofs of concept, tear down the ECS path when finished:

```bash
make ecs-terraform-destroy
```

This deletes the ECS service, task definition resources, ECR repository, IAM roles, log groups, Lambda metrics publisher, EventBridge schedule, security group, and secret container managed by this Terraform root.

## Files

- `task-definition.example.json` shows the worker container command, environment variables, and secret reference expected by ECS.
- `terraform/` provisions the Fargate service and the Cursor utilization metrics publisher.

Replace placeholder ARNs, image names, and CPU/memory values before registering the task definition.
