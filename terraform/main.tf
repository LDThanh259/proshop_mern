#terraform {
#  required_providers {
#    aws = {
#      source  = "hashicorp/aws"
#      version = "~> 5.0"
#    }
#  }
#}

provider "aws" {
  # Region triển khai EC2
  region = var.aws_region
}

resource "aws_security_group" "capstone_sg" {
  # Security Group cho server capstone
  name        = "capstone-sg"
  description = "Security group for ProShop capstone"

  ingress {
    # Chỉ cho phép SSH từ IP quản trị
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip_cidr]
  }

  ingress {
    # Mở HTTP cho public traffic
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    # Mở HTTPS để sẵn sàng bật TLS về sau
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    # Cho phép server đi ra Internet để cài package và pull image
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "capstone" {
  # EC2 chạy toàn bộ app và monitoring
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids  = [aws_security_group.capstone_sg.id]
  # Tự động cài Docker khi máy vừa boot
  user_data              = file("${path.module}/user_data.sh")

  root_block_device {
    # Disk gốc cho hệ điều hành và Docker data
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = {
    # Tên dễ nhận diện trên AWS Console
    Name = "capstone-server"
  }
}
