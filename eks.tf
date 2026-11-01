module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = "${var.project_name}-cluster"
  cluster_version = "1.37"

  # Cluster API endpoint access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Connect to VPC created in vpc.tf
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  # -------------------------------------------------------------
  # Compute Mode: EKS Auto Mode
  # Automatically handles node provisioning, patching, and scaling
  # -------------------------------------------------------------
  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  # Grants cluster admin permissions to the role/user executing Terraform
  enable_cluster_creator_admin_permissions = true

  # Enable IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  access_entries = {
    github_app_deployer = {
      principal_arn = "arn:aws:iam::255945442255:role/group2-tk-app-deployer-role"

      policy_associations = {
        retail_edit = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

          access_scope = {
            type = "cluster"
          }
        }
      }
    }
    # 2. Team Member: Eugene Wong
    eugene = {
      principal_arn = "arn:aws:iam::255945442255:user/students/ce13/eugenewongyj"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }

    # 3. Team Member: JoyLearn
    joylearn = {
      principal_arn = "arn:aws:iam::255945442255:user/students/ce13/JoyLearn"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }

    # 4. Team Member: TK / Peh
    peh3 = {
      principal_arn = "arn:aws:iam::255945442255:user/students/ce13/peh3"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }

    # 5. Team Member: tagitables
    tagitables = {
      principal_arn = "arn:aws:iam::255945442255:user/students/ce13/tagitables"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }

    # 6. Team Member: Zeyaul Haq
    zeyaulhaq = {
      principal_arn = "arn:aws:iam::255945442255:user/students/ce13/zeyaulhaq"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }


  tags = {
    Environment = "staging"
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}