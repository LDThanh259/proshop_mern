# 🎓 Tài Liệu Trình Bày Capstone — Cloud Computing
## ProShop MERN: Triển Khai & Giám Sát Trên AWS

> **Server:** `54.252.128.91` | **Region:** AWS ap-southeast-2 (Sydney) | **Stack:** MERN + Docker + Prometheus + Grafana + Loki

---

## Tiêu Chí 1 — Kiến Trúc Triển Khai & Web HTTPS (2.0đ)

### 1.1 Kiến Trúc Tổng Quan

```
           INTERNET
              │
     ┌────────▼────────┐
     │  Route 53 / DNS  │  ldthanh259.io.vn → 54.252.128.91
     └────────┬────────┘
              │ HTTPS :443 / HTTP :80
     ┌────────▼──────────────────────────────────────────┐
     │         EC2: nginx-public-server                   │
     │         Public Subnet 10.0.1.0/24                  │
     │                                                    │
     │  ┌──────────────────────────────────────────────┐  │
     │  │  Nginx Reverse Proxy (port 80 → 443 redirect)│  │
     │  │  SSL: Let's Encrypt fullchain.pem             │  │
     │  └──────┬──────────────────────────┬────────────┘  │
     │         │ /                        │ /api/*         │
     │  ┌──────▼──────┐          ┌────────▼──────┐        │
     │  │  frontend   │          │   backend     │        │
     │  │  React:80   │          │  Node.js:5000 │        │
     │  └─────────────┘          └───────┬───────┘        │
     │                                   │ MongoDB         │
     └───────────────────────────────────┼────────────────┘
                                         │ Private IP
                              ┌──────────▼───────────┐
                              │  EC2: mongo-private   │
                              │  Private Subnet        │
                              │  10.0.2.0/24           │
                              │  MongoDB 7.0 :27017    │
                              └──────────────────────-┘
```

### 1.2 Web HTTPS Với Let's Encrypt

Chứng chỉ SSL được cấp bởi **Let's Encrypt** (CA miễn phí, được tin cậy bởi tất cả trình duyệt). Certbot tự động gia hạn 90 ngày một lần.

**Cấu hình Nginx SSL — `app-stack/nginx/default.ssl.conf.template`:**

```nginx
# ① Server HTTPS — nhận traffic chính
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${DOMAIN};

    # Chứng chỉ SSL từ Let's Encrypt
    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    # Proxy đến Frontend (React) — không expose port ra ngoài
    location / {
        proxy_pass http://frontend:80;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Proxy đến Backend (API) — không expose port ra ngoài
    location /api {
        proxy_pass http://backend:5000;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# ② Tự động redirect HTTP → HTTPS
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://$host$request_uri;   # 301 Permanent Redirect
}
```

**Lệnh cấp SSL với Certbot:**
```bash
# Cài certbot
sudo apt install certbot

# Cấp chứng chỉ (dừng nginx tạm thời để certbot verify)
sudo certbot certonly --standalone -d ldthanh259.io.vn

# Chứng chỉ được lưu tại:
# /etc/letsencrypt/live/ldthanh259.io.vn/fullchain.pem
# /etc/letsencrypt/live/ldthanh259.io.vn/privkey.pem

# Tự động gia hạn (thêm vào crontab)
0 3 * * * certbot renew --quiet
```

**Kết quả kiểm tra SSL:**
```
Domain:   ldthanh259.io.vn
Issuer:   Let's Encrypt (R10)
Protocol: TLS 1.3
Cipher:   TLS_AES_256_GCM_SHA384
Grade:    A  (SSL Labs)
Expires:  90 ngày từ ngày cấp, tự gia hạn
```

---

## Tiêu Chí 2 — Bảo Mật Cổng Nội Bộ (2.0đ)

### 2.1 Lớp Bảo Mật: AWS Security Group

Security Group là tường lửa ở cấp **AWS infrastructure** — không thể bypass dù có exploit ở tầng OS.

**Security Group cho Nginx (Public Server) — `terraform/main.tf`:**
```hcl
resource "aws_security_group" "nginx_sg" {
  # ✅ Chỉ mở 3 cổng từ internet:
  ingress { from_port = 22;  cidr_blocks = [var.admin_ip_cidr] }  # SSH admin
  ingress { from_port = 80;  cidr_blocks = ["0.0.0.0/0"] }        # HTTP
  ingress { from_port = 443; cidr_blocks = ["0.0.0.0/0"] }        # HTTPS

  # ❌ KHÔNG có rule nào cho port 3000, 5000, 27017, 9090, 3100...
  egress { from_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}
```

**Security Group cho MongoDB (Private Server):**
```hcl
resource "aws_security_group" "mongo_sg" {
  # ✅ MongoDB :27017 — CHỈ cho phép từ nginx_sg (không phải từ internet)
  ingress {
    from_port       = 27017
    security_groups = [aws_security_group.nginx_sg.id]  # Chỉ từ nginx!
    # KHÔNG có cidr_blocks = "0.0.0.0/0"
  }

  # ✅ SSH — chỉ từ nginx (Bastion Host pattern)
  ingress {
    from_port       = 22
    security_groups = [aws_security_group.nginx_sg.id]
  }
}
```

### 2.2 Lớp Bảo Mật: Private Subnet

MongoDB nằm trong **Private Subnet (10.0.2.0/24)** — không có Internet Gateway, không có IP public:

```
Internet → Internet Gateway → Route Table Public → Nginx (Public Subnet)
                                                         ↓ (chỉ traffic từ nginx)
Internet → ❌ BLOCKED                          → MongoDB (Private Subnet)
                                                  Không có route từ internet!
```

### 2.3 Lớp Bảo Mật: Docker Network Isolation

Trong Docker Compose, `frontend` và `backend` **không expose port** ra ngoài host — chỉ Nginx mới truy cập được qua Docker network nội bộ:

```yaml
# app-stack/docker-compose.yml
frontend:
  image: ghcr.io/ldthanh259/proshop_mern-frontend:latest
  # ❌ Không có "ports:" → không accessible từ ngoài container network

backend:
  image: ghcr.io/ldthanh259/proshop_mern-backend:latest
  # ❌ Không có "ports:" → port 5000 chỉ trong Docker network
```

### 2.4 Kiểm Chứng — Scan Từ Ngoài Internet

```bash
# Test scan các cổng nhạy cảm từ ngoài internet
nmap -p 3000,5000,27017,9090,3100,9100 54.252.128.91

# Kết quả mong đợi:
# PORT      STATE     SERVICE
# 3000/tcp  filtered  ppp           ← BLOCKED
# 5000/tcp  filtered  upnp          ← BLOCKED
# 27017/tcp filtered  mongod        ← BLOCKED
# 9090/tcp  filtered  zeus-admin    ← BLOCKED
# 3100/tcp  filtered  unknown       ← BLOCKED
# 9100/tcp  filtered  jetdirect     ← BLOCKED

# Chỉ mở:
# 22/tcp    open      ssh
# 80/tcp    open      http
# 443/tcp   open      https
```

### 2.5 Tóm Tắt Các Lớp Bảo Mật

| Lớp | Công cụ | Bảo vệ gì |
|-----|---------|-----------|
| **L1 - AWS Network** | Private Subnet | MongoDB không có IP public, không route internet |
| **L2 - AWS Firewall** | Security Group | Chặn port 3000, 5000, 27017 ở cấp infrastructure |
| **L3 - App Proxy** | Nginx Reverse Proxy | Tất cả traffic qua Nginx, filter theo URL path |
| **L4 - Container** | Docker Network | Service không expose port ra host nếu không khai báo |

---

## Tiêu Chí 3 — Dashboard Giám Sát Grafana (2.0đ)

### 3.1 Kiến Trúc Monitoring Stack

```
EC2 Host OS Metrics                 Docker Container Metrics
      │                                       │
      ▼                                       ▼
node-exporter:9100              cadvisor:8080
      │                                       │
      └──────────────┬────────────────────────┘
                     │ scrape mỗi 15 giây
                     ▼
              Prometheus:9090
                     │
                     ▼
               Grafana:3000
              (Dashboard UI)
```

### 3.2 Các Metrics Hiển Thị Trong Grafana

**📊 CPU Usage — PromQL:**
```promql
# % CPU đang bận của toàn bộ máy EC2
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)

# % CPU của từng Docker container
rate(container_cpu_usage_seconds_total{name!=""}[1m]) * 100
```

**📊 RAM Usage — PromQL:**
```promql
# % RAM đang dùng
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
  / node_memory_MemTotal_bytes * 100

# RAM usage chi tiết (MB)
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1024 / 1024
```

**📊 Network I/O — PromQL:**
```promql
# Băng thông nhận vào (bytes/s)
rate(node_network_receive_bytes_total{device="eth0"}[5m])

# Băng thông gửi ra (bytes/s)
rate(node_network_transmit_bytes_total{device="eth0"}[5m])
```

**📊 Disk I/O — PromQL:**
```promql
# Tốc độ đọc disk (bytes/s)
rate(node_disk_read_bytes_total[5m])

# Tốc độ ghi disk (bytes/s)
rate(node_disk_written_bytes_total[5m])

# % Disk đã dùng
(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100
```

**📊 Container-level Metrics — PromQL:**
```promql
# RAM từng container (MB)
container_memory_usage_bytes{name=~"nginx|frontend|backend|mongodb"}
  / 1024 / 1024

# CPU từng container (%)
rate(container_cpu_usage_seconds_total{name=~"nginx|frontend|backend"}[1m]) * 100
```

### 3.3 Cấu Hình Monitoring Stack — `docker-compose.yml`

```yaml
services:
  prometheus:
    image: prom/prometheus:v2.55.1
    ports: ["9090:9090"]
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/rules:/etc/prometheus/rules:ro   # Alert rules

  grafana:
    image: grafana/grafana:11.3.0
    ports: ["3000:3000"]
    volumes:
      - grafana-data:/var/lib/grafana  # Dashboard data persistent

  node-exporter:
    image: prom/node-exporter:v1.8.2
    ports: ["9100:9100"]              # Metrics EC2 host (CPU, RAM, Disk, Net)

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.55.1
    ports: ["8080:8080"]             # Metrics từng Docker container
    privileged: true                  # Cần để đọc cgroups
    volumes:
      - /:/rootfs:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
```

### 3.4 Prometheus Scrape Config

```yaml
# prometheus/prometheus.yml
global:
  scrape_interval: 15s   # Thu thập mỗi 15 giây

scrape_configs:
  - job_name: node-exporter
    static_configs:
      - targets: ["node-exporter:9100"]   # Metrics máy chủ

  - job_name: cadvisor
    static_configs:
      - targets: ["cadvisor:8080"]         # Metrics container
```

---

## Tiêu Chí 4 — Cảnh Báo Tự Động Telegram (1.5đ)

### 4.1 Pipeline Cảnh Báo Đầy Đủ

```
Prometheus            Alertmanager          Telegram
    │                      │                    │
    │  evaluate rule        │                    │
    │  mỗi 15 giây         │                    │
    │                      │                    │
    ├─ CPU > 85% (1m) ───► │                    │
    │  state: FIRING        │                    │
    │                      ├──── HTTP POST ─────►│
    │                      │  Telegram Bot API   │  📱 Alert nhận được
    │                      │                    │
```

### 4.2 Alert Rules Đã Triển Khai

**`prometheus/rules/cpu-alerts.yml`:**
```yaml
groups:
  - name: cpu-alerts
    rules:
      - alert: HighCpuUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100) > 85
        for: 1m          # Phải duy trì > 85% liên tục 1 phút mới fire
        labels:
          severity: warning
        annotations:
          summary: "CPU usage is above 85%"
          description: "CPU usage on {{ $labels.instance }} is above 85% for more than 1 minute."
```

**`prometheus/rules/ram-alerts.yml`:**
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

### 4.3 Alertmanager Gửi Telegram

**`alertmanager/alertmanager.yml`:**
```yaml
global:
  resolve_timeout: 5m

route:
  receiver: telegram-notifications
  group_wait: 10s       # Gom alert trong 10s, gửi 1 lần
  group_interval: 30s
  repeat_interval: 1h   # Không spam — lặp lại sau 1 giờ

receivers:
  - name: telegram-notifications
    telegram_configs:
      - bot_token: ${TELEGRAM_BOT_TOKEN}   # Token Bot từ @BotFather
        chat_id: ${TELEGRAM_CHAT_ID}       # ID Group Telegram nhóm
        message: |-
          {{ range .Alerts -}}
          {{ .Annotations.summary }}
          {{ .Annotations.description }}
          {{ end }}

# Tắt warning khi đã có critical (tránh spam)
inhibit_rules:
  - source_matchers: [severity="critical"]
    target_matchers: [severity="warning"]
    equal: [alertname, instance]
```

### 4.4 Công Cụ Test Tải — `test_alerts.sh`

Nhóm sử dụng script tự viết để tạo tải giả lập:

```bash
# Chạy trên server
bash /opt/proshop/test_alerts.sh
```

**Menu test:**
```
1. Tạo tải CPU 100%  → yes > /dev/null × (số lõi CPU)
2. Tạo tải RAM 90%   → Python bytearray chiếm RAM, giữ 10 phút
3. Cả hai CPU + RAM  → Kết hợp cả hai
4. Dừng tất cả       → killall yes + pkill python
```

**Cơ chế tạo tải CPU:**
```bash
CORES=$(nproc)                    # Đếm số lõi: 2
for i in $(seq 1 $CORES); do
    yes > /dev/null &             # Mỗi lõi chạy 1 tiến trình yes
done                              # → CPU Busy = 100%
```

**Cơ chế chiếm RAM:**
```python
# Đọc MemAvailable từ /proc/meminfo
# Cấp phát bytearray đủ để còn lại chỉ 10% RAM
# Giữ 10 phút rồi tự giải phóng
a = bytearray(to_allocate * 1024)
time.sleep(600)
```

### 4.5 Kết Quả Test Thực Tế (07/06/2026)

```
12:46:44  Chạy test_alerts.sh, chọn option 3 (CPU + RAM)
12:47:26  RAM vượt 85% → Prometheus: PENDING
12:48:26  RAM FIRING → Alertmanager → Telegram 📱
          Nội dung: "Memory usage is above 85%
                     Memory usage on node-exporter:9100 is above 85%...
                     Current usage is 87.57%."

12:51:11  CPU FIRING → Alertmanager → Telegram 📱
          Nội dung: "CPU usage is above 85%
                     CPU usage on node-exporter:9100 is above 85%..."

Kết quả API xác nhận:
  HighCpuUsage:    state=firing, value=100%
  HighMemoryUsage: state=firing, value=87.57%
```

**Lệnh xác nhận alert đang active:**
```bash
curl -s http://localhost:9090/api/v1/alerts
# → {"status":"success","data":{"alerts":[
#     {"alertname":"HighCpuUsage","state":"firing","value":"1e+02"},
#     {"alertname":"HighMemoryUsage","state":"firing","value":"87.57"}
#   ]}}
```

---

## Tiêu Chí 5 — Truy Vấn Log Tìm IP Tấn Công (1.5đ)

### 5.1 Kiến Trúc Thu Thập Log

```
Docker Containers (nginx, backend, frontend, mongodb)
    │ stdout/stderr
    ▼
/var/lib/docker/containers/<id>/<id>-json.log
    │
    ▼ Promtail đọc real-time
    │ (docker_sd_configs — tự discover container)
    │ gắn labels: container, service, group
    ▼
Loki:3100 (lưu trữ log theo time-series)
    │
    ▼
Grafana (query bằng LogQL)
```

### 5.2 Cấu Hình Promtail — Labels Thu Thập

**`monitoring-stack/promtail/config.yml`:**
```yaml
scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s     # Tự phát hiện container mới sau 5s

    relabel_configs:
      # Đường dẫn log file của container
      - source_labels: [__meta_docker_container_id]
        target_label: __path__
        replacement: /var/lib/docker/containers/$1/$1-json.log

      # Labels để filter khi query
      - source_labels: [__meta_docker_container_name]
        target_label: container   # Tên container: nginx, backend...

      - source_labels: [__meta_docker_container_label_com_docker_compose_service]
        target_label: service     # Tên service trong docker-compose

      - source_labels: [__meta_docker_container_label_com_docker_compose_service]
        target_label: group
        # app: frontend, backend, nginx
        # db: mongodb
        # monitoring: prometheus, grafana, loki...
```

### 5.3 Các Câu Lệnh LogQL Tìm IP Tấn Công

#### Query 1: Lọc tất cả request đến Nginx theo IP

```logql
{service="nginx"}
| pattern `<ip> - - [<timestamp>] "<method> <path> <protocol>" <status> <bytes>`
| line_format "IP: {{.ip}} | {{.method}} {{.path}} | Status: {{.status}}"
```

#### Query 2: Tìm IP có nhiều request nhất (Top Attackers)

```logql
# Đếm số lần xuất hiện của từng IP trong 1 giờ
topk(10,
  sum by (remote_addr) (
    count_over_time(
      {service="nginx"}
      | json
      | unwrap remote_addr
      [1h]
    )
  )
)
```

#### Query 3: Tìm IP gây ra nhiều lỗi HTTP 4xx/5xx

```logql
# Lọc các request lỗi (400-599)
{service="nginx"}
| pattern `<ip> - - [<_>] "<_>" <status> <_>`
| status >= 400
| line_format "🚨 IP: {{.ip}} | HTTP {{.status}}"
```

#### Query 4: Phát hiện tấn công brute-force (login nhiều lần)

```logql
# Đếm POST /api/users/login theo IP trong 5 phút
sum by (remote_addr) (
  count_over_time(
    {service="nginx"}
    | pattern `<remote_addr> - - [<_>] "POST /api/users/login <_>" <_> <_>`
    [5m]
  )
) > 10  # Hơn 10 lần login trong 5 phút = nghi ngờ brute-force
```

#### Query 5: Tìm IP scan port hoặc tấn công path traversal

```logql
{service="nginx"}
| pattern `<ip> - - [<timestamp>] "<method> <path> <_>" <status> <_>`
| path =~ ".*(etc/passwd|\.\.\/|\.git|wp-admin|phpmyadmin|\.env).*"
| line_format "⚠️ ATTACK from {{.ip}}: {{.method}} {{.path}} → HTTP {{.status}}"
```

#### Query 6: Tổng hợp IP đáng ngờ (rate cao bất thường)

```logql
# Rate request mỗi giây theo IP — phát hiện DDoS
rate(
  {service="nginx"}
  | pattern `<ip> - - [<_>] "<_>" <_> <_>`
  [1m]
) > 10   # Hơn 10 request/giây từ 1 IP = bất thường
```

### 5.4 Ví Dụ Thực Tế — Phân Tích Nginx Log

**Log format của Nginx:**
```
1.2.3.4 - - [07/Jun/2026:05:47:22 +0000] "GET /api/products HTTP/1.1" 200 1234
5.6.7.8 - - [07/Jun/2026:05:47:23 +0000] "POST /api/users/login HTTP/1.1" 401 45
5.6.7.8 - - [07/Jun/2026:05:47:23 +0000] "POST /api/users/login HTTP/1.1" 401 45
5.6.7.8 - - [07/Jun/2026:05:47:24 +0000] "POST /api/users/login HTTP/1.1" 401 45
9.8.7.6 - - [07/Jun/2026:05:47:25 +0000] "GET /.env HTTP/1.1" 404 12
9.8.7.6 - - [07/Jun/2026:05:47:25 +0000] "GET /wp-admin HTTP/1.1" 404 12
```

**Kết quả phân tích:**
```
🔴 IP 5.6.7.8 → Brute-force login: 3 lần POST /api/users/login trong 2 giây
⚠️ IP 9.8.7.6 → Scan vulnerability: quét /.env và /wp-admin
✅ IP 1.2.3.4 → Normal: 1 GET request, HTTP 200
```

**Hành động xử lý:**
```bash
# Block IP tấn công bằng iptables
sudo iptables -A INPUT -s 5.6.7.8 -j DROP
sudo iptables -A INPUT -s 9.8.7.6 -j DROP

# Hoặc block bằng Nginx (không cần sudo mỗi lần)
# Thêm vào nginx.conf:
deny 5.6.7.8;
deny 9.8.7.6;
```

---

## Tiêu Chí 6 — Câu Hỏi Thêm (Tham Khảo, +1.0đ)

### Q: Tại sao dùng `rate()` thay vì giá trị trực tiếp của `node_cpu_seconds_total`?

> `node_cpu_seconds_total` là **counter** — chỉ tăng, không giảm. Ví dụ: sau 1000 giây CPU đang chạy, giá trị là 1000. `rate()` tính **tốc độ tăng** trong khoảng thời gian → cho ra tỷ lệ phần trăm thực tế đang dùng.

### Q: `MemAvailable` khác `MemFree` ở điểm nào?

> `MemFree` = RAM chưa dùng tí nào.  
> `MemAvailable` = RAM còn dùng được, bao gồm cả RAM đang làm **disk cache** (Linux dùng RAM nhàn rỗi để cache → khi app cần, Linux tự giải phóng cache). `MemAvailable` thực tế hơn cho monitoring.

### Q: Tại sao MongoDB đặt trong Private Subnet thay vì chỉ dùng Security Group?

> **Defense in Depth** — 2 lớp bảo vệ tốt hơn 1:  
> - Security Group: có thể bị misconfigure (lỗi người dùng)  
> - Private Subnet: không có route internet vào, ngay cả khi Security Group sai thì cũng không vào được vì không có đường đi

### Q: `group_wait`, `group_interval`, `repeat_interval` trong Alertmanager khác nhau thế nào?

> - `group_wait: 10s` → Đợi 10s để **gom nhiều alert** vào 1 tin nhắn (tránh spam)  
> - `group_interval: 30s` → Nếu group đang fire có alert mới, đợi 30s rồi gửi lại  
> - `repeat_interval: 1h` → Cùng 1 alert đang firing, không gửi lặp lại trước 1 giờ

### Q: LogQL khác SQL ở điểm gì?

> LogQL là **stream-based**: query theo nhãn (label) để chọn stream log, sau đó filter nội dung bằng regex hoặc pattern. Không có JOIN, không có schema cố định. Loki không index nội dung log, chỉ index labels → rất nhẹ nhưng query phải scan full text.

### Q: Tại sao cần `for: 1m` trong alert rule?

> Tránh **false positive**: CPU có thể spike lên 90% trong vài giây khi khởi động process, sau đó về bình thường. `for: 1m` đảm bảo chỉ alert khi CPU **duy trì cao liên tục 1 phút** — tức là có vấn đề thật sự.

---

## Tóm Tắt Kỹ Thuật

| Tiêu chí | Công nghệ | Trạng thái |
|----------|-----------|------------|
| **1. HTTPS** | Nginx + Let's Encrypt SSL | ✅ Hoạt động |
| **2. Bảo mật** | AWS Security Group + Private Subnet | ✅ Port 27017, 5000, 3000 bị block |
| **3. Dashboard** | Grafana + Prometheus + node-exporter + cAdvisor | ✅ Realtime |
| **4. Alert Telegram** | Alertmanager → Telegram Bot | ✅ Test thành công 07/06/2026 |
| **5. Log phân tích** | Loki + Promtail + LogQL | ✅ Cấu hình sẵn |

```
┌──────────────────────────────────────────────────────────────┐
│                   TECHNOLOGY STACK                            │
├─────────────────┬────────────────────────────────────────────┤
│ Infrastructure  │ AWS: VPC, EC2, Security Group, NAT Gateway  │
│ IaC             │ Terraform                                    │
│ CI/CD           │ GitHub Actions → GHCR                        │
│ Runtime         │ Docker + Docker Compose                      │
│ Reverse Proxy   │ Nginx 1.27 + Let's Encrypt SSL               │
│ Application     │ MERN (MongoDB 7, Express, React, Node.js)    │
│ Metrics         │ Prometheus + node-exporter + cAdvisor        │
│ Logs            │ Loki + Promtail                               │
│ Dashboard       │ Grafana 11.3                                  │
│ Alerting        │ Alertmanager → Telegram Bot API              │
│ Alert Rules     │ PromQL: CPU [1m] > 85%, RAM > 85%            │
└─────────────────┴────────────────────────────────────────────┘
```
