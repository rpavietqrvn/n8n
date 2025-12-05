# 🚀 N8N Production Stack với Automated Backup & Auto-Recovery

Hệ thống N8N production-ready với:
- ✅ **Backup tự động** hàng ngày
- ✅ **Watchdog Auto-Recovery** - Tự động restore khi N8N down
- ✅ **Telegram Notifications** - Thông báo realtime
- ✅ **Scalable Workers** - Queue processing với Redis
- ✅ **Disaster Recovery** - Restore nhanh chóng

---

## 📁 Cấu Trúc Project

```
d:\portainer\project/
├── n8n-stack/                    # 🟢 N8N Production Stack
│   ├── docker-compose.yml        # Main services (n8n, postgres, redis, worker)
│   ├── .env.example              # Template environment variables
│   └── README.md                 # Hướng dẫn n8n-stack
│
├── backup-stack/                 # 🔵 Backup & Auto-Recovery System
│   ├── docker-compose.yml        # Backup runner + Watchdog + Backup DB
│   ├── docker-compose.restore.yml # Template restore N8N (manual)
│   ├── backup.env                # Configuration (credentials, schedule)
│   ├── scripts/
│   │   ├── n8n_backup.sh         # Script backup tự động (cron)
│   │   ├── restore_n8n.sh        # Script restore từ backup
│   │   └── watchdog.sh           # Script giám sát + auto-recovery
│   ├── backup_volume/            # Lưu trữ backup files (gitignored)
│   │   ├── daily/                # Database dumps (.sql.gz)
│   │   ├── files/                # Volume archives (.tar.gz)
│   │   └── logs/                 # Backup logs
│   └── README-RESTORE.md         # Hướng dẫn restore chi tiết
│
├── portainer-stack/              # 🟣 Docker Management UI
│   └── docker-compose.yml
│
├── watchtower-stack/             # 🟡 Auto-update containers (optional)
│
├── DEPLOYMENT-CHECKLIST.md       # Checklist triển khai từ A-Z
├── REVIEW-SUMMARY.md             # Review notes
├── clean-n8n.ps1                 # Script cleanup (Windows)
└── .gitignore                    # Git ignore file
```

---

## ⚡ Quick Start

### 1️⃣ Tạo Network
```bash
docker network create n8n_network
```

### 2️⃣ Cấu Hình N8N Stack
```bash
cd n8n-stack
cp .env.example .env
# Chỉnh sửa .env (đặc biệt: passwords, encryption key, domain)
nano .env
```

### 3️⃣ Khởi Động N8N
```bash
docker compose up -d
```

### 4️⃣ Cấu Hình Backup
```bash
cd ../backup-stack
# Chỉnh sửa backup.env (credentials, retention, cron schedule)
nano backup.env
docker compose up -d
```

### 5️⃣ Bật Watchdog Auto-Recovery (Optional)
```bash
cd backup-stack
docker compose --profile watchdog up -d
```

### 6️⃣ Truy Cập N8N
```
http://localhost:5678          # N8N chính
http://localhost:5679          # N8N restored (khi auto-recovery)
```

**📖 Chi tiết đầy đủ:** Xem file [DEPLOYMENT-CHECKLIST.md](./DEPLOYMENT-CHECKLIST.md)

---

## 🎯 Tính Năng

### N8N Production Stack
- ✅ **PostgreSQL 14** - Database chính
- ✅ **Redis 7** - Queue system cho async workflows
- ✅ **N8N Worker** - Scalable workers (có thể chạy nhiều workers)
- ✅ **Resource Limits** - CPU/Memory limits cho từng service
- ✅ **Healthchecks** - Tự động kiểm tra health
- ✅ **Security** - Non-root user, security-opt, encryption key

### Automated Backup System
- ✅ **Dual Backup** - Backup cả database (SQL) và files (volume)
- ✅ **Automated** - Chạy tự động theo cron (mặc định 1h sáng)
- ✅ **Verification** - Restore vào backup DB để verify
- ✅ **Retention Policy** - Tự động xóa backup cũ hơn N ngày
- ✅ **Logging** - Log chi tiết mọi hoạt động
- ✅ **Telegram Notification** - Thông báo khi backup thành công/fail
- ✅ **Read-only Mount** - Mount volume nguồn ở chế độ read-only

### Disaster Recovery
- ✅ **Full Restore** - Script restore tự động từ backup
- ✅ **Standalone Stack** - Có thể restore sang server mới
- ✅ **Documentation** - Hướng dẫn restore chi tiết

### 🆕 Watchdog Auto-Recovery
- ✅ **Health Monitoring** - Kiểm tra N8N health mỗi 30s
- ✅ **Auto-Detect Failure** - Phát hiện N8N down sau 3 lần fail
- ✅ **Auto-Restore** - Tự động restore từ backup mới nhất
- ✅ **Telegram Alerts** - Thông báo khi N8N down và khi restore xong
- ✅ **Cooldown Period** - Tránh restore liên tục (5 phút)
- ✅ **Separate Instance** - N8N restored chạy trên port 5679

---

## 📊 Kiến Trúc

### Network Topology
```
┌──────────────────────────────────────────────────────────────────┐
│  n8n_network (bridge)                                            │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  n8n-stack (Production)                                     ││
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    ││
│  │  │   n8n    │  │  n8n-    │  │ postgres │  │  redis   │    ││
│  │  │  :5678   │  │  worker  │  │  :5432   │  │  :6379   │    ││
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘    ││
│  └─────────────────────────────────────────────────────────────┘│
│                              ▲                                   │
│                              │ health check                      │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  backup-stack                                               ││
│  │  ┌────────────┐  ┌─────────────┐  ┌──────────────┐         ││
│  │  │ backup-    │  │ backup-     │  │  watchdog    │         ││
│  │  │ runner     │  │ postgres    │  │ (optional)   │         ││
│  │  │ (cron)     │  │             │  │              │         ││
│  │  └────────────┘  └─────────────┘  └──────────────┘         ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│                              ▼ auto-restore                      │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  restored-stack (Auto-created khi N8N down)                 ││
│  │  ┌──────────────────┐  ┌─────────────────────┐             ││
│  │  │  n8n-restored    │  │ n8n-postgres-       │             ││
│  │  │     :5679        │  │ restored            │             ││
│  │  └──────────────────┘  └─────────────────────┘             ││
│  └─────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────┘
```

### Backup Flow
```
[Cron: 1h sáng mỗi ngày]
       ↓
┌──────────────────┐
│ n8n_backup.sh    │
└──────────────────┘
       ↓
┌──────────────────────────────────────────┐
│ 1. Dump DB từ n8n-production            │
│    → /backup/daily/n8n_backup_*.sql.gz  │
└──────────────────────────────────────────┘
       ↓
┌──────────────────────────────────────────┐
│ 2. Restore vào backup-postgres (verify) │
└──────────────────────────────────────────┘
       ↓
┌──────────────────────────────────────────┐
│ 3. Tar volume n8n-storage                │
│    → /backup/files/n8n_files_*.tar.gz   │
└──────────────────────────────────────────┘
       ↓
┌──────────────────────────────────────────┐
│ 4. Cleanup backup cũ hơn N ngày         │
└──────────────────────────────────────────┘
       ↓
┌──────────────────────────────────────────┐
│ 5. Send Telegram notification (optional)│
└──────────────────────────────────────────┘
```

### Restore Flow
```
[Chạy restore_n8n.sh]
       ↓
┌────────────────────────────────────┐
│ 1. Tìm backup mới nhất             │
└────────────────────────────────────┘
       ↓
┌────────────────────────────────────┐
│ 2. Tạo container postgres mới      │
│    n8n-postgres-restored           │
└────────────────────────────────────┘
       ↓
┌────────────────────────────────────┐
│ 3. Restore DB từ .sql.gz           │
└────────────────────────────────────┘
       ↓
┌────────────────────────────────────┐
│ 4. Restore volume từ .tar.gz       │
│    n8n-storage-restored            │
└────────────────────────────────────┘
       ↓
┌────────────────────────────────────┐
│ 5. Dựng stack N8N mới với          │
│    docker-compose.restore.yml      │
└────────────────────────────────────┘
```

### 🆕 Watchdog Auto-Recovery Flow
```
┌─────────────────────────────────────────────────────────────────┐
│                    N8N WATCHDOG SERVICE                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Check N8N Health (mỗi 30s)   │
              │  GET http://n8n:5678/healthz  │
              └───────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
              ┌──────────┐        ┌──────────┐
              │ Healthy  │        │Unhealthy │
              │   ✓      │        │    ✗     │
              └──────────┘        └──────────┘
                    │                   │
                    ▼                   ▼
              Reset counter      Increment counter
                    │                   │
                    │         ┌─────────┴─────────┐
                    │         ▼                   ▼
                    │   ┌──────────┐        ┌──────────┐
                    │   │ < 3 lần  │        │ >= 3 lần │
                    │   │ ⚠️ Warn  │        │ 🔴 CRIT  │
                    │   └──────────┘        └──────────┘
                    │         │                   │
                    │         ▼                   ▼
                    │   Telegram Alert     ┌─────────────────┐
                    │                      │ TRIGGER RESTORE │
                    │                      └─────────────────┘
                    │                             │
                    │         ┌───────────────────┴───────────────────┐
                    │         ▼                                       ▼
                    │   ┌─────────────┐                    ┌─────────────────┐
                    │   │ Restore DB  │                    │ Restore Volume  │
                    │   │ (31 tables) │                    │ (n8n-storage)   │
                    │   └─────────────┘                    └─────────────────┘
                    │         │                                       │
                    │         └───────────────────┬───────────────────┘
                    │                             ▼
                    │                 ┌─────────────────────┐
                    │                 │ Start n8n-restored  │
                    │                 │     port 5679       │
                    │                 └─────────────────────┘
                    │                             │
                    │                             ▼
                    │                 ┌─────────────────────┐
                    │                 │ Telegram: Restored! │
                    │                 │        ✅           │
                    │                 └─────────────────────┘
                    │                             │
                    └─────────────────────────────┘
                              │
                              ▼
                     [Loop every 30s]
```

**Timeline khi N8N down:**
| Thời gian | Sự kiện |
|-----------|---------|
| T+0s | N8N stop/crash |
| T+30s | Watchdog detect fail #1 → Telegram ⚠️ |
| T+60s | Fail #2 → Telegram ⚠️ |
| T+90s | Fail #3 → **TRIGGER RESTORE** 🔴 |
| T+100s | Restore DB từ backup |
| T+110s | Restore volume từ backup |
| T+120s | Start n8n-restored |
| T+150s | N8N restored ready → Telegram ✅ |

---

## 🔧 Cấu Hình Nâng Cao

### Scale Workers
```bash
# Tăng số lượng workers lên 3
cd n8n-stack
docker compose up -d --scale n8n-worker=3
```

### Thay Đổi Backup Schedule
Sửa file `backup-stack/backup.env`:
```bash
# Chạy backup 2h sáng mỗi ngày
BACKUP_CRON_SCHEDULE=0 2 * * *

# Chạy backup mỗi 6 giờ
BACKUP_CRON_SCHEDULE=0 */6 * * *

# Chạy backup mỗi 30 phút (test)
BACKUP_CRON_SCHEDULE=*/30 * * * *
```

### Thay Đổi Retention Policy
```bash
# Giữ backup trong 30 ngày
BACKUP_RETENTION_DAYS=30

# Giữ backup trong 7 ngày
BACKUP_RETENTION_DAYS=7
```

### Cấu Hình Watchdog
Trong `backup-stack/docker-compose.yml`:
```yaml
environment:
  N8N_HEALTH_URL: http://n8n:5678/healthz  # URL health check
  CHECK_INTERVAL: "30"                      # Kiểm tra mỗi 30s
  MAX_FAILURES: "3"                         # 3 lần fail → restore
  RESTORE_COOLDOWN: "300"                   # Đợi 5 phút giữa các lần restore
```

**Bật/Tắt Watchdog:**
```bash
# Bật watchdog
docker compose --profile watchdog up -d

# Tắt watchdog (giữ backup-runner)
docker stop n8n-watchdog

# Xem logs watchdog
docker logs -f n8n-watchdog
```

---

## 🚨 Xử Lý Sự Cố

### N8N không kết nối được Database
```bash
# 1. Check Postgres có chạy không
docker ps | grep postgres

# 2. Check healthcheck
docker inspect n8n-postgres | grep -A 5 Health

# 3. Xem logs
docker logs n8n-postgres

# 4. Test connection thủ công
docker exec -it n8n-postgres psql -U lequyet_n8n -d n8n -c '\dt'
```

### Backup Fail
```bash
# 1. Xem log backup
tail -f backup-stack/backup_volume/logs/backup_$(date +%Y%m%d).log

# 2. Test backup thủ công
docker exec -it n8n-backup-runner /scripts/n8n_backup.sh

# 3. Check credentials
docker exec -it n8n-backup-runner env | grep POSTGRES

# 4. Check network
docker network inspect n8n_network
```

### N8N Chậm/Lag
```bash
# 1. Check resource usage
docker stats

# 2. Tăng memory limit trong docker-compose.yml
# 3. Scale thêm workers
docker compose up -d --scale n8n-worker=3

# 4. Check Redis
docker logs n8n-redis
```

### Watchdog/Auto-Restore Issues
```bash
# 1. Xem logs watchdog
docker logs n8n-watchdog --tail 50

# 2. Test restore thủ công
docker exec n8n-watchdog /scripts/restore_n8n.sh

# 3. Kiểm tra backup files có tồn tại không
ls backup-stack/backup_volume/daily/
ls backup-stack/backup_volume/files/

# 4. Xóa restored containers để test lại
docker rm -f n8n-restored n8n-postgres-restored
docker volume rm n8n-storage-restored

# 5. Restart watchdog
docker restart n8n-watchdog
```

### Sau khi Auto-Restore
```bash
# N8N restored chạy trên port 5679
# Để quay lại N8N gốc:

# 1. Start N8N gốc
docker start n8n

# 2. Xóa N8N restored
docker rm -f n8n-restored n8n-postgres-restored
docker volume rm n8n-storage-restored
```

---

## 📚 Tài Liệu Tham Khảo

- [DEPLOYMENT-CHECKLIST.md](./DEPLOYMENT-CHECKLIST.md) - Checklist triển khai đầy đủ
- [backup-stack/README-RESTORE.md](./backup-stack/README-RESTORE.md) - Hướng dẫn restore chi tiết
- [N8N Official Docs](https://docs.n8n.io/)
- [N8N Self-Hosting Guide](https://docs.n8n.io/hosting/)

---

## 🔐 Security Best Practices

1. **Đổi tất cả passwords mặc định**
   - Postgres password
   - Redis password
   - Backup DB password

2. **Bảo vệ Encryption Key**
   - Generate key mạnh (min 32 chars)
   - Backup key ra nơi an toàn
   - KHÔNG commit vào Git

3. **Enable HTTPS**
   - Dùng reverse proxy (Nginx/Traefik)
   - Install SSL certificate (Let's Encrypt)
   - Set `N8N_SECURE_COOKIE=true`

4. **Network Security**
   - Không expose Postgres/Redis ports ra ngoài
   - Dùng firewall giới hạn access
   - Network isolation giữa các stacks

5. **Backup Off-Site**
   - Upload backup lên cloud storage
   - Encrypt backup trước khi upload
   - Test restore định kỳ

---

## 📈 Monitoring & Alerts

### Metrics
```bash
# N8N có sẵn metrics endpoint
curl http://localhost:5678/metrics
```

### Prometheus (Optional)
Thêm Prometheus để scrape metrics từ N8N

### Grafana (Optional)
Dùng Grafana để visualize metrics

### Telegram Alerts
Backup script đã tích hợp Telegram notification. Để enable:
1. Tạo bot qua @BotFather
2. Lấy bot token và chat ID
3. Điền vào `backup-stack/backup.env`

---

## 🤝 Contributing

Nếu bạn tìm thấy bug hoặc có ý tưởng cải thiện:
1. Tạo issue để thảo luận
2. Fork repo và tạo branch mới
3. Submit pull request

---

## 📝 License

This project is provided as-is for personal and commercial use.

---

## 👤 Author

**N8N Portainer Production Stack**
- Tạo bởi: VietQR
- Email: VietQR
- GitHub: VietQR

---

## 🎯 Roadmap

- [x] ~~Watchdog Auto-Recovery~~ ✅ **DONE**
- [x] ~~Telegram Notifications~~ ✅ **DONE**
- [ ] Watchtower integration (auto-update containers)
- [ ] Prometheus + Grafana monitoring stack
- [ ] Automated off-site backup (S3/GCS)
- [ ] Multi-region replication
- [ ] Kubernetes deployment template
- [ ] Ansible playbook cho automated deployment

---



# n8n
