# N8N Production Stack

**Version:** 1.68.1  
**Status:** ✅ Production Ready  
**Last Cleanup:** 04/12/2025

---

## 📋 Tổng Quan

Stack N8N production-ready với queue mode, Redis, và PostgreSQL. Hỗ trợ scaling workers và disaster recovery.

### **Services**
- **N8N Main:** Workflow automation engine (port 5678)
- **N8N Worker:** Xử lý jobs bất đồng bộ (scalable)
- **PostgreSQL:** Database chính (14-alpine)
- **Redis:** Queue & cache (7-alpine)

---

## 🚀 Quick Start

### **1. Cấu Hình**
```bash
# Copy template
cp .env.example .env

# Edit config
nano .env
```

**Required:**
- `POSTGRES_NON_ROOT_PASSWORD` - Database password
- `REDIS_PASSWORD` - Redis password
- `N8N_ENCRYPTION_KEY` - Encryption key (min 10 chars)

### **2. Deploy**
```bash
# Start all services
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f n8n
```

### **3. Access**
```
URL: http://localhost:5678
```

---

## 📁 File Structure

```
n8n-stack/
├── .env                     # Active config (gitignored)
├── .env.example             # Config template
├── docker-compose.yml       # Stack definition
├── CLEANUP-SUMMARY.md       # Cleanup report
└── README.md                # This file
```

---

## ⚙️ Configuration

### **Environment Variables**

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_DB` | `n8n` | Database name |
| `POSTGRES_SCHEMA` | `public` | Database schema |
| `POSTGRES_NON_ROOT_USER` | `lequyet_n8n` | DB user |
| `POSTGRES_NON_ROOT_PASSWORD` | - | DB password (CHANGE!) |
| `REDIS_PASSWORD` | - | Redis password (CHANGE!) |
| `N8N_ENCRYPTION_KEY` | - | Encryption key (CHANGE!) |
| `N8N_HOST` | `localhost` | N8N hostname |
| `N8N_PORT` | `5678` | N8N port |
| `EXECUTIONS_MODE` | `queue` | Execution mode |

### **Resource Limits**

| Service | CPU | Memory |
|---------|-----|--------|
| **N8N** | 2 cores | 2 GB |
| **Worker** | - | 7.68 GB |
| **Postgres** | 1 core | 1 GB |
| **Redis** | 0.5 core | 512 MB |

---

## 🔧 Operations

### **Scaling Workers**
```bash
# 1. Comment out container_name in docker-compose.yml
# Line 154: container_name: n8n-worker

# 2. Scale to 3 workers
docker compose up -d --scale n8n-worker=3

# 3. Verify
docker compose ps
```

### **Restart Services**
```bash
# Restart all
docker compose restart

# Restart specific service
docker compose restart n8n
```

### **Update N8N**
```bash
# 1. Update image tag in docker-compose.yml
# image: n8nio/n8n:1.XX.X

# 2. Pull new image
docker compose pull

# 3. Recreate containers
docker compose up -d

# 4. Verify
curl http://localhost:5678/healthz
```

### **View Logs**
```bash
# All services
docker compose logs -f

# Specific service
docker logs n8n -f
docker logs n8n-worker -f
docker logs n8n-postgres -f
docker logs n8n-redis -f
```

---

## 🔍 Monitoring

### **Health Checks**
```bash
# N8N
curl http://localhost:5678/healthz
# Expected: {"status":"ok"}

# Postgres
docker exec n8n-postgres pg_isready -U lequyet_n8n -d n8n

# Redis
docker exec n8n-redis redis-cli -a <PASSWORD> ping
# Expected: PONG
```

### **Container Stats**
```bash
docker stats n8n n8n-worker n8n-postgres n8n-redis
```

### **Queue Status**
```bash
# Check Redis keys
docker exec n8n-redis redis-cli -a <PASSWORD> KEYS "bull:*"

# Check job count
docker exec n8n-redis redis-cli -a <PASSWORD> GET "bull:jobs:id"
```

---

## 🛡️ Security

### **Best Practices**
- ✅ Non-root users (`user: node:node`)
- ✅ Security options enabled (`no-new-privileges`)
- ✅ Passwords in `.env` (not hardcoded)
- ✅ `.env` gitignored
- ✅ Log rotation enabled
- ✅ Resource limits defined

### **Change Default Passwords**
```bash
# Generate strong passwords
openssl rand -base64 32

# Update .env
nano .env
```

### **Generate Encryption Key**
```bash
# Method 1: OpenSSL
openssl rand -hex 32

# Method 2: PowerShell
-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
```

---

## 🐛 Troubleshooting

### **N8N Won't Start**
```bash
# Check logs
docker logs n8n

# Common issues:
# - Wrong DB credentials
# - Redis not accessible
# - Port 5678 already in use
```

### **Worker Not Processing Jobs**
```bash
# Check worker logs
docker logs n8n-worker

# Verify Redis connection
docker exec n8n-worker env | grep REDIS
```

### **Database Connection Issues**
```bash
# Test connection
docker exec n8n pg_isready -h postgres -U lequyet_n8n -d n8n

# Check credentials in .env
cat .env | grep POSTGRES
```

### **Redis Authentication Failed**
```bash
# Verify password
docker exec n8n-redis redis-cli -a <PASSWORD> ping

# Check password in .env matches
cat .env | grep REDIS_PASSWORD
```

---

## 📦 Volumes

| Volume | Purpose | Size |
|--------|---------|------|
| `n8n-storage` | Workflows, credentials, settings | ~100 MB |
| `n8n-postgres-data` | Database files | ~500 MB |
| `n8n-redis-data` | Queue data | ~50 MB |

### **Backup Volumes**
```bash
# Automated backup in ../backup-stack
# Manual backup:
docker run --rm -v n8n-storage:/data -v $(pwd):/backup alpine tar czf /backup/n8n-storage.tar.gz -C /data .
```

---

## 🔗 Related Documentation

- **Cleanup Report:** [CLEANUP-SUMMARY.md](./CLEANUP-SUMMARY.md)
- **Deployment Checklist:** [../DEPLOYMENT-CHECKLIST.md](../DEPLOYMENT-CHECKLIST.md)
- **Review Summary:** [../REVIEW-SUMMARY.md](../REVIEW-SUMMARY.md)
- **Backup Stack:** [../backup-stack/](../backup-stack/)

---

## 📞 Support

### **Official Resources**
- N8N Docs: https://docs.n8n.io/
- N8N Community: https://community.n8n.io/
- N8N GitHub: https://github.com/n8n-io/n8n

### **Project Status**
- ✅ Production Ready
- ✅ Tested & Validated
- ✅ Cleanup Completed (04/12/2025)
- ✅ Ghost Container Removed

---

**Last Updated:** 04/12/2025  
**Maintained By:** DevOps Team
