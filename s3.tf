resource "aws_s3_bucket" "loki_logs" {
  bucket        = "group2-capstone-loki-logs-ap-southeast-1" # Must be globally unique
  force_destroy = true                                 # Set to false in real production
}

# Optional but recommended: block public access
resource "aws_s3_bucket_public_access_block" "loki_logs" {
  bucket                  = aws_s3_bucket.loki_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 1. Dedicated IAM Policy granting S3 access for Loki
resource "aws_iam_policy" "loki_s3" {
  name        = "${var.project_name}-loki-s3-policy"
  description = "Allows Loki to read and write log chunks to the S3 bucket"

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
        # Scoped specifically to your Loki logs bucket
        Resource = [
          aws_s3_bucket.loki_logs.arn,
          "${aws_s3_bucket.loki_logs.arn}/*"
        ]
      }
    ]
  })
}

# 2. Dedicated NEW IAM Role for Loki
# Trusts EKS Pod Identity (pods.eks.amazonaws.com)
resource "aws_iam_role" "loki_s3" {
  name = "${var.project_name}-loki-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

# 3. Attach the policy to the new Loki role
resource "aws_iam_role_policy_attachment" "loki_s3" {
  role       = aws_iam_role.loki_s3.name
  policy_arn = aws_iam_policy.loki_s3.arn
}

# 4. Map the new Role directly to the Kubernetes ServiceAccount via Pod Identity
resource "aws_eks_pod_identity_association" "loki_s3" {
  cluster_name    = module.eks.cluster_name
  namespace       = "logging"
  service_account = "loki"
  role_arn        = aws_iam_role.loki_s3.arn
}