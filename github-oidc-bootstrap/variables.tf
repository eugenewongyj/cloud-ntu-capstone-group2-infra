variable "aws_region" {
  type = string
  #default     = "us-east-1"
  default     = "ap-southeast-1"
  description = "AWS region for all resources"
}
variable "prefix" {
  type        = string
  default     = "group2-capstone"
  description = "Prefix for all resources"
}
# variable "name" {
#   type        = string
#   default     = "group2"
#   description = "Name for all resources"
# }

# ==========================================================
# Variables & Outputs
# ==========================================================
variable "github_repository_username" {
  description = "GitHub repository username"
  type        = string
  default     = "eugenewongyj"
}

variable "github_app_repository_name" {
  description = "GitHub repository name for application"
  type        = string
  default     = "cloud-ntu-capstone-group2-app"
}

variable "github_infra_repository_name" {
  description = "GitHub repository name for Terraform infra"
  type        = string
  default     = "cloud-ntu-capstone-group2-infra"
}

variable "tfstate_bucket_name" {
  description = "S3 bucket storing terraform state"
  type        = string
  #default     = "sctp-tfstate-ce13"
  default     = "sctp-core-tfstate"
}
