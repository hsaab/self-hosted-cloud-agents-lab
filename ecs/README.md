# ECS Approach

Use this approach to run Cursor self-hosted workers as ECS tasks, either on Fargate or on an ECS cluster backed by EC2 capacity.

## Current Status

This folder is a scaffold. It includes a task definition example to capture the expected container shape, but it is not wired to Terraform or CloudFormation yet.

## Intended Shape

- Build and publish the shared worker image from `docker/` to ECR.
- Store the Cursor service account API key in Secrets Manager.
- Run the worker as an ECS service with desired count set to the number of standing workers you want.
- Give the task outbound HTTPS access to Cursor APIs, Cursor downloads, and Cursor cloud-agent artifacts.

## Files

- `task-definition.example.json` shows the worker container command, environment variables, and secret reference expected by ECS.

Replace placeholder ARNs, image names, and CPU/memory values before registering the task definition.
