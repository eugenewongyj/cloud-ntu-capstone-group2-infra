# =====================================================================
# Web Application Firewall (WAF) for the shared public ALB.
#
# How it is attached:
#   The ALB is created by EKS Auto Mode (from Kubernetes Ingresses), not by
#   Terraform. The WAF is attached BY NAME with this Ingress annotation in
#   gitops/app/apps/ui.yaml:
#     alb.ingress.kubernetes.io/wafv2-acl-name: group2-capstone-web-acl
#   All websites share ONE ALB (IngressClassParams group "group2-shared"),
#   so attaching it on one Ingress protects all of them.
#   If you rename this Web ACL, update that annotation too.
#
# CloudFront (cloudfront.tf, ADR-0006):
#   - The shop's own WAF with the rate limit now sits on CloudFront.
#   - This ALB WAF has NO rate limit rule any more: behind CloudFront it
#     would see CloudFront's IPs and could block CloudFront in a sale.
#   - Rule 0 locks the shop: requests for group2-retail.sctp-sandbox.com
#     must carry CloudFront's secret X-Origin-Verify header.
#     Argo CD, Grafana and the staging shop are not affected by rule 0.
# =====================================================================

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-web-acl"
  description = "Protects the shared public ALB - shop via CloudFront, Argo CD, Grafana, staging"
  scope       = "REGIONAL" # REGIONAL = for ALBs

  default_action {
    allow {} # let traffic through unless a rule below blocks it
  }

  # Rule 0: the shop only accepts traffic that came through CloudFront.
  # Block if Host = group2-retail.sctp-sandbox.com AND the secret header
  # from CloudFront is missing or wrong.
  rule {
    name     = "ShopOnlyViaCloudFront"
    priority = 0

    action {
      block {}
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            search_string         = local.origin_domain
            positional_constraint = "EXACTLY"
            field_to_match {
              single_header {
                name = "host"
              }
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
        statement {
          not_statement {
            statement {
              byte_match_statement {
                search_string         = random_password.origin_verify.result
                positional_constraint = "EXACTLY"
                field_to_match {
                  single_header {
                    name = lower(local.origin_verify_header)
                  }
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "shop-only-via-cloudfront"
      sampled_requests_enabled   = true
    }
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
