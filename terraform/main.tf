# BLOQUE 1: CONFIGURACION DEL PROVEEDOR Y BACKEND
provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket  = "examen-suple-kafka-2026" 
    key     = "proyecto-kafka-eda/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

# BLOQUE 2: RED POR DEFECTO (VPC Y SUBNETS)
data "aws_vpc" "default" { 
  default = true 
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# BLOQUE 3: SEGURIDAD (SECURITY GROUPS)

# Seguridad para el Balanceador de Entrada
resource "aws_security_group" "sg_kafka_alb" {
  name        = "sg_kafka_public_access"
  description = "Acceso externo al Gateway de eventos"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Seguridad para las instancias del cluster Kafka/App
resource "aws_security_group" "sg_kafka_nodes" {
  name        = "sg_kafka_internal_cluster"
  description = "Comunicacion interna para Kafka y Microservicios"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_kafka_alb.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# BLOQUE 4: BALANCEADOR DE CARGA (ALB)
resource "aws_lb" "kafka_alb" {
  name               = "alb-sistema-eventos-kafka"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_kafka_alb.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "kafka_tg" {
  name     = "tg-gateway-kafka-3000"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path = "/health"
  }
}

resource "aws_lb_listener" "kafka_listener" {
  load_balancer_arn = aws_lb.kafka_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kafka_tg.arn
  }
}

# BLOQUE 5: INFRAESTRUCTURA DE INSTANCIAS (LAUNCH TEMPLATE)
resource "aws_launch_template" "kafka_lt" {
  name_prefix   = "lt-nodo-kafka-eda-"
  image_id      = "ami-0c7217cdde317cfec" 
  instance_type = "t3.medium" 
  key_name      = var.ssh_key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.sg_kafka_nodes.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y docker.io docker-compose
              sudo systemctl start docker

              mkdir -p /home/ubuntu/app && cd /home/ubuntu/app

              cat <<EOT > docker-compose.yml
              version: '3'
              services:
                zookeeper:
                  image: bitnami/zookeeper:latest
                  environment:
                    - ALLOW_ANONYMOUS_LOGIN=yes

                kafka:
                  image: bitnami/kafka:latest
                  environment:
                    - KAFKA_BROKER_ID=1
                    - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
                    - KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092
                    - ALLOW_PLAINTEXT_LISTENER=yes
                  depends_on:
                    - zookeeper

                db-redis-logs:
                  image: redis:latest

                gateway-producer:
                  image: ${var.docker_user}/gateway-kafka:latest
                  ports:
                    - "3000:3000"
                  environment:
                    - KAFKA_BROKER=kafka:9092
                  depends_on:
                    - kafka

                auditoria-consumer:
                  image: ${var.docker_user}/auditoria-kafka:latest
                  environment:
                    - KAFKA_BROKER=kafka:9092
                    - REDIS_HOST=db-redis-logs
                    - BUCKET_NAME=${var.bucket_logs_kafka}
                    - AWS_ACCESS_KEY_ID=${var.aws_access_key}
                    - AWS_SECRET_ACCESS_KEY=${var.aws_secret_key}
                    - AWS_SESSION_TOKEN=${var.aws_session_token}
                  depends_on:
                    - kafka
                    - db-redis-logs
              EOT
              sudo docker-compose up -d
              EOF
  )
}

# BLOQUE 6: GRUPO DE AUTO ESCALAMIENTO (ASG)
resource "aws_autoscaling_group" "kafka_asg" {
  name                = "asg-cluster-eventos-kafka"
  desired_capacity    = 1
  max_size            = 2
  min_size            = 1
  target_group_arns   = [aws_lb_target_group.kafka_tg.arn]
  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.kafka_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "EC2-Kafka-Microservice-Mauro"
    propagate_at_launch = true
  }
}

# BLOQUE 7: ALMACENAMIENTO S3 PARA LOGS PROCESADOS
resource "aws_s3_bucket" "kafka_bucket" {
  bucket        = var.bucket_logs_kafka
  force_destroy = true
}

# BLOQUE 8: SALIDAS (OUTPUTS)
output "url_balanceador_kafka" {
  description = "DNS para conectar el Sender al Gateway Kafka"
  value       = aws_lb.kafka_alb.dns_name
}