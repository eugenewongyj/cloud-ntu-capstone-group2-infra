# =====================================================================
# Orders events queue: the orders service publishes "order created" events here.
# Pay-per-request: ~$0 when idle, scales automatically during a flash sale.
# (The Project tag is added automatically by default_tags in provider.tf.)
# =====================================================================
resource "aws_sqs_queue" "orders_events" {
  name                       = "${var.project_name}-orders-events"
  message_retention_seconds  = 86400 # 1 day: no consumer yet, keeps the queue small
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true # encryption at rest

  tags = {
    Environment = "staging"
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------------------
# IAM role for the orders pod via EKS Pod Identity: no access keys anywhere
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "orders_pod_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "orders_pod" {
  name               = "${var.project_name}-orders-pod-role"
  assume_role_policy = data.aws_iam_policy_document.orders_pod_trust.json
}

# Least privilege: send to THIS queue only (cannot read, delete or touch other queues)
resource "aws_iam_role_policy" "orders_sqs_send" {
  name = "${var.project_name}-orders-sqs-send"
  role = aws_iam_role.orders_pod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendOrderEventsOnly"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.orders_events.arn
      }
    ]
  })
}

# Link: pods using service account "orders" in retail-store get the role above
resource "aws_eks_pod_identity_association" "orders" {
  cluster_name    = module.eks.cluster_name
  namespace       = var.orders_namespace
  service_account = "orders"
  role_arn        = aws_iam_role.orders_pod.arn
}

output "orders_events_queue_name" {
  description = "Queue name used by the orders service"
  value       = aws_sqs_queue.orders_events.name
}