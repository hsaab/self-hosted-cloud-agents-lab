SHELL := /bin/bash

-include .env
export

WORKER_IMAGE ?= cursor-self-hosted-worker:local
K8S_NAMESPACE ?= cursord
WORKER_DEPLOYMENT_NAME ?= my-workers
CURSOR_API_KEY_SECRET_NAME ?= my-workers-api-key

.PHONY: help docker-build docker-run helm-install-controller helm-create-api-key-secret helm-apply helm-delete k8s-create-api-key-secret k8s-apply k8s-delete ec2-terraform-init ec2-terraform-plan terraform-init terraform-plan

help:
	@echo "Targets:"
	@echo "  docker-build                  Build the shared worker image"
	@echo "  docker-run                    Run one worker locally with Docker"
	@echo "  helm-install-controller       Install or upgrade the Cursor worker controller"
	@echo "  helm-create-api-key-secret    Create the Cursor service account API key secret"
	@echo "  helm-apply                    Apply Helm approach manifests"
	@echo "  helm-delete                   Delete the example WorkerDeployment"
	@echo "  ec2-terraform-init            Initialize the EC2 Terraform scaffold"
	@echo "  ec2-terraform-plan            Plan the EC2 Terraform scaffold"

docker-build:
	docker build -f docker/Dockerfile -t "$(WORKER_IMAGE)" .

docker-run:
	docker run --rm \
		--env CURSOR_API_KEY \
		--env CURSOR_WORKER_POOL_NAME \
		--env CURSOR_WORKER_IDLE_RELEASE_TIMEOUT \
		"$(WORKER_IMAGE)"

helm-install-controller:
	./helm/scripts/install-controller.sh

helm-create-api-key-secret:
	./helm/scripts/create-api-key-secret.sh

helm-apply:
	kubectl apply -f helm/manifests/namespace.yaml
	kubectl apply -f helm/manifests/worker-deployment.yaml

helm-delete:
	kubectl delete -f helm/manifests/worker-deployment.yaml --ignore-not-found

k8s-create-api-key-secret: helm-create-api-key-secret

k8s-apply: helm-apply

k8s-delete: helm-delete

ec2-terraform-init:
	terraform -chdir=ec2/terraform init

ec2-terraform-plan:
	terraform -chdir=ec2/terraform plan

terraform-init: ec2-terraform-init

terraform-plan: ec2-terraform-plan
