# =====================================================================
# Web Application Firewall (WAF) for the shared public ALB.
#
# How it is attached:
#   The ALB is created by EKS Auto Mode (from Kubernetes Ingresses), not by
#   Terraform. So the WAF is attached with this Ingress annotation, using the
#   ARN from the "waf_web_acl_arn" output below:
#     alb.ingress.kubernetes.io/wafv2-acl-arn: "<waf_web_acl_arn>"
#   All websites share ONE ALB (IngressClassParams group "group2-shared"),
#   so attaching it on one Ingress protects all of them.
#
# NOTE: the ARN changes if this Web ACL is destroyed and re-created.
#       Update the annotation if that happens.
# NOTE: when CloudFront is added in front of the shop, revisit the rate
#       limit rule (the ALB will then see CloudFront's IPs, not shoppers').
# =====================================================================

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-web-acl"
  description = "Protects the shared public ALB (shop, Argo CD, Grafana, Prometheus)"
  scope       = "REGIONAL" # REGIONAL = for ALBs

  default_action {
    allow {} # let traffic through unless a rule below blocks it
  }

  # Rule 1: AWS ready-made rules for common web attacks
  rule {
    name     = "AWSCommonRules"
    priority = 1

    override_action {
      none {} # use the rule group's own actions (block)
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS ready-made rules for known bad inputs
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
      metric_name                = "bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: block any single IP sending too many requests in 5 minutes
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
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.project_name}-web-acl"
    Environment = "staging"
    ManagedBy   = "Terraform"
  }
}

output "waf_web_acl_arn" {
  description = "Put this in the alb.ingress.kubernetes.io/wafv2-acl-arn annotation (gitops/app/apps/ui.yaml)"
  value       = aws_wafv2_web_acl.main.arn
}
