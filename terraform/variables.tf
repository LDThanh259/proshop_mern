variable "aws_region" {
  # Region AWS dùng để tạo tài nguyên
  type    = string
  default = "ap-southeast-1"
}

variable "admin_ip_cidr" {
  # IP public của bạn ở dạng CIDR, ví dụ 1.2.3.4/32
  type        = string
  description = "Your public IP in CIDR form, for example 1.2.3.4/32"
}

variable "ami_id" {
  # AMI ID của hệ điều hành dùng cho EC2
  type        = string
  description = "EC2 AMI ID"
}

variable "instance_type" {
  # Cỡ máy EC2
  type    = string
  default = "t3.medium"
}

variable "key_name" {
  # Tên key pair SSH trong AWS
  type        = string
  description = "EC2 key pair name"
}

variable "root_volume_size" {
  # Dung lượng ổ đĩa gốc tính theo GB
  type    = number
  default = 20
}
