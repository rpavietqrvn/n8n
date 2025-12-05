# 📋 Checklist Triển Khai N8N Production

Checklist này giúp đảm bảo bạn đã cấu hình đầy đủ trước khi chạy production.

---

## ✅ Bước 1: Chuẩn Bị Môi Trường

### 1.1 Cài Đặt Docker
- [ ] Docker Engine đã cài đặt (version >= 20.10)
- [ ] Docker Compose đã cài đặt (version >= 2.0)
- [ ] User hiện tại có quyền chạy Docker (hoặc dùng sudo)

**Kiểm tra:**
```bash
docker --version
docker compose version
docker ps
```

### 1.2 Tạo Network
- [ ] Tạo network `n8n_network` cho các stack

```bash
docker network create n8n_network
```

---

## ✅ Bước 2: Cấu Hình N8N Stack

### 2.1 Tạo File Environment
- [ ] Copy `.env.example` thành `.env`
- [ ] Điền đầy đủ thông tin trong `.env`

```bash
cd n8n-stack
cp .env.example .env
nano .env  # hoặc editor khác
```

### 2.2 Cấu Hình Quan Trọng
- [ ] **POSTGRES_NON_ROOT_PASSWORD**: Đổi từ `123456` thành password mạnh
- [ ] **REDIS_PASSWORD**: Đổi thành password mạnh
- [ ] **N8N_ENCRYPTION_KEY**: Generate key mạnh (min 10 ký tự)
- [ ] **N8N_HOST**: Điền domain hoặc IP của server
- [ ] **WEBHOOK_URL**: Điền URL đầy đủ (http://domain.com/ hoặc https://)

**Generate encryption key:**
```bash
# Cách 1: OpenSSL
openssl rand -hex 16

# Cách 2: Node.js
node -e "console.log(require('crypto').randomBytes(16).toString('hex'))"

# Cách 3: /dev/urandom
head -c 16 /dev/urandom | base64
```

### 2.3 Kiểm Tra Schema
- [ ] Xác định dùng schema nào: `public` hay `n8n_vietqr`
- [ ] Nếu dùng `n8n_vietqr`: Set `POSTGRES_SCHEMA=n8n_vietqr` trong `.env`
- [ ] Nếu dùng `public`: Xóa file `init-db/create-n8n-schema.sql`

### 2.4 HTTPS (Nếu Cần)
- [ ] Nếu dùng HTTPS, set `N8N_SECURE_COOKIE=true`
- [ ] Cấu hình reverse proxy (Nginx/Traefik/Caddy)
- [ ] Cài đặt SSL certificate

---

## ✅ Bước 3: Khởi Động N8N Stack

### 3.1 Start Services
```bash
cd n8n-stack
docker compose up -d
```

### 3.2 Kiểm Tra Logs
```bash
# Xem logs tất cả services
docker compose logs -f

# Xem log từng service
docker compose logs -f n8n
docker compose logs -f postgres
docker compose logs -f redis
```

### 3.3 Verify Services
- [ ] PostgreSQL healthy: `docker ps | grep n8n-postgres`
- [ ] Redis healthy: `docker ps | grep n8n-redis`
- [ ] N8N running: `docker ps | grep n8n`
- [ ] Worker running: `docker ps | grep n8n-worker`

### 3.4 Truy Cập N8N
- [ ] Truy cập: `http://localhost:5678` (hoặc domain đã cấu hình)
- [ ] Tạo tài khoản admin
- [ ] Đăng nhập thành công

---

## ✅ Bước 4: Cấu Hình Backup Stack

### 4.1 Cấu Hình backup.env
- [ ] Mở file `backup-stack/backup.env`
- [ ] Điền thông tin Postgres nguồn (n8n-production):
  - `POSTGRES_SOURCE_HOST=postgres`
  - `POSTGRES_SOURCE_USER=lequyet_n8n` (phải khớp với n8n stack)
  - `POSTGRES_SOURCE_PASSWORD=<password của n8n stack>`
- [ ] Đổi password backup DB:
  - `BACKUP_POSTGRES_PASSWORD=<password mạnh>`
- [ ] Cấu hình retention: `BACKUP_RETENTION_DAYS=5` (hoặc số ngày khác)
- [ ] Cấu hình cron: `BACKUP_CRON_SCHEDULE=0 1 * * *` (1h sáng mỗi ngày)

### 4.2 Cấu Hình Telegram Notification (Optional)
- [ ] Tạo Telegram bot qua @BotFather
- [ ] Lấy bot token
- [ ] Lấy chat ID (gửi message cho bot, xem qua API)
- [ ] Điền vào `backup.env`:
  - `TELEGRAM_BOT_TOKEN=<your_token>`
  - `TELEGRAM_CHAT_ID=<your_chat_id>`

### 4.3 Khởi Động Backup Stack
```bash
cd backup-stack
docker compose up -d
```

### 4.4 Test Backup Ngay
```bash
# Chạy backup thủ công để test
docker exec -it n8n-backup-runner /scripts/n8n_backup.sh
```

### 4.5 Kiểm Tra Kết Quả
- [ ] Check log: `tail -f backup-stack/backup_volume/logs/backup_*.log`
- [ ] Verify file backup tạo ra:
  - `backup-stack/backup_volume/daily/n8n_backup_*.sql.gz`
  - `backup-stack/backup_volume/files/n8n_files_*.tar.gz`
- [ ] Nếu có Telegram, check đã nhận notification chưa

---

## ✅ Bước 5: Test Restore (QUAN TRỌNG!)

### 5.1 Chạy Script Restore
```bash
docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v d:/portainer/project/backup-stack/backup_volume:/backup \
  -v d:/portainer/project/backup-stack/scripts:/scripts \
  --network n8n_network \
  alpine sh /scripts/restore_n8n.sh
```

### 5.2 Kiểm Tra Kết Quả
- [ ] Container `n8n-postgres-restored` đã tạo
- [ ] Volume `n8n-storage-restored` đã tạo
- [ ] Không có lỗi trong log

### 5.3 Dựng Stack Restored
```bash
cd backup-stack
docker compose -f docker-compose.restore.yml up -d
```

### 5.4 Verify N8N Restored
- [ ] Truy cập: `http://localhost:5679`
- [ ] Đăng nhập bằng tài khoản cũ
- [ ] Workflows có đầy đủ
- [ ] Credentials hoạt động

### 5.5 Dọn Dẹp Test
```bash
# Stop n8n restored
docker compose -f docker-compose.restore.yml down

# Xóa container và volume test (optional)
docker rm -f n8n-postgres-restored
docker volume rm n8n-storage-restored n8n-postgres-restored-data
```

---

## ✅ Bước 6: Portainer (Optional)

### 6.1 Khởi Động Portainer
```bash
cd portainer-stack
docker compose up -d
```

### 6.2 Truy Cập Portainer
- [ ] Truy cập: `http://localhost:9000`
- [ ] Tạo tài khoản admin
- [ ] Kết nối với Docker local environment

---

## ✅ Bước 7: Monitoring & Maintenance

### 7.1 Log Monitoring
- [ ] Thiết lập log rotation (đã config trong compose)
- [ ] Định kỳ check logs:
  ```bash
  docker logs n8n --tail 100
  docker logs n8n-backup-runner --tail 100
  ```

### 7.2 Backup Verification
- [ ] Hàng tuần: Kiểm tra backup log
- [ ] Hàng tháng: Test restore để đảm bảo backup hoạt động

### 7.3 Resource Monitoring
```bash
# Xem resource usage
docker stats

# Xem disk usage
docker system df -v
```

### 7.4 Update Strategy
- [ ] Subscribe N8N release notes
- [ ] Test updates trên môi trường staging trước
- [ ] Backup trước khi update

---

## ✅ Bước 8: Security Hardening

### 8.1 Firewall
- [ ] Chỉ mở port cần thiết (5678 cho N8N, 9000 cho Portainer)
- [ ] Block direct access tới Postgres/Redis port

### 8.2 SSL/TLS
- [ ] Cài đặt SSL certificate (Let's Encrypt)
- [ ] Force HTTPS
- [ ] Set `N8N_SECURE_COOKIE=true`

### 8.3 Access Control
- [ ] Dùng mật khẩu mạnh cho tất cả services
- [ ] Enable 2FA cho N8N (nếu có)
- [ ] Giới hạn login attempts

### 8.4 Network Isolation
- [ ] Verify network isolation giữa các stack
- [ ] Không expose Postgres/Redis ra ngoài

---

## ✅ Bước 9: Backup Off-Site (Recommended)

### 9.1 Tự Động Upload Backup
Thêm script upload lên cloud storage (S3, Google Drive, etc.)

```bash
# Example với rclone
docker exec n8n-backup-runner sh -c \
  "rclone sync /backup remote:n8n-backup"
```

### 9.2 Encrypt Backup
```bash
# Encrypt trước khi upload
gpg --symmetric --cipher-algo AES256 backup_file.tar.gz
```

---

## ✅ Bước 10: Documentation

### 10.1 Lưu Thông Tin Quan Trọng
- [ ] Encryption key (lưu ở nơi an toàn, KHÔNG commit vào Git)
- [ ] Database passwords
- [ ] Telegram bot token (nếu dùng)
- [ ] Domain/IP server

### 10.2 Tạo Runbook
- [ ] Quy trình restart services
- [ ] Quy trình restore từ backup
- [ ] Quy trình troubleshooting

---

## 🎯 Final Checklist

- [ ] N8N stack chạy ổn định
- [ ] Backup tự động hoạt động
- [ ] Đã test restore thành công
- [ ] Monitoring đã setup
- [ ] Security hardening đã áp dụng
- [ ] Đã backup encryption key
- [ ] Team đã được training về restore procedure

---

## 📞 Troubleshooting

### N8N không khởi động
1. Check logs: `docker logs n8n`
2. Verify DB connection: `docker exec n8n-postgres pg_isready`
3. Check .env file có đầy đủ không

### Backup fail
1. Check log: `tail -f backup-stack/backup_volume/logs/backup_*.log`
2. Verify network: `docker network inspect n8n_network`
3. Check credentials trong `backup.env`

### Restore fail
1. Verify backup files tồn tại
2. Check Docker socket có mount không
3. Xem log chi tiết khi chạy script

---

**🎉 Chúc bạn triển khai thành công!**
