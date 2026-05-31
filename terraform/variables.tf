variable "aws_region" {
  # Region AWS dùng để tạo tài nguyên
  type    = string
  default = "ap-southeast-2"
}

variable "admin_ip_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "SSH CIDR block, default opens SSH to the Internet for demo use"
}

variable "ami_id" {
  # AMI ID của hệ điều hành dùng cho EC2
  type        = string
  default     = "ami-0f5d1713c9af4fe30"
  description = "EC2 AMI ID"
}

variable "instance_type" {
  # Cỡ máy EC2
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  # Tên key pair SSH trong AWS
  type        = string
  default     = "my-aws-key"
}

variable "root_volume_size" {
  # Dung lượng ổ đĩa gốc tính theo GB
  type    = number
  default = 8
}
