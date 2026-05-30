output "public_ip" {
  # Public IP để SSH và truy cập app
  value = aws_instance.capstone.public_ip
}

output "instance_id" {
  # Instance ID để quản trị trên AWS
  value = aws_instance.capstone.id
}
