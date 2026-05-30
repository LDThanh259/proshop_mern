#!/bin/bash
set -e

# Cập nhật package index trước khi cài phần mềm
apt-get update -y
# Cài Docker và Docker Compose plugin
apt-get install -y docker.io docker-compose-plugin

# Bật Docker chạy cùng hệ thống
systemctl enable docker
systemctl start docker

# Cho user ubuntu quyền dùng Docker không cần sudo mỗi lần
usermod -aG docker ubuntu || true

# Tạo thư mục làm việc nếu sau này muốn mount file deploy
mkdir -p /opt/proshop
