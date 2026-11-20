# 0. Look up available AZs in the region
# data "aws_availability_zones" "aws_az" {
#   state = "available"
# }

# 1. Create VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    environment = "common"
    component   = "infra"
  }
}

# 2. Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    environment = "common"
    component   = "infra"
  }
}

# 3. Public Subnets (Dynamically mapped across available AZs)
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.aws_az.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.project_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb" = "1" # Required by AWS Load Balancer Controller for public internet-facing ALBs
    environment              = "common"
    component                = "infra"
  }
}

# 4. Private Subnets (Dynamically mapped across available AZs)
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.aws_az.names[count.index]

  tags = {
    Name                              = "${var.project_name}-private-subnet-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1" # Required by AWS Load Balancer Controller for internal NLBs/ALBs
    environment                       = "common"
    component                         = "infra"
  }
}

# 5. Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    environment = "common"
    component   = "infra"
  }
}

# 6. Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# High availability: ONE NAT Gateway PER AZ (one in each public subnet).
# Each private subnet sends internet traffic to the NAT in its OWN AZ,
# so if one AZ (or its NAT) fails, the other AZ keeps working.

# 1. Allocate one Elastic IP per NAT Gateway
resource "aws_eip" "nat" {
  count  = length(var.private_subnet_cidrs)
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-nat-eip-${count.index + 1}"
    environment = "common"
    component   = "infra"
  }
}

# 2. One NAT Gateway in EACH public subnet (AZ-a and AZ-b)
resource "aws_nat_gateway" "main" {
  count         = length(var.private_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "${var.project_name}-nat-gw-${count.index + 1}"
    environment = "common"
    component   = "infra"
  }

  # Ensure IGW exists before creating NAT GW to avoid provisioning errors
  depends_on = [aws_internet_gateway.igw]
}

# 3. One Private Route Table PER AZ, each pointing at its own AZ's NAT
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name        = "${var.project_name}-private-rt-${count.index + 1}"
    environment = "common"
    component   = "infra"
  }
}

# 4. Associate each Private Subnet with the Route Table of its own AZ
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Keep the EXISTING NAT, EIP and route table (now index [0]) instead of
# destroying and recreating them when they moved from single to count.
moved {
  from = aws_eip.nat
  to   = aws_eip.nat[0]
}

moved {
  from = aws_nat_gateway.main
  to   = aws_nat_gateway.main[0]
}

moved {
  from = aws_route_table.private
  to   = aws_route_table.private[0]
}

# Free Gateway VPC Endpoints: traffic to DynamoDB (carts) and S3 (e.g. ECR
# image layers) stays on the AWS network instead of going through the NAT.
# This saves NAT data charges and keeps working even if a NAT is down.
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name        = "${var.project_name}-dynamodb-endpoint"
    environment = "common"
    component   = "infra"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name        = "${var.project_name}-s3-endpoint"
    environment = "common"
    component   = "infra"
  }
}

# 5. Database Subnets (Dynamically mapped across available AZs, isolated from internet)
resource "aws_subnet" "database" {
  count             = length(var.database_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.aws_az.names[count.index]

  tags = {
    Name        = "${var.project_name}-database-subnet-${count.index + 1}"
    environment = "common"
    component   = "infra"
  }
}

# 6. Database Route Table (no 0.0.0.0/0 route: VPC-local traffic only)
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-database-rt"
    environment = "common"
    component   = "infra"
  }
}

# 7. Associate Database Subnets with the Database Route Table
resource "aws_route_table_association" "database" {
  count          = length(aws_subnet.database)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}