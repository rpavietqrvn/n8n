#!/bin/bash

# ==========================================
# N8N Test Environment - SSL Setup Script
# ==========================================

set -e

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
echo -e "${BLUE}N8N Test Environment - SSL Setup${NC}"
echo -e "${BLUE}===========================================${NC}"

# Check required variables
if [ -z "$N8N_DOMAIN" ] || [ -z "$SSL_EMAIL" ]; then
    echo -e "${RED}Error: N8N_DOMAIN and SSL_EMAIL must be set in .env file${NC}"
    exit 1
fi

echo -e "${YELLOW}Domain: $N8N_DOMAIN${NC}"
echo -e "${YELLOW}Email: $SSL_EMAIL${NC}"

# Step 1: Start basic services without SSL
echo -e "\n${BLUE}Step 1: Starting basic services...${NC}"
docker compose up -d postgres redis n8n-main

# Wait for services to be ready
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
sleep 30

# Check if N8N is responding
echo -e "${YELLOW}Checking N8N health...${NC}"
for i in {1..10}; do
    if docker exec n8n-test-main wget --no-verbose --tries=1 --spider http://localhost:5678/healthz 2>/dev/null; then
        echo -e "${GREEN}✅ N8N is ready${NC}"
        break
    else
        echo -e "${YELLOW}⏳ Waiting for N8N... (attempt $i/10)${NC}"
        sleep 10
    fi
    
    if [ $i -eq 10 ]; then
        echo -e "${RED}❌ N8N failed to start${NC}"
        exit 1
    fi
done

# Step 2: Start Nginx without SSL (for Let's Encrypt challenge)
echo -e "\n${BLUE}Step 2: Starting Nginx for Let's Encrypt challenge...${NC}"

# Create temporary nginx config for HTTP only
mkdir -p nginx/conf.d/temp
cat > nginx/conf.d/temp/http-only.conf << EOF
server {
    listen 80;
    server_name $N8N_DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        proxy_pass http://n8n-main:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Start Nginx with HTTP-only config
docker run -d --name n8n-test-nginx-temp \
    --network n8n_test_network \
    -p 80:80 \
    -v $(pwd)/nginx/conf.d/temp:/etc/nginx/conf.d:ro \
    -v nginx_ssl_www:/var/www/certbot \
    nginx:1.25-alpine

sleep 5

# Step 3: Obtain SSL certificate
echo -e "\n${BLUE}Step 3: Obtaining SSL certificate...${NC}"

# Check if certificate already exists
if docker run --rm \
    -v nginx_ssl_certs:/etc/letsencrypt \
    certbot/certbot:latest \
    certificates | grep -q "$N8N_DOMAIN"; then
    echo -e "${GREEN}✅ Certificate already exists for $N8N_DOMAIN${NC}"
else
    echo -e "${YELLOW}🔐 Requesting new certificate for $N8N_DOMAIN...${NC}"
    
    # Request certificate
    docker run --rm \
        --network n8n_test_network \
        -v nginx_ssl_certs:/etc/letsencrypt \
        -v nginx_ssl_www:/var/www/certbot \
        certbot/certbot:latest \
        certonly --webroot --webroot-path=/var/www/certbot \
        --email $SSL_EMAIL \
        --agree-tos --no-eff-email \
        -d $N8N_DOMAIN
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ SSL certificate obtained successfully${NC}"
    else
        echo -e "${RED}❌ Failed to obtain SSL certificate${NC}"
        docker rm -f n8n-test-nginx-temp
        exit 1
    fi
fi

# Step 4: Stop temporary Nginx and start full stack
echo -e "\n${BLUE}Step 4: Starting full stack with SSL...${NC}"

# Stop temporary Nginx
docker rm -f n8n-test-nginx-temp

# Remove temporary config
rm -rf nginx/conf.d/temp

# Start full stack
docker compose up -d

# Step 5: Verify SSL setup
echo -e "\n${BLUE}Step 5: Verifying SSL setup...${NC}"

# Wait for Nginx to start
sleep 10

# Test HTTPS connection
echo -e "${YELLOW}Testing HTTPS connection...${NC}"
for i in {1..5}; do
    if curl -f -s --connect-timeout 10 https://$N8N_DOMAIN/healthz > /dev/null; then
        echo -e "${GREEN}✅ HTTPS is working correctly${NC}"
        break
    else
        echo -e "${YELLOW}⏳ Waiting for HTTPS... (attempt $i/5)${NC}"
        sleep 10
    fi
    
    if [ $i -eq 5 ]; then
        echo -e "${RED}❌ HTTPS connection failed${NC}"
        echo -e "${YELLOW}Check Nginx logs: docker logs n8n-test-nginx${NC}"
        exit 1
    fi
done

# Step 6: Setup SSL renewal cron job
echo -e "\n${BLUE}Step 6: Setting up SSL renewal...${NC}"

# Create renewal script
cat > scripts/renew-ssl.sh << 'EOF'
#!/bin/bash

# SSL Certificate Renewal Script
echo "[$(date)] Starting SSL certificate renewal..."

# Renew certificates
docker run --rm \
    -v nginx_ssl_certs:/etc/letsencrypt \
    -v nginx_ssl_www:/var/www/certbot \
    certbot/certbot:latest \
    renew --quiet

# Reload Nginx if renewal was successful
if [ $? -eq 0 ]; then
    echo "[$(date)] Certificate renewal successful, reloading Nginx..."
    docker exec n8n-test-nginx nginx -s reload
    echo "[$(date)] SSL renewal completed successfully"
else
    echo "[$(date)] SSL renewal failed"
    exit 1
fi
EOF

chmod +x scripts/renew-ssl.sh

echo -e "${GREEN}✅ SSL renewal script created at scripts/renew-ssl.sh${NC}"
echo -e "${YELLOW}💡 Add to crontab: 0 12 * * * /path/to/scripts/renew-ssl.sh${NC}"

# Final status
echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}🎉 SSL Setup Completed Successfully!${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}✅ N8N Test Environment: https://$N8N_DOMAIN${NC}"
echo -e "${GREEN}✅ SSL Certificate: Valid${NC}"
echo -e "${GREEN}✅ Auto-renewal: Configured${NC}"
echo -e "\n${BLUE}Next Steps:${NC}"
echo -e "${YELLOW}1. Access N8N at: https://$N8N_DOMAIN${NC}"
echo -e "${YELLOW}2. Setup initial admin user${NC}"
echo -e "${YELLOW}3. Run load tests: docker compose --profile testing up -d${NC}"
echo -e "${YELLOW}4. Scale workers: docker compose up -d --scale n8n-worker=4${NC}"

echo -e "\n${BLUE}Useful Commands:${NC}"
echo -e "${YELLOW}• View logs: docker compose logs -f${NC}"
echo -e "${YELLOW}• Check SSL: curl -I https://$N8N_DOMAIN${NC}"
echo -e "${YELLOW}• Renew SSL: ./scripts/renew-ssl.sh${NC}"
echo -e "${YELLOW}• Scale workers: docker compose up -d --scale n8n-worker=N${NC}"
