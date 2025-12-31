# Runbook Triển Khai N8N (Ubuntu + Nginx)

Tài liệu này mô tả quy trình chuẩn để triển khai hệ thống:
- `n8n-stack` (N8N + Postgres + Redis + Worker)
- `backup-stack` (backup định kỳ + watchdog auto-restore)
- Nginx reverse proxy + HTTPS

## 1) Yêu cầu

- Ubuntu 20.04+ (khuyến nghị 22.04 LTS)
- Domain trỏ về server (A/AAAA record)
- Docker Engine + Docker Compose plugin (compose v2)
- Mở firewall:
  - 80/tcp, 443/tcp (public)
  - (tuỳ chọn) 22/tcp SSH
- Không expose Postgres/Redis ra public

## 2) Cài Docker

Tham khảo hướng dẫn chính thức Docker cho Ubuntu.

Kiểm tra:

```bash
docker --version
docker compose version
```

## 3) Deploy source code

Ví dụ thư mục:

```bash
sudo mkdir -p /opt/n8n
sudo chown -R $USER:$USER /opt/n8n
cd /opt/n8n
# git clone <repo_url> .
```

## 4) Chuẩn bị secrets / env

### 4.1 n8n-stack/.env

Tạo file `/opt/n8n/n8n-stack/.env` từ `.env.example` và chỉnh các biến quan trọng:

- `POSTGRES_NON_ROOT_PASSWORD=<strong_password>`
- `REDIS_PASSWORD=<strong_password>`
- `QUEUE_BULL_REDIS_PASSWORD=<same_as_REDIS_PASSWORD>`
- `N8N_ENCRYPTION_KEY=<strong_key>`  (PHẢI giữ ổn định để decrypt credentials)
- `N8N_HOST=<domain>`
- `N8N_PROTOCOL=https`
- `N8N_PORT=5678`
- `WEBHOOK_URL=https://<domain>/`
- `N8N_SECURE_COOKIE=true`

### 4.2 backup-stack/backup.env

Tạo file `/opt/n8n/backup-stack/backup.env` (KHÔNG commit).

Bắt buộc:
- `POSTGRES_SOURCE_HOST=postgres`
- `POSTGRES_SOURCE_DB=n8n`
- `POSTGRES_SOURCE_USER=<POSTGRES_NON_ROOT_USER>`
- `POSTGRES_SOURCE_PASSWORD=<POSTGRES_NON_ROOT_PASSWORD>`

Backup DB (nội bộ backup-stack):
- `BACKUP_POSTGRES_USER=backup_admin`
- `BACKUP_POSTGRES_PASSWORD=<strong_password>`
- `POSTGRES_USER=backup_admin`
- `POSTGRES_PASSWORD=<same_as_BACKUP_POSTGRES_PASSWORD>`

Optional Telegram:
- `TELEGRAM_BOT_TOKEN=<token>`
- `TELEGRAM_CHAT_ID=<chat_id>`

## 5) Tạo docker network dùng chung

```bash
docker network create n8n_network || true
```

## 6) Start n8n-stack

```bash
cd /opt/n8n/n8n-stack
docker compose up -d
```

Kiểm tra:

```bash
docker compose ps
curl -fsS http://127.0.0.1:5678/healthz
```

## 7) Start backup-stack

```bash
cd /opt/n8n/backup-stack
docker compose up -d
```

Test backup thủ công:

```bash
docker exec -it n8n-backup-runner /scripts/n8n_backup.sh
```

## 8) Bật watchdog (optional)

```bash
cd /opt/n8n/backup-stack
docker compose --profile watchdog up -d

docker logs -f n8n-watchdog
```

## 9) Nginx reverse proxy + HTTPS

### 9.1 Cài Nginx

```bash
sudo apt-get update
sudo apt-get install -y nginx
```

### 9.2 Nginx config (reverse proxy)

Tạo file:

`/etc/nginx/sites-available/n8n.conf`

Ví dụ (chưa có domain, truy cập bằng IP trong LAN):

```nginx
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        client_max_body_size 64m;

        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
```

Ví dụ (HTTP -> HTTPS sẽ bổ sung khi có cert):

```nginx
server {
    listen 80;
    server_name <domain>;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        client_max_body_size 64m;

        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
```

Enable:

```bash
sudo ln -s /etc/nginx/sites-available/n8n.conf /etc/nginx/sites-enabled/n8n.conf
sudo nginx -t
sudo systemctl reload nginx
```

### 9.3 SSL bằng Let's Encrypt

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d <domain>
```

Sau khi có SSL:
- Đảm bảo `.env` của n8n đã set:
  - `N8N_PROTOCOL=https`
  - `WEBHOOK_URL=https://<domain>/`
  - `N8N_SECURE_COOKIE=true`
- Restart n8n:

```bash
cd /opt/n8n/n8n-stack
docker compose up -d
```

## 10) Checklist test sau deploy

- N8N UI:
  - `https://<domain>/` mở được
  - Login OK
  - Tạo workflow test và chạy OK
- Redis:
  - `docker exec n8n-redis redis-cli -a "$REDIS_PASSWORD" ping` (trong container env)
- Worker:
  - `docker logs n8n-worker --tail 100` không có lỗi Redis/DB
- Backup:
  - `backup-stack/backup_volume/daily/*.sql.gz` và `files/*.tar.gz` được tạo
- Restore (staging test):
  - chạy `backup-stack/scripts/restore_n8n.sh --auto` và login vào restored OK

## 11) Ghi chú quan trọng

- Không commit các file:
  - `n8n-stack/.env`
  - `backup-stack/backup.env`
- `N8N_ENCRYPTION_KEY` phải được lưu trữ an toàn. Mất key sẽ không decrypt credentials.
- Khuyến nghị off-site backup (S3/rclone) và test restore định kỳ.
