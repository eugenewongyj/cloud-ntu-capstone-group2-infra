# =====================================================================
# ElastiCache Serverless (Valkey) for the checkout service.
#
# Why Serverless:
#   - Finance  : pay for actual usage, not peak-sized nodes 24/7
#   - Marketing: scales automatically; before a sale, raise the ECPU minimum
#                so capacity is already warm at the launch minute
#
# Why Valkey: open-source Redis fork, works with the app's ioredis client
# unchanged, ~33% cheaper than Redis OSS on Serverless, 100 MB minimum storage.
#
# The checkout app (src/checkout) uses simple GET/SET/DEL and supports TLS
# (rediss://). Serverless always uses TLS, so set app.persistence.redis.tls=true.
#
# Variables for this feature are kept in this file so it is self-contained.
# =====================================================================

# ---------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------
variable "checkout_cache_max_storage_gb" {
  description = "Maximum data stored in the cache (GB). Cost safety cap."
  type        = number
  default     = 5
}

variable "checkout_cache_ecpu_min" {
  description = <<-EOT
    Minimum ECPUs per second (pre-warm). 0 = no minimum (pay only for usage).
    Before a flash sale, raise to the expected peak (>= 1000) about 1 hour ahead,
    then set back to 0 afterwards. See README pre-flash-sale checklist.
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.checkout_cache_ecpu_min == 0 || var.checkout_cache_ecpu_min >= 1000
    error_message = "checkout_cache_ecpu_min must be 0 (off) or at least 1000."
  }
}

variable "checkout_cache_ecpu_max" {
  description = "Maximum ECPUs per second. Cost safety cap (1,000 - 15,000,000)."
  type        = number
  default     = 100000
}

variable "checkout_cache_snapshot_time" {
  description = "Daily backup time in UTC (18:00 UTC = 02:00 Singapore time)"
  type        = string
  default     = "18:00"
}

variable "checkout_cache_snapshot_retention_days" {
  description = "Days to keep daily backups (checkout data is short-lived)"
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------
# 1. Security group: only traffic from the EKS cluster (same as orders_db)
#    6379 = read/write endpoint, 6380 = read-only (reader) endpoint
#    The top-level description below is out of date but is left unchanged on
#    purpose: changing a security group's description forces AWS to replace
#    the whole group, which fails while the cache is attached to it.
# ---------------------------------------------------------------------
resource "aws_security_group" "checkout_cache" {
  name        = "${var.project_name}-checkout-cache-sg"
  description = "Allow Valkey/Redis access to the checkout cache from within the VPC"
  vpc_id      = aws_vpc.main.id

  # DevSecOps: only the EKS cluster SG may connect (not the whole VPC)
  ingress {
    description     = "Valkey (read/write + reader) from EKS pods"
    from_port       = 6379
    to_port         = 6380
    protocol        = "tcp"
    security_groups = [module.eks.cluster_primary_security_group_id]
  }

  # No outbound rules: the cache only answers connections, it never starts
  # them. "egress = []" makes Terraform remove the default allow-all rule
  # (leaving the egress block out would keep it).
  egress = []

  tags = {
    Name        = "${var.project_name}-checkout-cache-sg"
    environment = "staging"
    component   = "apps"
  }
}

# ---------------------------------------------------------------------
# 2. The serverless cache
# ---------------------------------------------------------------------
resource "aws_elasticache_serverless_cache" "checkout" {
  name                 = "${var.project_name}-checkout"
  description          = "Checkout session store (Valkey Serverless)"
  engine               = "valkey"
  major_engine_version = "8"

  # Private subnets (2 AZs), same as the EKS pods; multi-AZ is built in
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.checkout_cache.id]

  # Encryption in transit (TLS) is always on for Serverless.
  # Encryption at rest is always on; kms_key_id omitted = AWS-managed key.

  cache_usage_limits {
    data_storage {
      maximum = var.checkout_cache_max_storage_gb
      unit    = "GB"
    }

    ecpu_per_second {
      # null = no minimum, so the minimum is only sent when pre-warming for a sale
      minimum = var.checkout_cache_ecpu_min > 0 ? var.checkout_cache_ecpu_min : null
      maximum = var.checkout_cache_ecpu_max
    }
  }

  daily_snapshot_time      = var.checkout_cache_snapshot_time
  snapshot_retention_limit = var.checkout_cache_snapshot_retention_days

  tags = {
    Name        = "${var.project_name}-checkout"
    environment = "staging"
    component   = "apps"
  }
}

# ---------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------
output "checkout_cache_endpoint" {
  description = "Set as app.persistence.redis.endpoint (host:port) in gitops/app/apps/checkout.yaml"
  value       = "${aws_elasticache_serverless_cache.checkout.endpoint[0].address}:${aws_elasticache_serverless_cache.checkout.endpoint[0].port}"
}

output "checkout_cache_reader_endpoint" {
  description = "Read-only endpoint (host:port), for optional read scaling"
  value       = "${aws_elasticache_serverless_cache.checkout.reader_endpoint[0].address}:${aws_elasticache_serverless_cache.checkout.reader_endpoint[0].port}"
}
