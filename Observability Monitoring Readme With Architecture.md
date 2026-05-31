# Observability / Monitoring Stack

## Tổng quan

Stack này dùng để:

* Monitor server metrics
* Monitor Docker containers
* Collect logs tập trung
* Visualize dashboards
* Setup alerting

---

# Kiến trúc tổng thể

![Observability Architecture](https://images.openai.com/static-rsc-4/Cei4OojhILXF9_Gj_D8BqPPcKBjf2PvjukAcDfihWY5WapYgk7BEKWci4EAUrxvLv1MOgp7OP9o8ZF7iefp-OOTM6NSN26EaZvUu5WfNJZzHwqKuN1nQoWNy93EoHpAsjtGoTBGrNP31R950ASG4-XjaqSeRg9w48g7AlnbDSnBskGdzj8o8FODBx515kbCJ?purpose=fullsize)

---

# Thành phần trong hệ thống

| Service       | Vai trò                       |
| ------------- | ----------------------------- |
| Prometheus    | Thu thập và lưu metrics       |
| Node Exporter | Metrics của host/server       |
| cAdvisor      | Metrics của Docker containers |
| Grafana       | Dashboard visualization       |
| Loki          | Log storage                   |
| Promtail      | Log collector                 |
| Alertmanager  | Gửi alerts                    |

---

# Metrics Flow

```text
Node Exporter ----\
                    \
cAdvisor -----------> Prometheus ---> Grafana
```

## Node Exporter

Expose metrics của host:

* CPU
* RAM
* Disk
* Filesystem
* Network

---

## cAdvisor

Monitor Docker containers:

* Container CPU
* Container Memory
* Network usage
* Restart count

---

## Prometheus

Prometheus sẽ:

* scrape metrics từ exporters
* lưu metrics time-series
* evaluate alert rules

Ví dụ metrics:

* CPU usage
* RAM usage
* Container memory
* Disk usage

---

# Logs Flow

```text
Docker Logs
     ↓
 Promtail
     ↓
   Loki
     ↓
 Grafana
```

---

## Promtail

Promtail đọc logs từ:

```text
/var/lib/docker/containers
```

Sau đó push logs sang Loki.

---

## Loki

Loki là centralized log storage.

Lưu:

* application logs
* container logs
* error logs

Loki thường expose API thay vì UI.

Root endpoint:

```text
http://localhost:3100
```

có thể trả:

```text
404 page not found
```

là bình thường.

Health check:

```text
http://localhost:3100/ready
```

---

# Grafana

Grafana là dashboard UI.

Port mặc định:

```text
3000
```

Truy cập:

```text
http://localhost:3000
```

Grafana dùng để:

* visualize metrics
* visualize logs
* create dashboards
* query Prometheus
* query Loki

---

# Alerting

```text
Prometheus
    ↓
Alertmanager
    ↓
Telegram / Slack / Email
```

---

## Alertmanager

Alertmanager nhận alerts từ Prometheus.

Ví dụ:

* CPU > 90%
* RAM gần full
* Container down
* Disk usage cao

Sau đó forward notification sang:

* Telegram
* Slack
* Discord
* Email

---

# Docker Compose Services

| Container     | Port |
| ------------- | ---- |
| Grafana       | 3000 |
| Prometheus    | 9090 |
| Alertmanager  | 9093 |
| Node Exporter | 9100 |
| cAdvisor      | 8080 |
| Loki          | 3100 |

---

# Grafana Datasources

## Prometheus

Datasource URL:

```text
http://prometheus:9090
```

---

## Loki

Datasource URL:

```text
http://loki:3100
```

---

# Xem Metrics

## Explore → Prometheus

Ví dụ query CPU:

```promql
rate(node_cpu_seconds_total[5m])
```

---

## RAM usage

```promql
node_memory_MemAvailable_bytes
```

---

## Container CPU

```promql
rate(container_cpu_usage_seconds_total[5m])
```

---

# Xem Logs

## Explore → Loki

Query toàn bộ logs:

```logql
{}
```

---

## Filter errors

```logql
{} |= "error"
```

---

## Logs backend container

```logql
{container="backend"}
```

---

# Dashboard IDs hữu ích

## Node Exporter Dashboard

```text
1860
```

---

## Docker Monitoring Dashboard

```text
193
```

---

## Loki Logs Dashboard

```text
13639
```

---

# Docker Network

```yaml
observability:
  external: true
```

Tạo network:

```bash
docker network create observability
```

---

# Named Volume

```yaml
grafana-data:/var/lib/grafana
```

Dùng để persist:

* dashboards
* datasource configs
* users

---

# Troubleshooting

## Loki 404

Bình thường.

Test:

```text
http://localhost:3100/ready
```

---

## Check containers

```bash
docker ps
```

---

## Check logs

```bash
docker logs <container>
```

---

## Prometheus targets

```text
http://localhost:9090/targets
```

---

# Best Practices

## Monitoring

* Monitor infrastructure metrics
* Monitor containers
* Setup alerts
* Collect centralized logs

---

## Docker

* Không hardcode secrets
* Không copy .env vào image
* Dùng immutable tags
* Dùng multi-stage builds

---

# Kiến trúc hoàn chỉnh

```text
Docker Containers
       ↓
Metrics + Logs
       ↓
Prometheus + Loki
       ↓
Grafana Dashboards
       ↓
Alerts → Telegram/Slack
```
