data "aws_caller_identity" "current" {}

# 1. Existing GitHub OIDC Provider in AWS
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ==========================================================
# ROLE 1: Infrastructure Pipeline Role (group2-infra)
# ==========================================================
data "aws_iam_policy_document" "infra_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository_username}*/${var.github_infra_repository_name}*:*"]
    }
  }
}

resource "aws_iam_role" "infra_deployer_role" {
  name               = "${var.prefix}-infra-deployer-role"
  assume_role_policy = data.aws_iam_policy_document.infra_trust.json

  tags = {
    Name    = "${var.prefix}-infra-deployer-role"
    Purpose = "CI/CD Role for Terraform Infrastructure Repo"
  }
}

# Scoped Terraform permissions replacing *FullAccess
# Policy Part 1: Core Storage, Compute, Networking, and Database permissions
resource "aws_iam_policy" "infra_scoped_policy_part1" {
  name        = "${var.prefix}-infra-deployer-policy-part1"
  description = "Core EKS, EC2, S3, RDS, and ECR permissions for Terraform"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBTerraformStateLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.prefix}-tflocks-*"
        ]
      },
      {
        Sid    = "S3ScopedAccess"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::${var.prefix}-*",
          "arn:aws:s3:::${var.prefix}-*/*",
          "arn:aws:s3:::${var.tfstate_bucket_name}",
          "arn:aws:s3:::${var.tfstate_bucket_name}/*"
        ]
      },
      {
        Sid    = "EKSClusterAndNodeGroupManagement"
        Effect = "Allow"
        Action = [
          "eks:CreateCluster", "eks:DeleteCluster", "eks:DescribeCluster", "eks:UpdateClusterConfig",
          "eks:UpdateClusterVersion", "eks:CreateNodegroup", "eks:DeleteNodegroup", "eks:DescribeNodegroup",
          "eks:UpdateNodegroupConfig", "eks:UpdateNodegroupVersion", "eks:DescribeUpdate", "eks:TagResource",
          "eks:UntagResource", "eks:ListTagsForResource", "eks:ListClusters", "eks:ListNodegroups",
          "eks:CreateAddon", "eks:DeleteAddon", "eks:DescribeAddon", "eks:UpdateAddon", "eks:CreateAccessEntry",
          "eks:DeleteAccessEntry", "eks:DescribeAccessEntry", "eks:AssociateAccessPolicy", "eks:DisassociateAccessPolicy",
          "eks:CreatePodIdentityAssociation", "eks:DeletePodIdentityAssociation", "eks:DescribePodIdentityAssociation",
          "eks:ListPodIdentityAssociations", "eks:ListAssociatedAccessPolicies", "eks:ListAccessEntries"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRRepoManagement"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories", "ecr:GetRepositoryPolicy",
          "ecr:SetRepositoryPolicy", "ecr:DeleteRepositoryPolicy", "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy", "ecr:TagResource", "ecr:UntagResource", "ecr:ListTagsForResource"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
      {
        # Rule 1: Read-Only / Describe (Must be "*", no conditions)
        Sid      = "EC2NetworkingRead"
        Effect   = "Allow"
        Action   = ["ec2:Describe*"]
        Resource = "*"
      },
      {
        # Rule 2: Creation (Must be "*", but strictly guarded by RequestTag)
        # Terraform can only create these if it applies your group2-tk tag during creation
        Sid    = "EC2NetworkingCreate"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc", "ec2:CreateSubnet", "ec2:CreateRouteTable",
          "ec2:CreateInternetGateway", "ec2:CreateNatGateway", "ec2:AllocateAddress",
          "ec2:CreateSecurityGroup", "ec2:RunInstances", "ec2:CreateTags"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" : var.project
          }
        }
      },
      {
        # Rule 3: Modify/Delete (Must be "*", but strictly guarded by ResourceTag)
        # Terraform can only delete or modify resources that ALREADY have your group2-tk tag
        Sid    = "EC2NetworkingModifyDelete"
        Effect = "Allow"
        Action = [
          "ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
          "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway", "ec2:DeleteNatGateway", "ec2:DeleteSecurityGroup", 
          "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress", 
          "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" : var.project
          }
        }
      },{
        # NEW BLOCK: For actions that target untaggable network associations 
        # or shared EKS security groups that lack the Prefix tag
        Sid    = "EC2UntaggableResources"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags", 
          "ec2:DeleteTags",
          "ec2:AllocateAddress", 
          "ec2:ReleaseAddress", 
          "ec2:AssociateAddress",
          "ec2:DisassociateAddress"
        ]
        Resource = "*"
      },{
        # 1. Authorize the creation of the new tagged resources
        Sid    = "EC2NetworkingCreateTaggedResources"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc", "ec2:CreateSubnet", "ec2:CreateRouteTable",
          "ec2:CreateInternetGateway", "ec2:CreateNatGateway", "ec2:AllocateAddress", 
          "ec2:CreateSecurityGroup", "ec2:RunInstances"
        ]
        Resource = [
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:vpc/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subnet/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:route-table/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:internet-gateway/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:natgateway/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:security-group/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:volume/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:elastic-ip/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project": var.project
          }
        }
      },
      {
        # 2. Authorize placing those resources INSIDE the parent VPC
        Sid    = "EC2NetworkingCreateInsideVpc"
        Effect = "Allow"
        Action = [
          "ec2:CreateSubnet", "ec2:CreateRouteTable",
          "ec2:CreateInternetGateway", "ec2:CreateNatGateway",
          "ec2:CreateSecurityGroup", "ec2:RunInstances"
        ]
        # This targets the existing VPC, not the new resource
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:vpc/*"
        Condition = {
          StringEquals = {
            # Notice this is ResourceTag: it verifies the VPC already has your project tag
            "aws:ResourceTag/Project": var.project 
          }
        }
      },
      {
        Sid    = "RDSClusterAndSubnetGroupManagement"
        Effect = "Allow"
        Action = [
          "rds:CreateDBSubnetGroup", "rds:DeleteDBSubnetGroup", "rds:DescribeDBSubnetGroups", "rds:ModifyDBSubnetGroup",
          "rds:CreateDBCluster", "rds:DeleteDBCluster", "rds:DescribeDBClusters", "rds:DescribeGlobalClusters",
          "rds:ModifyDBCluster", "rds:CreateDBInstance", "rds:DeleteDBInstance", "rds:DescribeDBInstances",
          "rds:ModifyDBInstance", "rds:ListTagsForResource", "rds:AddTagsToResource", "rds:RemoveTagsFromResource",
          "rds:DescribeDBClusterSnapshots", "rds:DescribeDBClusterEndpoints"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy Part 2: IAM, Route53, KMS, Secrets Manager, and Logging permissions
resource "aws_iam_policy" "infra_scoped_policy_part2" {
  name        = "${var.prefix}-infra-deployer-policy-part2"
  description = "IAM, Route53, KMS, Secrets, and Logging permissions for Terraform"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ACMCertificateManagement"
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate",
          "acm:DescribeCertificate",
          "acm:DeleteCertificate",
          "acm:ListCertificates",
          "acm:AddTagsToCertificate",
          "acm:RemoveTagsFromCertificate",
          "acm:ListTagsForCertificate",
          "acm:AddTagsToResource",
          "acm:RemoveTagsFromResource",
          "acm:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53CertificateValidation"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:GetHostedZone",
          "route53:ChangeResourceRecordSets",
          "route53:GetChange",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerManagement"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:DescribeSecret",
          "secretsmanager:GetResourcePolicy", "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret", "secretsmanager:TagResource", "secretsmanager:UntagResource",
          "secretsmanager:RestoreSecret", "secretsmanager:ListSecrets"
        ]
        # Only allow access to secrets starting with your project prefix
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.prefix}-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.prefix}/*",
          # ADDED: Allow RDS to auto-generate managed passwords
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:rds!*"
        ]
      },
      {
        Sid    = "LogsManagement"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups", "logs:CreateLogGroup", "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy", "logs:ListTagsForResource", "logs:TagResource", "logs:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMScopedToPrefix"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:CreatePolicy",
          "iam:DeletePolicy", "iam:GetPolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:TagRole",
          "iam:UntagRole", "iam:TagPolicy", "iam:ListInstanceProfilesForRole", "iam:ListRoleTags", "iam:UntagPolicy",
          "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.prefix}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.prefix}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/*"
        ]
      },
      {
        Sid      = "PassRoleForEKSServices"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.prefix}-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" : [
              "eks.amazonaws.com",
              "ec2.amazonaws.com",
              "pods.eks.amazonaws.com"
            ]
          }
        }
      },
      {
        # Block 1: Creating keys requires the RequestTag
        Sid      = "KMSCreateAndTag"
        Effect   = "Allow"
        Action   = ["kms:CreateKey", "kms:TagResource"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" : var.project
          }
        }
      },
      {
        # Block 2: Modifying existing keys requires the ResourceTag
        Sid    = "KMSManageExistingKeys"
        Effect = "Allow"
        Action = [
          "kms:EnableKey", "kms:EnableKeyRotation",
          "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:PutKeyPolicy",
          "kms:ScheduleKeyDeletion", "kms:UntagResource", "kms:UpdateKeyDescription"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" : var.project
          }
        }
      },
      {
        # Block 3: Aliases, reading, and grants do not support tag conditions
        Sid    = "KMSAliasesAndUsage"
        Effect = "Allow"
        Action = [
          "kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias", "kms:ListAliases",
          "kms:DescribeKey", "kms:ListResourceTags",
          "kms:CreateGrant", "kms:RetireGrant", "kms:Decrypt", "kms:GenerateDataKey*"
        ]
        Resource = "*"
      },
      # SQS: application messaging queues, scoped to project prefix
      {
        Sid    = "SQSScopedToProject"
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue",
          "sqs:DeleteQueue",
          "sqs:GetQueueAttributes",
          "sqs:SetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:TagQueue",
          "sqs:UntagQueue",
          "sqs:ListQueueTags"
        ]
        Resource = "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:group2-capstone-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_scoped_attach_part1" {
  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = aws_iam_policy.infra_scoped_policy_part1.arn
}

resource "aws_iam_role_policy_attachment" "infra_scoped_attach_part2" {
  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = aws_iam_policy.infra_scoped_policy_part2.arn
}

# ---------------------------------------------------------------------
# Separate policy for application messaging (SQS).
# Kept apart from infra_scoped_policy because IAM managed policies are
# limited to 6,144 characters.
# ---------------------------------------------------------------------
resource "aws_iam_policy" "infra_messaging_policy" {
  name        = "${var.prefix}-infra-deployer-messaging"
  description = "Allow the infra pipeline to manage project SQS queues"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSScopedToProject"
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue",
          "sqs:DeleteQueue",
          "sqs:GetQueueAttributes",
          "sqs:SetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:TagQueue",
          "sqs:UntagQueue",
          "sqs:ListQueueTags"
        ]
        Resource = "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:group2-capstone-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_messaging_attach" {
  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = aws_iam_policy.infra_messaging_policy.arn
}

# ==========================================================
# ROLE 2: Application Pipeline Role (group2-app)
# ==========================================================
data "aws_iam_policy_document" "app_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository_username}*/${var.github_app_repository_name}*:*"]
    }
  }
}

resource "aws_iam_role" "app_deployer_role" {
  name               = "${var.prefix}-app-deployer-role"
  assume_role_policy = data.aws_iam_policy_document.app_trust.json

  tags = {
    Name    = "${var.prefix}-app-deployer-role"
    Purpose = "CI/CD Role for Container App Deployment to EKS"
  }
}

# Scoped App deployment permissions for ECR and EKS deployments
resource "aws_iam_policy" "app_scoped_policy" {
  name        = "${var.prefix}-app-deployer-least-privilege"
  description = "Scoped permissions strictly required for ECR image push and EKS cluster deployment"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 1. ECR Auth Token (must be Resource: "*")
      {
        Sid    = "ECRAuthToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      # 2. Push rights restricted to Retail Store microservice ECR repos
      {
        Sid    = "ECRPushRestricted"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.prefix}-*"
        ]
      },
      # 3. EKS DescribeCluster (required for `aws eks update-kubeconfig`)
      {
        Sid    = "EKSClusterDescribe"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = [
          "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/*${var.prefix}*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_scoped_attach" {
  role       = aws_iam_role.app_deployer_role.name
  policy_arn = aws_iam_policy.app_scoped_policy.arn
}