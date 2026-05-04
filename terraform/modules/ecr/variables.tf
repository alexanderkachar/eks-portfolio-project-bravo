variable "project_name" {
  description = "Short project identifier (used in tags)."
  type        = string
}

variable "environment" {
  description = "Environment name (used in tags)."
  type        = string
}

variable "repository_names" {
  description = "ECR repository names to create."
  type        = list(string)
  default     = null
}

variable "untagged_image_expiry_days" {
  description = "Days after push before untagged images are expired by lifecycle policy."
  type        = number
  default     = 7
}

variable "tagged_image_retention_count" {
  description = "How many tagged images to keep per repository before older tagged images are expired."
  type        = number
  default     = 10
}
