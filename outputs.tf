###############################################################
# outputs.tf
###############################################################

output "elastic_ip" {
  description = "IP Elástica pública de la instancia WordPress"
  value       = aws_eip.wordpress_eip.public_ip
}

output "instance_id" {
  description = "ID de la instancia EC2"
  value       = aws_instance.wordpress.id
}

output "instance_type" {
  description = "Tipo de instancia utilizado"
  value       = aws_instance.wordpress.instance_type
}

output "ami_id" {
  description = "AMI usada en el despliegue"
  value       = aws_instance.wordpress.ami
}

output "vpc_id" {
  description = "ID de la VPC creada"
  value       = aws_vpc.wordpress_vpc.id
}

output "subnet_id" {
  description = "ID de la subnet pública"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "ID del Security Group de WordPress"
  value       = aws_security_group.wordpress_sg.id
}

output "wordpress_url" {
  description = "URL de acceso a WordPress una vez instalado"
  value       = "http://${aws_eip.wordpress_eip.public_ip}"
}

output "ssh_command" {
  description = "Comando SSH para conectarte a la instancia"
  value       = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_eip.wordpress_eip.public_ip}"
}
