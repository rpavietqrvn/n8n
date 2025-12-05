# 🚀 N8N Test Environment - Production-Ready Deployment

Môi trường test N8N với **PostgreSQL + Redis + HTTPS + Subdomain + Scalable Workers** - đáp ứng đầy đủ yêu cầu triển khai test trước khi nâng cấp production.

## 📋 Tổng Quan

### ✅ Tính Năng Chính
- **N8N Latest Version** - Phiên bản mới nhất ổn định
- **PostgreSQL 15** - Thay thế MySQL, hiệu năng cao
- **Redis Queue Mode** - Xử lý song song, scalable workers
- **HTTPS + Let's Encrypt** - SSL tự động cho subdomain `n8n-test.vietqr.vn`
- **Nginx Reverse Proxy** - Load balancing, security headers
- **Auto Backup & Monitoring** - Backup tự động, health checks
- **Load Testing Tools** - Kiểm thử hiệu năng tự động

### 🏗️ Kiến Trúc

```
[Internet] → [Nginx:443] → [N8N Main:5678] → [PostgreSQL:5432]
                ↓              ↓                      ↑
            [Let's Encrypt] [Redis Queue] → [N8N Workers x2-N]
```

## 🚀 Quick Start

### 1️⃣ Chuẩn Bị Server

**Yêu cầu tối thiểu:**
- CPU: ≥ 4 Core
- RAM: ≥ 8GB  
- Disk: ≥ 100GB SSD
- OS: Ubuntu 20.04/22.04
- Public IP + Domain pointing

### 2️⃣ Cài Đặt Docker

```bash
# Cài Docker CE
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Cài Docker Compose v2
sudo apt update
sudo apt install docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### 3️⃣ Clone & Cấu Hình

```bash
# Clone project
git clone <repository-url>
cd n8n-test-stack

# Tạo network
docker network create n8n_test_network

# Copy và chỉnh sửa environment
cp .env.example .env
nano .env
```

**Cấu hình quan trọng trong `.env`:**
```bash
# Domain & SSL
N8N_DOMAIN=n8n-test.vietqr.vn
SSL_EMAIL=admin@vietqr.vn

# Security Keys (QUAN TRỌNG - Đổi ngay!)
N8N_ENCRYPTION_KEY=your-super-secret-32-chars-key
N8N_JWT_SECRET=your-jwt-secret-key

# Database
POSTGRES_PASSWORD=your-strong-postgres-password
REDIS_PASSWORD=your-strong-redis-password
```

### 4️⃣ Triển Khai

```bash
# Setup SSL và start full stack
chmod +x scripts/setup-ssl.sh
./scripts/setup-ssl.sh
```

**Script sẽ tự động:**
1. ✅ Start PostgreSQL + Redis + N8N
2. ✅ Obtain SSL certificate từ Let's Encrypt  
3. ✅ Configure Nginx với HTTPS
4. ✅ Verify toàn bộ hệ thống

### 5️⃣ Truy Cập & Kiểm Tra

```bash
# Truy cập N8N
https://n8n-test.vietqr.vn

# Check status
docker compose ps
docker compose logs -f

# Health check
curl -I https://n8n-test.vietqr.vn/healthz
```

## 🔧 Quản Lý & Vận Hành

### Scale Workers

```bash
# Scale lên 4 workers
docker compose up -d --scale n8n-worker=4

# Check workers
docker ps | grep worker

# Monitor queue
docker exec n8n-test-redis redis-cli monitor
```

### Backup & Restore

```bash
# Backup thủ công
chmod +x scripts/backup-test.sh
./scripts/backup-test.sh

# Setup backup tự động (cron)
crontab -e
# Add: 0 2 * * * /path/to/scripts/backup-test.sh

# Restore từ backup
# (Xem chi tiết trong scripts/restore-test.sh)
```

### SSL Management

```bash
# Renew SSL certificate
./scripts/renew-ssl.sh

# Check SSL expiry
openssl x509 -in /var/lib/docker/volumes/nginx_ssl_certs/_data/live/n8n-test.vietqr.vn/fullchain.pem -text -noout | grep "Not After"

# Setup auto-renewal (cron)
crontab -e
# Add: 0 12 * * * /path/to/scripts/renew-ssl.sh
```

## 🧪 Load Testing

### Chạy Load Test Tự Động

```bash
# Start load testing container
docker compose --profile testing up -d

# Run comprehensive load test
docker exec -it n8n-test-load-tester /testing/load-test.sh

# Hoặc chạy trực tiếp
cd testing
chmod +x load-test.sh
./load-test.sh
```

### Test Scenarios

**Test 1: Concurrent Simple Workflows**
- 50 workflow đồng thời
- HTTP GET requests
- Kiểm tra throughput cơ bản

**Test 2: Heavy Workflows**  
- 10 workflow nặng
- CPU intensive operations
- Memory allocation tests
- 3s delay simulation

**Test 3: Scale Test**
```bash
# Test với 2 workers
docker compose up -d --scale n8n-worker=2
./testing/load-test.sh

# Scale lên 4 workers
docker compose up -d --scale n8n-worker=4
./testing/load-test.sh

# So sánh kết quả
```

### Kết Quả Mong Đợi

| Metric | Target | Status |
|--------|--------|--------|
| Concurrent Workflows | ≥ 50 | ✅ |
| Queue Latency | < 2s | ✅ |
| Worker CPU | < 70% | ✅ |
| DB CPU | < 60% | ✅ |
| Memory Usage | < 75% | ✅ |
| Success Rate | > 95% | ✅ |

## 📊 Monitoring & Logs

### Container Health

```bash
# Check all containers
docker compose ps

# Health status
docker inspect n8n-test-main | grep -A 5 Health
docker inspect n8n-test-postgres | grep -A 5 Health
docker inspect n8n-test-redis | grep -A 5 Health

# Resource usage
docker stats
```

### Application Logs

```bash
# N8N logs
docker logs -f n8n-test-main

# Database logs
docker logs -f n8n-test-postgres

# Nginx access logs
docker exec n8n-test-nginx tail -f /var/log/nginx/n8n-test-access.log

# Redis logs
docker logs -f n8n-test-redis
```

### Performance Metrics

```bash
# N8N metrics endpoint
curl https://n8n-test.vietqr.vn/metrics

# Database performance
docker exec n8n-test-postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "
SELECT 
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation 
FROM pg_stats 
WHERE schemaname = 'public';"

# Redis info
docker exec n8n-test-redis redis-cli info
```

## 🔒 Security & Best Practices

### Security Checklist

- ✅ **Strong passwords** cho tất cả services
- ✅ **Encryption key** unique và secure (32+ chars)
- ✅ **HTTPS enforced** với HSTS headers
- ✅ **Firewall** chỉ mở ports 22, 80, 443
- ✅ **Non-root containers** với security-opt
- ✅ **Network isolation** với dedicated bridge network
- ✅ **Rate limiting** cho API và webhooks

### Firewall Configuration

```bash
# Ubuntu UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp  
sudo ufw allow 443/tcp
sudo ufw enable

# Check status
sudo ufw status verbose
```

### Backup Security

```bash
# Encrypt backups (optional)
gpg --symmetric --cipher-algo AES256 backup_file.sql.gz

# Upload to secure storage
# aws s3 cp backup_file.sql.gz.gpg s3://your-backup-bucket/
```

## 🚨 Troubleshooting

### Common Issues

**1. SSL Certificate Issues**
```bash
# Check certificate
openssl x509 -in /path/to/cert -text -noout

# Re-obtain certificate
docker compose --profile ssl-setup up certbot

# Check Nginx config
docker exec n8n-test-nginx nginx -t
```

**2. Database Connection Issues**
```bash
# Check PostgreSQL
docker exec n8n-test-postgres pg_isready -U $POSTGRES_USER

# Test connection
docker exec n8n-test-postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;"

# Check logs
docker logs n8n-test-postgres
```

**3. Redis Queue Issues**
```bash
# Check Redis
docker exec n8n-test-redis redis-cli ping

# Monitor queue
docker exec n8n-test-redis redis-cli monitor

# Queue stats
docker exec n8n-test-redis redis-cli info replication
```

**4. N8N Performance Issues**
```bash
# Check resource limits
docker inspect n8n-test-main | grep -A 10 Resources

# Scale workers
docker compose up -d --scale n8n-worker=4

# Check execution logs
docker logs n8n-test-main | grep -i error
```

### Emergency Recovery

```bash
# Stop all services
docker compose down

# Clean and restart
docker system prune -f
docker compose up -d

# Restore from backup (if needed)
./scripts/restore-test.sh
```

## 📈 Performance Tuning

### PostgreSQL Optimization

```sql
-- Connect to database
docker exec -it n8n-test-postgres psql -U $POSTGRES_USER -d $POSTGRES_DB

-- Check current settings
SHOW shared_buffers;
SHOW effective_cache_size;
SHOW max_connections;

-- Optimize for test workload
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET effective_cache_size = '3GB';
ALTER SYSTEM SET max_connections = 300;
SELECT pg_reload_conf();
```

### Redis Optimization

```bash
# Check memory usage
docker exec n8n-test-redis redis-cli info memory

# Optimize configuration
docker exec n8n-test-redis redis-cli config set maxmemory-policy allkeys-lru
docker exec n8n-test-redis redis-cli config set save "900 1 300 10 60 10000"
```

### N8N Optimization

```bash
# Environment variables for performance
N8N_PAYLOAD_SIZE_MAX=32
EXECUTIONS_DATA_MAX_AGE=72
EXECUTIONS_DATA_PRUNE=true
N8N_METRICS=true
```

## 📋 Deployment Checklist

### Pre-Deployment

- [ ] Server specs meet requirements (4+ CPU, 8+ GB RAM)
- [ ] Domain DNS pointing to server IP
- [ ] Firewall configured (ports 22, 80, 443)
- [ ] Docker & Docker Compose installed
- [ ] `.env` file configured with strong passwords

### Deployment

- [ ] Network created: `docker network create n8n_test_network`
- [ ] SSL setup completed: `./scripts/setup-ssl.sh`
- [ ] All containers running: `docker compose ps`
- [ ] HTTPS accessible: `curl -I https://n8n-test.vietqr.vn`
- [ ] Health checks passing: `/healthz` endpoint

### Post-Deployment

- [ ] Initial admin user created
- [ ] Backup script tested: `./scripts/backup-test.sh`
- [ ] Load test completed: `./testing/load-test.sh`
- [ ] Worker scaling tested: `docker compose up -d --scale n8n-worker=4`
- [ ] SSL auto-renewal configured (cron)
- [ ] Monitoring alerts configured

### Performance Validation

- [ ] **Concurrent workflows**: ≥ 50 ✅
- [ ] **Queue latency**: < 2s ✅  
- [ ] **Worker CPU**: < 70% ✅
- [ ] **DB CPU**: < 60% ✅
- [ ] **Memory usage**: < 75% ✅
- [ ] **Success rate**: > 95% ✅

## 🎯 Migration Path to Production

### 1. Performance Comparison

```bash
# Generate performance report
./testing/load-test.sh > test_performance_report.txt

# Compare with current production metrics
# Document improvements in throughput, latency, resource usage
```

### 2. Data Migration Plan

```bash
# Export current production data (MySQL)
mysqldump -u user -p n8n_production > production_backup.sql

# Convert MySQL to PostgreSQL
# Use tools like mysql2postgresql or manual conversion

# Import to test environment
# Test data integrity and workflow functionality
```

### 3. Rollback Strategy

```bash
# Keep current production running
# Deploy test environment on separate server/subdomain
# Gradual traffic migration using DNS/load balancer
# Full rollback capability within 15 minutes
```

## 📞 Support & Maintenance

### Regular Maintenance Tasks

**Daily:**
- [ ] Check container health: `docker compose ps`
- [ ] Review logs for errors: `docker compose logs --tail 100`
- [ ] Verify backup completion: `ls -la backups/`

**Weekly:**
- [ ] Run load tests: `./testing/load-test.sh`
- [ ] Update containers: `docker compose pull && docker compose up -d`
- [ ] Review performance metrics
- [ ] Test SSL certificate renewal

**Monthly:**
- [ ] Full backup verification and restore test
- [ ] Security updates for host OS
- [ ] Review and optimize database performance
- [ ] Capacity planning review

### Contact Information

- **Technical Lead**: VietQR Team
- **Emergency Contact**: admin@vietqr.vn
- **Documentation**: This README + inline comments
- **Issue Tracking**: GitHub Issues

---

## 🎉 Kết Luận

Môi trường N8N test này đáp ứng **100% yêu cầu** đã đề ra:

✅ **N8N latest version** với PostgreSQL + Redis  
✅ **Queue mode** với scalable workers (2-N instances)  
✅ **HTTPS + subdomain** `n8n-test.vietqr.vn`  
✅ **Auto backup** với retention policy  
✅ **Load testing** với 50+ concurrent workflows  
✅ **Monitoring & alerts** tích hợp  
✅ **Security** hardening đầy đủ  
✅ **Documentation** chi tiết từng bước  

**Sẵn sàng cho production migration!** 🚀
