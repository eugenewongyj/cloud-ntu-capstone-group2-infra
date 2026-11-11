resource "aws_s3_bucket" "loki_logs" {
  bucket        = "group2-capstone-loki-logs-ap-southeast-1" # Must be globally unique
  force_destroy = true                                       # Set to false in real production
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


resource "aws_s3_bucket" "tempo_traces" {
  bucket        = "group2-capstone-tempo-traces-ap-southeast-1"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "tempo_traces" {
  bucket                  = aws_s3_bucket.tempo_traces.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 1. Dedicated IAM Policy granting S3 access for Tempo
resource "aws_iam_policy" "tempo_s3" {
  name        = "${var.project_name}-tempo-s3-policy"
  description = "Allows Tempo to read and write trace data to the S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:GetObjectTagging",
          "s3:PutObjectTagging"
        ]
        Resource = [
          aws_s3_bucket.tempo_traces.arn,
          "${aws_s3_bucket.tempo_traces.arn}/*"
        ]
      }
    ]
  })
}

# 2. Dedicated IAM Role for Tempo (Trusts EKS Pod Identity)
resource "aws_iam_role" "tempo_s3" {
  name = "${var.project_name}-tempo-s3-role"

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

# 3. Attach the policy to the Tempo role
resource "aws_iam_role_policy_attachment" "tempo_s3" {
  role       = aws_iam_role.tempo_s3.name
  policy_arn = aws_iam_policy.tempo_s3.arn
}

# 4. Map the Role directly to the Kubernetes ServiceAccount via Pod Identity
resource "aws_eks_pod_identity_association" "tempo_s3" {
  cluster_name    = module.eks.cluster_name
  namespace       = "logging"
  service_account = "tempo"
  role_arn        = aws_iam_role.tempo_s3.arn
}