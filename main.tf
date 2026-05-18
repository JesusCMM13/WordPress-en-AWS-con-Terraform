###############################################################
# main.tf — WordPress en EC2 con VPC + Elastic IP (eu-west-1)
###############################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── DATA SOURCES ────────────────────────────────────────────
# Última AMI de Amazon Linux 2023
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── VPC ─────────────────────────────────────────────────────
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, { Name = "${var.project_name}-vpc" })
}

# ─── INTERNET GATEWAY ────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = merge(var.common_tags, { Name = "${var.project_name}-igw" })
}

# ─── SUBNETS ─────────────────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false # usaremos Elastic IP

  tags = merge(var.common_tags, { Name = "${var.project_name}-public-subnet" })
}

# ─── ROUTE TABLE ─────────────────────────────────────────────
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-public-rt" })
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# ─── SECURITY GROUP ──────────────────────────────────────────
resource "aws_security_group" "wordpress_sg" {
  name        = "${var.project_name}-sg"
  description = "Trafico permitido para WordPress"
  vpc_id      = aws_vpc.wordpress_vpc.id

  # SSH (restringe a tu IP en producción)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    # trivy:ignore:aws-0107 - Necesario para que el público acceda a la web
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Todo el trafico saliente"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    # trivy:ignore:aws-0104 - Necesario para descargar actualizaciones de Linux/WordPress
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-sg" })
}

# ─── KEY PAIR ────────────────────────────────────────────────
resource "aws_key_pair" "wordpress_key" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = var.common_tags
}

# ─── EC2 INSTANCE ────────────────────────────────────────────
resource "aws_instance" "wordpress" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  key_name               = aws_key_pair.wordpress_key.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(var.common_tags, { Name = "${var.project_name}-root-volume" })
  }

  user_data = templatefile("${path.module}/userdata.sh", {
    db_name     = var.db_name
    db_user     = var.db_user
    db_password = var.db_password
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Fuerza el uso de tokens (IMDSv2)
    http_put_response_hop_limit = 1
  }

  # Protección anti-borrado accidental
  disable_api_termination = false

  tags = merge(var.common_tags, { Name = "${var.project_name}-ec2" })

  lifecycle {
    ignore_changes = [ami] # no reemplaza la instancia si sale nueva AMI
  }
}

# ─── ELASTIC IP ──────────────────────────────────────────────
resource "aws_eip" "wordpress_eip" {
  domain   = "vpc"
  instance = aws_instance.wordpress.id

  depends_on = [aws_internet_gateway.igw]

  tags = merge(var.common_tags, { Name = "${var.project_name}-eip" })
}

resource "aws_flow_log" "wordpress_vpc_flow_log" {
  log_destination      = aws_s3_bucket.vpc_logs.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"

  vpc_id = aws_vpc.wordpress_vpc.id
}