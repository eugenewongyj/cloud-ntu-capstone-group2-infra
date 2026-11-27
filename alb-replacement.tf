# Capstone - Terraform-managed replacement ALB
# Existing EKS, VPC, ACM, WAF and CloudFront retained.
# DNS cutover intentionally excluded from phase 1.

variable "replacement_alb_enabled" {
  description = "Enable the replacement shared ALB"
  type        = bool
  default     = true
}

locals {
  replacement_alb_backends = {
    argocd = {
      host    = "group2-capstone-argocd.sctp-sandbox.com"
      path    = "/"
      matcher = "200-399"
      port    = 8080
    }
    grafana = {
      host    = "group2-capstone-grafana.sctp-sandbox.com"
      path    = "/api/health"
      matcher = "200"
      port    = 3000
    }
    staging = {
      host    = "group2-retail-staging.sctp-sandbox.com"
      path    = "/"
      matcher = "200-399"
      port    = 8080
    }
    production = {
      host    = "group2-retail.sctp-sandbox.com"
      path    = "/"
      matcher = "200-399"
      port    = 8080
    }
  }

  replacement_alb_active_backends = (
    var.replacement_alb_enabled
    ? local.replacement_alb_backends
    : {}
  )
}

resource "aws_security_group" "replacement_alb" {
  count       = var.replacement_alb_enabled ? 1 : 0
  name_prefix = "group2-replacement-alb-"
  description = "Capstone replacement shared ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Public HTTP redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Public HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Backend traffic within Capstone VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = {
    Name      = "group2-replacement-alb-sg"
    ManagedBy = "Terraform"
    component = "infra"
  }
}

resource "aws_lb" "replacement" {
  count              = var.replacement_alb_enabled ? 1 : 0
  name               = "group2-replacement-alb"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"

  security_groups = [
    aws_security_group.replacement_alb[0].id
  ]

  subnets = aws_subnet.public[*].id

  drop_invalid_header_fields = true

  tags = {
    Name      = "group2-replacement-alb"
    ManagedBy = "Terraform"
    component = "infra"
  }
}

resource "aws_lb_target_group" "replacement" {
  for_each = local.replacement_alb_active_backends

  name        = "group2-repl-${each.key}"
  port        = each.value.port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = each.value.path
    matcher             = each.value.matcher
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name      = "group2-repl-${each.key}"
    ManagedBy = "Terraform"
    component = "infra"
  }
}

resource "aws_lb_listener" "replacement_http" {
  count             = var.replacement_alb_enabled ? 1 : 0
  load_balancer_arn = aws_lb.replacement[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "replacement_https" {
  count             = var.replacement_alb_enabled ? 1 : 0
  load_balancer_arn = aws_lb.replacement[0].arn
  port              = 443
  protocol          = "HTTPS"

  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  certificate_arn = (
    aws_acm_certificate_validation.cert.certificate_arn
  )

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "replacement" {
  for_each = local.replacement_alb_active_backends

  listener_arn = aws_lb_listener.replacement_https[0].arn

  priority = (
    index(sort(keys(local.replacement_alb_backends)), each.key) + 10
  )

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.replacement[each.key].arn
  }

  condition {
    host_header {
      values = [each.value.host]
    }
  }
}

resource "aws_wafv2_web_acl_association" "replacement" {
  count        = var.replacement_alb_enabled ? 1 : 0
  resource_arn = aws_lb.replacement[0].arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

output "replacement_alb_dns_name" {
  value = try(aws_lb.replacement[0].dns_name, null)
}

output "replacement_alb_zone_id" {
  value = try(aws_lb.replacement[0].zone_id, null)
}

output "replacement_alb_security_group_id" {
  value = try(aws_security_group.replacement_alb[0].id, null)
}

output "replacement_alb_target_group_arns" {
  value = {
    for key, tg in aws_lb_target_group.replacement :
    key => tg.arn
  }
}
