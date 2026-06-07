# 📘 Tài Liệu Kỹ Thuật Chi Tiết: Deploy & Monitoring — ProShop MERN Capstone

> **Phiên bản:** 1.0 | **Ngày:** 07/06/2026 | **Server:** `54.252.128.91` (AWS ap-southeast-2)

---

## Mục Lục

1. [Tổng Quan Kiến Trúc](#1-tổng-quan-kiến-trúc)
2. [Tầng Hạ Tầng — Infrastructure as Code với Terraform](#2-tầng-hạ-tầng--infrastructure-as-code-với-terraform)
3. [Tầng CI/CD — GitHub Actions](#3-tầng-cicd--github-actions)
4. [Tầng Ứng Dụng — App Stack](#4-tầng-ứng-dụng--app-stack)
5. [Tầng Giám Sát — Monitoring Stack](#5-tầng-giám-sát--monitoring-stack)
6. [Hệ Thống Cảnh Báo — Alerting Pipeline](#6-hệ-thống-cảnh-báo--alerting-pipeline)
7. [Test & Chẩn Đoán Thực Tế](#7-test--chẩn-đoán-thực-tế)
8. [Nhận Xét Tổng Quan](#8-nhận-xét-tổng-quan)
9. [Định Hướng Mở Rộng Tương Lai](#9-định-hướng-mở-rộng-tương-lai)

---

## 1. Tổng Quan Kiến Trúc

### Sơ đồ toàn hệ thống

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                │
└───────────────────────────┬─────────────────────────────────────┘
                            │ HTTP/HTTPS :80/:443
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              AWS VPC: capstone-vpc (10.0.0.0/16)                │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │         Public Subnet: 10.0.1.0/24                       │   │
│  │                                                          │   │
│  │  ┌─────────────────────────────────────────────────┐     │   │
│  │  │  EC2: nginx-public-server (54.252.128.91)        │     │   │
│  │  │  ┌──────────┐ ┌──────────┐ ┌────────────────┐   │     │   │
│  │  │  │  nginx   │ │ frontend │ │    backend     │   │     │   │
│  │  │  │ :80/:443 │ │ (React)  │ │  (Node.js)     │   │     │   │
│  │  │  └────┬─────┘ └──────────┘ └───────┬────────┘   │     │   │
│  │  │       │ reverse proxy               │            │     │   │
│  │  │  ┌────▼─────────────────────────────▼────────┐   │     │   │
│  │  │  │         Docker Network: observability      │   │     │   │
│  │  │  │  ┌────────┐ ┌───────┐ ┌─────────────────┐ │   │     │   │
│  │  │  │  │Prometheus│ │Grafana│ │  Alertmanager  │ │   │     │   │
│  │  │  │  │ :9090  │ │ :3000 │ │    :9093        │ │   │     │   │
│  │  │  │  └────────┘ └───────┘ └─────────────────┘ │   │     │   │
│  │  │  │  ┌───────────────┐ ┌──────────────────┐   │   │     │   │
│  │  │  │  │ node-exporter │ │    cadvisor      │   │   │     │   │
│  │  │  │  │    :9100      │ │     :8080        │   │   │     │   │
│  │  │  │  └───────────────┘ └──────────────────┘   │   │     │   │
│  │  │  │  ┌─────────┐ ┌──────────┐                 │   │     │   │
│  │  │  │  │  loki   │ │ promtail │                 │   │     │   │
│  │  │  │  │ :3100   │ │          │                 │   │     │   │
│  │  │  │  └─────────┘ └──────────┘                 │   │     │   │
│  │  │  └───────────────────────────────────────────┘   │     │   │
│  │  └─────────────────────────────────────────────────┘     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                            │ Private IP (10.0.x.x)              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │         Private Subnet: 10.0.2.0/24                      │   │
│  │  ┌──────────────────────────────────────────────────┐    │   │
│  │  │  EC2: mongo-private-server                        │    │   │
│  │  │  MongoDB 7.0 (port 27017)                         │    │   │
│  │  └──────────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼ Alert
                     📱 Telegram Bot
```

### Luồng dữ liệu tổng quát

| Hướng | Mô tả |
|-------|-------|
| `User → Nginx → Frontend/Backend` | Traffic HTTP/HTTPS người dùng |
| `Backend → MongoDB` | Truy vấn dữ liệu qua Private IP |
| `node-exporter → Prometheus` | Thu thập metrics EC2 host mỗi 15s |
| `cadvisor → Prometheus` | Thu thập metrics Docker container mỗi 15s |
| `Prometheus → Alertmanager` | Đẩy alert khi vi phạm rule |
| `Alertmanager → Telegram Bot` | Gửi tin nhắn cảnh báo |
| `Promtail → Loki → Grafana` | Thu thập và hiển thị logs |

---

## 2. Tầng Hạ Tầng — Infrastructure as Code với Terraform

### 2.1 Tại sao dùng Terraform?

Terraform là công cụ **Infrastructure as Code (IaC)** — thay vì click tay trên AWS Console, toàn bộ hạ tầng được mô tả bằng file `.tf` và tạo ra hoàn toàn tự động, có thể tái tạo và kiểm soát phiên bản bằng Git.

**Ví dụ thực tế:** Nếu server bị hỏng, chỉ cần chạy `terraform apply` là có ngay một server mới giống hệt trong vài phút.

### 2.2 Mạng (VPC) — `vpc.tf`

```hcl
# VPC chính — dải mạng riêng 10.0.0.0/16 (65,536 IP)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true   # Cho phép resolve tên miền nội bộ
  enable_dns_support   = true
}

# Subnet Public — 10.0.1.0/24 (256 IP) — có thể ra internet
resource "aws_subnet" "public" {
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true   # EC2 mới tự nhận IP public
}

# Subnet Private — 10.0.2.0/24 (256 IP) — KHÔNG có IP public
resource "aws_subnet" "private" {
  cidr_block = "10.0.2.0/24"
}

# NAT Gateway — đặt trong Public Subnet
# → Cho phép EC2 Private Subnet đi ra internet (download packages)
# → Nhưng internet KHÔNG THỂ kết nối vào Private Subnet
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id  # PHẢI đặt trong public subnet
}
```

**🔍 Hiểu sâu về Public/Private Subnet:**

```
Internet
   │
   │ (ai cũng vào được)
   ▼
Internet Gateway (IGW)
   │
   ▼
Public Subnet (nginx-server)  ─── có IP public: 54.252.128.91
   │
   │ (chỉ nginx mới vào được, qua Security Group)
   ▼
Private Subnet (mongo-server)  ─── KHÔNG có IP public
   │                               chỉ nhận kết nối từ nginx
   │
   ▼ (khi cần download)
NAT Gateway → Internet  (một chiều: ra được, vào không được)
```

### 2.3 Security Groups — `main.tf`

Security Group hoạt động như **tường lửa ở cấp độ instance**, kiểm tra từng gói tin:

```hcl
# Security Group cho Nginx (Public)
resource "aws_security_group" "nginx_sg" {
  # Cho phép SSH chỉ từ IP admin
  ingress { from_port = 22; cidr_blocks = [var.admin_ip_cidr] }
  
  # Cho phép HTTP từ mọi nơi (web traffic)
  ingress { from_port = 80; cidr_blocks = ["0.0.0.0/0"] }
  
  # Cho phép HTTPS từ mọi nơi
  ingress { from_port = 443; cidr_blocks = ["0.0.0.0/0"] }
  
  # Cho phép tất cả traffic đi ra (để cài packages, pull images...)
  egress { from_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

# Security Group cho MongoDB (Private) — CỰC KỲ QUAN TRỌNG
resource "aws_security_group" "mongo_sg" {
  # MongoDB chỉ nhận kết nối từ nginx_sg — không cho internet vào thẳng
  ingress {
    from_port       = 27017
    security_groups = [aws_security_group.nginx_sg.id]  # Chỉ từ nginx!
  }
  
  # SSH chỉ từ nginx (dùng nginx làm Bastion Host)
  ingress {
    from_port       = 22
    security_groups = [aws_security_group.nginx_sg.id]
  }
}
```

**🛡️ Mô hình bảo mật Bastion Host:**
```
Developer ──SSH──► Nginx (Public IP) ──SSH──► MongoDB (Private IP)
                   (Bastion Host)             (Không có public IP)
```

### 2.4 EC2 Instances

```hcl
resource "aws_instance" "nginx" {
  ami           = var.ami_id           # Ubuntu 22.04 LTS
  instance_type = "c7i-flex.large"     # 2 vCPU, 4GB RAM
  subnet_id     = aws_subnet.public.id # Đặt trong Public Subnet
  user_data     = file("nginx_user_data.sh")  # Chạy script khi boot
}

resource "aws_instance" "mongo" {
  ami           = var.ami_id
  instance_type = "c7i-flex.large"
  subnet_id     = aws_subnet.private.id  # Đặt trong Private Subnet
  user_data     = file("mongo_user_data.sh")
}
```

**`user_data`** là script chạy tự động một lần khi EC2 khởi động lần đầu:

```bash
# mongo_user_data.sh — Bootstrap MongoDB tự động
#!/bin/bash
apt-get update -y
apt-get install -y mongodb-org

# QUAN TRỌNG: Mặc định MongoDB chỉ lắng nghe localhost
# Cần sửa để nginx server (Private IP khác) kết nối được
sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf

systemctl start mongod
systemctl enable mongod
```

---

## 3. Tầng CI/CD — GitHub Actions

### 3.1 Luồng CI/CD

```
Developer push code
        │
        ▼
GitHub (main branch)
        │ trigger khi thay đổi trong proshop_mern/**
        ▼
GitHub Actions Runner (ubuntu-latest)
        │
        ├── Build Frontend Image (React → serve)
        │   └── docker build -f Dockerfile.serve
        │
        └── Build Backend Image (Node.js/Express)
            └── docker build -f Dockerfile
                │
                ▼
        Push to GHCR (GitHub Container Registry)
        ghcr.io/ldthanh259/proshop_mern-frontend:latest
        ghcr.io/ldthanh259/proshop_mern-backend:latest
                │
                ▼
        EC2 Server: docker compose pull && up -d
```

### 3.2 Workflow chi tiết — `publish-ghcr.yml`

```yaml
name: Publish Docker images to GHCR

on:
  push:
    branches: [main]
    paths:
      - "proshop_mern/**"          # Chỉ trigger khi code app thay đổi
      - ".github/workflows/**"     # Hoặc khi sửa chính workflow này

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        include:
          # Build song song cả frontend lẫn backend
          - name: frontend
            context: ./proshop_mern
            file: ./proshop_mern/frontend/Dockerfile.serve
            image: ghcr.io/ldthanh259/proshop_mern-frontend
          - name: backend
            context: ./proshop_mern
            file: ./proshop_mern/backend/Dockerfile
            image: ghcr.io/ldthanh259/proshop_mern-backend

    steps:
      - uses: actions/checkout@v4

      # Login vào GHCR bằng token tự động (không cần lưu password)
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}  # Token tự động từ GitHub

      # Tạo tag: cả 'latest' và tag theo commit SHA
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ matrix.image }}
          tags: |
            type=raw,value=latest    # Tag cố định latest
            type=sha                 # Tag theo commit: sha-abc1234

      # Build và push
      - uses: docker/build-push-action@v6
        with:
          push: true
          tags: ${{ steps.meta.outputs.tags }}
```

**💡 Lợi ích của strategy.matrix:** Chạy **song song** build frontend và backend, tiết kiệm thời gian CI/CD.

---

## 4. Tầng Ứng Dụng — App Stack

### 4.1 Docker Compose App Stack — `app-stack/docker-compose.yml`

```yaml
services:
  # ① Nginx — Cổng vào duy nhất từ internet
  nginx:
    image: nginx:1.27
    ports:
      - "80:80"    # HTTP
      - "443:443"  # HTTPS (với Let's Encrypt cert)
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro  # SSL certificate
    depends_on: [frontend, backend]

  # ② Frontend — React app được serve bởi serve (static file server)
  frontend:
    image: ghcr.io/ldthanh259/proshop_mern-frontend:latest
    # Không expose port ra ngoài — nginx proxy vào

  # ③ Backend — REST API Node.js/Express
  backend:
    image: ghcr.io/ldthanh259/proshop_mern-backend:latest
    env_file: .env
    environment:
      MONGO_URI: mongodb://mongodb:27017/proshop  # Tên service = hostname
      NODE_ENV: production
      JWT_SECRET: ${JWT_SECRET}
    depends_on:
      mongodb:
        condition: service_healthy  # Chờ MongoDB sẵn sàng mới start

  # ④ MongoDB — Database (chỉ trong môi trường local/all-in-one)
  mongodb:
    image: mongo:7
    volumes:
      - mongo-data:/data/db  # Dữ liệu không mất khi restart
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping').ok"]
      interval: 10s
      retries: 5

  # ⑤ Seed Service — Import dữ liệu mẫu (chỉ chạy khi cần)
  seed:
    profiles: [seed]  # Chỉ chạy khi: docker compose --profile seed up
    command: npm run data:import

networks:
  observability:
    external: true  # Dùng chung network với monitoring stack!
```

**🔑 Điểm quan trọng — Shared Network `observability`:**

Cả App Stack và Monitoring Stack đều dùng chung một Docker network tên `observability`. Điều này cho phép:
- `prometheus` scrape metric từ `node-exporter` và `cadvisor` bằng **tên service** (DNS nội bộ)
- `promtail` đọc log container của `nginx`, `frontend`, `backend`
- Không cần hardcode IP — chỉ cần dùng tên service

```bash
# Tạo network trước khi start cả hai stack
docker network create observability

# Sau đó start từng stack
cd monitoring-stack && docker compose up -d
cd app-stack && docker compose up -d
```

### 4.2 Nginx Reverse Proxy

Nginx đóng vai trò **reverse proxy** — nhận request từ internet và phân phối đến đúng service:

```
Request: GET / HTTP/1.1
  → Nginx kiểm tra URL path
  → path = /api/* → forward đến backend:5000
  → path = /* → forward đến frontend:3000
```

---

## 5. Tầng Giám Sát — Monitoring Stack

### 5.1 Sơ đồ luồng dữ liệu Monitoring

```
EC2 Host (CPU, RAM, Disk, Network)
    │
    │ expose metrics endpoint
    ▼
node-exporter:9100/metrics
    │
    │ scrape mỗi 15 giây
    ▼
Prometheus:9090  ◄──── cadvisor:8080/metrics (Container metrics)
    │                   (CPU/RAM của từng Docker container)
    │
    ├──► Evaluate Alert Rules (cpu-alerts.yml, ram-alerts.yml)
    │         │
    │         │ nếu vi phạm
    │         ▼
    │    Alertmanager:9093
    │         │
    │         ▼
    │    Telegram Bot 📱
    │
    └──► Grafana:3000  ◄──── Loki:3100 ◄──── Promtail
              (Dashboard)              (Log aggregation)
```

### 5.2 Prometheus — Thu thập Metrics

**Cấu hình `prometheus.yml`:**

```yaml
global:
  scrape_interval: 15s  # Cứ 15 giây lại đi "hỏi" các target một lần

# Khai báo các file chứa Alert Rules
rule_files:
  - /etc/prometheus/rules/*.yml  # Load tất cả file .yml trong thư mục rules

# Cấu hình nơi gửi alert
alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]  # Tên service = hostname

# Danh sách các nguồn metrics cần scrape
scrape_configs:
  - job_name: node-exporter
    static_configs:
      - targets: ["node-exporter:9100"]  # Metrics OS: CPU, RAM, Disk...

  - job_name: cadvisor
    static_configs:
      - targets: ["cadvisor:8080"]       # Metrics Container Docker
```

**Ví dụ dữ liệu Prometheus thu thập được:**

```
# Từ node-exporter (metric của máy chủ)
node_cpu_seconds_total{cpu="0", mode="idle"}     → Giây CPU lõi 0 ở chế độ rảnh
node_cpu_seconds_total{cpu="0", mode="user"}     → Giây CPU lõi 0 chạy user process
node_memory_MemTotal_bytes                        → Tổng RAM (bytes)
node_memory_MemAvailable_bytes                    → RAM còn dùng được (bytes)
node_filesystem_avail_bytes{mountpoint="/"}       → Dung lượng ổ đĩa trống

# Từ cadvisor (metric của container)
container_cpu_usage_seconds_total{name="backend"}  → CPU của container backend
container_memory_usage_bytes{name="nginx"}         → RAM của container nginx
```

### 5.3 Giải mã PromQL — Ngôn ngữ truy vấn Prometheus

**Bài toán: Tính % CPU đang bận**

```promql
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)
```

**Giải thích từng bước:**

```
Bước 1: node_cpu_seconds_total{mode="idle"}
         → Lấy counter đếm số giây CPU ở chế độ idle
         → Đây là counter — chỉ tăng, không giảm
         Ví dụ: {cpu="0"} = 12345.67 giây

Bước 2: rate(...[1m])
         → Tính tốc độ tăng của counter trong 1 phút gần nhất
         → Kết quả: tỷ lệ idle trong khoảng [0, 1]
         Ví dụ: rate = 0.05 → CPU rảnh 5% thời gian

Bước 3: avg by(instance) (...)
         → Tính trung bình qua tất cả các lõi CPU
         → Ví dụ: 2 lõi có rate=[0.05, 0.03] → avg = 0.04

Bước 4: * 100
         → Quy ra phần trăm: 0.04 → 4% CPU đang rảnh

Bước 5: 100 - (...)
         → 100% - 4% idle = 96% CPU ĐANG BẬN (Busy)
         → Đây là con số hiển thị trên Grafana

Bước 6: > 85
         → Nếu kết quả > 85 thì alert
```

**Tại sao `[1m]` nhanh hơn `[5m]`?**

```
[5m]: Trung bình 5 phút = phản ứng chậm nhưng ổn định, ít false alarm
      CPU tăng đột ngột → mất 4-5 phút mới vượt ngưỡng

[1m]: Trung bình 1 phút = phản ứng nhanh, nhạy cảm hơn
      CPU tăng đột ngột → mất ~1 phút là vượt ngưỡng

           CPU thực tế: ████████████████ 100%
rate[5m]:  ░░░░░▓▓▓▓▓▓▓▓████           Chậm tăng, mất ~4 phút
rate[1m]:  ░▓▓▓▓████████████           Nhanh tăng, mất ~1 phút
```

**Bài toán: Tính % RAM đang dùng**

```promql
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
  / node_memory_MemTotal_bytes * 100
```

```
Giải thích:
  node_memory_MemTotal_bytes     = Tổng RAM vật lý = 3,814 MB
  node_memory_MemAvailable_bytes = RAM Linux đánh giá còn dùng được
                                   (bao gồm cả RAM đang làm cache)

  RAM đang dùng = MemTotal - MemAvailable
              = 3814 - 460 = 3354 MB (đang chạy stress test)

  % dùng = 3354 / 3814 * 100 = 87.9%
```

> **⚠️ Lưu ý:** `MemAvailable` ≠ `MemFree`!  
> Linux dùng RAM nhàn rỗi để cache disk (tăng tốc I/O). Khi ứng dụng cần RAM, Linux **tự giải phóng cache**.  
> `MemAvailable` = MemFree + cache có thể giải phóng → Con số thực tế hơn.

### 5.4 cAdvisor — Giám sát Container

```yaml
cadvisor:
  image: gcr.io/cadvisor/cadvisor:v0.55.1
  privileged: true    # Cần quyền cao để đọc kernel cgroups
  volumes:
    - /:/rootfs:ro               # Đọc filesystem gốc
    - /var/run:/var/run:ro       # Đọc Docker socket
    - /sys:/sys:ro               # Đọc kernel subsystems
    - /var/lib/docker/:/var/lib/docker:ro  # Đọc Docker data
```

**Ví dụ query cAdvisor trên Prometheus:**

```promql
# CPU của container backend (% trong 1 phút)
rate(container_cpu_usage_seconds_total{name="backend"}[1m]) * 100

# RAM của container nginx
container_memory_usage_bytes{name="nginx"} / 1024 / 1024  # MB
```

### 5.5 Loki + Promtail — Quản lý Logs

**Luồng log:**
```
Docker container → stdout/stderr
    → /var/lib/docker/containers/<id>/<id>-json.log
    → Promtail đọc file này (theo dõi real-time)
    → Parse metadata: container_name, image, ...
    → Push đến Loki:3100
    → Grafana query Loki → hiển thị log
```

**Ưu điểm của Loki:** Loki KHÔNG index nội dung log (chỉ index labels như `container_name`, `level`), nên **rất nhẹ** và tiết kiệm dung lượng so với Elasticsearch.

---

## 6. Hệ Thống Cảnh Báo — Alerting Pipeline

### 6.1 Alert Rules — Định nghĩa điều kiện

**`cpu-alerts.yml`:**
```yaml
groups:
  - name: cpu-alerts
    rules:
      - alert: HighCpuUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100) > 85
        for: 1m        # Phải vi phạm LIÊN TỤC trong 1 phút mới fire
        labels:
          severity: warning
        annotations:
          summary: "CPU usage is above 85%"
          description: "CPU usage on {{ $labels.instance }} is above 85% for more than 1 minute."
```

**`ram-alerts.yml`:**
```yaml
groups:
  - name: ram-alerts
    rules:
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Memory usage is above 85%"
          description: "Memory usage on {{ $labels.instance }} is above 85% for more than 1 minute. Current usage is {{ $value | printf \"%.2f\" }}%."
```

**Vòng đời của một Alert:**

```
Metric vượt ngưỡng → INACTIVE
         │
         │ (giữ nguyên trong thời gian for: 1m)
         ▼
      PENDING ─── metric xuống lại ──► INACTIVE
         │
         │ (đủ 1 phút)
         ▼
      FIRING ──► Gửi đến Alertmanager
         │
         │ (metric về dưới ngưỡng)
         ▼
      RESOLVED ──► Gửi thông báo "đã giải quyết"
```

**Tại sao cần `for: 1m`?**  
Tránh alert giả (false alarm) khi CPU spike ngắn 5-10 giây. Chỉ alert khi thực sự có vấn đề kéo dài.

### 6.2 Alertmanager — Định tuyến và Gửi Alert

**`alertmanager.yml`:**
```yaml
global:
  resolve_timeout: 5m   # Sau 5 phút không có alert mới → coi là resolved

route:
  receiver: telegram-notifications
  group_wait: 10s       # Gom nhóm các alert trong 10s rồi gửi 1 lần
  group_interval: 30s   # Nếu có alert mới trong group, đợi 30s
  repeat_interval: 1h   # Cùng alert không gửi lặp lại trong 1 tiếng

receivers:
  - name: telegram-notifications
    telegram_configs:
      - bot_token: ${TELEGRAM_BOT_TOKEN}   # Biến môi trường từ .env
        chat_id: ${TELEGRAM_CHAT_ID}
        message: |-
          {{ range .Alerts -}}
          {{ .Annotations.summary }}
          {{ .Annotations.description }}
          {{ end }}

# Tắt tiếng alert nhỏ khi đã có alert lớn hơn
inhibit_rules:
  - source_matchers: [severity="critical"]   # Nếu đang có critical
    target_matchers: [severity="warning"]    # Thì tắt warning
    equal: [alertname, instance]             # Của cùng instance đó
```

**Ví dụ tin nhắn Telegram nhận được:**
```
CPU usage is above 85%
CPU usage on node-exporter:9100 is above 85% for more than 1 minute.

Memory usage is above 85%
Memory usage on node-exporter:9100 is above 85% for more than 1 minute. Current usage is 87.57%.
```

### 6.3 Timeline Alert thực tế (06/06/2026)

```
12:46:44  Bắt đầu stress test (CPU + RAM)
          └─ yes > /dev/null × 2 lõi (đốt 100% CPU)
          └─ python3 chiếm 90% RAM (~2.4 GB)

12:47:26  RAM vượt 85% → PENDING
          └─ MemAvailable giảm từ 2,615 MB → 460 MB ngay lập tức

12:48:26  RAM FIRING → Alertmanager → Telegram 📱 (tin nhắn thứ 1)

12:50:xx  CPU rate[1m] bắt đầu vượt 85%
          └─ Do rate[1m] cần ~1 phút để phản ánh tải cao
          
12:51:11  CPU FIRING → Alertmanager → Telegram 📱 (tin nhắn thứ 2)

          [Sau khi đổi từ rate[5m] sang rate[1m]]
          → Cả hai alert sẽ fire gần như ĐỒNG THỜI (~1-2 phút sau test)
```

---

## 7. Test & Chẩn Đoán Thực Tế

### 7.1 Script test_alerts.sh

File [test_alerts.sh](file:///f:/Cloud%20Computing/Capstone%20Project/test_alerts.sh) cung cấp menu tương tác để test alert:

```bash
# Chạy trực tiếp trên server
bash /opt/proshop/test_alerts.sh

# Chọn:
# 1 → Đốt CPU 100% (dùng lệnh yes)
# 2 → Chiếm 90% RAM (Python bytearray)
# 3 → Cả hai
# 4 → Dừng tất cả (killall yes + pkill python)
# 5 → Bật logger ghi top process mỗi 10s
# 6 → Xem log chẩn đoán
```

**Cơ chế đốt CPU:**
```bash
CORES=$(nproc)          # Đếm số lõi CPU (ví dụ: 2)
for i in $(seq 1 $CORES); do
    yes > /dev/null &   # Tạo 1 tiến trình ghi "y\n" liên tục vào /dev/null
done                    # Mỗi tiến trình chiếm đúng 1 lõi → 100% toàn bộ CPU
```

**Cơ chế chiếm RAM:**
```python
# Đọc thông tin RAM từ /proc/meminfo
with open('/proc/meminfo') as f:
    meminfo = {parts[0].strip(':'): int(parts[1]) for line in f ...}

total = meminfo['MemTotal']        # Tổng RAM (KB)
avail = meminfo['MemAvailable']    # RAM còn dùng được

# Tính lượng cần cấp phát để chỉ còn lại 10% RAM trống
target_avail = int(total * 0.10)
to_allocate  = avail - target_avail  # KB cần cấp phát

# Cấp phát bytearray — giữ trong RAM 10 phút, KHÔNG tốn CPU
a = bytearray(to_allocate * 1024)
time.sleep(600)
```

### 7.2 Truy vấn nhanh từ terminal

```bash
# Kiểm tra CPU đang ở bao nhiêu %
curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=100 - (avg by(instance) (rate(node_cpu_seconds_total[1m])) * 100)'

# Kiểm tra RAM đang ở bao nhiêu %  
curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100'

# Xem tất cả alerts đang active
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool

# Reload Prometheus khi sửa config (không cần restart)
curl -X POST http://localhost:9090/-/reload
```

### 7.3 Chẩn đoán khi CPU cao bất thường

**Bước 1: Xem tiến trình ngốn CPU nhiều nhất**
```bash
# Tức thời
top -o %CPU
ps -eo pid,ppid,cmd,%cpu --sort=-%cpu | head -n 10

# Log tự động 10s/lần (bật bằng option 5 trong test_alerts.sh)
tail -f /tmp/cpu_diagnostic.log
```

**Bước 2: Kiểm tra container nào ngốn CPU**
```bash
docker stats --no-stream
# Output:
# CONTAINER   CPU %   MEM USAGE / LIMIT
# backend     45.2%   320MiB / 3.81GiB
# nginx        2.1%    15MiB / 3.81GiB
```

**Bước 3: Dùng Prometheus để trace lịch sử**
```promql
# CPU của từng container trong 1 giờ qua
rate(container_cpu_usage_seconds_total{name=~"backend|frontend|nginx"}[5m]) * 100
```

---

## 8. Nhận Xét Tổng Quan

### ✅ Điểm mạnh

| Khía cạnh | Nhận xét |
|-----------|---------|
| **Infrastructure as Code** | Toàn bộ hạ tầng AWS được mô tả bằng Terraform, tái tạo được trong vài phút. Version control được qua Git. |
| **Bảo mật mạng** | MongoDB nằm trong Private Subnet, không có IP public. Chỉ Nginx mới vào được qua Security Group. Pattern Bastion Host chuẩn mực. |
| **CI/CD tự động** | Push code → tự động build Docker image → push GHCR. Developer chỉ cần pull image mới là deploy xong. |
| **Observability đầy đủ** | Có cả Metrics (Prometheus), Logs (Loki), Dashboard (Grafana) — đủ 3 trụ cột Observability. |
| **Alerting chủ động** | Không cần ngồi nhìn dashboard. Khi có vấn đề, Telegram tự thông báo. |
| **Shared Docker Network** | Thiết kế thông minh: một network `observability` cho cả App Stack và Monitoring Stack giao tiếp với nhau bằng tên service. |

### ⚠️ Hạn chế hiện tại

| Hạn chế | Ảnh hưởng |
|---------|-----------|
| **Single Point of Failure** | Toàn bộ app và monitoring trên 1 EC2. Server chết → mất cả monitoring. |
| **Không có CD hoàn chỉnh** | CI tự build image, nhưng việc `docker compose pull && up -d` trên server vẫn phải làm tay. |
| **MongoDB không có replica** | Không có backup tự động. Dữ liệu mất nếu volume bị xóa hoặc EBS hỏng. |
| **Monitoring không giám sát chính nó** | Prometheus/Alertmanager đang down thì ai báo? |
| **Alert đơn giản** | Chỉ có CPU và RAM. Chưa có disk, network, error rate ứng dụng... |
| **Không có HTTPS cho monitoring** | Grafana/Prometheus đang chạy HTTP thuần, không có auth ngoài firewall. |

---

## 9. Định Hướng Mở Rộng Tương Lai

### 🚀 Ngắn hạn (1-2 tháng)

#### 9.1 Bổ sung Alert Rules

```yaml
# Cảnh báo disk sắp đầy
- alert: HighDiskUsage
  expr: (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 > 80
  for: 5m
  annotations:
    description: "Disk usage is {{ $value | printf \"%.1f\" }}% on {{ $labels.instance }}"

# Cảnh báo server không phản hồi
- alert: InstanceDown
  expr: up == 0
  for: 1m
  labels:
    severity: critical
  annotations:
    description: "Instance {{ $labels.instance }} has been down for more than 1 minute"

# Cảnh báo error rate API cao
- alert: HighHttpErrorRate
  expr: rate(nginx_http_requests_total{status=~"5.."}[5m]) / rate(nginx_http_requests_total[5m]) > 0.05
  for: 2m
  annotations:
    description: "HTTP 5xx error rate is {{ $value | humanizePercentage }}"
```

#### 9.2 Hoàn thiện CD Pipeline

```yaml
# Thêm vào publish-ghcr.yml sau khi push image
- name: Deploy to EC2
  uses: appleboy/ssh-action@master
  with:
    host: ${{ secrets.EC2_HOST }}
    username: ${{ secrets.EC2_USER }}
    key: ${{ secrets.SSH_PRIVATE_KEY }}
    script: |
      cd /opt/proshop/app-stack
      docker compose pull
      docker compose up -d --remove-orphans
```

#### 9.3 Backup MongoDB tự động

```bash
# Cron job mỗi ngày backup MongoDB sang S3
0 2 * * * docker exec mongodb mongodump --archive | \
  aws s3 cp - s3://proshop-backup/$(date +%Y%m%d).archive
```

### 🏗️ Trung hạn (3-6 tháng)

#### 9.4 Tách Monitoring ra server riêng

```
[Server App]          [Server Monitoring]
nginx, frontend  →→→  Prometheus, Grafana, Alertmanager
backend, mongodb      Loki, Promtail

Lợi ích:
- App server down → vẫn thấy alert
- Monitoring không chiếm RAM/CPU của app
```

#### 9.5 Thêm Distributed Tracing (Jaeger/Tempo)

```
Request → Nginx → Backend → MongoDB
  │           │         │
  └── TraceID ┘─────────┘  → Grafana Tempo

Giúp trả lời: "Request này mất thời gian ở bước nào?"
```

#### 9.6 Process Exporter — Giám sát tiến trình Linux

```yaml
# docker-compose.yml
process-exporter:
  image: ncabatoff/process-exporter:latest
  volumes:
    - /proc:/host/proc:ro
    - ./process-exporter.yml:/config/config.yml:ro
  command: --procfs /host/proc --config.path /config/config.yml
```

```yaml
# process-exporter.yml
process_names:
  - name: "{{.Comm}}"
    cmdline: ['.+']  # Giám sát tất cả process
```

```promql
# Alert khi process cụ thể ngốn quá nhiều CPU
rate(namedprocess_namegroup_cpu_seconds_total{groupname="node"}[1m]) * 100 > 50
```

### 🌐 Dài hạn (6+ tháng)

#### 9.7 Kubernetes + Helm

```
Hiện tại:
  EC2 → Docker Compose → Manual scaling

Tương lai:
  EKS (Kubernetes) → Helm Charts → Auto-scaling

Lợi ích:
  - Tự scale khi CPU/RAM cao (HPA)
  - Self-healing: Pod chết tự restart
  - Rolling deployment: 0 downtime
  - Prometheus Operator: tự quản lý scrape config
```

#### 9.8 Multi-region Deployment

```
ap-southeast-2 (Sydney) ──── Primary
ap-southeast-1 (Singapore) ─ Secondary (Read Replica)
          │
      Route 53 (DNS Failover)
          │
     Latency-based routing
```

#### 9.9 SLO/SLI Monitoring

```promql
# SLI: Tỷ lệ request thành công (Availability)
sum(rate(nginx_requests_total{status!~"5.."}[5m]))
  / sum(rate(nginx_requests_total[5m]))

# SLO Target: 99.9% availability
# Error Budget: 0.1% × 30 days × 24h × 60m = 43.2 phút/tháng downtime cho phép
```

---

## Tổng kết

```
┌─────────────────────────────────────────────────────┐
│            TECHNOLOGY STACK SUMMARY                  │
├────────────────────┬────────────────────────────────┤
│ Infrastructure     │ Terraform (AWS VPC, EC2, SG)   │
│ Container Runtime  │ Docker + Docker Compose         │
│ CI/CD              │ GitHub Actions + GHCR           │
│ App Framework      │ MERN (MongoDB, Express, React,  │
│                    │       Node.js)                  │
│ Reverse Proxy      │ Nginx                           │
│ Metrics            │ Prometheus + node-exporter      │
│                    │ + cAdvisor                      │
│ Logs               │ Loki + Promtail                 │
│ Dashboard          │ Grafana                         │
│ Alerting           │ Alertmanager → Telegram Bot     │
│ Alert Rules        │ PromQL (CPU [1m], RAM)          │
└────────────────────┴────────────────────────────────┘
```

> Dự án đã xây dựng thành công một hệ thống **full-stack cloud deployment** với monitoring hoàn chỉnh theo chuẩn SRE (Site Reliability Engineering), phù hợp với quy mô startup và làm nền tảng cho việc scale lên môi trường enterprise trong tương lai.
