#!/bin/bash

# ==========================================
# N8N Test Environment - Worker Scaling Script
# ==========================================

set -e

# Configuration
WORKER_COUNT=${1:-2}
MAX_WORKERS=10
MIN_WORKERS=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}N8N Test Environment - Worker Scaling${NC}"
echo -e "${BLUE}Target Workers: $WORKER_COUNT${NC}"
echo -e "${BLUE}===========================================${NC}"

# Function to log messages
log_message() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

# Function to handle errors
handle_error() {
    echo -e "${RED}❌ Error: $1${NC}"
    exit 1
}

# Validate worker count
if ! [[ "$WORKER_COUNT" =~ ^[0-9]+$ ]] || [ "$WORKER_COUNT" -lt $MIN_WORKERS ] || [ "$WORKER_COUNT" -gt $MAX_WORKERS ]; then
    handle_error "Invalid worker count. Must be between $MIN_WORKERS and $MAX_WORKERS"
fi

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    handle_error "docker-compose.yml not found. Run from project root directory."
fi

# Check if N8N main is running
if ! docker ps | grep -q "n8n-test-main"; then
    handle_error "N8N main container is not running. Start the stack first: docker compose up -d"
fi

# Check Redis connection
if ! docker exec n8n-test-redis redis-cli ping > /dev/null 2>&1; then
    handle_error "Redis is not responding. Check Redis container: docker logs n8n-test-redis"
fi

# Get current worker count
CURRENT_WORKERS=$(docker ps | grep "n8n-worker" | wc -l)
log_message "📊 Current workers: $CURRENT_WORKERS"
log_message "🎯 Target workers: $WORKER_COUNT"

if [ "$CURRENT_WORKERS" -eq "$WORKER_COUNT" ]; then
    log_message "✅ Already running $WORKER_COUNT workers. No scaling needed."
    exit 0
fi

# Pre-scaling metrics
log_message "📈 Collecting pre-scaling metrics..."

# Redis queue info
QUEUE_WAITING_BEFORE=$(docker exec n8n-test-redis redis-cli llen "bull:n8n:waiting" 2>/dev/null || echo "0")
QUEUE_ACTIVE_BEFORE=$(docker exec n8n-test-redis redis-cli llen "bull:n8n:active" 2>/dev/null || echo "0")

log_message "   Queue waiting: $QUEUE_WAITING_BEFORE"
log_message "   Queue active: $QUEUE_ACTIVE_BEFORE"

# System resources before scaling
CPU_BEFORE=$(docker stats --no-stream --format "table {{.CPUPerc}}" n8n-test-main | tail -1 | tr -d '%')
MEMORY_BEFORE=$(docker stats --no-stream --format "table {{.MemUsage}}" n8n-test-main | tail -1 | cut -d'/' -f1 | tr -d 'MiB ')

log_message "   N8N CPU: ${CPU_BEFORE}%"
log_message "   N8N Memory: ${MEMORY_BEFORE}MiB"

# Perform scaling
if [ "$WORKER_COUNT" -gt "$CURRENT_WORKERS" ]; then
    log_message "📈 Scaling UP from $CURRENT_WORKERS to $WORKER_COUNT workers..."
    ACTION="scale up"
elif [ "$WORKER_COUNT" -lt "$CURRENT_WORKERS" ]; then
    log_message "📉 Scaling DOWN from $CURRENT_WORKERS to $WORKER_COUNT workers..."
    ACTION="scale down"
fi

# Execute scaling
log_message "🚀 Executing scaling operation..."
docker compose up -d --scale n8n-worker=$WORKER_COUNT

if [ $? -eq 0 ]; then
    log_message "✅ Scaling command completed"
else
    handle_error "Scaling command failed"
fi

# Wait for workers to stabilize
log_message "⏳ Waiting for workers to stabilize..."
sleep 15

# Verify scaling
NEW_WORKER_COUNT=$(docker ps | grep "n8n-worker" | wc -l)
if [ "$NEW_WORKER_COUNT" -eq "$WORKER_COUNT" ]; then
    log_message "✅ Scaling successful: $NEW_WORKER_COUNT workers running"
else
    handle_error "Scaling verification failed. Expected: $WORKER_COUNT, Actual: $NEW_WORKER_COUNT"
fi

# Check worker health
log_message "🔍 Checking worker health..."
HEALTHY_WORKERS=0

for i in $(seq 1 $WORKER_COUNT); do
    CONTAINER_NAME="n8n-test-stack-n8n-worker-$i"
    if docker ps | grep -q "$CONTAINER_NAME"; then
        # Check if worker process is running
        if docker exec "$CONTAINER_NAME" ps aux | grep -q '[n]8n worker' 2>/dev/null; then
            HEALTHY_WORKERS=$((HEALTHY_WORKERS + 1))
            log_message "   ✅ Worker $i: Healthy"
        else
            log_message "   ❌ Worker $i: Process not found"
        fi
    else
        log_message "   ❌ Worker $i: Container not found"
    fi
done

log_message "📊 Healthy workers: $HEALTHY_WORKERS/$WORKER_COUNT"

# Post-scaling metrics
log_message "📊 Collecting post-scaling metrics..."
sleep 5

# Redis queue info after scaling
QUEUE_WAITING_AFTER=$(docker exec n8n-test-redis redis-cli llen "bull:n8n:waiting" 2>/dev/null || echo "0")
QUEUE_ACTIVE_AFTER=$(docker exec n8n-test-redis redis-cli llen "bull:n8n:active" 2>/dev/null || echo "0")

log_message "   Queue waiting: $QUEUE_WAITING_AFTER"
log_message "   Queue active: $QUEUE_ACTIVE_AFTER"

# System resources after scaling
CPU_AFTER=$(docker stats --no-stream --format "table {{.CPUPerc}}" n8n-test-main | tail -1 | tr -d '%')
MEMORY_AFTER=$(docker stats --no-stream --format "table {{.MemUsage}}" n8n-test-main | tail -1 | cut -d'/' -f1 | tr -d 'MiB ')

log_message "   N8N CPU: ${CPU_AFTER}%"
log_message "   N8N Memory: ${MEMORY_AFTER}MiB"

# Performance test (optional)
if [ "$2" = "--test" ]; then
    log_message "🧪 Running performance test..."
    
    # Create simple test workflow
    TEST_URL="http://localhost:5678/webhook/scale-test-$(date +%s)"
    
    # Run concurrent requests
    log_message "   Sending 20 concurrent requests..."
    for i in {1..20}; do
        curl -s "$TEST_URL" > /dev/null &
    done
    
    # Wait for requests to complete
    wait
    
    # Check queue processing
    sleep 5
    QUEUE_FINAL=$(docker exec n8n-test-redis redis-cli llen "bull:n8n:waiting" 2>/dev/null || echo "0")
    log_message "   Final queue size: $QUEUE_FINAL"
    
    if [ "$QUEUE_FINAL" -lt 5 ]; then
        log_message "   ✅ Queue processing efficiently"
    else
        log_message "   ⚠️ Queue may be backlogged"
    fi
fi

# Generate scaling report
REPORT_FILE="scaling_report_$(date +%Y%m%d_%H%M%S).txt"
cat > $REPORT_FILE << EOF
N8N Worker Scaling Report
========================
Date: $(date)
Action: $ACTION
Previous Workers: $CURRENT_WORKERS
New Workers: $WORKER_COUNT
Healthy Workers: $HEALTHY_WORKERS

Performance Metrics:
===================
Queue Waiting (Before): $QUEUE_WAITING_BEFORE
Queue Waiting (After): $QUEUE_WAITING_AFTER
Queue Active (Before): $QUEUE_ACTIVE_BEFORE
Queue Active (After): $QUEUE_ACTIVE_AFTER

Resource Usage:
==============
N8N CPU (Before): ${CPU_BEFORE}%
N8N CPU (After): ${CPU_AFTER}%
N8N Memory (Before): ${MEMORY_BEFORE}MiB
N8N Memory (After): ${MEMORY_AFTER}MiB

Worker Status:
=============
$(for i in $(seq 1 $WORKER_COUNT); do
    CONTAINER_NAME="n8n-test-stack-n8n-worker-$i"
    if docker ps | grep -q "$CONTAINER_NAME"; then
        echo "Worker $i: Running"
    else
        echo "Worker $i: Not Found"
    fi
done)

Status: $(if [ "$HEALTHY_WORKERS" -eq "$WORKER_COUNT" ]; then echo "SUCCESS"; else echo "PARTIAL"; fi)
EOF

log_message "📋 Scaling report generated: $REPORT_FILE"

# Summary
echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}🎉 Scaling Operation Completed!${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}📊 Summary:${NC}"
echo -e "${YELLOW}• Previous workers: $CURRENT_WORKERS${NC}"
echo -e "${YELLOW}• New workers: $WORKER_COUNT${NC}"
echo -e "${YELLOW}• Healthy workers: $HEALTHY_WORKERS${NC}"
echo -e "${YELLOW}• Queue waiting: $QUEUE_WAITING_AFTER${NC}"
echo -e "${YELLOW}• Success rate: $(echo "scale=1; $HEALTHY_WORKERS * 100 / $WORKER_COUNT" | bc -l)%${NC}"

echo -e "\n${BLUE}Management Commands:${NC}"
echo -e "${YELLOW}• View workers: docker ps | grep worker${NC}"
echo -e "${YELLOW}• Worker logs: docker logs n8n-test-stack-n8n-worker-1${NC}"
echo -e "${YELLOW}• Monitor queue: docker exec n8n-test-redis redis-cli monitor${NC}"
echo -e "${YELLOW}• Scale again: ./scripts/scale-workers.sh <count>${NC}"

echo -e "\n${BLUE}Performance Tips:${NC}"
if [ "$WORKER_COUNT" -gt 4 ]; then
    echo -e "${YELLOW}• Consider monitoring CPU/memory usage with $WORKER_COUNT workers${NC}"
    echo -e "${YELLOW}• Optimal worker count depends on workflow complexity${NC}"
fi

if [ "$QUEUE_WAITING_AFTER" -gt 10 ]; then
    echo -e "${YELLOW}• Queue backlog detected, consider more workers${NC}"
elif [ "$QUEUE_WAITING_AFTER" -eq 0 ] && [ "$WORKER_COUNT" -gt 2 ]; then
    echo -e "${YELLOW}• No queue backlog, fewer workers might be sufficient${NC}"
fi

log_message "🏁 Worker scaling completed successfully"
