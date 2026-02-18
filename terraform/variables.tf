# Region de despliegue
variable "aws_region" {
  description = "Region de AWS donde se desplegara la infraestructura de Kafka"
  type        = string
  default     = "us-east-1"
}

# Nombre del Par de Llaves (Inyectado desde GitHub Secrets)
variable "ssh_key_name" {
  description = "Nombre del par de llaves .pem para acceso SSH"
  type        = string
}

# Usuario de Docker Hub (Inyectado desde GitHub Secrets)
variable "docker_user" {
  description = "Usuario de Docker Hub para descargar las imagenes de los microservicios"
  type        = string
}

# Nombre del Bucket de Logs para Kafka
variable "bucket_logs_kafka" {
  description = "Nombre unico del bucket S3 para almacenar los eventos procesados"
  type        = string
  default     = "auditoria-kafka-logs-mauro-2026"
}

# Credenciales temporales de AWS Academy (Inyectadas desde GitHub Secrets)
variable "aws_access_key" {
  description = "AWS Access Key ID de la consola de Academy"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key de la consola de Academy"
  type        = string
  sensitive   = true
}

variable "aws_session_token" {
  description = "AWS Session Token de la consola de Academy"
  type        = string
  sensitive   = true
}