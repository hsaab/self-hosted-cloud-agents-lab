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
