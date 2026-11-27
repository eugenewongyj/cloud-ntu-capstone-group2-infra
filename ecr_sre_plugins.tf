resource "aws_ecr_repository" "sre_plugins" {
  name                 = "${var.project_name}-sre-plugins"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = "shared"
    ManagedBy   = "Terraform"
    Component   = "SRE"
  }
}

output "sre_plugins_repository_url" {
  description = "Shared Capstone Grafana plugins image repository"
  value       = aws_ecr_repository.sre_plugins.repository_url
}

resource "aws_ecr_lifecycle_policy" "sre_plugins" {
  repository = aws_ecr_repository.sre_plugins.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after seven days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Retain ten recent tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
