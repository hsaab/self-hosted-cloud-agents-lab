terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# TODO: Decide whether this lab should create a VPC or target existing subnets.
# TODO: Add an ECR repository for the worker image once the image naming convention is settled.
# TODO: Add an EC2 instance profile with least-privilege access for image pulls, logs, and optional SSM.
# TODO: Add a security group that allows outbound HTTPS and keeps inbound access restricted.
# TODO: Add user data or a bootstrap script that starts the shared worker image on boot.
