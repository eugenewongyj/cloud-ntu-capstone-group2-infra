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
  default = "sctp-core-tfstate"
}

variable "project" {
  type        = string
  description = "Prefix for tagging resources"
  default     = "capstone-project-group-02"
}

variable "github_owner_id" {
  description = "Immutable GitHub numeric ID for the repository owner"
  type        = string
  default     = "53294396"
}

variable "github_infra_repo_id" {
  description = "Immutable GitHub numeric ID for the Terraform infra repository"
  type        = string
  default     = "1422914125"
}

variable "github_app_repo_id" {
  description = "Immutable GitHub numeric ID for the application repository"
  type        = string
  default     = "1430670707"
}