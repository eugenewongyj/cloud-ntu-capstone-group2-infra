terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket = "sctp-core-tfstate"
    key    = "tk/group2-tk-infra.tfstate"
    region = "ap-southeast-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
}
