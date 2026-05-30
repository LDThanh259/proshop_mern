Dưới đây là một setup gần với production thật cho capstone của bạn:

* Terraform tạo EC2 + Security Group
* Docker Compose chạy app + observability
* Nginx containerized
* HTTPS ready
* Monitoring đầy đủ

---

# 1. Kiến trúc tổng thể

```text id="d6h7g8"
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

---

# 2. Cấu trúc project

```text id="m1q4s9"
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

---

# 3. Terraform — provider

## terraform/main.tf

```hcl
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}
```

---

# 4. Terraform — Security Group

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

---

# 5. Terraform — EC2

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

---

# 6. Terraform output

## outputs.tf

```hcl
output "public_ip" {
  value = aws_instance.capstone.public_ip
}
```

---

# 7. Deploy Terraform

```bash
terraform init
terraform apply
```

---

# 8. SSH vào server

```bash
ssh -i key.pem ubuntu@PUBLIC_IP
```

---

# 9. Cài Docker

```bash
sudo apt update

sudo apt install docker.io docker-compose -y

sudo usermod -aG docker ubuntu
```

---

# 10. Tạo Docker network

```bash
docker network create observability
```

---

# 11. App Stack Compose

## app-stack/docker-compose.yml

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

---

# 12. Nginx config

## nginx/default.conf

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

---

# 13. Monitoring Stack

## monitoring-stack/docker-compose.yml

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

---

# 14. Prometheus config

## prometheus/prometheus.yml

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

---

# 15. Promtail config

## promtail/config.yml

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

---

# 16. Chạy stack

## App stack

```bash
cd app-stack

docker compose up -d --build
```

---

## Monitoring stack

```bash
cd monitoring-stack

docker compose up -d
```

---

# 17. Kiểm tra

## Containers

```bash
docker ps
```

---

## Grafana

```text id="b2w6x1"
http://SERVER_IP:3000
```

Default:

* admin/admin

---

## Prometheus

```text id="z8n4c0"
http://SERVER_IP:9090
```

---

# 18. Add datasource Grafana

## Prometheus

```text id="t7p9d2"
http://prometheus:9090
```

---

## Loki

```text id="g3m8k5"
http://loki:3100
```

---

# 19. Dashboard quan trọng

Import:

* Node Exporter Full

ID:

```text id="q9f2n6"
1860
```

---

# 20. Kiến trúc này có gì tốt?

## Có separation of concern

| Stack            | Vai trò       |
| ---------------- | ------------- |
| app-stack        | business app  |
| monitoring-stack | observability |

---

## Có container networking chuẩn

```text id="m4v8s3"
backend
frontend
prometheus
grafana
```

resolve qua Docker DNS.

---

## Có observability thật

* metrics
* logs
* dashboard
* container monitoring

---

# 21. Muốn lên level nữa?

Bạn có thể thêm:

## Alertmanager

```text id="v5c1k7"
Telegram alerts
```

---

## HTTPS

```text id="x8r3p2"
certbot
```

---

## CI/CD

```text id="n6w4j9"
GitHub Actions
```

---

## Terraform user_data

Auto install Docker khi EC2 boot.

---

# 22. Đây đã gần production chưa?

Khá gần.

Thiếu:

* autoscaling
* load balancer
* backup strategy
* secrets manager
* Kubernetes
* centralized logging cluster

Nhưng với capstone/student project:

* đã vượt xa mức yêu cầu
* rất giống real-world small production setup.