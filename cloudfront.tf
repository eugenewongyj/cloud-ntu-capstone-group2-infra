# =====================================================================
# CloudFront CDN in front of the shop (ADR-0006, option 2).
#
#   Shopper -> https://group2-shop.sctp-sandbox.com    (CloudFront + CloudFront WAF)
#           -> https://group2-retail.sctp-sandbox.com  (shared ALB + ALB WAF)
#           -> ui pods
#
# - HTTPS on both legs (shopper -> CloudFront, CloudFront -> ALB).
# - Only /assets/* (images, CSS, JS) is cached at the edge. Every other
#   page (catalog, cart, checkout, orders) is NOT cached.
# - The origin is the shop's existing DNS name (made by external-dns), not
#   the ALB's own name, which changes whenever the ALB is re-created.
# - CloudFront sends Host = group2-retail.sctp-sandbox.com to the ALB, so the
#   existing Ingress host rule keeps working (no Kubernetes change needed).
# - LOCK: CloudFront adds a secret header (X-Origin-Verify) to every request.
#   The ALB WAF (waf.tf, rule "ShopOnlyViaCloudFront") blocks requests for
#   group2-retail.sctp-sandbox.com that do not carry it. The secret is made
#   by Terraform and kept only in Terraform state, never in this public repo.
# - Access logs go to an S3 bucket in Singapore (ap-southeast-1).
# =====================================================================

locals {
  cdn_domain    = "group2-shop.sctp-sandbox.com"
  origin_domain = "group2-retail.sctp-sandbox.com"
  zone_id       = "Z00541411T1NGPV97B5C0" # sctp-sandbox.com (same as acm.tf)

  origin_verify_header = "X-Origin-Verify"

  # AWS managed CloudFront policies (fixed IDs, same in every AWS account)
  cache_policy_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  cache_policy_caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
  origin_policy_all_except_host  = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader
}

# ---------------------------------------------------------------------
# 1. Secret header value (CloudFront sends it, the ALB WAF checks it)
# ---------------------------------------------------------------------
resource "random_password" "origin_verify" {
  length  = 40
  special = false
}

# ---------------------------------------------------------------------
# 2. Certificate for the CloudFront address (CloudFront needs us-east-1)
# ---------------------------------------------------------------------
resource "aws_acm_certificate" "cdn" {
  provider          = aws.us_east_1
  domain_name       = local.cdn_domain
  validation_method = "DNS"

  tags = {
    Name        = "${var.project_name}-cdn-cert"
    Environment = "staging"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cdn_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cdn.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.zone_id
}

resource "aws_acm_certificate_validation" "cdn" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cdn.arn
  validation_record_fqdns = [for r in aws_route53_record.cdn_cert_validation : r.fqdn]
}

# ---------------------------------------------------------------------
# 3. CloudFront WAF (scope CLOUDFRONT must live in us-east-1)
#    Same 3 rules as before; the rate limit now sees real shopper IPs.
# ---------------------------------------------------------------------
resource "aws_wafv2_web_acl" "cdn" {
  provider    = aws.us_east_1
  name        = "${var.project_name}-cdn-web-acl"
  description = "Protects the shop CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSCommonRules"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cdn-common-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSKnownBadInputs"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cdn-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit_per_ip
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cdn-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-cdn-web-acl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.project_name}-cdn-web-acl"
    Environment = "staging"
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------------------
# 4. S3 bucket for CloudFront access logs (in Singapore)
# ---------------------------------------------------------------------
resource "aws_s3_bucket" "cdn_logs" {
  bucket        = "${var.project_name}-cdn-logs-ap-southeast-1"
  force_destroy = true
}

# CloudFront standard logs are written using bucket ACLs, so ACLs must be allowed
resource "aws_s3_bucket_ownership_controls" "cdn_logs" {
  bucket = aws_s3_bucket.cdn_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "cdn_logs" {
  bucket                  = aws_s3_bucket.cdn_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cdn_logs" {
  bucket = aws_s3_bucket.cdn_logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}

# ---------------------------------------------------------------------
# 5. The CloudFront distribution
# ---------------------------------------------------------------------
resource "aws_cloudfront_distribution" "shop" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.project_name} shop CDN"
  aliases         = [local.cdn_domain]
  price_class     = "PriceClass_200" # includes Asia edge locations (Singapore)
  web_acl_id      = aws_wafv2_web_acl.cdn.arn

  origin {
    origin_id   = "shop-alb"
    domain_name = local.origin_domain

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # The "key" the ALB WAF checks for (see waf.tf)
    custom_header {
      name  = local.origin_verify_header
      value = random_password.origin_verify.result
    }
  }

  # Default: all pages - NOT cached, everything (cookies, query, forms) passed on
  default_cache_behavior {
    target_origin_id         = "shop-alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = local.origin_policy_all_except_host
    compress                 = true
  }

  # Static files: product images, CSS, JS - cached at the edge
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    target_origin_id       = "shop-alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.cache_policy_caching_optimized
    compress               = true
  }

  logging_config {
    bucket          = aws_s3_bucket.cdn_logs.bucket_domain_name
    prefix          = "shop/"
    include_cookies = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cdn.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name        = "${var.project_name}-shop-cdn"
    Environment = "staging"
    ManagedBy   = "Terraform"
  }

  depends_on = [aws_s3_bucket_ownership_controls.cdn_logs]
}

# ---------------------------------------------------------------------
# 6. DNS: group2-shop.sctp-sandbox.com -> CloudFront
# ---------------------------------------------------------------------
resource "aws_route53_record" "cdn" {
  for_each = toset(["A", "AAAA"]) # IPv4 + IPv6

  zone_id = local.zone_id
  name    = local.cdn_domain
  type    = each.value

  alias {
    name                   = aws_cloudfront_distribution.shop.domain_name
    zone_id                = aws_cloudfront_distribution.shop.hosted_zone_id
    evaluate_target_health = false
  }
}

output "cloudfront_shop_url" {
  description = "Shop address through CloudFront"
  value       = "https://${local.cdn_domain}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (used to clear the cache)"
  value       = aws_cloudfront_distribution.shop.id
}
resource "aws_iam_role" "cloudwatch_observability" {
  name = "group2-capstone-cw-observability-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.cloudwatch_observability.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_pod_identity_association" "cloudwatch_agent" {
  cluster_name    = "group2-capstone-cluster"
  namespace       = "amazon-cloudwatch"
  service_account = "cloudwatch-agent"
  role_arn        = aws_iam_role.cloudwatch_observability.arn
}

resource "aws_eks_pod_identity_association" "fluent_bit" {
  cluster_name    = "group2-capstone-cluster"
  namespace       = "amazon-cloudwatch"
  service_account = "fluent-bit"
  role_arn        = aws_iam_role.cloudwatch_observability.arn
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = "group2-capstone-cluster"
  addon_name   = "amazon-cloudwatch-observability"

  depends_on = [
    aws_eks_pod_identity_association.cloudwatch_agent,
    aws_eks_pod_identity_association.fluent_bit
  ]
}