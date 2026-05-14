# EC2 Approach

Use this approach to run a Cursor self-hosted pool worker directly on an EC2 instance with Docker.

This path is useful for demos, proofs of concept, and customers that want the smallest possible AWS footprint before adopting Kubernetes or a managed container service.

## What Gets Created

Terraform creates:

- One EC2 worker host.
- One ECR repository for the worker image.
- One Secrets Manager secret container for the Cursor service account key.
- An IAM role and instance profile for ECR image pulls, Secrets Manager reads, and SSM access.
- A security group with no inbound rules and outbound HTTPS/DNS.

The Cursor API key value is uploaded separately with `make ec2-put-api-key-secret` so it does not land in Terraform state.

## End-To-End Flow

```bash
make ec2-terraform-init
make ec2-terraform-plan
make ec2-terraform-apply
make ec2-put-api-key-secret
make ecr-build-push
```

The EC2 bootstrap waits for the secret value and image for a few minutes, so it is okay if the instance starts while you are still pushing the first image. If the wait expires, connect with SSM and rerun `/var/lib/cloud/instance/scripts/part-001` or reboot the instance after both are available.

The default worker image platform is `linux/amd64`, which matches `t3`/`t3a` instance types. For `t4g` instances, set `WORKER_PLATFORM=linux/arm64` and `ami_architecture=arm64` in Terraform.

`WORKER_REPOSITORY_URL` defaults to the local git remote origin and is used only so the worker workspace has a git origin for Cursor's startup checks.

## Customer Step-By-Step: Docker On EC2

Use this sequence when walking a customer through the direct EC2 path.

### 1. Confirm Cursor prerequisites

In Cursor, confirm the customer has:

- Self-Hosted Cloud Agents enabled for the workspace.
- A service account API key created from Service Accounts settings.
- The Cursor GitHub App installed with access to the target repository.
- A pool name they want to route jobs to, such as `lab`, `staging`, or `build-fleet`.

The service account key is required for pool workers. A normal member, user, personal, team, or organization API key will not work.

### 2. Configure local environment

Copy the example env file and fill in customer-specific values:

```bash
cp .env.example .env
```

Required EC2 values:

```bash
CURSOR_API_KEY=<service-account-api-key>
CURSOR_WORKER_POOL_NAME=<pool-name>
WORKER_ENVIRONMENT_LABEL=lab
WORKER_OWNER_LABEL=platform-team
EC2_WORKER_INFRASTRUCTURE_LABEL=ec2
AWS_PROFILE=<aws-cli-profile>
AWS_REGION=<aws-region>
ECR_REPOSITORY_NAME=cursor-self-hosted-worker
EC2_INSTANCE_TYPE=t3.small
EC2_WORKER_HOST_NAME=cursor-worker-lab
```

`WORKER_REPOSITORY_URL` can stay empty. The Makefile defaults it to the local git remote origin.

The worker registers with Cursor using the reserved labels `repo=<repo>` and `pool=<pool-name>`. EC2 also passes custom labels through `CURSOR_WORKER_LABELS_JSON`, so Cursor should show values like `infrastructure=ec2`, `runtime=ec2-docker`, `environment=lab`, and `owner=platform-team`.

### 3. Authenticate to AWS

Use the customer's preferred AWS auth flow. For local demos:

```bash
aws login --profile "$AWS_PROFILE"
aws sts get-caller-identity --profile "$AWS_PROFILE"
```

The Makefile exports temporary credentials for Terraform with `aws configure export-credentials`, which avoids storing static AWS keys in the repo.

### 4. Review the Terraform plan

Initialize and plan before creating anything:

```bash
make ec2-terraform-init
make ec2-terraform-plan
```

The plan should show one EC2 instance, one ECR repository, one Secrets Manager secret container, IAM resources, and a no-inbound security group.

### 5. Apply the AWS infrastructure

Create the AWS resources:

```bash
make ec2-terraform-apply
```

Terraform creates the Secrets Manager secret metadata, but it does not put the Cursor API key value in Terraform state.

### 6. Upload the Cursor service account key

Write the key from `.env` into Secrets Manager:

```bash
make ec2-put-api-key-secret
```

This keeps the key out of committed files and Terraform state.

### 7. Build and push the worker image

Build the Docker image and push it to ECR:

```bash
make ecr-build-push
```

By default this builds `linux/amd64`, which matches `t3` and `t3a` instance types.

### 8. Let EC2 bootstrap the container

On boot, EC2 user data installs Docker, fetches the service account key from Secrets Manager, creates `/etc/cursor/worker.env`, pulls the image from ECR, and starts the worker container.

If the instance was created before the secret value or image existed, rerun the bootstrap script or reboot after completing steps 6 and 7:

```bash
aws ssm start-session --region "$AWS_REGION" --target "<instance-id>"
sudo /var/lib/cloud/instance/scripts/part-001
```

### 9. Validate the worker on EC2

Connect over SSM and check Docker:

```bash
aws ssm start-session --region "$AWS_REGION" --target "<instance-id>"
sudo docker ps --filter name=cursor-worker
sudo docker logs -f cursor-worker
```

Expected healthy log:

```text
Worker is now running
Registering to worker pool
Repo: <owner>/<repo>
Pool: <pool-name>
```

### 10. Start a Cloud Agent job

In Cursor Cloud Agents:

1. Select the repository.
2. Select Self Hosted.
3. Select the pool name from `.env`.
4. Start a test prompt.

The worker connects outbound to Cursor and claims work from the pool. No inbound EC2 ports need to be opened.

### 11. Rotate or replace the service account key

After changing `CURSOR_API_KEY` in `.env`:

```bash
make ec2-put-api-key-secret
```

Then recreate the container so Docker reads the updated env file. A plain restart does not reload `--env-file` values.

### 12. Clean up after the demo

To stop AWS spend:

```bash
terraform -chdir=ec2/terraform destroy
```

Confirm the EC2 instance, ECR repository, IAM resources, security group, and secret metadata are removed.

## How The Worker Starts

On first boot, `user_data.sh.tpl` runs on the EC2 host and:

1. Installs Docker, Git, and the AWS CLI.
2. Logs Docker into ECR with the instance role.
3. Fetches the Cursor service account key from Secrets Manager.
4. Writes `/etc/cursor/worker.env` on the EC2 host.
5. Initializes `/opt/cursor/worker` as a git repo and sets the GitHub origin.
6. Pulls the worker image from ECR.
7. Starts `cursor-worker` with Docker and mounts `/opt/cursor/worker` as `/workspace`.

The worker process reads `CURSOR_API_KEY` from the Docker environment, not from a `.env` file inside the container.

## Validation

Check EC2 and SSM:

```bash
aws ec2 describe-instance-status \
  --region "$AWS_REGION" \
  --instance-ids "<instance-id>" \
  --include-all-instances

aws ssm start-session \
  --region "$AWS_REGION" \
  --target "<instance-id>"
```

Check the container:

```bash
sudo docker ps --filter name=cursor-worker
sudo docker logs -f cursor-worker
```

A healthy log includes:

```text
Worker is now running
Registering to worker pool
Repo: <owner>/<repo>
Pool: <pool-name>
```

## Updating The Worker

After changing Docker files or the entrypoint:

```bash
make ecr-build-push
```

Then recreate the container on EC2 so it pulls the new image:

```bash
sudo docker rm -f cursor-worker
sudo docker pull "$ECR_WORKER_IMAGE"
sudo docker run -d \
  --name cursor-worker \
  --restart unless-stopped \
  --env-file /etc/cursor/worker.env \
  --volume /opt/cursor/worker:/workspace \
  "$ECR_WORKER_IMAGE"
```

After rotating the service account key:

```bash
make ec2-put-api-key-secret
```

Then refresh `/etc/cursor/worker.env` from Secrets Manager and recreate the container. A plain `docker restart` does not reload environment variables from `--env-file`.

## Common Blockers

### Terraform Cannot Use `aws login`

The AWS CLI can authenticate with `aws login`, but some Terraform AWS provider versions cannot read that cached login profile directly.

This repo's Make targets export temporary credentials with `aws configure export-credentials` before running Terraform. If Terraform reports `No valid credential sources found`, refresh local auth and rerun:

```bash
aws login --profile "$AWS_PROFILE"
make ec2-terraform-plan
```

### AMI Lookup Fails

Some provider versions reject `resolve:ssm:/...` AMI values in `aws_instance`.

This repo uses `data "aws_ssm_parameter"` to resolve the latest Amazon Linux 2023 AMI before passing the real AMI ID to EC2.

### Worker CLI Rejects Arguments

The worker options belong before the `start` subcommand. Use:

```bash
agent worker --pool --pool-name "$CURSOR_WORKER_POOL_NAME" start
```

not:

```bash
agent worker start --pool "$CURSOR_WORKER_POOL_NAME"
```

The Docker entrypoint follows the correct ordering.

### Worker Directory Is Not A Git Repo

Cursor derives the repo label from the worker directory's git remote. If `/workspace` is not inside a git repo with `origin`, startup fails.

The EC2 bootstrap initializes `/opt/cursor/worker` as a minimal git repo, sets `origin` to `WORKER_REPOSITORY_URL`, and mounts it into the container at `/workspace`.

### API Key Is Invalid

Pool workers require a Cursor **service account API key**. Normal user, member, team, personal, or organization API keys are rejected.

Create the key from Cursor's Service Accounts settings, update `.env`, run `make ec2-put-api-key-secret`, and recreate the container.

### New Secret Value Does Not Take Effect

Docker reads `--env-file` only when the container is created. If you update Secrets Manager or `/etc/cursor/worker.env`, `docker restart` is not enough.

Recreate the container:

```bash
sudo docker rm -f cursor-worker
sudo docker run -d \
  --name cursor-worker \
  --restart unless-stopped \
  --env-file /etc/cursor/worker.env \
  --volume /opt/cursor/worker:/workspace \
  "$ECR_WORKER_IMAGE"
```

### Cloud Agents Cannot Access The Repo

A connected worker is not enough. Cursor Cloud Agents also needs GitHub App access to the target repository.

Install or update the Cursor GitHub App for the repo owner, grant access to the repository, save the GitHub App settings, and refresh the Cloud Agents page.

### No Job Logs Appear

The worker CLI does not always emit detailed per-job logs at the default log level. First confirm the worker is registered and selected in the Cloud Agents UI. Then inspect:

```bash
sudo docker logs -f cursor-worker
```

and the Cloud Agents dashboard/job UI.

## Cleanup

To stop AWS spend after a demo:

```bash
terraform -chdir=ec2/terraform destroy
```

Because this lab sets the ECR repository to force-delete, Terraform can remove the repository even if it contains demo images.
