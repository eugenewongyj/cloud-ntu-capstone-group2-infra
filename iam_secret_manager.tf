#data "aws_caller_identity" "current" {}

# 1. Least-Privilege IAM Policy scoped strictly to the Discord webhook secret
resource "aws_iam_policy" "eso_sre_discord_webhook" {
  name        = "${var.project_name}-eso-sre-discord-webhook-policy"
  description = "Allows External Secrets Operator to read the SRE Alertmanager Discord webhook secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSreDiscordWebhookSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/sre/discord-webhook-??????"
        ]
      }
    ]
  })
}

# 2. Attach the managed policy to the existing ESO IAM Role (defined in aurora-postgres.tf)
resource "aws_iam_role_policy_attachment" "eso_sre_discord_webhook" {
  policy_arn = aws_iam_policy.eso_sre_discord_webhook.arn
  role       = aws_iam_role.eso.name
}

# 3. Output the Policy ARN for reference
output "eso_sre_discord_webhook_policy_arn" {
  description = "The ARN of the least-privilege IAM policy for the SRE Discord webhook secret"
  value       = aws_iam_policy.eso_sre_discord_webhook.arn
}