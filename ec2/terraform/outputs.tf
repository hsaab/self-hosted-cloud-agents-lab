output "worker_host_name" {
  description = "Planned EC2 worker host name."
  value       = var.worker_host_name
}

output "instance_type" {
  description = "Planned EC2 worker host instance type."
  value       = var.instance_type
}

output "worker_pool_name" {
  description = "Cursor worker pool name for this EC2 lab."
  value       = var.worker_pool_name
}

output "ecr_repository_name" {
  description = "Planned ECR repository name for the worker image."
  value       = var.ecr_repository_name
}
