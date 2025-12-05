#!/bin/sh
# Script backup cho stack n8n-backup
# - Chạy bên trong container "n8n-backup-runner"
# - Được cron gọi mỗi ngày (được cấu hình trong docker-compose)
# - Nhiệm vụ:
#   + Dump database từ stack n8n-production
#   + Nén và lưu file dump vào thư mục backup trên host (backup_volume)
#   + Restore lại dump này vào database backup riêng (backup-postgres)
#   + Nén toàn bộ dữ liệu file của n8n (volume n8n-storage) sang file .tar.gz
#   + Xóa các file backup cũ hơn 5 ngày

set -eu

# ============================
#  Biến môi trường nguồn (DB gốc của n8n-production)
# ============================
# Host/Postgres của stack n8n-production (service postgres chính)
POSTGRES_SOURCE_HOST=${POSTGRES_SOURCE_HOST:-postgres}
# Tên database đang dùng cho n8n
POSTGRES_SOURCE_DB=${POSTGRES_SOURCE_DB:?"POSTGRES_SOURCE_DB is required"}
# User có quyền đọc full database nguồn
POSTGRES_SOURCE_USER=${POSTGRES_SOURCE_USER:?"POSTGRES_SOURCE_USER is required"}
# Mật khẩu của user ở trên
POSTGRES_SOURCE_PASSWORD=${POSTGRES_SOURCE_PASSWORD:?"POSTGRES_SOURCE_PASSWORD is required"}

# ============================
#  Biến môi trường đích (DB backup riêng trong stack n8n-backup)
# ============================
# Host/Postgres của stack n8n-backup (service backup-postgres)
BACKUP_POSTGRES_HOST=${BACKUP_POSTGRES_HOST:-backup-postgres}
# Tên database backup lưu dữ liệu dump từ nguồn
BACKUP_POSTGRES_DB=${BACKUP_POSTGRES_DB:?"BACKUP_POSTGRES_DB is required"}
# User quản trị database backup
BACKUP_POSTGRES_USER=${BACKUP_POSTGRES_USER:?"BACKUP_POSTGRES_USER is required"}
# Mật khẩu của user backup
BACKUP_POSTGRES_PASSWORD=${BACKUP_POSTGRES_PASSWORD:?"BACKUP_POSTGRES_PASSWORD is required"}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-5}

# ============================
#  Cấu hình log
# ============================
# Thư mục log nằm trong /backup (đã được mount ra host qua ./backup_volume)
LOG_DIR="/backup/logs"
mkdir -p "$LOG_DIR"
# File log theo ngày, ví dụ: backup_20251201.log
LOG_FILE="${LOG_DIR}/backup_$(date +%Y%m%d).log"

# Ghi toàn bộ stdout + stderr vào file log
# (và vẫn in log() ra console khi chạy thủ công)
exec 3>&1 4>&2
exec >>"$LOG_FILE" 2>&1

# Hàm log đơn giản, có prefix thởi gian
log() {
    message="$1"
    timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    printf '[%s] %s\n' "$timestamp" "$message"
    printf '[%s] %s\n' "$timestamp" "$message" >&3 || true
    case "$message" in
        # Nếu message bắt đầu bằng "ERROR" thì có thể hook thêm notify
        ERROR*)
            send_notification "error" "$message"
            ;;
    esac
}

# Hàm gửi thông báo qua Telegram
send_notification() {
    notification_type="$1"  # "error" hoặc "success"
    message="$2"
    
    # Chỉ gửi nếu có cấu hình Telegram
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return 0
    fi
    
    # Format message
    if [ "$notification_type" = "error" ]; then
        emoji="🔴"
        text="*N8N Backup Error*%0A%0A${emoji} ${message}"
    else
        emoji="✅"
        text="*N8N Backup Success*%0A%0A${emoji} ${message}"
    fi
    
    # Gửi qua Telegram Bot API (dùng wget thay cho curl)
    wget -q -O /dev/null "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage?chat_id=${TELEGRAM_CHAT_ID}&text=${text}&parse_mode=Markdown" 2>/dev/null || true
}

# ============================
#  Backup database
# ============================
backup_database() {
    # Tạo timestamp để phân biệt từng lần backup
    timestamp=$(date +%Y%m%d_%H%M%S)
    # File dump tạm thởi bên trong container
    dump_file="/tmp/n8n_backup_${timestamp}.sql"
    # File dump đã nén lưu trong thư mục backup trên host
    archive_file="/backup/daily/n8n_backup_${timestamp}.sql.gz"

    log "Dumping source database..."
    # Dùng pg_dump để dump toàn bộ DB nguồn vào file .sql
    if ! PGPASSWORD="$POSTGRES_SOURCE_PASSWORD" pg_dump --no-owner --no-acl -h "$POSTGRES_SOURCE_HOST" -U "$POSTGRES_SOURCE_USER" "$POSTGRES_SOURCE_DB" > "$dump_file"; then
        log "ERROR: Failed to dump source database"
        rm -f "$dump_file"
        return 1
    fi

    log "Compressing dump..."
    # Nén file .sql thành .sql.gz để tiết kiệm dung lượng
    if ! gzip -c "$dump_file" > "$archive_file"; then
        log "ERROR: Failed to compress backup dump"
        rm -f "$dump_file"
        return 1
    fi

    log "Refreshing backup database..."
    # Drop toàn bộ database backup để tránh xung đột schema/role cũ
    if ! PGPASSWORD="$BACKUP_POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -h "$BACKUP_POSTGRES_HOST" -U "$BACKUP_POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$BACKUP_POSTGRES_DB\" WITH (FORCE);"; then
        log "ERROR: Failed to drop backup database"
        rm -f "$dump_file"
        return 1
    fi

    if ! PGPASSWORD="$BACKUP_POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -h "$BACKUP_POSTGRES_HOST" -U "$BACKUP_POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$BACKUP_POSTGRES_DB\";"; then
        log "ERROR: Failed to recreate backup database"
        rm -f "$dump_file"
        return 1
    fi

    # Tạo role lequyet_n8n nếu chưa tồn tại (để tránh lỗi khi restore dump)
    log "Creating required roles in backup database..."
    PGPASSWORD="$BACKUP_POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=0 -h "$BACKUP_POSTGRES_HOST" -U "$BACKUP_POSTGRES_USER" -d postgres -c "CREATE ROLE lequyet_n8n;" 2>/dev/null || true

    # Restore nội dung dump vào DB backup (sau khi đã tạo mới hoàn toàn)
    if ! PGPASSWORD="$BACKUP_POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -h "$BACKUP_POSTGRES_HOST" -U "$BACKUP_POSTGRES_USER" -d "$BACKUP_POSTGRES_DB" < "$dump_file"; then
        log "ERROR: Failed to restore dump into backup database"
        rm -f "$dump_file"
        return 1
    fi

    # Xóa file dump tạm
    rm -f "$dump_file"
    log "Database backup completed successfully"
    send_notification "success" "$archive_file"
    return 0
}

# ============================
#  Backup dữ liệu file (volume n8n_data)
# ============================
backup_files() {
    timestamp=$(date +%Y%m%d_%H%M%S)
    # File .tar.gz chứa toàn bộ nội dung thư mục /n8n_data
    archive="/backup/files/n8n_files_${timestamp}.tar.gz"

    log "Archiving n8n file data..."
    # Nén toàn bộ thư mục /n8n_data (mount từ volume n8n-storage của n8n-production)
    if ! tar -czf "$archive" -C /n8n_data .; then
        log "ERROR: Failed to archive n8n files"
        return 1
    fi

    log "File archive completed"
    send_notification "success" "$archive"
    return 0
}

# ============================
#  Dọn dẹp backup cũ
# ============================
cleanup_old_backups() {
    log "Cleaning up backups older than ${BACKUP_RETENTION_DAYS} days..."
    # Xóa các file dump DB cũ hơn ${BACKUP_RETENTION_DAYS} ngày
    find /backup/daily -name 'n8n_backup_*.sql.gz' -mtime +"$BACKUP_RETENTION_DAYS" -delete
    # Xóa các file .tar.gz dữ liệu n8n cũ hơn ${BACKUP_RETENTION_DAYS} ngày
    find /backup/files -name 'n8n_files_*.tar.gz' -mtime +"$BACKUP_RETENTION_DAYS" -delete
    log "Cleanup completed"
}

# ============================
#  Hàm main - luồng chính của script
# ============================
main() {
    log "=== Starting n8n Backup Process ==="
    # Đảm bảo tồn tại thư mục backup cần thiết bên trong container
    mkdir -p /backup/daily /backup/files

    success=0

    # Bước 1: backup database
    if ! backup_database; then
        success=1
    fi

    # Bước 2: backup file (volume n8n_data)
    if ! backup_files; then
        success=1
    fi

    # Nếu cả hai bước đều thành công thì dọn backup cũ và log thành công
    if [ "$success" -eq 0 ]; then
        cleanup_old_backups
        log "Backup process completed successfully"
        # Gửi thông báo tổng hợp khi backup hoàn tất
        summary="Database + Files backup completed at $(date '+%Y-%m-%d %H:%M:%S')"
        send_notification "success" "$summary"
    else
        log "ERROR: Backup process encountered errors"
        send_notification "error" "Backup process failed at $(date '+%Y-%m-%d %H:%M:%S')"
        exit 1
    fi
}

# Gọi hàm main khi script được chạy
main
