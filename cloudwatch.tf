# --- EKS CloudWatch Observability Add-on (Container Insights + App Logs) ---

resource "aws_iam_role" "cloudwatch_observability" {
  name = "${var.project_name}-cw-observability-role"

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
  cluster_name    = "${var.project_name}-cluster"
  namespace       = "amazon-cloudwatch"
  service_account = "cloudwatch-agent"
  role_arn        = aws_iam_role.cloudwatch_observability.arn
}

resource "aws_eks_pod_identity_association" "fluent_bit" {
  cluster_name    = "${var.project_name}-cluster"
  namespace       = "amazon-cloudwatch"
  service_account = "fluent-bit"
  role_arn        = aws_iam_role.cloudwatch_observability.arn
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = "${var.project_name}-cluster"
  addon_name   = "amazon-cloudwatch-observability"

  configuration_values = jsonencode({
    manager = {
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    }
  })

  depends_on = [
    aws_eks_pod_identity_association.cloudwatch_agent,
    aws_eks_pod_identity_association.fluent_bit
  ]
}

# --- CloudWatch Metric Alarms ---

resource "aws_cloudwatch_metric_alarm" "alb_p95_latency_slo" {
  count               = var.alb_arn_suffix != "" ? 1 : 0
  alarm_name          = "${var.project_name}-alb-p95-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p95"
  threshold           = var.alb_p95_latency_threshold_seconds
  alarm_description   = "Retail UI p95 latency exceeded ${var.alb_p95_latency_threshold_seconds * 1000}ms SLO"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "aurora_mysql_cpu" {
  alarm_name          = "${var.project_name}-aurora-mysql-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.aurora_cpu_threshold_percent
  alarm_description   = "Aurora MySQL cluster CPU exceeded ${var.aurora_cpu_threshold_percent}%"

  dimensions = {
    DBClusterIdentifier = "${var.project_name}-aurora-mysql"
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_carts_throttles" {
  alarm_name          = "${var.project_name}-dynamodb-carts-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DynamoDB carts table experienced throttled requests"

  dimensions = {
    TableName = "${var.project_name}-carts"
  }
}