#!/bin/sh
# Script restore n8n từ backup
# - Tạo Postgres mới cho n8n production
# - Restore DB từ file .sql.gz
# - Restore volume n8n-storage từ file .tar.gz
# - Hỗ trợ mode: manual (default) hoặc --auto (tự động start n8n)

set -eu

# ============================
#  Parse arguments
# ============================
AUTO_MODE=false
for arg in "$@"; do
    case "$arg" in
        --auto) AUTO_MODE=true ;;
    esac
done

# ============================
#  Cấu hình
# ============================
BACKUP_DIR="/backup"
DAILY_DIR="${BACKUP_DIR}/daily"
FILES_DIR="${BACKUP_DIR}/files"
LOG_DIR="${BACKUP_DIR}/logs"

# Tên volume và DB mới cho n8n production
NEW_VOLUME_NAME="n8n-storage-restored"
NEW_DB_CONTAINER="n8n-postgres-restored"
NEW_DB_NAME="n8n"
NEW_DB_USER="n8n_user"
NEW_DB_PASSWORD="n8n_secure_password_change_me"

# ============================
#  Hàm log
# ============================
log() {
    printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$1"
}

# ============================
#  Hàm tìm file backup mới nhất
# ============================
find_latest_backup() {
    backup_type="$1"  # "daily" hoặc "files"
    pattern="$2"      # pattern tìm kiếm
    
    if [ "$backup_type" = "daily" ]; then
        dir="$DAILY_DIR"
    else
        dir="$FILES_DIR"
    fi
    
    # Dùng ls -t để sort theo thời gian (compatible với Alpine/BusyBox)
    latest=$(ls -t "$dir"/$pattern 2>/dev/null | head -n1)
    
    if [ -z "$latest" ]; then
        log "ERROR: Không tìm thấy file backup với pattern: $pattern trong $dir"
        return 1
    fi
    
    echo "$latest"
}

# ============================
#  Hàm tạo Postgres mới
# ============================
create_new_postgres() {
    log "Tạo container Postgres mới: $NEW_DB_CONTAINER"
    
    # Kiểm tra container đã tồn tại chưa
    if docker ps -a --format '{{.Names}}' | grep -q "^${NEW_DB_CONTAINER}$"; then
        log "Container $NEW_DB_CONTAINER đã tồn tại. Xóa container cũ..."
        docker rm -f "$NEW_DB_CONTAINER" || true
    fi
    
    # Tạo container Postgres mới
    docker run -d \
        --name "$NEW_DB_CONTAINER" \
        --restart unless-stopped \
        --network n8n_network \
        -e POSTGRES_DB="$NEW_DB_NAME" \
        -e POSTGRES_USER="$NEW_DB_USER" \
        -e POSTGRES_PASSWORD="$NEW_DB_PASSWORD" \
        -v n8n-postgres-restored-data:/var/lib/postgresql/data \
        postgres:15-alpine
    
    log "Đợi Postgres khởi động..."
    sleep 10
    
    # Kiểm tra Postgres đã sẵn sàng chưa
    for i in $(seq 1 30); do
        if docker exec "$NEW_DB_CONTAINER" pg_isready -U "$NEW_DB_USER" -d "$NEW_DB_NAME" >/dev/null 2>&1; then
            log "Postgres đã sẵn sàng"
            return 0
        fi
        sleep 2
    done
    
    log "ERROR: Postgres không khởi động được sau 60 giây"
    return 1
}

# ============================
#  Hàm restore DB từ .sql.gz
# ============================
restore_database() {
    sql_file="$1"
    
    log "Restore database từ: $sql_file"
    
    # Drop và tạo lại database để đảm bảo clean state
    log "Cleaning database..."
    docker exec "$NEW_DB_CONTAINER" sh -c \
        "PGPASSWORD='$NEW_DB_PASSWORD' psql -U '$NEW_DB_USER' -d postgres -c \"DROP DATABASE IF EXISTS \\\"$NEW_DB_NAME\\\" WITH (FORCE);\"" 2>/dev/null || true
    docker exec "$NEW_DB_CONTAINER" sh -c \
        "PGPASSWORD='$NEW_DB_PASSWORD' psql -U '$NEW_DB_USER' -d postgres -c \"CREATE DATABASE \\\"$NEW_DB_NAME\\\";\"" || {
            log "ERROR: Cannot create database"
            return 1
        }
    
    # Copy file vào container
    docker cp "$sql_file" "${NEW_DB_CONTAINER}:/tmp/restore.sql.gz"
    
    # Giải nén và restore (bỏ ON_ERROR_STOP để tiếp tục khi có warning)
    log "Restoring data..."
    if ! docker exec "$NEW_DB_CONTAINER" sh -c \
        "gunzip -c /tmp/restore.sql.gz | PGPASSWORD='$NEW_DB_PASSWORD' psql -U '$NEW_DB_USER' -d '$NEW_DB_NAME'" 2>&1 | grep -v "already exists" | head -20; then
        log "WARN: Có một số warning khi restore, tiếp tục..."
    fi
    
    # Kiểm tra database có data không
    table_count=$(docker exec "$NEW_DB_CONTAINER" sh -c \
        "PGPASSWORD='$NEW_DB_PASSWORD' psql -U '$NEW_DB_USER' -d '$NEW_DB_NAME' -t -c \"SELECT count(*) FROM information_schema.tables WHERE table_schema='public';\"" | tr -d ' ')
    
    if [ "$table_count" -lt 5 ]; then
        log "ERROR: Database restore có vẻ không thành công (chỉ có $table_count tables)"
        return 1
    fi
    
    # Xóa file tạm
    docker exec "$NEW_DB_CONTAINER" rm -f /tmp/restore.sql.gz
    
    log "Restore database thành công ($table_count tables)"
    return 0
}

# ============================
#  Hàm restore volume n8n-storage
# ============================
restore_volume() {
    tar_file="$1"
    
    log "Restore volume n8n-storage từ: $tar_file"
    
    # Tạo volume nếu chưa có
    if ! docker volume inspect "$NEW_VOLUME_NAME" >/dev/null 2>&1; then
        log "Tạo volume mới: $NEW_VOLUME_NAME"
        docker volume create "$NEW_VOLUME_NAME"
    fi
    
    # Tạo container tạm để extract tar
    temp_container="n8n-restore-temp-$$"
    
    # Chạy container tạm với volume mounted
    docker run -d --name "$temp_container" \
        -v "${NEW_VOLUME_NAME}:/n8n_data" \
        alpine sleep 300 >/dev/null
    
    # Copy file tar vào container
    docker cp "$tar_file" "${temp_container}:/tmp/restore.tar.gz"
    
    # Extract vào volume
    if ! docker exec "$temp_container" sh -c "rm -rf /n8n_data/* && tar -xzf /tmp/restore.tar.gz -C /n8n_data"; then
        log "ERROR: Restore volume thất bại"
        docker rm -f "$temp_container" >/dev/null 2>&1
        return 1
    fi
    
    # Cleanup container tạm
    docker rm -f "$temp_container" >/dev/null 2>&1
    
    log "Restore volume thành công"
    return 0
}

# ============================
#  Hàm main
# ============================
main() {
    log "=== Bắt đầu quy trình restore n8n ==="
    
    # Tìm file backup mới nhất
    log "Tìm file backup mới nhất..."
    
    db_backup=$(find_latest_backup "daily" "n8n_backup_*.sql.gz")
    if [ $? -ne 0 ]; then
        log "ERROR: Không tìm thấy file backup database"
        exit 1
    fi
    log "File DB backup: $db_backup"
    
    files_backup=$(find_latest_backup "files" "n8n_files_*.tar.gz")
    if [ $? -ne 0 ]; then
        log "ERROR: Không tìm thấy file backup dữ liệu"
        exit 1
    fi
    log "File dữ liệu backup: $files_backup"
    
    # Tạo Postgres mới
    if ! create_new_postgres; then
        log "ERROR: Không thể tạo Postgres mới"
        exit 1
    fi
    
    # Restore database
    if ! restore_database "$db_backup"; then
        log "ERROR: Restore database thất bại"
        exit 1
    fi
    
    # Restore volume
    if ! restore_volume "$files_backup"; then
        log "ERROR: Restore volume thất bại"
        exit 1
    fi
    
    log "=== Restore hoàn tất ==="
    log ""
    log "Thông tin DB mới:"
    log "  - Container: $NEW_DB_CONTAINER"
    log "  - Database: $NEW_DB_NAME"
    log "  - User: $NEW_DB_USER"
    log "  - Password: $NEW_DB_PASSWORD"
    log "  - Network: n8n_network"
    log ""
    log "Volume đã restore:"
    log "  - Volume name: $NEW_VOLUME_NAME"
    
    # Nếu auto mode, tự động start n8n-restored
    if [ "$AUTO_MODE" = true ]; then
        log ""
        log "=== AUTO MODE: Khởi động N8N Restored ==="
        start_n8n_restored
    else
        log ""
        log "Bước tiếp theo:"
        log "  1. Chỉnh file docker-compose.restore.yml trong backup-stack/"
        log "  2. Chạy: docker compose -f backup-stack/docker-compose.restore.yml up -d"
        log "  3. Kiểm tra n8n mới tại: http://localhost:5679 (hoặc port bạn cấu hình)"
    fi
}

# ============================
#  Hàm start n8n restored (cho auto mode)
# ============================
start_n8n_restored() {
    log "Khởi động container n8n-restored..."
    
    # Xóa container cũ nếu có
    docker rm -f n8n-restored 2>/dev/null || true
    
    # Start n8n-restored container
    docker run -d \
        --name n8n-restored \
        --restart unless-stopped \
        --network n8n_network \
        -p 5679:5678 \
        -e DB_TYPE=postgresdb \
        -e DB_POSTGRESDB_HOST="$NEW_DB_CONTAINER" \
        -e DB_POSTGRESDB_PORT=5432 \
        -e DB_POSTGRESDB_DATABASE="$NEW_DB_NAME" \
        -e DB_POSTGRESDB_USER="$NEW_DB_USER" \
        -e DB_POSTGRESDB_PASSWORD="$NEW_DB_PASSWORD" \
        -e GENERIC_TIMEZONE=Asia/Ho_Chi_Minh \
        -e TZ=Asia/Ho_Chi_Minh \
        -e N8N_HOST=localhost \
        -e N8N_PORT=5678 \
        -e N8N_PROTOCOL=http \
        -e NODE_ENV=production \
        -v "${NEW_VOLUME_NAME}:/home/node/.n8n" \
        --user node:node \
        n8nio/n8n:1.68.1
    
    log "Đợi n8n-restored khởi động..."
    sleep 30
    
    # Kiểm tra health
    for i in $(seq 1 10); do
        if wget -q -T 5 -O /dev/null "http://n8n-restored:5678/healthz" 2>/dev/null; then
            log "✓ N8N Restored đã sẵn sàng tại port 5679"
            return 0
        fi
        sleep 5
    done
    
    log "WARN: N8N Restored có thể chưa hoàn toàn sẵn sàng, nhưng container đã chạy"
    return 0
}

# Chạy main
main
