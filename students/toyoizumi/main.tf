locals {
  name_prefix = "iac2026-${var.executor_name}"
}

# AMI & AZ Data Sources
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

data "aws_availability_zones" "available" {}

# Network (VPC & Subnets)
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "web" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.31.2.${count.index * 64}/26"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "${local.name_prefix}-web-sn-${count.index}"
  }
}

resource "aws_subnet" "db" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.31.2.${128 + (count.index * 64)}/26"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "${local.name_prefix}-db-sn-${count.index}"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-sng"
  subnet_ids = aws_subnet.db[*].id
}

# IAM & Secrets Manager
resource "aws_secretsmanager_secret" "db_secret" {
  name = "${local.name_prefix}-db-secret"
}

resource "aws_iam_role" "ec2_role" {
  name = "${local.name_prefix}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_policy" {
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Action = "secretsmanager:GetSecretValue", Effect = "Allow", Resource = aws_secretsmanager_secret.db_secret.arn },
      { Action = "logs:PutLogEvents", Effect = "Allow", Resource = "*" }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Compute & Load Balancer
resource "aws_lb" "internal_alb" {
  name               = "${local.name_prefix}-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = aws_subnet.web[*].id
}

resource "aws_instance" "web" {
  count                = 2
  ami                  = data.aws_ami.al2023.id
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  root_block_device {
    volume_size = 10
  }
  tags = {
    Name = "${local.name_prefix}-web-${count.index + 1}"
  }
}

# Database
resource "aws_db_instance" "db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  db_subnet_group_name = aws_db_subnet_group.main.name
  skip_final_snapshot  = true
}