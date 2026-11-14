# 1. Request the ACM Wildcard Certificate
resource "aws_acm_certificate" "cert" {
  domain_name       = "sctp-sandbox.com"
  validation_method = "DNS"

  subject_alternative_names = [
    "*.sctp-sandbox.com"
  ]

  tags = {
    Environment = "staging"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 2. Automatically create the DNS CNAME records required by ACM using your explicit Zone ID
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
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
  zone_id         = "Z00541411T1NGPV97B5C0" # Hardcoded directly to avoid permission lookups
}

# 3. Wait for the certificate validation to complete
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# 4. Output the ARN for your Ingress annotations
output "acm_certificate_arn" {
  value       = aws_acm_certificate_validation.cert.certificate_arn
  description = "The ARN of the validated ACM wildcard certificate"
}