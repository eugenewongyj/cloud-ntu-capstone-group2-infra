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