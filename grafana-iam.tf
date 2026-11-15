# ==============================================================================
# Grafana CloudWatch IAM Role (IRSA)
# ==============================================================================

# 1. Least-Privilege IAM Policy for Grafana
resource "aws_iam_policy" "grafana_cloudwatch" {
  name        = "${var.project_name}-grafana-cloudwatch-policy"
  description = "Allows Grafana to read specific CloudWatch metrics and scoped logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Block 1: Actions that AWS forces to be Resource: "*"
        Sid    = "UnscopableCloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetInsightRuleReport",
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "tag:GetResources"
        ]
        Resource = "*"
      },
      {
        # Block 2: Describe operations needed for Grafana's UI dropdowns
        Sid    = "LogGroupDiscovery"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarmsForMetric"
        ]
        Resource = "*"
      },
      {
        # Block 3: STRICTLY SCOPED LOG ACCESS
        # Grafana can only read logs and query data from your specific project's log groups
        Sid    = "ScopedLogDataQuery"
        Effect = "Allow"
        Action = [
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = [
          # Scopes access to your EKS cluster logs
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${var.project_name}*:*",
          # Scopes access to Container Insights logs
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/containerinsights/${var.project_name}*:*",
          # (Optional) Add any custom application log groups here
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/${var.project_name}-logs/*:*"
        ]
      }
    ]
  })
}

# 2. OIDC Trust Policy mapped to the Grafana ServiceAccount
data "aws_iam_policy_document" "grafana_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      # This explicitly locks the role to the Grafana pod in the monitoring namespace
      values = ["system:serviceaccount:monitoring:kube-prometheus-stack-grafana"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [module.eks.oidc_provider_arn]
      type        = "Federated"
    }
  }
}

# 3. The IAM Role itself
resource "aws_iam_role" "grafana_cloudwatch" {
  name               = "${var.project_name}-grafana-cloudwatch-role"
  assume_role_policy = data.aws_iam_policy_document.grafana_trust.json
}

# 4. Attach the policy to the role
resource "aws_iam_role_policy_attachment" "grafana_cloudwatch" {
  policy_arn = aws_iam_policy.grafana_cloudwatch.arn
  role       = aws_iam_role.grafana_cloudwatch.name
}

# 5. Output the ARN to use in your GitOps values.yaml
output "grafana_cloudwatch_role_arn" {
  description = "The ARN of the Grafana CloudWatch IAM role for IRSA"
  value       = aws_iam_role.grafana_cloudwatch.arn
}