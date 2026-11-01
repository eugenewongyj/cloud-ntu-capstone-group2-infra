################################################################################
# S3 Storage for Grafana Loki Log Chunks
################################################################################
resource "aws_s3_bucket" "loki_storage" {
  bucket        = "${var.project_name}-loki-logs"
  force_destroy = true # Convenient for test/sandbox teardown

  tags = {
    Name        = "${var.project_name}-loki-logs"
    Environment = "staging"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki_storage" {
  bucket = aws_s3_bucket.loki_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "loki_storage" {
  bucket = aws_s3_bucket.loki_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Auto-expire logs after 14 days to keep storage lean
resource "aws_s3_bucket_lifecycle_configuration" "loki_storage" {
  bucket = aws_s3_bucket.loki_storage.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {} # <--- Applies to all objects without throwing warnings

    expiration {
      days = 14
    }
  }
}

data "aws_iam_policy_document" "loki_s3_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "loki_s3_role" {
  name               = "${var.project_name}-loki-s3-role"
  assume_role_policy = data.aws_iam_policy_document.loki_s3_trust.json
}

resource "aws_iam_role_policy" "loki_s3_policy" {
  name = "${var.project_name}-loki-s3-policy"
  role = aws_iam_role.loki_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.loki_storage.arn,
          "${aws_s3_bucket.loki_storage.arn}/*"
        ]
      }
    ]
  })
}
