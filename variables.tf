variable "aws_region" {
  type        = string
  default     = "ap-southeast-1"
  description = "Target AWS region"
}

variable "project_name" {
  type        = string
  description = "Prefix for tagging resources"
  default     = "group2-tk"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "database_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for isolated database subnets"
  default     = ["10.0.5.0/24", "10.0.6.0/24"]
}

variable "aurora_db_name" {
  type        = string
  description = "Initial database name for the Aurora MySQL cluster"
  default     = "Catalog"
}

variable "aurora_master_username" {
  type        = string
  description = "Master username for the Aurora MySQL cluster"
  default     = "dbadmin"
}

variable "aurora_min_capacity" {
  type        = number
  description = "Minimum Aurora Serverless v2 capacity in ACUs"
  default     = 0.5
}

variable "aurora_max_capacity" {
  type        = number
  description = "Maximum Aurora Serverless v2 capacity in ACUs"
  default     = 1
}

variable "aurora_engine_version" {
  type        = string
  description = "Aurora MySQL engine version (Data API on Serverless v2 requires 3.07+)"
  default     = "8.0.mysql_aurora.3.08.2"
}

variable "aurora_instance_count" {
  type        = number
  description = "Number of Aurora Serverless v2 instances (1 writer + n-1 readers)"
  default     = 2
}

variable "aurora_backup_retention_days" {
  type        = number
  description = "Days to retain automated Aurora backups"
  default     = 1
}