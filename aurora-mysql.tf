# 1. DB Subnet Group (Aurora lives in the isolated database subnets)
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project_name}-aurora-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name        = "${var.project_name}-aurora-subnet-group"
    environment = "prod"
    component   = "apps"
  }
}

# 2. Security Group (MySQL access from anywhere inside the VPC)
resource "aws_security_group" "aurora" {
  name        = "${var.project_name}-aurora-sg"
  description = "Allow MySQL access from within the VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-aurora-sg"
    environment = "prod"
    component   = "apps"
  }
}

# 3. Aurora MySQL Cluster (Serverless v2)
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${var.project_name}-aurora-mysql"
  engine             = "aurora-mysql"
  engine_mode        = "provisioned" # Serverless v2 uses provisioned mode + db.serverless instances
  engine_version     = var.aurora_engine_version
  database_name      = var.aurora_db_name
  master_username    = var.aurora_master_username

  # Master password is generated and rotated by AWS in Secrets Manager (never stored in tfstate)
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]
  storage_encrypted      = true

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  # Data API (Query Editor / SDK access without VPC connectivity)
  enable_http_endpoint = true

  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  backup_retention_period = var.aurora_backup_retention_days
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true

  tags = {
    Name        = "${var.project_name}-aurora-mysql"
    environment = "prod"
    component   = "apps"
  }
}

# 4. Serverless v2 Instances (1 writer + readers spread across AZs; AWS picks the writer, not necessarily index 0)
resource "aws_rds_cluster_instance" "aurora" {
  count              = var.aurora_instance_count
  identifier         = "${var.project_name}-aurora-mysql-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
  # Pin instances to AZs so writer and reader are spread across AZs (cluster survives an AZ outage).
  # Instance N goes to the AZ of database subnet N; "%" wraps extra instances back onto AZs
  # that have a database subnet, since the subnet group has no subnet in any other AZ.
  availability_zone   = data.aws_availability_zones.aws_az.names[count.index % length(var.database_subnet_cidrs)]
  publicly_accessible = false
  apply_immediately   = true

  tags = {
    Name        = "${var.project_name}-aurora-mysql-${count.index + 1}"
    environment = "prod"
    component   = "apps"
  }
}