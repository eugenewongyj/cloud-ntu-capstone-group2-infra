# 1. Dedicated IAM Policy granting Route 53 access
resource "aws_iam_policy" "external_dns" {
  name        = "${var.project_name}-external-dns-policy"
  description = "Allows ExternalDNS to modify Route 53 record sets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "route53:ChangeResourceRecordSets"
        # Scoped specifically to your capstone public hosted zone
        Resource = "arn:aws:route53:::hostedzone/Z00541411T1NGPV97B5C0"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResources"
        ]
        Resource = "*"
      }
    ]
  })
}

# 2. Dedicated NEW IAM Role for ExternalDNS
# Trusts EKS Pod Identity (pods.eks.amazonaws.com)
resource "aws_iam_role" "external_dns" {
  name = "${var.project_name}-external-dns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

# 3. Attach the policy to the new ExternalDNS role
resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

# 4. Map the new Role directly to the Kubernetes ServiceAccount via Pod Identity
resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
}