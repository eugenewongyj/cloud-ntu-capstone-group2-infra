terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region = "ap-southeast-1" # Add your region here

  default_tags {
    tags = {
      Project = var.project
    }
  }
}