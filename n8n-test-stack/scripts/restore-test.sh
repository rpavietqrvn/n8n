#!/bin/bash

# ==========================================
# N8N Test Environment - Restore Script
# ==========================================

set -e

# Configuration
BACKUP_DIR="./backups"
RESTORE_TIMESTAMP=${1:-$(ls -t $BACKUP_DIR/database/*.sql.gz 2>/dev/null | head -1 | grep -o '[0-9]\{8\}_[0-9]\{6\}' || echo "")}

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
echo -e "${BLUE}N8N Test Environment - Restore${NC}"
echo -e "${BLUE}Timestamp: ${RESTORE_TIMESTAMP:-latest}${NC}"
echo -e "${BLUE}===========================================${NC}"

# Function to log messages
log_message() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Function to handle errors
handle_error() {
    echo -e "${RED}❌ Error: $1${NC}"
    exit 1
}

# Function to cleanup on exit
cleanup() {
    log_message "🧹 Cleaning up temporary containers..."
    docker rm -f n8n-restored n8n-postgres-restored 2>/dev/null || true
    docker volume rm n8n-storage-restored 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    handle_error "Backup directory not found: $BACKUP_DIR"
fi

# Find backup files
if [ -z "$RESTORE_TIMESTAMP" ]; then
    # Find latest backup
    DB_BACKUP_FILE=$(ls -t $BACKUP_DIR/database/*.sql.gz 2>/dev/null | head -1)
    VOLUME_BACKUP_FILE=$(ls -t $BACKUP_DIR/volumes/n8n_test_volume_*.tar.gz 2>/dev/null | head -1)
else
    # Use specific timestamp
    DB_BACKUP_FILE="$BACKUP_DIR/database/n8n_test_db_${RESTORE_TIMESTAMP}.sql.gz"
    VOLUME_BACKUP_FILE="$BACKUP_DIR/volumes/n8n_test_volume_${RESTORE_TIMESTAMP}.tar.gz"
fi

# Verify backup files exist
if [ ! -f "$DB_BACKUP_FILE" ]; then
    handle_error "Database backup file not found: $DB_BACKUP_FILE"
fi

if [ ! -f "$VOLUME_BACKUP_FILE" ]; then
    handle_error "Volume backup file not found: $VOLUME_BACKUP_FILE"
fi

log_message "📁 Using backup files:"
log_message "   Database: $DB_BACKUP_FILE"
log_message "   Volume: $VOLUME_BACKUP_FILE"

# Check if restore containers already exist
if docker ps -a | grep -q "n8n-restored\|n8n-postgres-restored"; then
    log_message "⚠️ Existing restore containers found. Removing..."
    docker rm -f n8n-restored n8n-postgres-restored 2>/dev/null || true
fi

if docker volume ls | grep -q "n8n-storage-restored"; then
    log_message "⚠️ Existing restore volume found. Removing..."
    docker volume rm n8n-storage-restored 2>/dev/null || true
fi

# Step 1: Create restored PostgreSQL container
log_message "🗄️ Creating restored PostgreSQL container..."

docker run -d \
    --name n8n-postgres-restored \
    --network n8n_test_network \
    -e POSTGRES_DB=${POSTGRES_DB}_restored \
    -e POSTGRES_USER=${POSTGRES_USER} \
    -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
    postgres:15-alpine

# Wait for PostgreSQL to be ready
log_message "⏳ Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if docker exec n8n-postgres-restored pg_isready -U $POSTGRES_USER > /dev/null 2>&1; then
        log_message "✅ PostgreSQL is ready"
        break
    else
        sleep 2
    fi
    
    if [ $i -eq 30 ]; then
        handle_error "PostgreSQL failed to start within 60 seconds"
    fi
done

# Step 2: Restore database from backup
log_message "📥 Restoring database from backup..."

# Decompress and restore database
gunzip -c "$DB_BACKUP_FILE" | docker exec -i n8n-postgres-restored psql -U $POSTGRES_USER -d ${POSTGRES_DB}_restored

if [ $? -eq 0 ]; then
    log_message "✅ Database restored successfully"
    
    # Verify restored data
    TABLE_COUNT=$(docker exec n8n-postgres-restored psql -U $POSTGRES_USER -d ${POSTGRES_DB}_restored -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' ')
    log_message "📊 Restored tables: $TABLE_COUNT"
else
    handle_error "Database restore failed"
fi

# Step 3: Restore N8N volume
log_message "📁 Restoring N8N volume..."

# Create restored volume
docker volume create n8n-storage-restored

# Restore volume data
docker run --rm \
    -v n8n-storage-restored:/target \
    -v $(pwd)/$BACKUP_DIR/volumes:/backup:ro \
    alpine:latest \
    tar xzf /backup/$(basename "$VOLUME_BACKUP_FILE") -C /target

if [ $? -eq 0 ]; then
    log_message "✅ Volume restored successfully"
    
    # Verify volume contents
    FILE_COUNT=$(docker run --rm -v n8n-storage-restored:/source alpine:latest find /source -type f | wc -l)
    log_message "📊 Restored files: $FILE_COUNT"
else
    handle_error "Volume restore failed"
fi

# Step 4: Create restored N8N container
log_message "🚀 Starting restored N8N container..."

docker run -d \
    --name n8n-restored \
    --network n8n_test_network \
    -p 5679:5678 \
    -e DB_TYPE=postgresdb \
    -e DB_POSTGRESDB_HOST=n8n-postgres-restored \
    -e DB_POSTGRESDB_PORT=5432 \
    -e DB_POSTGRESDB_DATABASE=${POSTGRES_DB}_restored \
    -e DB_POSTGRESDB_USER=${POSTGRES_USER} \
    -e DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD} \
    -e N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY} \
    -e N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_JWT_SECRET} \
    -e N8N_PROTOCOL=http \
    -e N8N_HOST=localhost \
    -e N8N_PORT=5679 \
    -e WEBHOOK_URL=http://localhost:5679 \
    -e EXECUTIONS_MODE=regular \
    -e N8N_LOG_LEVEL=info \
    -e GENERIC_TIMEZONE=${TIMEZONE:-Asia/Ho_Chi_Minh} \
    -e TZ=${TIMEZONE:-Asia/Ho_Chi_Minh} \
    -v n8n-storage-restored:/home/node/.n8n \
    --user 1000:1000 \
    n8nio/n8n:${N8N_VERSION:-latest}

# Wait for N8N to start
log_message "⏳ Waiting for N8N to start..."
for i in {1..60}; do
    if curl -f -s http://localhost:5679/healthz > /dev/null 2>&1; then
        log_message "✅ N8N restored is ready"
        break
    else
        sleep 2
    fi
    
    if [ $i -eq 60 ]; then
        log_message "⚠️ N8N may still be starting (timeout after 2 minutes)"
        log_message "   Check logs: docker logs n8n-restored"
        break
    fi
done

# Step 5: Verify restore integrity
log_message "🔍 Verifying restore integrity..."

# Check database connection
if docker exec n8n-restored wget --no-verbose --tries=1 --spider http://localhost:5678/healthz 2>/dev/null; then
    log_message "✅ N8N health check passed"
else
    log_message "⚠️ N8N health check failed (may still be initializing)"
fi

# Check workflows count
sleep 10
WORKFLOW_COUNT=$(docker exec n8n-postgres-restored psql -U $POSTGRES_USER -d ${POSTGRES_DB}_restored -t -c "SELECT COUNT(*) FROM workflow_entity;" 2>/dev/null | tr -d ' ' || echo "0")
log_message "📊 Restored workflows: $WORKFLOW_COUNT"

# Check executions count
EXECUTION_COUNT=$(docker exec n8n-postgres-restored psql -U $POSTGRES_USER -d ${POSTGRES_DB}_restored -t -c "SELECT COUNT(*) FROM execution_entity;" 2>/dev/null | tr -d ' ' || echo "0")
log_message "📊 Restored executions: $EXECUTION_COUNT"

# Step 6: Generate restore report
log_message "📋 Generating restore report..."

REPORT_FILE="$BACKUP_DIR/logs/restore_report_$(date +%Y%m%d_%H%M%S).txt"
cat > $REPORT_FILE << EOF
N8N Test Environment Restore Report
==================================
Restore Date: $(date)
Backup Timestamp: $RESTORE_TIMESTAMP

Source Files:
- Database: $DB_BACKUP_FILE
- Volume: $VOLUME_BACKUP_FILE

Restored Data:
- Database Tables: $TABLE_COUNT
- Volume Files: $FILE_COUNT
- Workflows: $WORKFLOW_COUNT
- Executions: $EXECUTION_COUNT

Restored Services:
- PostgreSQL: n8n-postgres-restored (internal network)
- N8N: n8n-restored (http://localhost:5679)
- Volume: n8n-storage-restored

Status: SUCCESS

Next Steps:
1. Access restored N8N at: http://localhost:5679
2. Verify workflows and data integrity
3. Test critical workflows
4. When satisfied, clean up: docker rm -f n8n-restored n8n-postgres-restored && docker volume rm n8n-storage-restored
EOF

log_message "✅ Restore report generated: $REPORT_FILE"

# Step 7: Send notification (if configured)
if [ ! -z "$TELEGRAM_BOT_TOKEN" ] && [ ! -z "$TELEGRAM_CHAT_ID" ]; then
    log_message "📱 Sending Telegram notification..."
    
    MESSAGE="🔄 N8N Test Restore Completed

📅 Time: $(date)
📁 Source: $RESTORE_TIMESTAMP
📊 Tables: $TABLE_COUNT
📄 Files: $FILE_COUNT
🔄 Workflows: $WORKFLOW_COUNT
🎯 Executions: $EXECUTION_COUNT
🌐 URL: http://localhost:5679
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
echo -e "${GREEN}🎉 Restore Completed Successfully!${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}📊 Summary:${NC}"
echo -e "${YELLOW}• Database tables: ${TABLE_COUNT}${NC}"
echo -e "${YELLOW}• Volume files: ${FILE_COUNT}${NC}"
echo -e "${YELLOW}• Workflows: ${WORKFLOW_COUNT}${NC}"
echo -e "${YELLOW}• Executions: ${EXECUTION_COUNT}${NC}"

echo -e "\n${BLUE}Access Information:${NC}"
echo -e "${YELLOW}• N8N Restored: http://localhost:5679${NC}"
echo -e "${YELLOW}• PostgreSQL: n8n-postgres-restored (internal)${NC}"
echo -e "${YELLOW}• Volume: n8n-storage-restored${NC}"

echo -e "\n${BLUE}Management Commands:${NC}"
echo -e "${YELLOW}• View logs: docker logs n8n-restored${NC}"
echo -e "${YELLOW}• Check DB: docker exec n8n-postgres-restored psql -U $POSTGRES_USER -d ${POSTGRES_DB}_restored${NC}"
echo -e "${YELLOW}• Cleanup: docker rm -f n8n-restored n8n-postgres-restored && docker volume rm n8n-storage-restored${NC}"

echo -e "\n${BLUE}Verification Steps:${NC}"
echo -e "${YELLOW}1. Access N8N at http://localhost:5679${NC}"
echo -e "${YELLOW}2. Login with existing credentials${NC}"
echo -e "${YELLOW}3. Verify workflows are present and functional${NC}"
echo -e "${YELLOW}4. Test critical workflows${NC}"
echo -e "${YELLOW}5. Check execution history${NC}"

log_message "🏁 Restore process completed successfully"

# Don't run cleanup on successful completion
trap - EXIT
