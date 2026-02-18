provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket  = "examen-suple-grpc-2026"
    key     = "proyecto-kafka-eda/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

# SEGURIDAD: Security Groups
resource "aws_security_group" "sg_kafka_alb" {
  name        = "sg_kafka_public_access"
  vpc_id      = "vpc-064883582455b57bc" # Asegúrate que este ID sea el de tu VPC actual

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

resource "aws_security_group" "sg_kafka_nodes" {
  name        = "sg_kafka_internal_cluster"
  vpc_id      = "vpc-064883582455b57bc"

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

# INFRAESTRUCTURA: ALB y ASG
resource "aws_lb" "kafka_alb" {
  name               = "alb-sistema-eventos-kafka"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_kafka_alb.id]
  subnets            = ["subnet-06a09282305a420b9", "subnet-075b9f767850567be"] 
}

resource "aws_lb_target_group" "kafka_tg" {
  name     = "tg-gateway-kafka-3000"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = "vpc-064883582455b57bc"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
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

# LANZAMIENTO: EC2 con Docker Compose
resource "aws_launch_template" "kafka_lt" {
  name_prefix   = "lt-nodo-kafka-"
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
                  image: confluentinc/cp-zookeeper:latest
                  environment:
                    ZOOKEEPER_CLIENT_PORT: 2181

                kafka:
                  image: confluentinc/cp-kafka:latest
                  depends_on:
                    - zookeeper
                  environment:
                    KAFKA_BROKER_ID: 1
                    KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
                    KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092,PLAINTEXT_HOST://localhost:9092
                    KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
                    KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
                    KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1

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

resource "aws_autoscaling_group" "kafka_asg" {
  name                = "asg-cluster-eventos-kafka"
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1
  target_group_arns   = [aws_lb_target_group.kafka_tg.arn]
  vpc_zone_identifier = ["subnet-06a09282305a420b9", "subnet-075b9f767850567be"]

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

output "url_balanceador_kafka" {
  value = aws_lb.kafka_alb.dns_name
}