terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket = "sctp-core-tfstate"
    key    = "group2/cloud-ntu-capstone-group2-infra.tfstate"
    region = "ap-southeast-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.110" # needed for OpenSearch Serverless collection groups (opensearch.tf)
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project = var.project
    }
  }
}

# AWS Cloud Control provider (used for OpenSearch Serverless collection groups)
provider "awscc" {
  region = var.aws_region
}

# Second AWS provider for us-east-1 (N. Virginia).
# CloudFront only accepts certificates and WAF Web ACLs from us-east-1
# (cloudfront.tf). No customer data lives there.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project = var.project
    }
  }
}
