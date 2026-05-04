data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  repository_names = var.repository_names != null ? var.repository_names : [
    "${var.project_name}-${var.environment}-app",
  ]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.repository_names)

  name                 = each.key
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  force_delete = true

  tags = {
    Name        = each.key
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_expiry_days} days."
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.tagged_image_retention_count} tagged images."
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.tagged_image_retention_count
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}
