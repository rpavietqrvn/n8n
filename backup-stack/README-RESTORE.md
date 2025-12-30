# Hướng dẫn Restore N8N từ Backup

Tài liệu này hướng dẫn cách khôi phục n8n từ backup khi n8n production bị chết hoặc cần dựng lại trên server mới.

---

## 1. Tổng quan quy trình

Khi n8n production gặp sự cố, bạn có thể khôi phục bằng cách:

1. **Chạy script restore** để:
   - Tạo container Postgres mới cho n8n.
   - Restore database từ file `.sql.gz` mới nhất.
   - Restore volume `n8n-storage` từ file `.tar.gz` mới nhất.

2. **Dựng stack n8n mới** từ file `docker-compose.restore.yml`.

3. **Kiểm tra** n8n mới hoạt động đúng.

4. **Chuyển traffic** (nếu cần) từ n8n cũ sang n8n mới.

---

## 2. Yêu cầu trước khi restore

- Đã có ít nhất 1 lần backup thành công (file `.sql.gz` và `.tar.gz` trong `backup_volume/`).
- Network `n8n_network` đã tồn tại (do stack n8n cũ hoặc backup-stack tạo).
- Docker daemon đang chạy.

---

## 3. Các bước thực hiện

### Bước 1: Chạy script restore

Từ thư mục `backup-stack`, chạy:

```bash
# Trên Windows PowerShell
docker run --rm -it `
  -v /var/run/docker.sock:/var/run/docker.sock `
  -v d:/portainer/project/backup-stack/backup_volume:/backup `
  -v d:/portainer/project/backup-stack/scripts:/scripts `
  --network n8n_network `
  alpine sh /scripts/restore_n8n.sh
```

Hoặc nếu bạn đã vào trong container `n8n-backup-runner`:

```bash
docker exec -it n8n-backup-runner /scripts/restore_n8n.sh
```

**Lưu ý**: Script cần quyền truy cập Docker socket để tạo container/volume mới.

Script sẽ:
- Tìm file backup mới nhất.
- Tạo container `n8n-postgres-restored`.
- Restore DB và volume.
- In ra thông tin kết nối DB mới.

### Bước 2: Kiểm tra kết quả

Sau khi script chạy xong, kiểm tra:

```bash
# Kiểm tra container Postgres mới
docker ps | grep n8n-postgres-restored

# Kiểm tra volume đã tạo
docker volume ls | grep n8n-storage-restored
```

### Bước 3: Chỉnh cấu hình (nếu cần)

Mở file `backup-stack/docker-compose.restore.yml` và chỉnh:

- **Port**: Mặc định `5679` (tránh conflict với n8n cũ). Đổi nếu cần.
- **Environment variables**: 
  - `N8N_HOST`, `WEBHOOK_URL` theo domain/IP của bạn.
  - Password DB của restored được lấy từ env (`POSTGRES_SOURCE_PASSWORD` / `DB_POSTGRESDB_PASSWORD`). Không hardcode trong file.
  - `N8N_ENCRYPTION_KEY` phải khớp với production để credentials decrypt được.
- **Redis** (nếu dùng queue mode): bỏ comment các dòng Redis.

### Bước 4: Dựng stack n8n mới

```bash
# Từ thư mục project
docker compose -f backup-stack/docker-compose.restore.yml up -d
```

### Bước 5: Kiểm tra n8n mới

Truy cập:

```
http://localhost:5679
```

Hoặc domain/IP bạn đã cấu hình.

Đăng nhập bằng tài khoản cũ (đã được restore từ DB).

Kiểm tra:
- Workflows có đầy đủ không.
- Credentials có hoạt động không (nhờ `encryptionKey` đã restore).
- Executions history có đúng không.

---

## 4. Chuyển traffic từ n8n cũ sang n8n mới

Có 2 cách:

### Cách 1: Thay thế hoàn toàn

1. Dừng n8n cũ:
   ```bash
   docker stop n8n n8n-worker
   ```

2. Đổi port n8n mới về `5678` (sửa trong `docker-compose.restore.yml`):
   ```yaml
   ports:
     - "5678:5678"
   ```

3. Restart n8n mới:
   ```bash
   docker compose -f backup-stack/docker-compose.restore.yml up -d
   ```

### Cách 2: Dùng reverse proxy

Nếu bạn dùng Nginx/Traefik/Caddy:
- Chỉnh upstream từ `n8n:5678` sang `n8n-restored:5678`.
- Không cần đổi port.

---

## 5. Sau khi restore thành công

### Dọn dẹp (tùy chọn)

Nếu n8n mới đã chạy ổn định, bạn có thể:

- Xóa container n8n cũ:
  ```bash
  docker rm -f n8n n8n-worker
  ```

- Xóa volume cũ (cẩn thận!):
  ```bash
  docker volume rm n8n-storage n8n-postgres-data n8n-redis-data
  ```

### Tiếp tục backup

Để backup n8n mới:

1. Sửa `backup-stack/backup.env`:
   - `POSTGRES_SOURCE_HOST=n8n-postgres-restored`
   - `POSTGRES_SOURCE_USER=n8n_user`
   - `POSTGRES_SOURCE_PASSWORD=<password DB của n8n user (phải khớp production)>`

2. Sửa `backup-stack/docker-compose.yml`:
   - Volume `n8n_data_from_stack` trỏ tới `n8n-storage-restored`:
     ```yaml
     n8n_data_from_stack:
       external: true
       name: n8n-storage-restored
     ```

3. Restart backup stack:
   ```bash
   docker compose -f backup-stack/docker-compose.yml up -d
   ```

---

## 6. Xử lý sự cố

### Script restore báo lỗi "Không tìm thấy file backup"

- Kiểm tra thư mục `backup_volume/daily/` và `backup_volume/files/` có file không.
- Đảm bảo đã mount đúng volume khi chạy script.

### Postgres không khởi động

- Kiểm tra log:
  ```bash
  docker logs n8n-postgres-restored
  ```
- Có thể do volume cũ conflict, thử xóa volume `n8n-postgres-restored-data` và chạy lại.

### N8n không kết nối được DB

- Kiểm tra password trong `docker-compose.restore.yml` khớp với env.
- Kiểm tra network `n8n_network` đã tồn tại:
  ```bash
  docker network ls | grep n8n_network
  ```

### Credentials không hoạt động

- Đảm bảo `N8N_ENCRYPTION_KEY` (env) khớp với key đã dùng trên production.
- Kiểm tra file `config` trong volume đã có `encryptionKey` chưa:
  ```bash
  docker run --rm -v n8n-storage-restored:/data alpine cat /data/config
  ```
- Nếu thiếu, có thể file `.tar.gz` backup bị lỗi.

---

## 7. Tham khảo

- Script restore: `backup-stack/scripts/restore_n8n.sh`
- Compose template: `backup-stack/docker-compose.restore.yml`
- Backup script: `backup-stack/scripts/n8n_backup.sh`
- Log backup: `backup-stack/backup_volume/logs/`

---

**Lưu ý quan trọng**:

- Luôn **test restore** định kỳ để đảm bảo backup hoạt động.
- Giữ an toàn file `backup.env` và `encryptionKey` (không commit vào git public).
- Sau khi restore, nhớ cập nhật lại cấu hình backup để trỏ tới n8n mới.
