#!/bin/bash

# ==========================================
# N8N Test Environment - Load Testing Script
# ==========================================

set -e

# Load environment variables
if [ -f ../.env ]; then
    export $(cat ../.env | grep -v '#' | awk '/=/ {print $1}')
fi

# Default configuration
N8N_URL="https://${N8N_DOMAIN:-n8n-test.vietqr.vn}"
CONCURRENT_WORKFLOWS=${LOAD_TEST_CONCURRENT_WORKFLOWS:-50}
HEAVY_WORKFLOWS=${LOAD_TEST_HEAVY_WORKFLOWS:-10}
TEST_DURATION=${LOAD_TEST_DURATION_MINUTES:-30}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}N8N Test Environment - Load Testing${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "${YELLOW}Target URL: $N8N_URL${NC}"
echo -e "${YELLOW}Concurrent Workflows: $CONCURRENT_WORKFLOWS${NC}"
echo -e "${YELLOW}Heavy Workflows: $HEAVY_WORKFLOWS${NC}"
echo -e "${YELLOW}Test Duration: $TEST_DURATION minutes${NC}"

# Create results directory
RESULTS_DIR="./results/$(date +%Y%m%d_%H%M%S)"
mkdir -p $RESULTS_DIR

# Function to log messages
log_message() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $RESULTS_DIR/load_test.log
}

# Function to check N8N health
check_health() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$N8N_URL/healthz" || echo "000")
    if [ "$response" = "200" ]; then
        return 0
    else
        return 1
    fi
}

# Function to create simple workflow via API
create_simple_workflow() {
    local workflow_name="LoadTest_Simple_$1"
    local webhook_id="test-simple-$(date +%s)-$RANDOM"
    
    local workflow_json='{
        "name": "'$workflow_name'",
        "nodes": [
            {
                "parameters": {
                    "httpMethod": "GET",
                    "path": "'$webhook_id'",
                    "responseMode": "onReceived",
                    "options": {}
                },
                "name": "Webhook",
                "type": "n8n-nodes-base.webhook",
                "typeVersion": 1,
                "position": [250, 300],
                "webhookId": "'$webhook_id'"
            },
            {
                "parameters": {
                    "values": {
                        "string": [
                            {
                                "name": "message",
                                "value": "Hello from load test workflow '$workflow_name'"
                            },
                            {
                                "name": "timestamp",
                                "value": "={{new Date().toISOString()}}"
                            }
                        ]
                    },
                    "options": {}
                },
                "name": "Set",
                "type": "n8n-nodes-base.set",
                "typeVersion": 1,
                "position": [450, 300]
            }
        ],
        "connections": {
            "Webhook": {
                "main": [
                    [
                        {
                            "node": "Set",
                            "type": "main",
                            "index": 0
                        }
                    ]
                ]
            }
        },
        "active": true,
        "settings": {},
        "staticData": null
    }'
    
    echo "$N8N_URL/webhook/$webhook_id"
}

# Function to create heavy workflow via API
create_heavy_workflow() {
    local workflow_name="LoadTest_Heavy_$1"
    local webhook_id="test-heavy-$(date +%s)-$RANDOM"
    
    local workflow_json='{
        "name": "'$workflow_name'",
        "nodes": [
            {
                "parameters": {
                    "httpMethod": "POST",
                    "path": "'$webhook_id'",
                    "responseMode": "onReceived",
                    "options": {}
                },
                "name": "Webhook",
                "type": "n8n-nodes-base.webhook",
                "typeVersion": 1,
                "position": [250, 300],
                "webhookId": "'$webhook_id'"
            },
            {
                "parameters": {
                    "functionCode": "// Heavy computation simulation\nconst start = Date.now();\nlet result = 0;\n\n// CPU intensive loop\nfor (let i = 0; i < 1000000; i++) {\n    result += Math.sqrt(i) * Math.sin(i);\n}\n\n// Memory allocation\nconst largeArray = new Array(100000).fill(0).map((_, i) => ({\n    id: i,\n    data: Math.random().toString(36),\n    timestamp: new Date().toISOString()\n}));\n\nconst processingTime = Date.now() - start;\n\nreturn [{\n    json: {\n        workflowName: \"'$workflow_name'\",\n        processingTime: processingTime,\n        result: result,\n        arrayLength: largeArray.length,\n        timestamp: new Date().toISOString(),\n        message: \"Heavy workflow completed\"\n    }\n}];"
                },
                "name": "Function",
                "type": "n8n-nodes-base.function",
                "typeVersion": 1,
                "position": [450, 300]
            },
            {
                "parameters": {
                    "amount": 3,
                    "unit": "seconds"
                },
                "name": "Wait",
                "type": "n8n-nodes-base.wait",
                "typeVersion": 1,
                "position": [650, 300]
            }
        ],
        "connections": {
            "Webhook": {
                "main": [
                    [
                        {
                            "node": "Function",
                            "type": "main",
                            "index": 0
                        }
                    ]
                ]
            },
            "Function": {
                "main": [
                    [
                        {
                            "node": "Wait",
                            "type": "main",
                            "index": 0
                        }
                    ]
                ]
            }
        },
        "active": true,
        "settings": {},
        "staticData": null
    }'
    
    echo "$N8N_URL/webhook/$webhook_id"
}

# Function to run concurrent requests
run_concurrent_requests() {
    local url=$1
    local count=$2
    local type=$3
    local pids=()
    
    log_message "🚀 Starting $count concurrent $type requests to $url"
    
    for i in $(seq 1 $count); do
        {
            local start_time=$(date +%s.%N)
            local response
            local http_code
            
            if [ "$type" = "simple" ]; then
                response=$(curl -s -o /dev/null -w "%{http_code},%{time_total}" "$url" 2>/dev/null || echo "000,0")
            else
                response=$(curl -s -o /dev/null -w "%{http_code},%{time_total}" -X POST -H "Content-Type: application/json" -d '{"test": true}' "$url" 2>/dev/null || echo "000,0")
            fi
            
            local end_time=$(date +%s.%N)
            local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
            
            IFS=',' read -r http_code time_total <<< "$response"
            
            echo "$i,$http_code,$time_total,$duration,$(date '+%Y-%m-%d %H:%M:%S')" >> $RESULTS_DIR/${type}_requests.csv
        } &
        pids+=($!)
        
        # Limit concurrent processes to avoid overwhelming the system
        if [ ${#pids[@]} -ge 20 ]; then
            wait ${pids[0]}
            pids=("${pids[@]:1}")
        fi
    done
    
    # Wait for all remaining processes
    for pid in "${pids[@]}"; do
        wait $pid
    done
    
    log_message "✅ Completed $count $type requests"
}

# Function to monitor system resources
monitor_resources() {
    log_message "📊 Starting resource monitoring..."
    
    {
        echo "timestamp,cpu_usage,memory_usage,redis_memory,postgres_connections"
        while true; do
            local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            
            # Get container stats
            local n8n_stats=$(docker stats --no-stream --format "table {{.CPUPerc}},{{.MemUsage}}" n8n-test-main 2>/dev/null | tail -1 || echo "0%,0B / 0B")
            local cpu_usage=$(echo "$n8n_stats" | cut -d',' -f1 | tr -d '%')
            local memory_usage=$(echo "$n8n_stats" | cut -d',' -f2 | cut -d'/' -f1 | tr -d 'B MiGKB' | tr -d ' ')
            
            # Get Redis memory usage
            local redis_memory=$(docker exec n8n-test-redis redis-cli --raw info memory 2>/dev/null | grep used_memory_human | cut -d':' -f2 | tr -d '\r' || echo "0M")
            
            # Get PostgreSQL connections
            local postgres_connections=$(docker exec n8n-test-postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ' || echo "0")
            
            echo "$timestamp,$cpu_usage,$memory_usage,$redis_memory,$postgres_connections"
            sleep 5
        done
    } > $RESULTS_DIR/resource_monitoring.csv &
    
    MONITOR_PID=$!
}

# Function to generate load test report
generate_report() {
    log_message "📋 Generating load test report..."
    
    local report_file="$RESULTS_DIR/load_test_report.txt"
    local simple_total=$(wc -l < $RESULTS_DIR/simple_requests.csv 2>/dev/null || echo "0")
    local heavy_total=$(wc -l < $RESULTS_DIR/heavy_requests.csv 2>/dev/null || echo "0")
    
    # Calculate success rates
    local simple_success=$(awk -F',' '$2 == 200 {count++} END {print count+0}' $RESULTS_DIR/simple_requests.csv 2>/dev/null || echo "0")
    local heavy_success=$(awk -F',' '$2 == 200 {count++} END {print count+0}' $RESULTS_DIR/heavy_requests.csv 2>/dev/null || echo "0")
    
    # Calculate average response times
    local simple_avg_time=$(awk -F',' '$2 == 200 {sum+=$3; count++} END {if(count>0) print sum/count; else print 0}' $RESULTS_DIR/simple_requests.csv 2>/dev/null || echo "0")
    local heavy_avg_time=$(awk -F',' '$2 == 200 {sum+=$3; count++} END {if(count>0) print sum/count; else print 0}' $RESULTS_DIR/heavy_requests.csv 2>/dev/null || echo "0")
    
    cat > $report_file << EOF
N8N Test Environment - Load Test Report
======================================
Test Date: $(date)
Target URL: $N8N_URL
Test Duration: $TEST_DURATION minutes

Test Configuration:
- Concurrent Simple Workflows: $CONCURRENT_WORKFLOWS
- Heavy Workflows: $HEAVY_WORKFLOWS

Results Summary:
===============

Simple Workflows:
- Total Requests: $simple_total
- Successful Requests: $simple_success
- Success Rate: $(echo "scale=2; $simple_success * 100 / $simple_total" | bc -l 2>/dev/null || echo "0")%
- Average Response Time: ${simple_avg_time}s

Heavy Workflows:
- Total Requests: $heavy_total
- Successful Requests: $heavy_success
- Success Rate: $(echo "scale=2; $heavy_success * 100 / $heavy_total" | bc -l 2>/dev/null || echo "0")%
- Average Response Time: ${heavy_avg_time}s

Performance Analysis:
====================
$(if [ -f $RESULTS_DIR/resource_monitoring.csv ]; then
    echo "Peak CPU Usage: $(awk -F',' 'NR>1 {if($2>max) max=$2} END {print max"%"}' $RESULTS_DIR/resource_monitoring.csv)"
    echo "Peak Memory Usage: $(awk -F',' 'NR>1 {if($3>max) max=$3} END {print max"MB"}' $RESULTS_DIR/resource_monitoring.csv)"
    echo "Max PostgreSQL Connections: $(awk -F',' 'NR>1 {if($5>max) max=$5} END {print max}' $RESULTS_DIR/resource_monitoring.csv)"
else
    echo "Resource monitoring data not available"
fi)

Test Status: $(if [ "$simple_success" -gt 0 ] && [ "$heavy_success" -gt 0 ]; then echo "PASSED"; else echo "FAILED"; fi)

Files Generated:
- simple_requests.csv: Individual simple workflow request results
- heavy_requests.csv: Individual heavy workflow request results
- resource_monitoring.csv: System resource usage during test
- load_test.log: Detailed test execution log
EOF

    log_message "✅ Load test report generated: $report_file"
}

# Main execution
main() {
    log_message "🏁 Starting N8N load test..."
    
    # Pre-flight checks
    log_message "🔍 Running pre-flight checks..."
    
    if ! check_health; then
        log_message "❌ N8N health check failed. URL: $N8N_URL/healthz"
        exit 1
    fi
    log_message "✅ N8N is healthy"
    
    # Check Docker containers
    if ! docker ps | grep -q "n8n-test-main"; then
        log_message "❌ N8N main container is not running"
        exit 1
    fi
    log_message "✅ N8N containers are running"
    
    # Start resource monitoring
    monitor_resources
    
    # Initialize CSV files
    echo "request_id,http_code,response_time,total_duration,timestamp" > $RESULTS_DIR/simple_requests.csv
    echo "request_id,http_code,response_time,total_duration,timestamp" > $RESULTS_DIR/heavy_requests.csv
    
    # Create webhook URLs (simulate workflow creation)
    log_message "🔧 Preparing test workflows..."
    SIMPLE_WEBHOOK_URL="$N8N_URL/webhook/test-simple-$(date +%s)"
    HEAVY_WEBHOOK_URL="$N8N_URL/webhook/test-heavy-$(date +%s)"
    
    # Test 1: Simple concurrent workflows
    log_message "📝 Test 1: Running $CONCURRENT_WORKFLOWS simple concurrent workflows..."
    run_concurrent_requests "$SIMPLE_WEBHOOK_URL" "$CONCURRENT_WORKFLOWS" "simple"
    
    # Wait between tests
    log_message "⏳ Waiting 30 seconds between tests..."
    sleep 30
    
    # Test 2: Heavy workflows
    log_message "📝 Test 2: Running $HEAVY_WORKFLOWS heavy workflows..."
    run_concurrent_requests "$HEAVY_WEBHOOK_URL" "$HEAVY_WORKFLOWS" "heavy"
    
    # Wait for all executions to complete
    log_message "⏳ Waiting for all executions to complete..."
    sleep 60
    
    # Stop resource monitoring
    if [ ! -z "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null || true
        log_message "✅ Resource monitoring stopped"
    fi
    
    # Generate report
    generate_report
    
    # Final summary
    echo -e "\n${GREEN}===========================================${NC}"
    echo -e "${GREEN}🎉 Load Test Completed!${NC}"
    echo -e "${GREEN}===========================================${NC}"
    echo -e "${YELLOW}📊 Results saved to: $RESULTS_DIR${NC}"
    echo -e "${YELLOW}📋 Report: $RESULTS_DIR/load_test_report.txt${NC}"
    echo -e "\n${BLUE}Quick Stats:${NC}"
    
    if [ -f "$RESULTS_DIR/simple_requests.csv" ]; then
        local simple_success=$(awk -F',' '$2 == 200 {count++} END {print count+0}' $RESULTS_DIR/simple_requests.csv)
        local simple_total=$(wc -l < $RESULTS_DIR/simple_requests.csv)
        echo -e "${YELLOW}• Simple workflows: $simple_success/$simple_total successful${NC}"
    fi
    
    if [ -f "$RESULTS_DIR/heavy_requests.csv" ]; then
        local heavy_success=$(awk -F',' '$2 == 200 {count++} END {print count+0}' $RESULTS_DIR/heavy_requests.csv)
        local heavy_total=$(wc -l < $RESULTS_DIR/heavy_requests.csv)
        echo -e "${YELLOW}• Heavy workflows: $heavy_success/$heavy_total successful${NC}"
    fi
    
    log_message "🏁 Load test completed successfully"
}

# Execute main function
main "$@"
