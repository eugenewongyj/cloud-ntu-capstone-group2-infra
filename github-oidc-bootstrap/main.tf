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
          "eks:CreateAddon", "eks:DeleteAddon", "eks:DescribeAddon", "eks:UpdateAddon",
          "eks:DescribeAddonVersions", "eks:DescribeAddonConfiguration",
          "eks:CreateAccessEntry", "eks:DeleteAccessEntry", "eks:DescribeAccessEntry",
          "eks:AssociateAccessPolicy", "eks:DisassociateAccessPolicy",
          "eks:CreatePodIdentityAssociation", "eks:DeletePodIdentityAssociation", "eks:DescribePodIdentityAssociation",
        "eks:ListPodIdentityAssociations", "eks:ListAssociatedAccessPolicies", "eks:ListAccessEntries"]
        Resource = "*"
      },
      {
        Sid    = "ECRRepoManagement"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories", "ecr:GetRepositoryPolicy",
          "ecr:SetRepositoryPolicy", "ecr:DeleteRepositoryPolicy", "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy", "ecr:TagResource", "ecr:UntagResource", "ecr:ListTagsForResource",
          "ecr:DescribeImages"
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
        Sid    = "EC2NetworkingModifyDelete"
        Effect = "Allow"
        Action = [
          "ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
          "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable", "ec2:ReplaceRouteTableAssociation",
          "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway",
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
        }, {
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
        }, {
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
            "aws:RequestTag/Project" : var.project
          }
        }
      },
      {
        # 2a. Authorize associating new resources with existing TAGGED parent resources
        Sid    = "EC2NetworkingCreateInsideParentTagged"
        Effect = "Allow"
        Action = [
          "ec2:CreateSubnet", "ec2:CreateRouteTable",
          "ec2:CreateInternetGateway", "ec2:CreateNatGateway",
          "ec2:CreateSecurityGroup", "ec2:RunInstances"
        ]
        Resource = [
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:vpc/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subnet/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:security-group/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" : var.project
          }
        }
      },
      {
        # 2b. Authorize linking to resources where AWS drops tag context or doesn't own the resource
        Sid    = "EC2NetworkingCreateInsideParentUntagged"
        Effect = "Allow"
        Action = [
          "ec2:CreateNatGateway",
          "ec2:RunInstances"
        ]
        Resource = [
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:elastic-ip/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:image/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key-pair/*"
        ]
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
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.prefix}-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.prefix}/*",
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
          "iam:UpdateAssumeRolePolicy", # <-- ADDED: Allows updating IRSA/OIDC trust policies
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:CreatePolicy",
          "iam:DeletePolicy", "iam:GetPolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:TagRole",
          "iam:UntagRole", "iam:TagPolicy", "iam:ListInstanceProfilesForRole", "iam:ListRoleTags", "iam:UntagPolicy",
          "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint", "iam:AddClientIDToOpenIDConnectProvider", "iam:RemoveClientIDFromOpenIDConnectProvider",
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
        Sid    = "KMSAliasesAndUsage"
        Effect = "Allow"
        Action = [
          "kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias", "kms:ListAliases",
          "kms:DescribeKey", "kms:ListResourceTags",
          "kms:CreateGrant", "kms:RetireGrant", "kms:Decrypt", "kms:GenerateDataKey*"
        ]
        Resource = "*"
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

resource "aws_iam_policy" "infra_tagging_guard_policy" {
  name        = "group2-capstone-infra-deployer-tagging-guard"
  description = "Allows Resource Groups Tagging API audit and remediation for capstone cluster resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ResourceGroupsTaggingAuditAndRemediate"
        Effect = "Allow"
        Action = [
          "tag:GetResources",
          "tag:GetTagKeys",
          "tag:GetTagValues",
          "tag:TagResources"
        ]
        Resource = "*"
      },
      {
        Sid    = "ServiceLevelTaggingForDynamicK8sAssets"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DescribeTags",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_tagging_guard_attach" {
  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = aws_iam_policy.infra_tagging_guard_policy.arn
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

# ---------------------------------------------------------------------
# Separate policy for OpenSearch Serverless (catalog search, opensearch.tf).
# Kept apart for the same 6,144-character managed policy limit.
# ---------------------------------------------------------------------
resource "aws_iam_policy" "infra_search_policy" {
  name        = "${var.prefix}-infra-deployer-search"
  description = "Allow the infra pipeline to manage OpenSearch Serverless for the catalog"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # AOSS policies and VPC endpoints have no ARNs, so Resource must be "*"
        Sid      = "OpenSearchServerlessManagement"
        Effect   = "Allow"
        Action   = ["aoss:*"]
        Resource = "*"
      },
      {
        # The awscc provider calls AWS through the Cloud Control API
        Sid    = "CloudControlApi"
        Effect = "Allow"
        Action = [
          "cloudformation:CreateResource",
          "cloudformation:GetResource",
          "cloudformation:UpdateResource",
          "cloudformation:DeleteResource",
          "cloudformation:GetResourceRequestStatus",
          "cloudformation:ListResources"
        ]
        Resource = "*"
      },
      {
        # Creating an AOSS VPC endpoint creates an EC2 interface endpoint + private DNS on our behalf
        Sid    = "AossVpcEndpointDependencies"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpcEndpoint",
          "ec2:DeleteVpcEndpoints",
          "ec2:ModifyVpcEndpoint",
          "ec2:DescribeVpcEndpoints",
          "route53:CreateHostedZone",
          "route53:DeleteHostedZone",
          "route53:GetHostedZone",
          "route53:ListHostedZonesByName",
          "route53:ListHostedZonesByVPC",
          "route53:AssociateVPCWithHostedZone",
          "route53:DisassociateVPCFromHostedZone",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:GetChange"
        ]
        Resource = "*"
      },
      {
        # First AOSS collection in the account creates its service-linked role
        Sid      = "AossServiceLinkedRole"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/observability.aoss.amazonaws.com/*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "observability.aoss.amazonaws.com" }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_search_attach" {
  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = aws_iam_policy.infra_search_policy.arn
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

# ---------------------------------------------------------------------
# Infra pipeline: DynamoDB + DAX for the cart service (dynamodb-dax.tf).
# Separate policy because IAM managed policies are limited to 6,144 characters.
# ---------------------------------------------------------------------
resource "aws_iam_policy" "infra_cart_data_policy" {
  name        = "${var.prefix}-infra-deployer-cart-data"
  description = "Allow the infra pipeline to manage the cart DynamoDB table and DAX cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBCartTable"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:UpdateContinuousBackups",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:ListTagsOfResource",
          "dynamodb:TagResource",
          "dynamodb:UntagResource"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.prefix}-*"
        ]
      },
      {
        # DAX subnet/parameter groups have no ARNs, so Resource must be "*"
        Sid    = "DAXManagement"
        Effect = "Allow"
        Action = [
          "dax:CreateCluster",
          "dax:DeleteCluster",
          "dax:DescribeClusters",
          "dax:UpdateCluster",
          "dax:IncreaseReplicationFactor",
          "dax:DecreaseReplicationFactor",
          "dax:CreateSubnetGroup",
          "dax:DeleteSubnetGroup",
          "dax:DescribeSubnetGroups",
          "dax:UpdateSubnetGroup",
          "dax:CreateParameterGroup",
          "dax:DeleteParameterGroup",
          "dax:DescribeParameterGroups",
          "dax:DescribeParameters",
          "dax:UpdateParameterGroup",
          "dax:TagResource",
          "dax:UntagResource",
          "dax:ListTags"
        ]
        Resource = "*"
      },
      {
        # DAX assumes a service role to reach the table; Terraform must be allowed to hand it over
        Sid      = "PassRoleToDAX"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.prefix}-*"
        Condition = {
          StringEquals = { "iam:PassedToService" = "dax.amazonaws.com" }
        }
      },
      {
        # First DAX cluster in the account creates its service-linked role
        Sid      = "DAXServiceLinkedRole"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/dax.amazonaws.com/*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "dax.amazonaws.com" }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_cart_data_attach" {
  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = aws_iam_policy.infra_cart_data_policy.arn
}


# ---------------------------------------------------------------------
# Infra pipeline: ElastiCache Serverless for the checkout service (elasticache.tf).
# Separate policy because IAM managed policies are limited to 6,144 characters.
# ---------------------------------------------------------------------
resource "aws_iam_policy" "infra_checkout_cache_policy" {
  name        = "${var.prefix}-infra-deployer-checkout-cache"
  description = "Allow the infra pipeline to manage the checkout ElastiCache Serverless cache"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ElastiCacheServerlessScoped"
        Effect = "Allow"
        Action = [
          "elasticache:CreateServerlessCache",
          "elasticache:DeleteServerlessCache",
          "elasticache:ModifyServerlessCache",
          "elasticache:AddTagsToResource",
          "elasticache:RemoveTagsFromResource",
          "elasticache:ListTagsForResource"
        ]
        Resource = [
          "arn:aws:elasticache:${var.aws_region}:${data.aws_caller_identity.current.account_id}:serverlesscache:${var.prefix}-*",
          "arn:aws:elasticache:${var.aws_region}:${data.aws_caller_identity.current.account_id}:serverlesscachesnapshot:*"
        ]
      },
      {
        # Describe calls do not support resource-level scoping
        Sid    = "ElastiCacheDescribe"
        Effect = "Allow"
        Action = [
          "elasticache:DescribeServerlessCaches",
          "elasticache:DescribeServerlessCacheSnapshots"
        ]
        Resource = "*"
      },
      {
        # Serverless places VPC endpoints in our subnets on our behalf
        Sid    = "ElastiCacheVpcEndpoints"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpcEndpoint",
          "ec2:ModifyVpcEndpoint",
          "ec2:DeleteVpcEndpoints",
          "ec2:DescribeVpcEndpoints"
        ]
        Resource = "*"
      },
      {
        # First ElastiCache resource in the account creates its service-linked role
        Sid      = "ElastiCacheServiceLinkedRole"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/elasticache.amazonaws.com/*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "elasticache.amazonaws.com" }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_checkout_cache_attach" {
  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = aws_iam_policy.infra_checkout_cache_policy.arn
}

# ---------------------------------------------------------------------
# WAF (waf.tf): let the infra pipeline manage the project's Web ACL
# ---------------------------------------------------------------------
resource "aws_iam_policy" "infra_waf_policy" {
  name        = "${var.prefix}-infra-deployer-waf"
  description = "Allow the infra pipeline to manage the project WAF Web ACL"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WafWebAclScoped"
        Effect = "Allow"
        Action = [
          "wafv2:CreateWebACL",
          "wafv2:UpdateWebACL",
          "wafv2:DeleteWebACL",
          "wafv2:GetWebACL",
          "wafv2:TagResource",
          "wafv2:UntagResource",
          "wafv2:ListTagsForResource"
        ]
        Resource = [
          "arn:aws:wafv2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:regional/webacl/${var.prefix}-*/*",
          # AWS managed rule groups used inside the Web ACL
          # (AWS checks these against OUR account id, not "aws")
          "arn:aws:wafv2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:regional/managedruleset/*/*"
        ]
      },
      {
        # List / describe calls do not support resource-level scoping
        Sid    = "WafRead"
        Effect = "Allow"
        Action = [
          "wafv2:ListWebACLs",
          "wafv2:DescribeManagedRuleGroup",
          "wafv2:CheckCapacity"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_waf_attach" {
  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = aws_iam_policy.infra_waf_policy.arn
}
