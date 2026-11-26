# 1. IAM Role assumed by the AWS DevOps Agent Space
resource "aws_iam_role" "devops_agent_space" {
  name = "${var.project_name}-devops-agent-space-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "aidevops.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "devops_agent_space_policy" {
  role       = aws_iam_role.devops_agent_space.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}

# 2. IAM Role for the DevOps Agent Operator Web App
resource "aws_iam_role" "devops_agent_operator" {
  name = "${var.project_name}-devops-agent-operator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "aidevops.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "devops_agent_operator_policy" {
  role       = aws_iam_role.devops_agent_operator.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsOperatorAppAccessPolicy"
}

# Wait 15s for IAM role propagation before Cloud Control API validates the role
resource "time_sleep" "wait_for_devops_agent_iam" {
  depends_on = [
    aws_iam_role_policy_attachment.devops_agent_space_policy,
    aws_iam_role_policy_attachment.devops_agent_operator_policy
  ]
  create_duration = "15s"
}

# 3. AWS DevOps Agent Space (via Cloud Control API)
resource "awscc_devopsagent_agent_space" "capstone" {
  name        = "${var.project_name}-agent-space"
  description = "Automated root-cause investigation space for ${var.project_name} EKS and retail-store"

  depends_on = [time_sleep.wait_for_devops_agent_iam]
}

# 4. Associate this AWS Account with the Agent Space
resource "awscc_devopsagent_association" "aws_account" {
  agent_space_id = awscc_devopsagent_agent_space.capstone.agent_space_id
  service_id     = "aws"

  configuration = {
    aws = {
      account_id         = data.aws_caller_identity.current.account_id
      account_type       = "monitor"
      assumable_role_arn = aws_iam_role.devops_agent_space.arn
    }
  }
}

# 5. Grant Kubernetes API Read/Diagnostic Access on EKS to the Agent Role
resource "aws_eks_access_entry" "devops_agent" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.devops_agent_space.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "devops_agent" {
  cluster_name  = aws_eks_access_entry.devops_agent.cluster_name
  principal_arn = aws_eks_access_entry.devops_agent.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonAIOpsAssistantPolicy"

  access_scope {
    type = "cluster"
  }
}

output "devops_agent_space_id" {
  value = awscc_devopsagent_agent_space.capstone.agent_space_id
}

output "devops_agent_space_arn" {
  value = awscc_devopsagent_agent_space.capstone.arn
}