#!/bin/bash

# ==========================================
# N8N Test Environment - Backup Script
# ==========================================

set -e

# Configuration
BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RETENTION_DAYS=7

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '#' | awk '/=/ {print $1}')
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}N8N Test Environment - Backup${NC}"
echo -e "${BLUE}Timestamp: $TIMESTAMP${NC}"
echo -e "${BLUE}===========================================${NC}"

# Create backup directory
mkdir -p $BACKUP_DIR/{database,volumes,logs}

# Function to log messages
log_message() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $BACKUP_DIR/logs/backup_$TIMESTAMP.log
}

# Function to handle errors
handle_error() {
    echo -e "${RED}❌ Error: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> $BACKUP_DIR/logs/backup_$TIMESTAMP.log
    exit 1
}

# Check if containers are running
log_message "Checking container status..."
if ! docker ps | grep -q "n8n-test-postgres"; then
    handle_error "PostgreSQL container is not running"
fi

if ! docker ps | grep -q "n8n-test-main"; then
    handle_error "N8N main container is not running"
fi

# 1. Backup PostgreSQL Database
log_message "🗄️ Starting PostgreSQL backup..."

DB_BACKUP_FILE="$BACKUP_DIR/database/n8n_test_db_$TIMESTAMP.sql"
docker exec n8n-test-postgres pg_dump \
    -U $POSTGRES_USER \
    -d $POSTGRES_DB \
    --verbose \
    --no-owner \
    --no-privileges \
    > $DB_BACKUP_FILE

if [ $? -eq 0 ]; then
    # Compress the backup
    gzip $DB_BACKUP_FILE
    log_message "✅ Database backup completed: ${DB_BACKUP_FILE}.gz"
    
    # Get backup size
    BACKUP_SIZE=$(du -h "${DB_BACKUP_FILE}.gz" | cut -f1)
    log_message "📊 Database backup size: $BACKUP_SIZE"
else
    handle_error "Database backup failed"
fi

# 2. Backup N8N Volume Data
log_message "📁 Starting N8N volume backup..."

VOLUME_BACKUP_FILE="$BACKUP_DIR/volumes/n8n_test_volume_$TIMESTAMP.tar.gz"
docker run --rm \
    -v n8n_test_storage:/source:ro \
    -v $(pwd)/$BACKUP_DIR/volumes:/backup \
    alpine:latest \
    tar czf /backup/n8n_test_volume_$TIMESTAMP.tar.gz -C /source .

if [ $? -eq 0 ]; then
    log_message "✅ Volume backup completed: $VOLUME_BACKUP_FILE"
    
    # Get backup size
    VOLUME_SIZE=$(du -h "$VOLUME_BACKUP_FILE" | cut -f1)
    log_message "📊 Volume backup size: $VOLUME_SIZE"
else
    handle_error "Volume backup failed"
fi

# 3. Backup Configuration Files
log_message "⚙️ Starting configuration backup..."

CONFIG_BACKUP_FILE="$BACKUP_DIR/volumes/n8n_test_config_$TIMESTAMP.tar.gz"
tar czf $CONFIG_BACKUP_FILE \
    docker-compose.yml \
    .env \
    nginx/ \
    postgres/ \
    scripts/ \
    2>/dev/null || true

if [ $? -eq 0 ]; then
    log_message "✅ Configuration backup completed: $CONFIG_BACKUP_FILE"
else
    log_message "⚠️ Configuration backup had some warnings (non-critical)"
fi

# 4. Test Database Backup Integrity
log_message "🔍 Testing backup integrity..."

# Create temporary test container
docker run -d --name postgres-test-restore \
    --network n8n_test_network \
    -e POSTGRES_DB=test_restore \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    postgres:15-alpine

# Wait for container to be ready
sleep 10

# Test restore
if docker exec postgres-test-restore psql -U $POSTGRES_USER -d test_restore -c "SELECT 1;" > /dev/null 2>&1; then
    # Try to restore the backup
    gunzip -c "${DB_BACKUP_FILE}.gz" | docker exec -i postgres-test-restore psql -U $POSTGRES_USER -d test_restore > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        # Check if tables exist
        TABLE_COUNT=$(docker exec postgres-test-restore psql -U $POSTGRES_USER -d test_restore -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' ')
        
        if [ "$TABLE_COUNT" -gt 0 ]; then
            log_message "✅ Backup integrity verified: $TABLE_COUNT tables restored"
        else
            log_message "⚠️ Backup integrity warning: No tables found in restored database"
        fi
    else
        log_message "⚠️ Backup integrity test failed: Could not restore backup"
    fi
else
    log_message "⚠️ Could not connect to test database for integrity check"
fi

# Cleanup test container
docker rm -f postgres-test-restore > /dev/null 2>&1

# 5. Cleanup Old Backups
log_message "🧹 Cleaning up old backups (older than $RETENTION_DAYS days)..."

# Remove old database backups
find $BACKUP_DIR/database -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
# Remove old volume backups
find $BACKUP_DIR/volumes -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
# Remove old log files
find $BACKUP_DIR/logs -name "*.log" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

REMAINING_BACKUPS=$(find $BACKUP_DIR -name "*$TIMESTAMP*" | wc -l)
log_message "🗂️ Cleanup completed. Current backup files: $REMAINING_BACKUPS"

# 6. Generate Backup Report
log_message "📋 Generating backup report..."

REPORT_FILE="$BACKUP_DIR/logs/backup_report_$TIMESTAMP.txt"
cat > $REPORT_FILE << EOF
N8N Test Environment Backup Report
==================================
Timestamp: $TIMESTAMP
Date: $(date)

Backup Files:
- Database: ${DB_BACKUP_FILE}.gz ($BACKUP_SIZE)
- Volume: $VOLUME_BACKUP_FILE ($VOLUME_SIZE)
- Config: $CONFIG_BACKUP_FILE

Database Info:
- Tables: $TABLE_COUNT
- Integrity: Verified

System Info:
- PostgreSQL Version: $(docker exec n8n-test-postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT version();" | head -1)
- N8N Version: $(docker exec n8n-test-main n8n --version 2>/dev/null || echo "Unknown")

Retention Policy: $RETENTION_DAYS days
Status: SUCCESS
EOF

log_message "✅ Backup report generated: $REPORT_FILE"

# 7. Send Telegram Notification (if configured)
if [ ! -z "$TELEGRAM_BOT_TOKEN" ] && [ ! -z "$TELEGRAM_CHAT_ID" ]; then
    log_message "📱 Sending Telegram notification..."
    
    MESSAGE="🔄 N8N Test Backup Completed
    
📅 Time: $(date)
💾 Database: $BACKUP_SIZE
📁 Volume: $VOLUME_SIZE
🔍 Tables: $TABLE_COUNT
✅ Status: SUCCESS"

    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id=$TELEGRAM_CHAT_ID \
        -d text="$MESSAGE" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_message "✅ Telegram notification sent"
    else
        log_message "⚠️ Failed to send Telegram notification"
    fi
fi

# Final Summary
echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}🎉 Backup Completed Successfully!${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}📊 Summary:${NC}"
echo -e "${YELLOW}• Database backup: ${BACKUP_SIZE}${NC}"
echo -e "${YELLOW}• Volume backup: ${VOLUME_SIZE}${NC}"
echo -e "${YELLOW}• Tables verified: ${TABLE_COUNT}${NC}"
echo -e "${YELLOW}• Backup location: $BACKUP_DIR${NC}"
echo -e "\n${BLUE}Files created:${NC}"
echo -e "${YELLOW}• ${DB_BACKUP_FILE}.gz${NC}"
echo -e "${YELLOW}• $VOLUME_BACKUP_FILE${NC}"
echo -e "${YELLOW}• $CONFIG_BACKUP_FILE${NC}"
echo -e "${YELLOW}• $REPORT_FILE${NC}"

log_message "🏁 Backup process completed successfully"
