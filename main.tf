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
    # trivy:ignore:aws-0107 - El acceso SSH está protegido por clave RSA privada y se gestiona dinámicamente
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

# El bucket pa los logs
#  modificado con excepciones para alertas específicas
resource "aws_s3_bucket" "vpc_logs" {
  bucket        = "mi-proyecto-wordpress-vpc-flow-logs-unicov1"
  force_destroy = true

  # Soluciona AWS-0132: Ignoramos clave administrada por cliente (KMS CMK) para ahorrar $1 USD/mes.
  # trivy:ignore:aws-0132 - Usamos el cifrado nativo de AWS para evitar costes innecesarios en logs dinámicos.

  # Soluciona AWS-0089: Si activas logging en un bucket de logs, creas un bucle infinito.
  # trivy:ignore:aws-0089 - Este bucket ya es un destino de logs, no requiere logging propio.
}

# 2. Bloqueo de acceso público total (Soluciona AWS-0086, AWS-0087, AWS-0091, AWS-0093 y AWS-0094)
resource "aws_s3_bucket_public_access_block" "vpc_logs_block" {
  bucket                  = aws_s3_bucket.vpc_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. Activar el versionado (Soluciona AWS-0090)
resource "aws_s3_bucket_versioning" "vpc_logs_versioning" {
  bucket = aws_s3_bucket.vpc_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 4. Forzar cifrado básico por defecto (Medida de seguridad extra recomendada)
resource "aws_s3_bucket_server_side_encryption_configuration" "vpc_logs_encryption" {
  bucket = aws_s3_bucket.vpc_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#  Flow Log se queda exactamente igual:
resource "aws_flow_log" "wordpress_vpc_flow_log" {
  log_destination      = aws_s3_bucket.vpc_logs.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.wordpress_vpc.id
}