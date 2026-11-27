resource "aws_ecr_repository" "sre_controller" {
  name                 = "${var.project_name}-sre-controller"
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

output "sre_controller_repository_url" {
  description = "Shared Capstone SRE controller image repository"
  value       = aws_ecr_repository.sre_controller.repository_url
}

resource "aws_ecr_lifecycle_policy" "sre_controller" {
  repository = aws_ecr_repository.sre_controller.name

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
