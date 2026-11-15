# =====================================================================
# DynamoDB (on-demand) + DAX cache for the cart service.
#
# How the pieces fit together:
#   1. DynamoDB table   : stores cart items (pay-per-request, no capacity planning)
#   2. DAX cluster      : in-memory cache in front of the table (microsecond reads)
#      - subnet group   : DAX nodes live in the private subnets (same as EKS pods)
#      - security group : only traffic from inside the VPC on the DAX TLS port
#      - parameter group: how long cached items/queries are kept
#      - service role   : lets DAX read/write the table on the app's behalf
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

variable "dax_node_type" {
  description = "DAX node size. dax.t3.small is the cheapest; use dax.r5.large+ for production load"
  type        = string
  default     = "dax.t3.small"
}

variable "dax_node_count" {
  description = "Number of DAX nodes. 1 = cheapest (no failover). 3 = recommended for production (spread across AZs)"
  type        = number
  default     = 1
}

variable "dax_item_ttl_ms" {
  description = "How long DAX keeps cached items (GetItem results), in milliseconds"
  type        = number
  default     = 300000 # 5 minutes
}

variable "dax_query_ttl_ms" {
  # DAX does NOT refresh cached query results when items change. The cart app reads
  # "all items for customer X" with a query, so any value > 0 can show a stale cart
  # (e.g. an item just added is missing) until the TTL expires. 0 = no query caching.
  description = "How long DAX keeps cached query results, in milliseconds (0 = off, safest for carts)"
  type        = number
  default     = 0
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
# 2. DAX cluster
# ---------------------------------------------------------------------

# 2a. Service role: DAX uses this to read/write the table
data "aws_iam_policy_document" "dax_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["dax.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dax_service" {
  name               = "${var.project_name}-dax-service-role"
  assume_role_policy = data.aws_iam_policy_document.dax_trust.json
}

resource "aws_iam_role_policy" "dax_table_access" {
  name = "${var.project_name}-dax-table-access"
  role = aws_iam_role.dax_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CartTableOnly"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:ConditionCheckItem",
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

# 2b. Network: private subnets + security group
resource "aws_dax_subnet_group" "carts" {
  name       = "${var.project_name}-dax-subnets"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_security_group" "dax" {
  name        = "${var.project_name}-dax-sg"
  description = "Allow DAX (TLS) access from within the VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "DAX encrypted endpoint from VPC"
    from_port   = 9111
    to_port     = 9111
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-dax-sg"
    environment = "staging"
    component   = "apps"
  }
}

# 2c. Cache lifetimes
resource "aws_dax_parameter_group" "carts" {
  name = "${var.project_name}-dax-params"

  parameters {
    name  = "record-ttl-millis"
    value = tostring(var.dax_item_ttl_ms)
  }

  parameters {
    name  = "query-ttl-millis"
    value = tostring(var.dax_query_ttl_ms)
  }
}

# 2d. The cluster
resource "aws_dax_cluster" "carts" {
  cluster_name       = "${var.project_name}-dax" # max 20 chars
  iam_role_arn       = aws_iam_role.dax_service.arn
  node_type          = var.dax_node_type
  replication_factor = var.dax_node_count

  subnet_group_name    = aws_dax_subnet_group.carts.name
  security_group_ids   = [aws_security_group.dax.id]
  parameter_group_name = aws_dax_parameter_group.carts.name

  cluster_endpoint_encryption_type = "TLS" # encryption in transit (port 9111)

  server_side_encryption {
    enabled = true # encryption at rest
  }

  tags = {
    Name        = "${var.project_name}-dax"
    environment = "staging"
    component   = "apps"
  }

  # Role policy must exist before DAX tries to use the role
  depends_on = [aws_iam_role_policy.dax_table_access]
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
}

resource "aws_iam_role" "cart_pod" {
  name               = "${var.project_name}-cart-pod-role"
  assume_role_policy = data.aws_iam_policy_document.cart_pod_trust.json
}

# Least privilege: read/write THIS table (directly) and THIS DAX cluster only
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
      },
      {
        Sid    = "CartThroughDax"
        Effect = "Allow"
        Action = [
          "dax:GetItem",
          "dax:BatchGetItem",
          "dax:Query",
          "dax:PutItem",
          "dax:UpdateItem",
          "dax:DeleteItem",
          "dax:BatchWriteItem",
          "dax:ConditionCheckItem",
          "dax:DescribeClusters"
        ]
        Resource = aws_dax_cluster.carts.arn
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

output "cart_dax_endpoint" {
  description = "DAX cluster endpoint (daxs://...:9111) for the cart service"
  value       = aws_dax_cluster.carts.configuration_endpoint
}

output "cart_pod_role_arn" {
  description = "IAM role assumed by the cart pod via Pod Identity"
  value       = aws_iam_role.cart_pod.arn
}
