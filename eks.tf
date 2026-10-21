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

  tags = {
    Environment = "staging"
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}