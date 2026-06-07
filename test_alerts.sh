#!/bin/bash
# Script giả lập tải cao (CPU và RAM) và ghi log

LOG_FILE="/tmp/cpu_diagnostic.log"

echo "======================================"
echo "    CHỌN BÀI TEST BÁO ĐỘNG (ALERTS)"
echo "======================================"
echo "1. Tạo tải CPU cao 100% (Gây tuột Idle về 0%)"
echo "2. Tạo tải RAM cao 90% (Gây kích hoạt RAM Alert)"
echo "3. Cả hai (CPU 100% và RAM 90%)"
echo "4. Dừng tất cả bài test (Dọn dẹp)"
echo "5. Bật/Tắt bộ theo dõi ghi log CPU"
echo "6. Xem log chẩn đoán CPU"
echo -n "Nhập lựa chọn của bạn (1-6): "
read choice

case $choice in
  1)
    echo "Bắt đầu vắt kiệt CPU Busy..."
    CORES=$(nproc)
    for i in $(seq 1 $CORES); do
        yes > /dev/null &
    done
    echo "Đã khởi chạy $CORES tiến trình đốt CPU."
    ;;
  2)
    echo "Bắt đầu ngốn 90% RAM bằng Python..."
    # Dùng Python để phân bổ chính xác 90% RAM và giữ nó trong 10 phút, không ăn CPU
    python3 -c "
import time
meminfo = {}
with open('/proc/meminfo') as f:
    for line in f:
        parts = line.split()
        if len(parts) >= 2: meminfo[parts[0].strip(':')] = int(parts[1])
total = meminfo.get('MemTotal', 0)
avail = meminfo.get('MemAvailable', 0)
# Mục tiêu: để lại 10% RAM trống (nghĩa là dùng 90%)
target_avail = int(total * 0.10)
to_allocate = avail - target_avail
if to_allocate > 0:
    print(f'Đang chiếm dụng thêm {to_allocate/1024/1024:.2f} GB RAM... (Tự động nhả sau 10 phút)')
    try:
        a = bytearray(to_allocate * 1024)
        time.sleep(600)
    except Exception as e:
        print('Lỗi:', e)
else:
    print('RAM hiện tại đã vượt mức 90%, không cần chiếm thêm.')
" &
    echo "Tiến trình ngốn RAM đang chạy ngầm."
    ;;
  3)
    echo "Bắt đầu vắt kiệt CPU..."
    CORES=$(nproc)
    for i in $(seq 1 $CORES); do
        yes > /dev/null &
    done
    echo "Bắt đầu ngốn RAM..."
    python3 -c "import time; meminfo = {line.split()[0].strip(':'): int(line.split()[1]) for line in open('/proc/meminfo') if len(line.split()) >= 2}; total = meminfo.get('MemTotal', 0); avail = meminfo.get('MemAvailable', 0); target_avail = int(total * 0.10); to_allocate = avail - target_avail; a = bytearray(to_allocate * 1024) if to_allocate > 0 else None; time.sleep(600)" &
    echo "Đã bật cả test CPU và RAM."
    ;;
  4)
    echo "Đang dọn dẹp các tiến trình test..."
    killall yes 2>/dev/null
    pkill -f "bytearray" 2>/dev/null
    echo "Đã dừng và dọn dẹp tải CPU/RAM."
    ;;
  5)
    if pgrep -f "watch_cpu_log" > /dev/null; then
        pkill -f "watch_cpu_log" 2>/dev/null
        echo "Đã TẮT bộ theo dõi log CPU."
    else
        echo "Đang bật bộ theo dõi CPU ngầm (ghi mỗi 10 giây vào $LOG_FILE)..."
        cat << 'EOF' > /tmp/watch_cpu_log.sh
#!/bin/bash
while true; do
    echo "=== Thời gian: $(date) ===" >> /tmp/cpu_diagnostic.log
    ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 6 >> /tmp/cpu_diagnostic.log
    echo "" >> /tmp/cpu_diagnostic.log
    sleep 10
done
EOF
        chmod +x /tmp/watch_cpu_log.sh
        nohup /tmp/watch_cpu_log.sh > /dev/null 2>&1 &
        echo "Đã BẬT theo dõi."
    fi
    ;;
  6)
    if [ -f "$LOG_FILE" ]; then
        tail -n 30 "$LOG_FILE"
    else
        echo "Chưa có file log. Hãy chọn số 5 để bật."
    fi
    ;;
  *)
    echo "Lựa chọn không hợp lệ!"
    ;;
esac
