variable "aws_region" {
  type        = string
  default     = "ap-southeast-1"
  description = "Target AWS region"
}

variable "project_name" {
  type        = string
  description = "Prefix for tagging resources"
  default     = "group2-capstone"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "database_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for isolated database subnets"
  default     = ["10.0.5.0/24", "10.0.6.0/24"]
}

variable "aurora_db_name" {
  type        = string
  description = "Initial database name for the Aurora MySQL cluster"
  default     = "Catalog"
}

variable "aurora_master_username" {
  type        = string
  description = "Master username for the Aurora MySQL cluster"
  default     = "dbadmin"
}

variable "aurora_min_capacity" {
  type        = number
  description = "Minimum Aurora Serverless v2 capacity in ACUs"
  default     = 0.5
}

variable "aurora_max_capacity" {
  type        = number
  description = "Maximum Aurora Serverless v2 capacity in ACUs"
  default     = 1
}

variable "aurora_engine_version" {
  type        = string
  description = "Aurora MySQL engine version (Data API on Serverless v2 requires 3.07+)"
  default     = "8.0.mysql_aurora.3.08.2"
}

variable "aurora_instance_count" {
  type        = number
  description = "Number of Aurora Serverless v2 instances (1 writer + n-1 readers)"
  default     = 2
}

variable "aurora_backup_retention_days" {
  type        = number
  description = "Days to retain automated Aurora backups"
  default     = 1
}

variable "orders_namespace" {
  description = "Kubernetes namespace where the orders service runs"
  type        = string
  default     = "retail-store"
}
variable "project" {
  type        = string
  description = "Prefix for tagging resources"
  default     = "capstone-project-group-02"
}
# ---------------------------------------------------------------------
# OpenSearch Serverless (catalog search)
# ---------------------------------------------------------------------
variable "catalog_namespace" {
  description = "Kubernetes namespace where the catalog service runs"
  type        = string
  default     = "retail-store"
}

# OCU values: AWS only accepts 0, 2, 4, 8, 16 or a multiple of 16 (max 1,700).
# Staging: minimum 0 = no compute cost when idle (first search after a quiet
# period may be slow for a few seconds). Before a sale, raise the minimums to 2+.

variable "opensearch_search_ocu_min" {
  description = "Minimum search OCUs for the catalog collection (0 = scale to zero when idle)"
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 2, 4, 8], var.opensearch_search_ocu_min) || (var.opensearch_search_ocu_min >= 16 && var.opensearch_search_ocu_min <= 1700 && var.opensearch_search_ocu_min % 16 == 0)
    error_message = "OCU values must be 0, 2, 4, 8, 16 or a multiple of 16 (max 1700)."
  }
}

variable "opensearch_search_ocu_max" {
  description = "Maximum search OCUs for the catalog collection (cost cap)"
  type        = number
  default     = 32

  validation {
    condition     = contains([2, 4, 8], var.opensearch_search_ocu_max) || (var.opensearch_search_ocu_max >= 16 && var.opensearch_search_ocu_max <= 1700 && var.opensearch_search_ocu_max % 16 == 0)
    error_message = "Maximum OCU must be 2, 4, 8, 16 or a multiple of 16 (max 1700)."
  }
}

variable "opensearch_index_ocu_min" {
  description = "Minimum indexing OCUs for the catalog collection (0 = scale to zero when idle)"
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 2, 4, 8], var.opensearch_index_ocu_min) || (var.opensearch_index_ocu_min >= 16 && var.opensearch_index_ocu_min <= 1700 && var.opensearch_index_ocu_min % 16 == 0)
    error_message = "OCU values must be 0, 2, 4, 8, 16 or a multiple of 16 (max 1700)."
  }
}

variable "opensearch_index_ocu_max" {
  description = "Maximum indexing OCUs for the catalog collection (cost cap)"
  type        = number
  default     = 8

  validation {
    condition     = contains([2, 4, 8], var.opensearch_index_ocu_max) || (var.opensearch_index_ocu_max >= 16 && var.opensearch_index_ocu_max <= 1700 && var.opensearch_index_ocu_max % 16 == 0)
    error_message = "Maximum OCU must be 2, 4, 8, 16 or a multiple of 16 (max 1700)."
  }
}

variable "opensearch_standby_replicas" {
  description = "ENABLED = Multi-AZ standby copies (resilient). DISABLED = cheaper, single-AZ (dev/test only)"
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.opensearch_standby_replicas)
    error_message = "opensearch_standby_replicas must be ENABLED or DISABLED."
  }
}

variable "opensearch_admin_principals" {
  description = "Extra IAM user/role ARNs given read/write access to the catalog collection data (e.g. team members for debugging)"
  type        = list(string)
  default     = []
}
