# =====================================================================
# OpenSearch Serverless (AOSS) for the catalog service's product search.
#
# How the pieces fit together:
#   1. Collection group  : holds the OCU (compute) min/max limits
#   2. Encryption policy : must exist BEFORE the collection is created
#   3. VPC endpoint      : private door into AOSS from inside our VPC
#   4. Network policy    : collection is reachable ONLY through that endpoint
#   5. Collection        : the actual search "cluster" (type SEARCH)
#   6. IAM role + Pod Identity : the catalog pod gets AWS credentials, no keys
#   7. Data access policy: what that role may do inside the collection
#
# Note: the collection group / collection use the "awscc" provider because
# the "aws" provider only supports collection groups from v6, and the EKS
# module (v20) pins aws < 6.0.
# =====================================================================

locals {
  aoss_name = "${var.project_name}-catalog" # max 32 chars, lowercase
}

# ---------------------------------------------------------------------
# 1. Collection group: OCU capacity range for the catalog collection
#    (scoped to this group only, does not affect the rest of the account)
# ---------------------------------------------------------------------
resource "awscc_opensearchserverless_collection_group" "catalog" {
  name             = "${local.aoss_name}-grp"
  description      = "Capacity limits for the catalog search collection"
  generation       = "NEXTGEN"
  standby_replicas = var.opensearch_standby_replicas

  capacity_limits = {
    min_search_capacity_in_ocu   = var.opensearch_search_ocu_min
    max_search_capacity_in_ocu   = var.opensearch_search_ocu_max
    min_indexing_capacity_in_ocu = var.opensearch_index_ocu_min
    max_indexing_capacity_in_ocu = var.opensearch_index_ocu_max
  }

  tags = [
    { key = "Project", value = var.project },
    { key = "Environment", value = "staging" },
    { key = "ManagedBy", value = "Terraform" },
  ]
}

# ---------------------------------------------------------------------
# 2. Encryption policy (encryption at rest with an AWS-owned key)
# ---------------------------------------------------------------------
resource "aws_opensearchserverless_security_policy" "catalog_encryption" {
  name        = "${local.aoss_name}-enc"
  type        = "encryption"
  description = "Encryption at rest policy for product catalogue collection"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.aoss_name}"]
      }
    ]
    AWSOwnedKey = true
  })
}

# ---------------------------------------------------------------------
# 3. VPC endpoint in the private subnets (where the EKS pods run)
# ---------------------------------------------------------------------
resource "aws_security_group" "opensearch" {
  name        = "${var.project_name}-opensearch-sg"
  description = "Allow HTTPS to OpenSearch Serverless from within the VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
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
    Name        = "${var.project_name}-opensearch-sg"
    environment = "staging"
    component   = "apps"
  }
}

resource "aws_opensearchserverless_vpc_endpoint" "catalog" {
  name               = "${local.aoss_name}-vpce"
  vpc_id             = aws_vpc.main.id
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.opensearch.id]
}

# ---------------------------------------------------------------------
# 4. Network policy: private only (no public internet access)
# ---------------------------------------------------------------------
resource "aws_opensearchserverless_security_policy" "catalog_network" {
  name = "${local.aoss_name}-net"
  type = "network"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.aoss_name}"]
        },
        {
          ResourceType = "dashboard"
          Resource     = ["collection/${local.aoss_name}"]
        }
      ]
      AllowFromPublic = false
      SourceVPCEs     = [aws_opensearchserverless_vpc_endpoint.catalog.id]
    }
  ])
}

# ---------------------------------------------------------------------
# 5. The collection itself
# ---------------------------------------------------------------------
resource "awscc_opensearchserverless_collection" "catalog" {
  name                  = local.aoss_name
  description           = "Product search for the catalog service"
  type                  = "SEARCH"
  standby_replicas      = var.opensearch_standby_replicas
  collection_group_name = awscc_opensearchserverless_collection_group.catalog.name

  tags = [
    { key = "Project", value = var.project },
    { key = "Environment", value = "staging" },
    { key = "ManagedBy", value = "Terraform" },
  ]

  depends_on = [
    aws_opensearchserverless_security_policy.catalog_encryption,
    aws_opensearchserverless_security_policy.catalog_network,
  ]
}

# ---------------------------------------------------------------------
# 6. IAM role for the catalog pod via EKS Pod Identity (same pattern as sqs.tf)
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "catalog_pod_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "catalog_pod" {
  name               = "${var.project_name}-catalog-pod-role"
  assume_role_policy = data.aws_iam_policy_document.catalog_pod_trust.json
}

# IAM side: allow calling the AOSS data API for THIS collection only.
# (What the role can do inside the collection is set by the data access policy below.)
resource "aws_iam_role_policy" "catalog_aoss_access" {
  name = "${var.project_name}-catalog-aoss-access"
  role = aws_iam_role.catalog_pod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CatalogCollectionApiAccess"
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = awscc_opensearchserverless_collection.catalog.arn
      }
    ]
  })
}

# Link: pods using service account "catalog" in retail-store get the role above
resource "aws_eks_pod_identity_association" "catalog" {
  cluster_name    = module.eks.cluster_name
  namespace       = var.catalog_namespace
  service_account = "catalog"
  role_arn        = aws_iam_role.catalog_pod.arn
}

# ---------------------------------------------------------------------
# 7. Data access policy: catalog pod can manage its indexes and documents
# ---------------------------------------------------------------------
resource "aws_opensearchserverless_access_policy" "catalog_data" {
  name = "${local.aoss_name}-access"
  type = "data"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.aoss_name}"]
          Permission   = ["aoss:DescribeCollectionItems"]
        },
        {
          ResourceType = "index"
          Resource     = ["index/${local.aoss_name}/*"]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument"
          ]
        }
      ]
      Principal = concat(
        [aws_iam_role.catalog_pod.arn],
        var.opensearch_admin_principals
      )
    }
  ])
}

# ---------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------
output "catalog_opensearch_endpoint" {
  description = "Set as RETAIL_CATALOG_SEARCH_OS_ENDPOINT in the catalog service"
  value       = awscc_opensearchserverless_collection.catalog.collection_endpoint
}

output "catalog_opensearch_dashboard_endpoint" {
  description = "OpenSearch Dashboards URL (reachable only from inside the VPC)"
  value       = awscc_opensearchserverless_collection.catalog.dashboard_endpoint
}

output "catalog_pod_role_arn" {
  description = "IAM role assumed by the catalog pod via Pod Identity"
  value       = aws_iam_role.catalog_pod.arn
}
