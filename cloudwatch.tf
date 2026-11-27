# --- CloudWatch Log Groups with Explicit Retention ---

locals {
  cw_log_groups = toset([
    "/aws/containerinsights/${var.project_name}-cluster/application",
    "/aws/containerinsights/${var.project_name}-cluster/dataplane",
    "/aws/containerinsights/${var.project_name}-cluster/host",
    "/aws/containerinsights/${var.project_name}-cluster/performance",
  ])
}

resource "aws_cloudwatch_log_group" "container_insights" {
  for_each          = local.cw_log_groups
  name              = each.value
  retention_in_days = 14
}

# --- SNS Alert Topic & Email Subscription ---

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

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
    aws_cloudwatch_log_group.container_insights,
    aws_eks_pod_identity_association.cloudwatch_agent,
    aws_eks_pod_identity_association.fluent_bit
  ]
}

# --- CloudWatch Metric Alarms (ALB, Aurora, DynamoDB, SQS) ---

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
  treat_missing_data  = "notBreaching"
  alarm_description   = "Retail UI p95 latency exceeded ${var.alb_p95_latency_threshold_seconds * 1000}ms SLO"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

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
  treat_missing_data  = "notBreaching"
  alarm_description   = "Aurora MySQL cluster CPU exceeded ${var.aurora_cpu_threshold_percent}%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = "${var.project_name}-aurora-mysql"
  }
}

resource "aws_cloudwatch_metric_alarm" "aurora_pg_cpu" {
  alarm_name          = "${var.project_name}-aurora-pg-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.aurora_cpu_threshold_percent
  treat_missing_data  = "notBreaching"
  alarm_description   = "Aurora PostgreSQL cluster CPU exceeded ${var.aurora_cpu_threshold_percent}%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = "${var.project_name}-aurora-pg"
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
  treat_missing_data  = "notBreaching"
  alarm_description   = "DynamoDB carts table experienced throttled requests"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    TableName = "${var.project_name}-carts"
  }
}

resource "aws_cloudwatch_metric_alarm" "sqs_orders_backlog" {
  alarm_name          = "${var.project_name}-sqs-orders-backlog"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 100
  treat_missing_data  = "notBreaching"
  alarm_description   = "SQS orders queue visible messages exceeded 100"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = "${var.project_name}-orders-events"
  }
}

# --- EKS Node & Retail Store Namespace Alarms (Container Insights) ---

resource "aws_cloudwatch_metric_alarm" "eks_node_cpu_high" {
  alarm_name          = "${var.project_name}-eks-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_description   = "EKS cluster average node CPU utilization exceeded 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = "${var.project_name}-cluster"
  }
}

resource "aws_cloudwatch_metric_alarm" "eks_node_memory_high" {
  alarm_name          = "${var.project_name}-eks-node-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  treat_missing_data  = "notBreaching"
  alarm_description   = "EKS cluster average node memory utilization exceeded 85%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = "${var.project_name}-cluster"
  }
}

resource "aws_cloudwatch_metric_alarm" "retail_store_pod_cpu_high" {
  alarm_name          = "${var.project_name}-retail-store-pod-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "pod_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_description   = "Average pod CPU utilization in ${var.orders_namespace} exceeded 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = "${var.project_name}-cluster"
    Namespace   = var.orders_namespace
  }
}

resource "aws_cloudwatch_metric_alarm" "retail_store_pod_restarts" {
  alarm_name          = "${var.project_name}-retail-store-pod-restarts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "pod_number_of_container_restarts"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "Container restarts detected in ${var.orders_namespace} namespace"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = "${var.project_name}-cluster"
    Namespace   = var.orders_namespace
  }
}

resource "aws_cloudwatch_metric_alarm" "retail_store_running_pods_low" {
  alarm_name          = "${var.project_name}-retail-store-running-pods-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "namespace_number_of_running_pods"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_description   = "Running pods in ${var.orders_namespace} dropped below 1"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = "${var.project_name}-cluster"
    Namespace   = var.orders_namespace
  }
}

# --- CloudWatch Dashboard ---

resource "aws_cloudwatch_dashboard" "capstone" {
  dashboard_name = "${var.project_name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EKS Cluster - Node CPU & Memory Utilization"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", "${var.project_name}-cluster"],
            [".", "node_memory_utilization", ".", "."]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EKS Cluster - Node & Pod Count"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            ["ContainerInsights", "cluster_node_count", "ClusterName", "${var.project_name}-cluster"],
            [".", "cluster_number_of_running_pods", ".", "."]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Aurora MySQL & PG - CPU Utilization (%)"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", "${var.project_name}-aurora-mysql"],
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", "${var.project_name}-aurora-pg"]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "DynamoDB Carts - Consumed Read/Write Capacity"
          region = var.aws_region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "${var.project_name}-carts"],
            [".", "ConsumedWriteCapacityUnits", ".", "."]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "SQS Orders Events - Visible Messages"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.project_name}-orders-events"]
          ]
        }
      }
    ]
  })
}