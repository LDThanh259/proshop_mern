# Deploy ProShop (phương án C)

Git là nguồn cấu hình deploy. EC2 chỉ chứa `app-stack/`, `monitoring-stack/`, `scripts/` tại `/opt/proshop` (không build `proshop_mern` trên server — dùng GHCR `ldthanh259`).

## Cấu trúc

| Thành phần | File |
|------------|------|
| App (GHCR) | `app-stack/docker-compose.yml` |
| Nginx HTTP (local) | `app-stack/nginx/default.http.conf` |
| Nginx HTTPS (EC2) | `app-stack/nginx/default.ssl.conf.template` → render `default.conf` |
| Monitoring base | `monitoring-stack/docker-compose.yml` |
| Monitoring prod | `monitoring-stack/docker-compose.prod.yml` |
| Deploy | `scripts/deploy-ec2.sh` |

Network dùng chung: `observability` (external).

## Lần đầu trên EC2

```bash
sudo mkdir -p /opt/proshop
sudo chown -R ubuntu:ubuntu /opt/proshop   # hoặc user deploy của bạn

# Từ máy dev (Git Bash / WSL / PowerShell)
export EC2_HOST=testuser@YOUR_EC2_IP
export SSH_KEY=/path/to/test_key
export SUDO_PASSWORD=testuser   # password sudo của testuser
./scripts/sync-to-ec2.sh

# Windows PowerShell:
# $env:EC2_HOST="testuser@3.107.1.188"; $env:SSH_KEY="...\test_key"; .\scripts\sync-to-ec2.ps1

# Trên EC2
cp /opt/proshop/.env.example /opt/proshop/.env   # nếu chưa có — chỉnh secret thật
nano /opt/proshop/monitoring-stack/.env          # TELEGRAM_*, GRAFANA_*

# Certbot (một lần, cần DOMAIN trỏ về EC2)
sudo certbot certonly --standalone -d proshop-mern.duckdns.org

# Deploy
cd /opt/proshop
export DOMAIN=proshop-mern.duckdns.org
sudo -E bash scripts/deploy-ec2.sh
```

## Local (Docker)

```bash
docker network create observability 2>/dev/null || true

cp .env.example app-stack/.env
# chỉnh JWT_SECRET, ...

cd app-stack
docker compose -f docker-compose.local.yml up -d --build

cd ../monitoring-stack
cp ../.env.example .env
docker compose up -d
```

Local dùng `default.http.conf` (mount trong `docker-compose.local.yml`), port 80 only.

## Cập nhật sau khi sửa Git

```bash
./scripts/sync-to-ec2.sh
ssh -i $SSH_KEY $EC2_HOST 'echo testuser | sudo -S bash /opt/proshop/scripts/deploy-ec2.sh'
```

## Biến môi trường

Xem `.env.example`. Backend bắt buộc có `JWT_SECRET`; `PAYPAL_CLIENT_ID` có thể để trống nếu không demo thanh toán.

Alertmanager đọc `TELEGRAM_BOT_TOKEN` và `TELEGRAM_CHAT_ID` từ `monitoring-stack/.env` (không hardcode trong YAML).

## Grafana: dashboard không có data

| Dashboard | Nguyên nhân thường gặp | Cách xử lý |
|-----------|------------------------|------------|
| **Node Exporter Full** | `job=node-exporter` | Mặc định đúng — đã scrape OK |
| **Cadvisor / Docker monitoring** | cAdvisor &lt; v0.55 lỗi Docker driver `overlayfs` → chỉ metric `id="/"` | Dùng **cAdvisor v0.55.1**; trong Grafana chọn biến **Host** = `cadvisor:8080`, **Container** ≠ All |
| **Logs / App** | Dashboard cần label `app`; Promtail trước đó chỉ gửi `service` | Đã map `app` từ compose service; Explore: `{service="nginx"}` hoặc `{app="backend"}` |
| **Alertmanager** | Flag `--config.expand-env` không có trên v0.27 | Chạy `scripts/render-alertmanager.sh` trước khi `up` |

Kiểm tra nhanh trên server:

```bash
# Prometheus: cAdvisor phải có nhiều hơn 1 series container_*
curl -s 'http://127.0.0.1:9090/api/v1/query?query=count(container_cpu_usage_seconds_total)by(id)' | head

# Loki: phải có label service/app
curl -s 'http://127.0.0.1:3100/loki/api/v1/label/service/values'
```

## Kiểm tra

```bash
curl -k https://YOUR_DOMAIN/api/products/top
curl http://127.0.0.1:9090/-/ready
curl http://127.0.0.1:3000/api/health
docker ps
```

## Security Group (lecture)

Chỉ mở **22** (IP cá nhân), **80**, **443**. Không mở 27017, 3000, 9090 ra Internet; truy cập Grafana qua SSH tunnel nếu cần:

```bash
ssh -i test_key -L 3000:127.0.0.1:3000 testuser@EC2_IP
```
