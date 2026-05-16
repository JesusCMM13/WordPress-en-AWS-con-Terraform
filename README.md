# 🚀 WordPress en AWS con Terraform

Infraestructura como código para desplegar WordPress en una instancia EC2 en AWS, incluyendo VPC propia, IP Elástica y configuración automática del servidor.

![Terraform](https://img.shields.io/badge/Terraform-≥1.5-7B42BC?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-eu--west--1-FF9900?logo=amazonaws)
![WordPress](https://img.shields.io/badge/WordPress-latest-21759B?logo=wordpress)
![License](https://img.shields.io/badge/License-MIT-green)

---

## 📐 Arquitectura

```
Internet
    │
    ▼
Elastic IP (estática)
    │
    ▼
┌─────────────────────────────────────┐
│  VPC  10.0.0.0/16   (eu-west-1)     │
│                                     │
│  ┌──────────────────────────────┐   │
│  │  Subnet pública 10.0.1.0/24  │   │
│  │                              │   │
│  │  ┌────────────────────────┐  │   │
│  │  │  EC2 t3.small          │  │   │
│  │  │  Amazon Linux 2023     │  │   │
│  │  │                        │  │   │
│  │  │  ├── Apache 2.4        │  │   │
│  │  │  ├── PHP-FPM 8.2       │  │   │
│  │  │  ├── MariaDB 10.5      │  │   │
│  │  │  └── WordPress latest  │  │   │
│  │  └────────────────────────┘  │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

## ✅ Recursos creados en AWS

| Recurso | Detalle |
|---|---|
| VPC | `10.0.0.0/16` con DNS habilitado |
| Subnet pública | `10.0.1.0/24` en `eu-west-1a` |
| Internet Gateway | Acceso a internet para la subred |
| Route Table | Ruta `0.0.0.0/0` hacia el IGW |
| Security Group | Puertos 22 (SSH), 80 (HTTP), 443 (HTTPS) |
| EC2 | `t3.small`, Amazon Linux 2023, volumen gp3 20GB cifrado |
| Elastic IP | IP pública estática asociada a la instancia |
| Key Pair | Clave SSH importada desde tu máquina |

---

## 📋 Requisitos previos

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [AWS CLI](https://aws.amazon.com/cli/) configurado con credenciales válidas (`aws configure`)
- Par de claves SSH generado en tu máquina (`~/.ssh/id_rsa` y `~/.ssh/id_rsa.pub`)

Verifica que todo está en orden:

```bash
terraform version
aws sts get-caller-identity
ls ~/.ssh/id_rsa.pub
```

---

## 🚀 Despliegue

### 1. Clona el repositorio

```bash
git clone https://github.com/tu-usuario/terraform-wordpress.git
cd terraform-wordpress
```

### 2. Configura tus variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars` con tus valores:

```hcl
db_password         = "TuContraseñaSegura!2024"
ssh_allowed_cidr    = "1.2.3.4/32"   # Tu IP pública (https://whatismyip.com)
ssh_public_key_path = "~/.ssh/id_rsa.pub"
```

### 3. Despliega

```bash
terraform init
terraform plan
terraform apply
```

Al finalizar verás los outputs con la IP y la URL de WordPress:

```
elastic_ip    = "52.x.x.x"
wordpress_url = "http://52.x.x.x"
ssh_command   = "ssh -i ~/.ssh/id_rsa ec2-user@52.x.x.x"
```

### 4. Espera a que WordPress se instale

El script `userdata.sh` instala y configura todo automáticamente. Puedes monitorizar el progreso:

```bash
ssh -i ~/.ssh/id_rsa ec2-user@<ELASTIC_IP>
sudo tail -f /var/log/userdata.log
```

Cuando aparezca `✅ WordPress instalado correctamente.`, accede al asistente:

```
http://<ELASTIC_IP>/wp-admin/install.php
```

---

## 🔒 SSL con Let's Encrypt (opcional)

Necesitas un dominio apuntando a tu Elastic IP. Con [DuckDNS](https://www.duckdns.org) puedes obtener un subdominio gratuito.

```bash
ssh -i ~/.ssh/id_rsa ec2-user@<ELASTIC_IP>

# Instalar Certbot
sudo dnf install -y certbot python3-certbot-apache

# Obtener certificado (sustituye con tu dominio)
sudo certbot --apache -d tudominio.duckdns.org
```

Certbot configura Apache automáticamente y activa la redirección HTTP → HTTPS.

---

## 💰 Coste estimado (eu-west-1)

| Recurso | $/mes | $/día |
|---|---|---|
| EC2 t3.small (on-demand) | ~$15.47 | ~$0.51 |
| Volumen gp3 20GB | ~$1.60 | ~$0.05 |
| Elastic IP (instancia activa) | $0.00 | $0.00 |
| Transferencia saliente (mínima) | ~$0.50 | ~$0.02 |
| **Total** | **~$17.57** | **~$0.58** |

> ⚠️ Si paras la instancia sin liberar la Elastic IP, AWS cobra ~$3.65/mes por la IP reservada.

Para ahorrar costes cuando no uses el entorno:

```bash
# Parar instancia (solo pagas el disco)
aws ec2 stop-instances --instance-ids <INSTANCE_ID> --region eu-west-1

# Arrancar de nuevo
aws ec2 start-instances --instance-ids <INSTANCE_ID> --region eu-west-1
```

---

## 🗑️ Destruir la infraestructura

```bash
terraform destroy
```

---

## 📁 Estructura del proyecto

```
terraform-wordpress/
├── main.tf                    # VPC, EC2, Elastic IP y todos los recursos AWS
├── variables.tf               # Declaración de variables con valores por defecto
├── outputs.tf                 # Outputs: IP, URL, comando SSH...
├── userdata.sh                # Script de instalación automática de WordPress
├── terraform.tfvars.example   # Plantilla de configuración (copiar a terraform.tfvars)
├── .gitignore                 # Excluye terraform.tfvars y ficheros de estado
└── README.md                  # Este fichero
```

---

## ⚙️ Variables disponibles

| Variable | Descripción | Default |
|---|---|---|
| `aws_region` | Región de AWS | `eu-west-1` |
| `project_name` | Prefijo para todos los recursos | `wordpress` |
| `instance_type` | Tipo de instancia EC2 | `t3.small` |
| `root_volume_size` | Tamaño del disco en GB | `20` |
| `vpc_cidr` | CIDR de la VPC | `10.0.0.0/16` |
| `public_subnet_cidr` | CIDR de la subnet pública | `10.0.1.0/24` |
| `ssh_allowed_cidr` | IP/CIDR permitida para SSH | `0.0.0.0/0` |
| `ssh_public_key_path` | Ruta a tu clave pública SSH | `~/.ssh/id_rsa.pub` |
| `db_name` | Nombre de la base de datos | `wordpress_db` |
| `db_user` | Usuario de MariaDB | `wp_user` |
| `db_password` | Contraseña de MariaDB | *(obligatorio)* |

---

## 🔮 Mejoras futuras

### 🤖 Automatización completa del despliegue
Actualmente el asistente de instalación de WordPress requiere configuración manual desde el navegador. El objetivo es completar el despliegue 100% sin intervención humana usando **WP-CLI**:

- Instalación y configuración de WordPress vía línea de comandos
- Creación del usuario administrador, título del sitio y email desde variables de Terraform
- El entorno estaría completamente operativo al terminar el `terraform apply`, sin necesidad de abrir el navegador

### 🌐 Registro automático de dominio con DuckDNS
En lugar de configurar el DNS manualmente, el `userdata.sh` llamaría a la API de DuckDNS para registrar automáticamente la Elastic IP bajo el subdominio deseado:

- El token y subdominio de DuckDNS se añadirían como variables sensibles en `terraform.tfvars`
- Tras registrar el dominio, Certbot se ejecutaría automáticamente para emitir el certificado SSL
- WordPress se configuraría directamente con `https://tusubdominio.duckdns.org` como URL base

### 🗄️ Base de datos en RDS
Migrar MariaDB de la propia EC2 a una instancia **Amazon RDS** para mayor fiabilidad, copias de seguridad automáticas y separación de responsabilidades.

### 📦 ALB + Auto Scaling
Añadir un **Application Load Balancer** y un grupo de Auto Scaling para soportar picos de tráfico y garantizar alta disponibilidad.

### 🪣 Medios en S3
Configurar WordPress para almacenar los uploads en un bucket **S3** en lugar del disco local, lo que facilita el escalado horizontal y reduce el coste del volumen EBS.

### 🔁 Remote State en S3 + DynamoDB
Configurar el **backend remoto de Terraform** para guardar el estado en S3 con bloqueo en DynamoDB, permitiendo trabajar en equipo sin conflictos de estado.

---

## 📄 Licencia

MIT — libre para usar, modificar y distribuir.
