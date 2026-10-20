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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}