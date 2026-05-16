###############################################################
# variables.tf
###############################################################

variable "aws_region" {
  description = "Región de AWS"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Nombre del proyecto (usado como prefijo en todos los recursos)"
  type        = string
  default     = "wordpress"
}

# ─── Red ─────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block de la subnet pública"
  type        = string
  default     = "10.0.1.0/24"
}

variable "ssh_allowed_cidr" {
  description = "IP/CIDR desde la que se permite SSH. Cambia a tu IP pública para mayor seguridad"
  type        = string
  default     = "0.0.0.0/0"  # ⚠️ Restringe esto en producción
}

# ─── EC2 ─────────────────────────────────────────────────────
variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.small"   # recomendado para WordPress con algo de tráfico
}

variable "root_volume_size" {
  description = "Tamaño del volumen raíz en GB"
  type        = number
  default     = 20
}

variable "ssh_public_key_path" {
  description = "Ruta a tu clave SSH pública"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# ─── WordPress / MariaDB ─────────────────────────────────────
variable "db_name" {
  description = "Nombre de la base de datos de WordPress"
  type        = string
  default     = "wordpress_db"
}

variable "db_user" {
  description = "Usuario de la base de datos"
  type        = string
  default     = "wp_user"
}

variable "db_password" {
  description = "Contraseña de la base de datos (usa terraform.tfvars o variable de entorno)"
  type        = string
  sensitive   = true
}

# ─── Tags comunes ────────────────────────────────────────────
variable "common_tags" {
  description = "Tags aplicados a todos los recursos"
  type        = map(string)
  default = {
    Project     = "WordPress"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
