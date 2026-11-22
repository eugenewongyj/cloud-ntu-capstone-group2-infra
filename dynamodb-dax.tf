# =====================================================================
# DynamoDB (on-demand) for the cart service.
#
# How the pieces fit together:
#   1. DynamoDB table   : stores cart items (pay-per-request, no capacity planning)
#   2. (removed) DAX cache: the cart app can only use DAX with an application code
#      change (DAX client library), so the DAX cluster was removed to save cost.
#   3. IAM role + Pod Identity : the cart pod gets AWS credentials, no keys
#
# Table layout matches the cart app (src/cart, DynamoItemEntity.java):
#   partition key "id", global index "idx_global_customerId" on "customerId".
#
# Variables for this feature are kept in this file so it is self-contained.
# =====================================================================

# ---------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------
variable "cart_namespace" {
  description = "Kubernetes namespace where the cart service runs"
  type        = string
  default     = "retail-store"
}

variable "cart_service_account" {
  description = "Service account of the cart pod (Helm release 'cart' + chart name 'carts')"
  type        = string
  default     = "cart-carts"
}

locals {
  cart_table_name = "${var.project_name}-carts"
}

# ---------------------------------------------------------------------
# 1. DynamoDB table (on-demand)
# ---------------------------------------------------------------------
resource "aws_dynamodb_table" "carts" {
  name         = local.cart_table_name
  billing_mode = "PAY_PER_REQUEST" # on-demand: pay per read/write, ~$0 when idle
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "customerId"
    type = "S"
  }

  # The cart app looks up "all items in a customer's cart" through this index
  global_secondary_index {
    name            = "idx_global_customerId"
    hash_key        = "customerId"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled = true # encryption at rest
  }

  point_in_time_recovery {
    enabled = true # restore to any second in the last 35 days
  }

  deletion_protection_enabled = false # staging: allow terraform destroy

  tags = {
    Name        = local.cart_table_name
    environment = "staging"
    component   = "apps"
  }
}

# ---------------------------------------------------------------------
# 3. IAM role for the cart pod via EKS Pod Identity (same pattern as sqs.tf)
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "cart_pod_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${var.cart_namespace}:${var.cart_service_account}"]
    }
  }
}

resource "aws_iam_role" "cart_pod" {
  name               = "${var.project_name}-cart-pod-role"
  assume_role_policy = data.aws_iam_policy_document.cart_pod_trust.json
}

# Least privilege: read/write THIS table only
resource "aws_iam_role_policy" "cart_data_access" {
  name = "${var.project_name}-cart-data-access"
  role = aws_iam_role.cart_pod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CartTableDirect"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "dynamodb:Query",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.carts.arn,
          "${aws_dynamodb_table.carts.arn}/index/*"
        ]
      }
    ]
  })
}

# Link: pods using the cart service account in retail-store get the role above
resource "aws_eks_pod_identity_association" "cart" {
  cluster_name    = module.eks.cluster_name
  namespace       = var.cart_namespace
  service_account = var.cart_service_account
  role_arn        = aws_iam_role.cart_pod.arn
}

# ---------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------
output "cart_dynamodb_table_name" {
  description = "Set as app.persistence.dynamodb.tableName in the cart Helm values"
  value       = aws_dynamodb_table.carts.name
}

output "cart_pod_role_arn" {
  description = "IAM role assumed by the cart pod via Pod Identity"
  value       = aws_iam_role.cart_pod.arn
}
