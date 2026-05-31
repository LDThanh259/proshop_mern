# Hướng Dẫn Thực Hành Capstone

Tài liệu này bám theo yêu cầu bài thực hành trong phần đánh giá của môn Cloud Computing & SRE.

## 1. Mục tiêu

- Clone và triển khai ứng dụng ProShop MERN lên AWS EC2.
- Dùng Docker Compose để chạy frontend, backend, MongoDB và monitoring stack.
- Dùng Nginx làm reverse proxy.
- Mở đúng cổng theo Security Group.
- Bật HTTPS bằng Certbot.
- Theo dõi hệ thống bằng Prometheus, Grafana, Loki, Promtail và AlertManager.

## 2. Cấu trúc thư mục

- `proshop_mern/`: source code ứng dụng gốc.
- `app-stack/`: compose chạy app.
- `monitoring-stack/`: compose chạy monitoring.
- `terraform/`: hạ tầng AWS.

## 3. Giai Đoạn Deployment

### 3.1 Tạo EC2

1. Điền biến trong Terraform.
2. Chạy:

```bash
cd terraform
terraform init
terraform apply
```

### 3.2 Cài Docker

```bash
sudo apt update
sudo apt install docker.io docker-compose-plugin -y
sudo usermod -aG docker ubuntu
```

### 3.3 Tạo network dùng chung

```bash
docker network create observability
```

### 3.4 Chạy app

Local:

```bash
cd app-stack
docker compose -f docker-compose.local.yml up -d --build
```

Server:

```bash
cd app-stack
docker compose up -d
```

### 3.5 Seed dữ liệu mẫu

Local:

```bash
cd app-stack
docker compose -f docker-compose.local.yml --profile seed up seed
```

Server:

```bash
cd app-stack
docker compose --profile seed up seed
```

## 4. Giai Đoạn Security

### 4.1 Security Group

- Chỉ mở `22` cho IP cá nhân.
- Mở `80` và `443` cho Internet.
- Không mở `27017` ra ngoài.

### 4.2 Nginx Reverse Proxy

- Frontend chạy ở `/`
- Backend API đi qua `/api`

### 4.3 HTTPS

Dùng Certbot với Let’s Encrypt để gắn SSL cho domain.

## 5. Giai Đoạn Observability

### 5.1 Prometheus

- Scrape `node-exporter`
- Scrape `cadvisor`
- Có alert rule CPU > 85%

### 5.2 Grafana

- Import dashboard Node Exporter Full với ID `1860`
- Kết nối datasource Prometheus và Loki

### 5.3 Loki + Promtail

- Promtail đọc Docker JSON logs:
  - `/var/lib/docker/containers/*/*-json.log`
- Log backend, frontend, nginx, mongodb đều có thể xem trong Grafana Explore

### 5.4 AlertManager

- Điền `TELEGRAM_BOT_TOKEN`
- Điền `TELEGRAM_CHAT_ID`
- Khi CPU vượt ngưỡng, alert sẽ bắn sang Telegram

## 6. Giai Đoạn DDoS / Post-mortem

### 6.1 Kiểm tra alert

- Tăng tải bằng `ab`
- Quan sát CPU trên Grafana
- Xác nhận AlertManager đã gửi cảnh báo Telegram

### 6.2 Tìm IP bất thường

Trong Grafana Explore dùng LogQL:

```logql
{job="docker"} |= "api"
```

hoặc lọc thêm theo IP:

```logql
{job="docker"} |= "127.0.0.1"
```

### 6.3 Post-mortem

- Nguyên nhân: request tăng đột biến
- Tác động: CPU tăng cao, latency cao
- Khắc phục: rate limit ở Nginx, chặn IP, tăng tài nguyên hoặc thêm load balancer

## 7. Lệnh kiểm tra nhanh

```bash
docker ps
docker compose -f app-stack/docker-compose.local.yml ps
docker compose -f monitoring-stack/docker-compose.yml ps
```

```bash
curl http://localhost:3001/api/products/top
curl http://localhost:9090/-/ready
```

