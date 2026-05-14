variable "aws_region" {
  description = "AWS region for future EC2 and ECR resources."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile to use while experimenting."
  type        = string
  default     = "default"
}

variable "worker_host_name" {
  description = "Name for a future EC2 worker host."
  type        = string
  default     = "cursor-worker-lab"
}

variable "instance_type" {
  description = "Initial EC2 instance type for the worker host."
  type        = string
  default     = "t3.large"
}

variable "worker_pool_name" {
  description = "Cursor worker pool name for EC2 experiments."
  type        = string
  default     = "lab"
}

variable "ecr_repository_name" {
  description = "Future ECR repository name for the self-hosted worker image."
  type        = string
  default     = "cursor-self-hosted-worker"
}
