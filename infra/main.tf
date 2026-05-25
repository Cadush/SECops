terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "instance_type" {
  default = "t3.large" # 2 vCPU, 8GB RAM - mínimo para SecOps
}

variable "key_name" {
  description = "Nome da key pair SSH já existente na AWS"
  type        = string
}

variable "allowed_cidr" {
  description = "CIDR permitido para acessar os dashboards (ex: seu IP/32)"
  type        = string
  default     = "0.0.0.0/0" # ⚠️ Restringir em produção!
}

# AMI Ubuntu 22.04 LTS
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "secops" {
  name        = "secops-server"
  description = "SecOps Pipeline Server"

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # DefectDojo
  ingress {
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # SonarQube
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Dependency-Track
  ingress {
    from_port   = 8080
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Vault
  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "secops" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.secops.id]

  root_block_device {
    volume_size = 50 # GB - imagens Docker + dados
    volume_type = "gp3"
  }

  user_data = file("${path.module}/setup-ec2.sh")

  tags = {
    Name = "secops-server"
  }
}

output "public_ip" {
  value = aws_instance.secops.public_ip
}

output "defectdojo_url" {
  value = "http://${aws_instance.secops.public_ip}:8888"
}

output "sonarqube_url" {
  value = "http://${aws_instance.secops.public_ip}:9000"
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.secops.public_ip}"
}
