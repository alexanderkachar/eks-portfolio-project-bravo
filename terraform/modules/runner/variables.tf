variable "project_name" {
  description = "Short project identifier."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR for HTTPS egress scoping."
  type        = string
}

variable "runner_subnet_id" {
  description = "Single runner subnet (AZ-a). Must route through NAT — the runner needs to reach github.com, ghcr.io, etc."
  type        = string
}

variable "github_owner" {
  description = "GitHub owner (user or org) for the repo the runner registers against."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (no owner prefix)."
  type        = string
}

variable "pat_ssm_parameter_name" {
  description = "SSM Parameter Store name for the GitHub PAT (SecureString). Created out of band — Terraform only references it by ARN. Default convention: /<project>/github/pat."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs the runner is allowed to push to. Scope-limits the layer upload permissions; GetAuthorizationToken stays at resource '*' because that's how AWS scopes it."
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name the runner deploys to."
  type        = string
}

variable "cluster_arn" {
  description = "EKS cluster ARN used to scope DescribeCluster permission."
  type        = string
}

variable "cluster_security_group_id" {
  description = "EKS cluster security group. The runner needs ingress to the private API endpoint on 443."
  type        = string
}

variable "runner_version" {
  description = "GitHub Actions runner binary version."
  type        = string
  default     = "2.334.0"
}

variable "runner_labels" {
  description = "Extra GitHub Actions labels assigned to this runner. GitHub automatically adds self-hosted, Linux, and X64."
  type        = string
  default     = "vpc"
}

variable "instance_type" {
  description = "EC2 instance type for the runner."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size."
  type        = number
  default     = 20
}
