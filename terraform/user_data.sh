#!/bin/bash
set -e

# Cập nhật package index và cài các gói tiền đề
apt-get update -y
apt-get install -y ca-certificates curl gnupg

# Thêm Docker GPG key vào keyring
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Thêm Docker apt repository chính thức
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Cài Docker Engine và Docker Compose plugin
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Bật Docker khởi động cùng hệ thống
systemctl enable docker
systemctl start docker

# Cho user ubuntu quyền chạy Docker không cần sudo
usermod -aG docker ubuntu || true

# Tạo thư mục làm việc cho project
mkdir -p /opt/proshop
