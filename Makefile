SHELL := /bin/bash

-include .env
export

WORKER_IMAGE ?= cursor-self-hosted-worker:local
K8S_WORKER_IMAGE ?= $(WORKER_IMAGE)
K8S_NAMESPACE ?= cursord
WORKER_DEPLOYMENT_NAME ?= my-workers
CURSOR_API_KEY_SECRET_NAME ?= my-workers-api-key
K8S_WORKER_LABELS_FILE ?= helm/labels.json
K8S_WORKER_LABELS_CONFIG_MAP ?= cursor-worker-labels
AWS_PROFILE ?= default
AWS_REGION ?= us-east-1
ECR_REPOSITORY_NAME ?= cursor-self-hosted-worker
EC2_INSTANCE_TYPE ?= t3.small
EC2_WORKER_HOST_NAME ?= cursor-worker-lab
ECS_CLUSTER_NAME ?= cursor-agents-lab
ECS_SERVICE_NAME ?= cursor-worker-service
ECS_TASK_FAMILY ?= cursor-self-hosted-worker
ECS_WORKER_POOL_NAME ?= ecs-$(CURSOR_WORKER_POOL_NAME)
ECS_TASK_CPU ?= 1024
ECS_TASK_MEMORY ?= 2048
ECS_TASK_CPU_ARCHITECTURE ?= X86_64
ECS_WORKER_LOG_GROUP_NAME ?= /ecs/$(ECS_SERVICE_NAME)
ECS_MIN_CAPACITY ?= 1
ECS_MAX_CAPACITY ?= 10
ECS_TARGET_UTILIZATION_PERCENT ?= 75
ECS_SCALE_OUT_COOLDOWN_SECONDS ?= 60
ECS_SCALE_IN_COOLDOWN_SECONDS ?= 900
ECS_ASSIGN_PUBLIC_IP ?= true
ECS_METRICS_NAMESPACE ?= Cursor/SelfHostedWorkers
ECS_METRICS_PUBLISHER_NAME ?= $(ECS_SERVICE_NAME)-metrics-publisher
ECS_METRICS_PUBLISH_SCHEDULE_EXPRESSION ?= rate(1 minute)
CURSOR_WORKER_MANAGEMENT_ADDR ?= 0.0.0.0:8080
WORKER_ENVIRONMENT_LABEL ?= lab
WORKER_OWNER_LABEL ?= local-experiment
EC2_WORKER_INFRASTRUCTURE_LABEL ?= ec2
ECS_WORKER_INFRASTRUCTURE_LABEL ?= ecs
WORKER_IMAGE_TAG ?= latest
WORKER_PLATFORM ?= linux/amd64
WORKER_REPOSITORY_URL ?= $(shell git config --get remote.origin.url 2>/dev/null)
AWS_ACCOUNT_ID_RESOLVED := $(if $(AWS_ACCOUNT_ID),$(AWS_ACCOUNT_ID),$(shell aws sts get-caller-identity --profile "$(AWS_PROFILE)" --query Account --output text 2>/dev/null))
ECR_REGISTRY := $(AWS_ACCOUNT_ID_RESOLVED).dkr.ecr.$(AWS_REGION).amazonaws.com
ECR_WORKER_IMAGE := $(ECR_REGISTRY)/$(ECR_REPOSITORY_NAME):$(WORKER_IMAGE_TAG)
EC2_TERRAFORM_VARS := \
	-var "aws_profile=" \
	-var "aws_region=$(AWS_REGION)" \
	-var "instance_type=$(EC2_INSTANCE_TYPE)" \
	-var "worker_host_name=$(EC2_WORKER_HOST_NAME)" \
	-var "worker_pool_name=$(CURSOR_WORKER_POOL_NAME)" \
	-var "worker_idle_release_timeout=$(CURSOR_WORKER_IDLE_RELEASE_TIMEOUT)" \
	-var "worker_environment_label=$(WORKER_ENVIRONMENT_LABEL)" \
	-var "worker_infrastructure_label=$(EC2_WORKER_INFRASTRUCTURE_LABEL)" \
	-var "worker_owner_label=$(WORKER_OWNER_LABEL)" \
	-var "ecr_repository_name=$(ECR_REPOSITORY_NAME)" \
	-var "worker_image_tag=$(WORKER_IMAGE_TAG)" \
	-var "worker_repository_url=$(WORKER_REPOSITORY_URL)" \
	-var "cursor_api_key_secret_name=$(CURSOR_API_KEY_SECRET_NAME)"
ECS_TERRAFORM_VARS := \
	-var "aws_profile=" \
	-var "aws_region=$(AWS_REGION)" \
	-var "ecs_cluster_name=$(ECS_CLUSTER_NAME)" \
	-var "ecs_service_name=$(ECS_SERVICE_NAME)" \
	-var "ecs_task_family=$(ECS_TASK_FAMILY)" \
	-var "task_cpu=$(ECS_TASK_CPU)" \
	-var "task_memory=$(ECS_TASK_MEMORY)" \
	-var "task_cpu_architecture=$(ECS_TASK_CPU_ARCHITECTURE)" \
	-var "worker_log_group_name=$(ECS_WORKER_LOG_GROUP_NAME)" \
	-var "worker_pool_name=$(ECS_WORKER_POOL_NAME)" \
	-var "worker_idle_release_timeout=$(CURSOR_WORKER_IDLE_RELEASE_TIMEOUT)" \
	-var "worker_environment_label=$(WORKER_ENVIRONMENT_LABEL)" \
	-var "worker_infrastructure_label=$(ECS_WORKER_INFRASTRUCTURE_LABEL)" \
	-var "worker_owner_label=$(WORKER_OWNER_LABEL)" \
	-var "cursor_worker_management_addr=$(CURSOR_WORKER_MANAGEMENT_ADDR)" \
	-var "ecr_repository_name=$(ECR_REPOSITORY_NAME)" \
	-var "worker_image_tag=$(WORKER_IMAGE_TAG)" \
	-var "worker_repository_url=$(WORKER_REPOSITORY_URL)" \
	-var "cursor_api_key_secret_name=$(CURSOR_API_KEY_SECRET_NAME)" \
	-var "min_capacity=$(ECS_MIN_CAPACITY)" \
	-var "max_capacity=$(ECS_MAX_CAPACITY)" \
	-var "target_utilization_percent=$(ECS_TARGET_UTILIZATION_PERCENT)" \
	-var "scale_out_cooldown_seconds=$(ECS_SCALE_OUT_COOLDOWN_SECONDS)" \
	-var "scale_in_cooldown_seconds=$(ECS_SCALE_IN_COOLDOWN_SECONDS)" \
	-var "assign_public_ip=$(ECS_ASSIGN_PUBLIC_IP)" \
	-var "metrics_namespace=$(ECS_METRICS_NAMESPACE)" \
	-var "metrics_publisher_name=$(ECS_METRICS_PUBLISHER_NAME)" \
	-var "metrics_publish_schedule_expression=$(ECS_METRICS_PUBLISH_SCHEDULE_EXPRESSION)"

.PHONY: help docker-build docker-run ecr-login ecr-build-push ec2-put-api-key-secret ecs-put-api-key-secret helm-install-controller helm-create-api-key-secret helm-render helm-apply helm-delete k8s-create-api-key-secret k8s-apply k8s-delete ec2-terraform-init ec2-terraform-plan ec2-terraform-apply ec2-terraform-destroy ecs-terraform-init ecs-terraform-plan ecs-terraform-apply ecs-terraform-destroy terraform-init terraform-plan

help:
	@echo "Targets:"
	@echo "  docker-build                  Build the shared worker image"
	@echo "  docker-run                    Run one worker locally with Docker"
	@echo "  ecr-login                     Authenticate Docker to ECR"
	@echo "  ecr-build-push                Build and push the worker image to ECR"
	@echo "  ec2-put-api-key-secret        Upload CURSOR_API_KEY to the EC2 Secrets Manager secret"
	@echo "  helm-install-controller       Install or upgrade the Cursor worker controller"
	@echo "  helm-create-api-key-secret    Create the Cursor service account API key secret"
	@echo "  helm-render                   Render the example WorkerDeployment"
	@echo "  helm-apply                    Apply Helm approach manifests"
	@echo "  helm-delete                   Delete the example WorkerDeployment"
	@echo "  ec2-terraform-init            Initialize the EC2 Terraform scaffold"
	@echo "  ec2-terraform-plan            Plan the EC2 Terraform deployment"
	@echo "  ec2-terraform-apply           Apply the EC2 Terraform deployment"
	@echo "  ec2-terraform-destroy         Destroy the EC2 Terraform deployment"
	@echo "  ecs-put-api-key-secret        Upload CURSOR_API_KEY to the ECS Secrets Manager secret"
	@echo "  ecs-terraform-init            Initialize the ECS Terraform scaffold"
	@echo "  ecs-terraform-plan            Plan the ECS Terraform deployment"
	@echo "  ecs-terraform-apply           Apply the ECS Terraform deployment"
	@echo "  ecs-terraform-destroy         Destroy the ECS Terraform deployment"

docker-build:
	docker build -f docker/Dockerfile -t "$(WORKER_IMAGE)" .

docker-run:
	docker run --rm \
		--env CURSOR_API_KEY \
		--env CURSOR_WORKER_POOL_NAME \
		--env CURSOR_WORKER_IDLE_RELEASE_TIMEOUT \
		"$(WORKER_IMAGE)"

ecr-login:
	@if [[ -z "$(AWS_ACCOUNT_ID_RESOLVED)" ]]; then echo "AWS_ACCOUNT_ID or AWS CLI auth is required."; exit 1; fi
	aws ecr get-login-password --profile "$(AWS_PROFILE)" --region "$(AWS_REGION)" \
		| docker login --username AWS --password-stdin "$(ECR_REGISTRY)"

ecr-build-push: ecr-login
	docker buildx build \
		--platform "$(WORKER_PLATFORM)" \
		-f docker/Dockerfile \
		-t "$(ECR_WORKER_IMAGE)" \
		--push \
		.

ec2-put-api-key-secret:
	@if [[ -z "$${CURSOR_API_KEY:-}" ]]; then echo "CURSOR_API_KEY must be set in .env or the shell."; exit 1; fi
	aws secretsmanager put-secret-value \
		--profile "$(AWS_PROFILE)" \
		--region "$(AWS_REGION)" \
		--secret-id "$(CURSOR_API_KEY_SECRET_NAME)" \
		--secret-string "$${CURSOR_API_KEY}" >/dev/null
	@echo "Updated Secrets Manager value for $(CURSOR_API_KEY_SECRET_NAME)."

ecs-put-api-key-secret: ec2-put-api-key-secret

helm-install-controller:
	./helm/scripts/install-controller.sh

helm-create-api-key-secret:
	./helm/scripts/create-api-key-secret.sh

helm-render:
	@./helm/scripts/render-worker-deployment.sh

helm-apply:
	./helm/scripts/apply-worker-deployment.sh

helm-delete:
	./helm/scripts/delete-worker-deployment.sh

k8s-create-api-key-secret: helm-create-api-key-secret

k8s-apply: helm-apply

k8s-delete: helm-delete

ec2-terraform-init:
	terraform -chdir=ec2/terraform init

ec2-terraform-plan:
	@tmpfile="$$(mktemp)"; \
	aws configure export-credentials --profile "$(AWS_PROFILE)" --format env-no-export > "$$tmpfile"; \
	set -a; source "$$tmpfile"; set +a; rm -f "$$tmpfile"; \
	terraform -chdir=ec2/terraform plan $(EC2_TERRAFORM_VARS)

ec2-terraform-apply:
	@tmpfile="$$(mktemp)"; \
	aws configure export-credentials --profile "$(AWS_PROFILE)" --format env-no-export > "$$tmpfile"; \
	set -a; source "$$tmpfile"; set +a; rm -f "$$tmpfile"; \
	terraform -chdir=ec2/terraform apply $(EC2_TERRAFORM_VARS)

ec2-terraform-destroy:
	@tmpfile="$$(mktemp)"; \
	aws configure export-credentials --profile "$(AWS_PROFILE)" --format env-no-export > "$$tmpfile"; \
	set -a; source "$$tmpfile"; set +a; rm -f "$$tmpfile"; \
	terraform -chdir=ec2/terraform destroy $(EC2_TERRAFORM_VARS)

ecs-terraform-init:
	terraform -chdir=ecs/terraform init

ecs-terraform-plan:
	@tmpfile="$$(mktemp)"; \
	aws configure export-credentials --profile "$(AWS_PROFILE)" --format env-no-export > "$$tmpfile"; \
	set -a; source "$$tmpfile"; set +a; rm -f "$$tmpfile"; \
	terraform -chdir=ecs/terraform plan $(ECS_TERRAFORM_VARS)

ecs-terraform-apply:
	@tmpfile="$$(mktemp)"; \
	aws configure export-credentials --profile "$(AWS_PROFILE)" --format env-no-export > "$$tmpfile"; \
	set -a; source "$$tmpfile"; set +a; rm -f "$$tmpfile"; \
	terraform -chdir=ecs/terraform apply $(ECS_TERRAFORM_VARS)

ecs-terraform-destroy:
	@tmpfile="$$(mktemp)"; \
	aws configure export-credentials --profile "$(AWS_PROFILE)" --format env-no-export > "$$tmpfile"; \
	set -a; source "$$tmpfile"; set +a; rm -f "$$tmpfile"; \
	terraform -chdir=ecs/terraform destroy $(ECS_TERRAFORM_VARS)

terraform-init: ec2-terraform-init

terraform-plan: ec2-terraform-plan
