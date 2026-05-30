# Tài liệu triển khai capstone gần production

Tài liệu này diễn giải lại nội dung trong `doc.md` theo cách dễ đọc hơn, đồng thời giải thích rõ vai trò của từng thành phần trong hệ thống.

## Mục tiêu kiến trúc

Mô hình này hướng tới một setup gần với production cho capstone:

- Terraform dùng để tạo hạ tầng trên AWS.
- Docker Compose dùng để chạy ứng dụng và hệ thống quan sát.
- Nginx đóng vai trò reverse proxy.
- Hệ thống sẵn sàng cho HTTPS.
- Có monitoring đầy đủ bằng metrics, logs và dashboard.

## 1. Kiến trúc tổng thể

Luồng vận hành của hệ thống:

```text
Terraform
   ↓
AWS EC2
   ↓
Docker Compose
   ├── nginx
   ├── frontend
   ├── backend
   ├── mongodb
   ├── prometheus
   ├── grafana
   ├── loki
   ├── promtail
   ├── cadvisor
   └── node-exporter
```

### Giải thích

- `Terraform` lo phần tạo hạ tầng tự động, thay vì tạo EC2 thủ công.
- `AWS EC2` là máy chủ chạy ứng dụng.
- `Docker Compose` gom các service thành một cụm dễ triển khai.
- `nginx` là lớp gateway nhận request từ bên ngoài.
- `frontend` phục vụ giao diện người dùng.
- `backend` xử lý logic nghiệp vụ và API.
- `mongodb` lưu dữ liệu.
- `prometheus` thu thập metrics.
- `grafana` hiển thị dashboard.
- `loki` lưu logs tập trung.
- `promtail` đẩy logs từ máy chủ vào Loki.
- `cadvisor` theo dõi container.
- `node-exporter` thu thập metric từ hệ điều hành.

## 2. Cấu trúc project đề xuất

```text
project/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── app-stack/
│   ├── docker-compose.yml
│   ├── nginx/
│   │   └── default.conf
│   ├── frontend/
│   └── backend/
│
└── monitoring-stack/
    ├── docker-compose.yml
    ├── prometheus/
    │   └── prometheus.yml
    ├── loki/
    │   └── local-config.yaml
    └── promtail/
        └── config.yml
```

### Giải thích

- `terraform/` chứa toàn bộ code hạ tầng.
- `app-stack/` chứa ứng dụng chính.
- `monitoring-stack/` chứa toàn bộ stack observability.
- Tách riêng như vậy giúp dễ bảo trì, dễ nâng cấp và rõ trách nhiệm từng phần.

## 3. Terraform

### 3.1 Provider

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}
```

### Giải thích

- Khối `required_providers` khai báo provider AWS.
- `version = "~> 5.0"` giúp khóa phạm vi version tương thích.
- `region = "ap-southeast-1"` đặt vùng triển khai tại Singapore, thường gần Việt Nam nên độ trễ thấp hơn.

### 3.2 Security Group

```hcl
resource "aws_security_group" "capstone_sg" {
  name = "capstone-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP/32"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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
```

### Giải thích

- Port `22` chỉ mở cho IP của bạn để SSH an toàn hơn.
- Port `80` mở cho HTTP.
- Port `443` mở cho HTTPS.
- `egress` cho phép máy chủ kết nối ra ngoài.

### Lưu ý an toàn

- Không nên để SSH mở cho toàn bộ internet.
- Thay `YOUR_IP/32` bằng IP public thật của bạn.

### 3.3 EC2 Instance

```hcl
resource "aws_instance" "capstone" {
  ami           = "ami-01811d4912b4ccb26"
  instance_type = "t3.medium"

  key_name = "your-key"

  vpc_security_group_ids = [
    aws_security_group.capstone_sg.id
  ]

  root_block_device {
    volume_size = 20
  }

  tags = {
    Name = "capstone-server"
  }
}
```

### Giải thích

- `ami` là image của máy ảo Ubuntu hoặc hệ điều hành tương ứng.
- `t3.medium` phù hợp cho capstone có cả app và monitoring nhỏ.
- `key_name` là SSH key pair để đăng nhập vào EC2.
- `volume_size = 20` cấp 20GB cho root disk.
- `tags` giúp dễ quản lý trên AWS Console.

### 3.4 Output

```hcl
output "public_ip" {
  value = aws_instance.capstone.public_ip
}
```

### Giải thích

- Output này giúp bạn lấy IP public của server sau khi Terraform tạo xong.

### 3.5 Chạy Terraform

```bash
terraform init
terraform apply
```

### Giải thích

- `terraform init` tải provider và khởi tạo project.
- `terraform apply` tạo hạ tầng thật trên AWS.

## 4. SSH vào server

```bash
ssh -i key.pem ubuntu@PUBLIC_IP
```

### Giải thích

- `key.pem` là private key của bạn.
- `ubuntu` là user mặc định nếu bạn dùng Ubuntu AMI.
- `PUBLIC_IP` là IP lấy từ output Terraform.

## 5. Cài Docker

```bash
sudo apt update
sudo apt install docker.io docker-compose -y
sudo usermod -aG docker ubuntu
```

### Giải thích

- `apt update` cập nhật danh sách gói.
- `docker.io` cài Docker engine.
- `docker-compose` cài Docker Compose.
- `usermod -aG docker ubuntu` cho phép user `ubuntu` chạy Docker mà không cần `sudo` mỗi lần.

### Lưu ý

Sau khi thêm user vào group `docker`, bạn nên đăng xuất và đăng nhập lại để group có hiệu lực.

## 6. Tạo Docker network dùng chung

```bash
docker network create observability
```

### Giải thích

- Đây là network external để app stack và monitoring stack có thể gọi nhau bằng tên container.
- Ví dụ: `backend`, `prometheus`, `grafana` có thể giao tiếp qua Docker DNS.

## 7. App Stack

### 7.1 Docker Compose

```yaml
version: '3.9'

services:

  nginx:
    image: nginx:latest
    container_name: nginx

    ports:
      - "80:80"
      - "443:443"

    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf

    depends_on:
      - frontend
      - backend

    networks:
      - observability

  frontend:
    build: ./frontend

    container_name: frontend

    networks:
      - observability

  backend:
    build: ./backend

    container_name: backend

    environment:
      - MONGO_URI=mongodb://mongodb:27017/proshop

    depends_on:
      - mongodb

    networks:
      - observability

  mongodb:
    image: mongo:latest

    container_name: mongodb

    volumes:
      - mongo-data:/data/db

    networks:
      - observability

volumes:
  mongo-data:

networks:
  observability:
    external: true
```

### Giải thích

- `nginx` là entrypoint nhận request từ bên ngoài.
- `frontend` build từ source code của giao diện.
- `backend` build từ source code API.
- `MONGO_URI` trỏ tới container MongoDB bằng tên service `mongodb`.
- `mongodb` dùng named volume `mongo-data` để giữ dữ liệu khi container bị recreate.
- `external: true` nghĩa là network này được tạo trước bằng lệnh `docker network create observability`.

### 7.2 Nginx config

```nginx
server {
    listen 80;

    location / {
        proxy_pass http://frontend:80;
    }

    location /api {
        proxy_pass http://backend:5000;
    }
}
```

### Giải thích

- Request vào `/` sẽ được chuyển sang frontend.
- Request vào `/api` sẽ được chuyển sang backend.
- Nginx đóng vai trò reverse proxy, giúp tách public traffic và nội bộ container.

### Gợi ý cải thiện

- Nếu muốn production hơn, nên bổ sung HTTPS và cấu hình redirect từ HTTP sang HTTPS.
- Có thể tinh chỉnh `proxy_set_header` để giữ nguyên thông tin client.

## 8. Monitoring Stack

### 8.1 Docker Compose

```yaml
version: '3.9'

services:

  prometheus:
    image: prom/prometheus

    container_name: prometheus

    ports:
      - "9090:9090"

    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml

    networks:
      - observability

  grafana:
    image: grafana/grafana

    container_name: grafana

    ports:
      - "3000:3000"

    networks:
      - observability

  node-exporter:
    image: prom/node-exporter

    container_name: node-exporter

    ports:
      - "9100:9100"

    networks:
      - observability

  cadvisor:
    image: gcr.io/cadvisor/cadvisor

    container_name: cadvisor

    ports:
      - "8080:8080"

    privileged: true

    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro

    networks:
      - observability

  loki:
    image: grafana/loki:latest

    container_name: loki

    ports:
      - "3100:3100"

    command: -config.file=/etc/loki/local-config.yaml

    volumes:
      - ./loki/local-config.yaml:/etc/loki/local-config.yaml

    networks:
      - observability

  promtail:
    image: grafana/promtail:latest

    container_name: promtail

    volumes:
      - /var/log:/var/log
      - ./promtail/config.yml:/etc/promtail/config.yml

    command: -config.file=/etc/promtail/config.yml

    networks:
      - observability

networks:
  observability:
    external: true
```

### Giải thích

- `prometheus` thu metrics từ node-exporter và cadvisor.
- `grafana` hiển thị dashboard.
- `node-exporter` theo dõi tài nguyên máy chủ như CPU, RAM, disk.
- `cadvisor` theo dõi container Docker.
- `loki` lưu logs.
- `promtail` đọc log file và đẩy vào Loki.

### 8.2 Prometheus config

```yaml
global:
  scrape_interval: 15s

scrape_configs:

  - job_name: node-exporter
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: cadvisor
    static_configs:
      - targets: ['cadvisor:8080']
```

### Giải thích

- `scrape_interval: 15s` nghĩa là Prometheus thu metric mỗi 15 giây.
- `node-exporter:9100` và `cadvisor:8080` là các target trong Docker network.

### 8.3 Promtail config

```yaml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:

  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*log
```

### Giải thích

- Promtail đọc log từ `/var/log/*log`.
- Log được gửi đến Loki qua endpoint `/loki/api/v1/push`.
- `positions.yaml` giúp promtail nhớ log đã đọc đến đâu.

## 9. Chạy hệ thống

### App stack

```bash
cd app-stack
docker compose up -d --build
```

### Monitoring stack

```bash
cd monitoring-stack
docker compose up -d
```

### Giải thích

- `--build` bắt Docker build lại image cho frontend/backend.
- `-d` chạy nền.
- Monitoring stack thường không cần build nên chỉ cần `up -d`.

## 10. Kiểm tra hệ thống

### Xem container

```bash
docker ps
```

### Grafana

```text
http://SERVER_IP:3000
```

Đăng nhập mặc định:

- username: `admin`
- password: `admin`

### Prometheus

```text
http://SERVER_IP:9090
```

## 11. Cấu hình datasource trong Grafana

### Prometheus

```text
http://prometheus:9090
```

### Loki

```text
http://loki:3100
```

### Giải thích

- Vì Grafana và Prometheus/Loki cùng nằm trong Docker network `observability`, bạn có thể dùng hostname container thay vì IP.
- Đây là cách cấu hình chuẩn khi các service chạy cùng network nội bộ.

## 12. Dashboard quan trọng

Nên import dashboard:

- Node Exporter Full

Dashboard ID:

```text
1860
```

### Giải thích

- Dashboard này hiển thị rất nhiều chỉ số hữu ích cho server Linux.
- Nó giúp bạn xem CPU, RAM, disk, load average và nhiều metric hệ thống khác.

## 13. Vì sao kiến trúc này tốt?

### 13.1 Tách biệt trách nhiệm

| Stack | Vai trò |
| --- | --- |
| app-stack | Chạy ứng dụng chính |
| monitoring-stack | Giám sát và logging |

### Ý nghĩa

- App không bị trộn lẫn với observability.
- Dễ bảo trì hơn.
- Khi lỗi xảy ra, bạn dễ xác định phần nào gây vấn đề.

### 13.2 Container networking chuẩn

Các service như `backend`, `frontend`, `prometheus`, `grafana` có thể giao tiếp qua Docker DNS.

### Ý nghĩa

- Không cần hard-code IP.
- Dễ scale và dễ thay đổi hạ tầng hơn.

### 13.3 Có observability thật

Hệ thống có:

- metrics
- logs
- dashboard
- container monitoring

### Ý nghĩa

- Đây là phần rất gần thực tế production.
- Bạn có thể theo dõi không chỉ app mà cả máy chủ và container.

## 14. Các bước nâng cấp tiếp theo

### Alertmanager

- Có thể cấu hình cảnh báo qua Telegram, email hoặc Slack khi server có vấn đề.

### HTTPS

- Dùng `certbot` hoặc reverse proxy có TLS để bật HTTPS.

### CI/CD

- Dùng GitHub Actions để tự động build, test và deploy.

### Terraform user_data

- Có thể cho EC2 tự cài Docker ngay khi khởi động.

## 15. Hệ thống này đã gần production chưa?

Khá gần, nhưng vẫn còn thiếu:

- autoscaling
- load balancer
- backup strategy
- secrets manager
- Kubernetes
- centralized logging cluster

### Kết luận

Với một capstone hoặc project sinh viên, kiến trúc này đã vượt xa mức demo đơn giản và phản ánh khá đúng mô hình production nhỏ trong thực tế.

