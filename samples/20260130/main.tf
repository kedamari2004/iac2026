data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az1 = data.aws_availability_zones.available.names[0]
  az2 = data.aws_availability_zones.available.names[1]

  base_name        = "${var.name_prefix}-${var.executor_name}"
  alb_ingress_cidr = coalesce(var.allowed_http_cidr, var.vpc_cidr)

  # /24 VPC でも動くように /28 を切り出す（AWS Subnet 最小 /28）
  # 例: VPC /16 -> newbits=12, VPC /24 -> newbits=4
  vpc_prefix_len = tonumber(split("/", var.vpc_cidr)[1])
  subnet_newbits = max(0, 28 - local.vpc_prefix_len)
}

# -----------------------------
# VPC / IGW
# -----------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.base_name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.base_name}-igw" }
}

# -----------------------------
# Subnets (VPCから /28 を6つ作る: netnum 0〜5)
# -----------------------------
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, local.subnet_newbits, 0)
  availability_zone       = local.az1
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.base_name}-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, local.subnet_newbits, 1)
  availability_zone       = local.az2
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.base_name}-public-2" }
}

resource "aws_subnet" "private_app_1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, local.subnet_newbits, 2)
  availability_zone = local.az1
  tags              = { Name = "${local.base_name}-private-app-1" }
}

resource "aws_subnet" "private_app_2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, local.subnet_newbits, 3)
  availability_zone = local.az2
  tags              = { Name = "${local.base_name}-private-app-2" }
}

resource "aws_subnet" "private_db_1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, local.subnet_newbits, 4)
  availability_zone = local.az1
  tags              = { Name = "${local.base_name}-private-db-1" }
}

resource "aws_subnet" "private_db_2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, local.subnet_newbits, 5)
  availability_zone = local.az2
  tags              = { Name = "${local.base_name}-private-db-2" }
}

# -----------------------------
# Route Tables + NAT GW（Privateからインターネットアウトバウンド用）
# -----------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.base_name}-rt-public" }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.base_name}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
  tags          = { Name = "${local.base_name}-natgw" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${local.base_name}-rt-private" }
}

resource "aws_route_table_association" "private_app_1" {
  subnet_id      = aws_subnet.private_app_1.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private_app_2" {
  subnet_id      = aws_subnet.private_app_2.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private_db_1" {
  subnet_id      = aws_subnet.private_db_1.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private_db_2" {
  subnet_id      = aws_subnet.private_db_2.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------
# Security Groups
# -----------------------------
resource "aws_security_group" "alb" {
  name        = "${local.base_name}-sg-alb"
  description = "Internal ALB SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.alb_ingress_cidr]
    description = "HTTP from allowed CIDR"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.base_name}-sg-alb" }
}

resource "aws_security_group" "web" {
  name        = "${local.base_name}-sg-web"
  description = "Web EC2 SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTP from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.base_name}-sg-web" }
}

resource "aws_security_group" "rds" {
  name        = "${local.base_name}-sg-rds"
  description = "RDS SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
    description     = "MySQL from web"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.base_name}-sg-rds" }
}

# -----------------------------
# Secrets Manager (DB credentials)
# -----------------------------
resource "random_password" "db" {
  length  = 20
  special = true
}

resource "aws_secretsmanager_secret" "db" {
  name = "${local.base_name}/mysql"
  tags = { Name = "${local.base_name}-secret-db" }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    dbname   = var.db_name
  })
}

# -----------------------------
# IAM Role for Web EC2 (Secret read + CW Logs + SSM)
# -----------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "web" {
  name               = "${local.base_name}-role-web"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = { Name = "${local.base_name}-role-web" }
}

data "aws_iam_policy_document" "web_inline" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [aws_secretsmanager_secret.db.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "web_inline" {
  name   = "${local.base_name}-policy-web-inline"
  role   = aws_iam_role.web.id
  policy = data.aws_iam_policy_document.web_inline.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "web" {
  name = "${local.base_name}-profile-web"
  role = aws_iam_role.web.name
}

# -----------------------------
# Web EC2 x2 (Amazon Linux 2023)
# -----------------------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

locals {
  user_data_min = <<-EOF
    #!/bin/bash
    set -eux
    # 後続Ansibleで httpd+PHP / CW agent / DB初期化などを実施する想定。
  EOF
}

resource "aws_instance" "web1" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type_ec2
  subnet_id              = aws_subnet.private_app_1.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name
  key_name               = var.ssh_key_name
  user_data              = local.user_data_min

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${local.base_name}-web-1" }
}

resource "aws_instance" "web2" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type_ec2
  subnet_id              = aws_subnet.private_app_2.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name
  key_name               = var.ssh_key_name
  user_data              = local.user_data_min

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${local.base_name}-web-2" }
}

# -----------------------------
# Internal ALB + TG + Listener(80)
# -----------------------------
resource "aws_lb" "internal" {
  name               = substr("${local.base_name}-alb", 0, 32)
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.private_app_1.id, aws_subnet.private_app_2.id]
  tags               = { Name = "${local.base_name}-alb" }
}

resource "aws_lb_target_group" "web" {
  name     = substr("${local.base_name}-tg", 0, 32)
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${local.base_name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_target_group_attachment" "web1" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web2" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web2.id
  port             = 80
}

# -----------------------------
# RDS MySQL (single)
# -----------------------------
resource "aws_db_subnet_group" "db" {
  name       = "${local.base_name}-dbsubnet"
  subnet_ids = [aws_subnet.private_db_1.id, aws_subnet.private_db_2.id]
  tags       = { Name = "${local.base_name}-dbsubnet" }
}

resource "aws_db_instance" "mysql" {
  identifier              = "${local.base_name}-mysql"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.instance_type_rds
  allocated_storage       = 20
  storage_type            = "gp3"
  db_name                 = var.db_name
  username                = var.db_username
  password                = random_password.db.result
  port                    = 3306
  publicly_accessible     = false
  multi_az                = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0

  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  tags = { Name = "${local.base_name}-mysql" }
}
