#!/bin/sh
# ===========================================
#  WATCHDOG SCRIPT - Giám sát N8N và tự động restore
#  - Chạy liên tục trong container
#  - Kiểm tra health của n8n mỗi 30s
#  - Nếu n8n chết > 3 lần liên tiếp -> trigger restore
# ===========================================

set -eu

# ============================
#  Cấu hình
# ============================
N8N_HEALTH_URL="${N8N_HEALTH_URL:-http://n8n:5678/healthz}"
RESTORED_HEALTH_URL="${RESTORED_HEALTH_URL:-http://n8n-restored:5678/healthz}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"        # Kiểm tra mỗi 30 giây
MAX_FAILURES="${MAX_FAILURES:-3}"             # Số lần fail trước khi restore
RESTORE_COOLDOWN="${RESTORE_COOLDOWN:-300}"   # Đợi 5 phút sau mỗi lần restore

# Biến đếm
failure_count=0
last_restore_time=0

# ============================
#  Log function
# ============================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ============================
#  Gửi Telegram notification
# ============================
send_telegram() {
    message="$1"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        encoded_msg=$(echo "$message" | sed 's/ /%20/g; s/\n/%0A/g')
        wget -q -O /dev/null "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage?chat_id=${TELEGRAM_CHAT_ID}&text=${encoded_msg}&parse_mode=Markdown" 2>/dev/null || true
    fi
}

# ============================
#  Kiểm tra health của n8n
# ============================
check_n8n_health() {
    # Thử gọi healthz endpoint
    if wget -q -T 10 -O /dev/null "$N8N_HEALTH_URL" 2>/dev/null; then
        return 0  # Healthy
    else
        return 1  # Unhealthy
    fi
}

# ============================
#  Kiểm tra health của n8n-restored (sau khi auto-restore)
# ============================
check_n8n_restored_health() {
    if wget -q -T 10 -O /dev/null "$RESTORED_HEALTH_URL" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ============================
#  Kiểm tra n8n container có đang chạy không
# ============================
check_n8n_container() {
    # Ping n8n host để xem container có tồn tại không
    if ping -c 1 -W 2 n8n >/dev/null 2>&1; then
        return 0  # Container exists
    else
        return 1  # Container not found
    fi
}

# ============================
#  Trigger restore process
# ============================
trigger_restore() {
    current_time=$(date +%s)
    time_since_last=$((current_time - last_restore_time))
    
    # Kiểm tra cooldown
    if [ "$time_since_last" -lt "$RESTORE_COOLDOWN" ]; then
        remaining=$((RESTORE_COOLDOWN - time_since_last))
        log "WARN: Still in cooldown period. ${remaining}s remaining."
        return 1
    fi
    
    log "=== TRIGGERING AUTO-RESTORE ==="
    send_telegram "🔴 *N8N Down Alert*%0A%0AN8N has been down for ${MAX_FAILURES} consecutive checks.%0AStarting auto-restore process..."
    
    # Chạy restore script
    if /scripts/restore_n8n.sh --auto; then
        log "Restore completed successfully"
        send_telegram "✅ *N8N Restored*%0A%0AAuto-restore completed successfully.%0APlease verify n8n is working."
        last_restore_time=$(date +%s)
        failure_count=0
        return 0
    else
        log "ERROR: Restore failed!"
        send_telegram "🔴 *Restore Failed*%0A%0AAuto-restore process failed.%0AManual intervention required!"
        return 1
    fi
}

# ============================
#  Main loop
# ============================
main() {
    log "=== N8N Watchdog Started ==="
    log "Health URL: $N8N_HEALTH_URL"
    log "Restored Health URL: $RESTORED_HEALTH_URL"
    log "Check interval: ${CHECK_INTERVAL}s"
    log "Max failures before restore: $MAX_FAILURES"
    
    send_telegram "🟢 *N8N Watchdog Started*%0A%0AMonitoring n8n health every ${CHECK_INTERVAL}s"
    
    while true; do
        # Kiểm tra health (ưu tiên n8n chính; nếu đã restore thì chấp nhận n8n-restored healthy)
        if check_n8n_health; then
            if [ "$failure_count" -gt 0 ]; then
                log "N8N recovered! Resetting failure count."
                send_telegram "🟢 *N8N Recovered*%0A%0AN8N is healthy again after ${failure_count} failures."
            fi
            failure_count=0
            log "N8N is healthy ✓"
        elif check_n8n_restored_health; then
            if [ "$failure_count" -gt 0 ]; then
                log "Primary N8N is unhealthy but n8n-restored is healthy. Resetting failure count."
            else
                log "Primary N8N is unhealthy but n8n-restored is healthy."
            fi
            failure_count=0
        else
            failure_count=$((failure_count + 1))
            log "WARNING: N8N health check failed! (${failure_count}/${MAX_FAILURES})"
            
            if [ "$failure_count" -ge "$MAX_FAILURES" ]; then
                log "CRITICAL: N8N has been down for ${MAX_FAILURES} checks!"
                trigger_restore
            else
                send_telegram "⚠️ *N8N Health Warning*%0A%0AHealth check failed (${failure_count}/${MAX_FAILURES})"
            fi
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Chạy main loop
main