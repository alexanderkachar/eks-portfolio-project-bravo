variable "project_name" {
  description = "Short project identifier used in resource names and tags."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the load balancer and target group are created."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the internet-facing application load balancer."
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "Security group attached to EKS nodes/pod ENIs that should accept ALB traffic."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for the app hostname."
  type        = string
}

variable "app_hostname" {
  description = "Public DNS hostname for the application."
  type        = string
}

variable "grafana_hostname" {
  description = "Public DNS hostname for Grafana."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN used by the HTTPS listener."
  type        = string
}

variable "target_port" {
  description = "Pod/container port registered in the ALB target group."
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "HTTP path used by the target group health check."
  type        = string
  default     = "/"
}

variable "grafana_target_port" {
  description = "Grafana pod/container port registered in the ALB target group."
  type        = number
  default     = 3000
}

variable "grafana_health_check_path" {
  description = "HTTP path used by the Grafana target group health check."
  type        = string
  default     = "/api/health"
}
