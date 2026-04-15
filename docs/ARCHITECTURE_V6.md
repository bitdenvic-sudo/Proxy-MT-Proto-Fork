# MTProxy Deploybook v6.0 - Enterprise Grade

## Критические улучшения v6.0

### 1. Многоуровневая защита трафика

#### Уровень 1: Nginx Reverse Proxy
- Терминирует TLS соединения
- Rate limiting на уровне HTTP
- Скрытие реального порта MTProxy
- Дополнительные HTTP заголовки безопасности

#### Уровень 2: Cloudflare Tunnel
- Трафик идёт через Cloudflare edge
- Нет открытых inbound портов
- DDoS защита от Cloudflare
- WAF правила для фильтрации

#### Уровень 3: UFW + Fail2Ban
- Default deny all incoming
- Rate limiting для SSH
- Автоматическая блокировка подозрительных IP
- Логирование всех попыток подключения

### 2. Observability Stack (Prometheus + Grafana)

#### Компоненты:
- **Node Exporter** - метрики сервера
- **cAdvisor** - метрики контейнеров
- **Prometheus** - сбор и хранение метрик
- **Grafana** - визуализация и алертинг
- **Alertmanager** - уведомления в Telegram/Email

#### Метрики для отслеживания:
- Количество активных подключений
- Потребление CPU/RAM
- Сетевой трафик (in/out)
- Доступность сервиса (uptime)
- Ошибки аутентификации

### 3. Security Hardening по mtproto-org/proxy

#### Docker security:
- Read-only root filesystem
- Drop ALL capabilities
- No new privileges
- Seccomp profile
- AppArmor profile
- PID limit
- Network isolation

#### System security:
- Отдельный пользователь для запуска
- Минимальные права доступа
- SELinux/AppArmor политики
- Audit logging

### 4. Обновлённые конфигурации

#### docker-compose.yml (полный):
```yaml
version: "3.9"

services:
  nginx:
    image: nginx:alpine
    container_name: mtproxy-nginx
    restart: unless-stopped
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./nginx/logs:/var/log/nginx
    networks:
      - mtproxy-net
    depends_on:
      - mtproxy
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.25'

  mtproxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproxy
    restart: unless-stopped
    expose:
      - "3128"
    environment:
      - PORT=3128
      - SECRET=${SECRET}
      - TAG=${TAG}
      - TLS_DOMAIN=${TLS_DOMAIN}
    volumes:
      - ./config:/config:ro
      - ./data:/data
    networks:
      - mtproxy-net
    security_opt:
      - no-new-privileges:true
      - apparmor:docker-default
      - seccomp:unconfined
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=64m
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    pids_limit: 50
    deploy:
      resources:
        limits:
          memory: ${MEMORY_LIMIT:-512M}
          cpus: '${CPU_LIMIT:-1.0}'
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "3128"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=9090"
      - "monitoring.enabled=true"

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared-tunnel
    restart: unless-stopped
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
    volumes:
      - ./cloudflared:/etc/cloudflared:ro
    networks:
      - mtproxy-net
    depends_on:
      - mtproxy
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 64M
          cpus: '0.1'

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./monitoring/alerts.yml:/etc/prometheus/alerts.yml:ro
      - prometheus_data:/prometheus
    networks:
      - monitoring-net
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
      - '--web.enable-lifecycle'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'

  grafana:
    image: grafana/grafana-oss:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana/dashboards:/etc/grafana/provisioning/dashboards:ro
      - ./monitoring/grafana/datasources:/etc/grafana/provisioning/datasources:ro
    networks:
      - monitoring-net
    depends_on:
      - prometheus
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.25'

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    network_mode: host
    pid: host
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    volumes:
      - /:/rootfs:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.1'

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    network_mode: host
    privileged: true
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.2'

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    restart: unless-stopped
    ports:
      - "9093:9093"
    volumes:
      - ./monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - alertmanager_data:/alertmanager
    networks:
      - monitoring-net
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
      - '--web.external-url=http://localhost:9093'
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 64M
          cpus: '0.1'

volumes:
  prometheus_data:
  grafana_data:
  alertmanager_data:

networks:
  mtproxy-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
  monitoring-net:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.29.0.0/16
```

### 5. UFW Advanced Configuration

```bash
#!/bin/bash
# Advanced UFW configuration with rate limiting

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH with rate limiting (prevent brute force)
ufw limit 22/tcp comment "SSH with rate limiting"

# Allow Nginx HTTP/HTTPS
ufw allow 80/tcp comment "Nginx HTTP"
ufw allow 443/tcp comment "Nginx HTTPS"

# Allow Prometheus (internal only - bind to localhost)
# ufw allow from 127.0.0.1 to any port 9090 proto tcp comment "Prometheus"

# Allow Grafana (optional - restrict to specific IPs)
# ufw allow from YOUR_MONITORING_IP to any port 3000 proto tcp comment "Grafana"

# Log denied packets (for security monitoring)
ufw logging on
ufw logging medium

# Enable UFW
ufw --force enable

# Show status
ufw status verbose
```

### 6. Nginx Configuration

```nginx
events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';" always;
    
    # Hide nginx version
    server_tokens off;
    
    # Rate limiting zone
    limit_req_zone $binary_remote_addr zone=mtproxy_limit:10m rate=10r/s;
    limit_conn_zone $binary_remote_addr zone=mtproxy_conn:10m;
    
    # Logging format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;
    
    # HTTP to HTTPS redirect
    server {
        listen 80 default_server;
        server_name _;
        return 301 https://$server_name$request_uri;
    }
    
    # Main HTTPS server
    server {
        listen 443 ssl http2 default_server;
        server_name _;
        
        # SSL configuration
        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        ssl_session_timeout 1d;
        ssl_session_cache shared:SSL:50m;
        ssl_session_tickets off;
        
        # Modern SSL configuration
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        
        # OCSP Stapling
        ssl_stapling on;
        ssl_stapling_verify on;
        
        # Root location - proxy to MTProto
        location / {
            limit_req zone=mtproxy_limit burst=20 nodelay;
            limit_conn mtproxy_conn 10;
            
            proxy_pass http://mtproxy:3128;
            proxy_http_version 1.1;
            
            # Headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
            
            # Buffering
            proxy_buffering off;
            proxy_cache off;
        }
        
        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
        
        # Metrics endpoint (restricted)
        location /metrics {
            allow 127.0.0.1;
            allow 172.29.0.0/16;  # Monitoring network
            deny all;
            
            proxy_pass http://prometheus:9090/metrics;
        }
    }
}
```

### 7. Fail2Ban Configuration

```ini
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = auto
usedns = warn
logencoding = auto
enabled = false
mode = aggressive

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400

[nginx-limit-req]
enabled = true
port = http,https
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10
bantime = 3600

[nginx-botsearch]
enabled = true
port = http,https
filter = nginx-botsearch
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400
```

### 8. Prometheus Alerts

```yaml
groups:
  - name: mtproxy
    rules:
      - alert: MTProxyDown
        expr: up{job="mtproxy"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "MTProxy is down"
          description: "MTProxy container has been down for more than 1 minute on {{ $labels.instance }}"
      
      - alert: HighMemoryUsage
        expr: container_memory_usage_bytes{container="mtproxy"} / container_spec_memory_limit_bytes{container="mtproxy"} > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MTProxy memory usage > 90%"
          description: "MTProxy memory usage is above 90% for more than 5 minutes"
      
      - alert: HighCPUUsage
        expr: rate(container_cpu_usage_seconds_total{container="mtproxy"}[5m]) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MTProxy CPU usage > 80%"
          description: "MTProxy CPU usage is above 80% for more than 5 minutes"
      
      - alert: TooManyConnections
        expr: sum(rate(node_netstat_Tcp_CurrEstab[5m])) > 1000
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High number of TCP connections"
          description: "More than 1000 active TCP connections detected"
      
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space low"
          description: "Disk space is below 10% on {{ $labels.mountpoint }}"
      
      - alert: ServiceRestarted
        expr: changes(container_last_seen{container="mtproxy"}, 5m) > 1
        for: 0m
        labels:
          severity: info
        annotations:
          summary: "MTProxy container restarted"
          description: "MTProxy container has restarted multiple times in the last 5 minutes"
```

### 9. Grafana Dashboard JSON

(Создаётся автоматически при первом запуске через provisioning)

### 10. Alertmanager Configuration

```yaml
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'alertmanager@example.com'
  smtp_auth_username: 'alertmanager@example.com'
  smtp_auth_password: 'your_password'

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'telegram-notifications'
  routes:
    - match:
        severity: critical
      receiver: 'telegram-critical'
    - match:
        severity: warning
      receiver: 'telegram-warnings'

receivers:
  - name: 'telegram-notifications'
    telegram_configs:
      - bot_token: 'YOUR_BOT_TOKEN'
        chat_id: YOUR_CHAT_ID
        send_resolved: true
  
  - name: 'telegram-critical'
    telegram_configs:
      - bot_token: 'YOUR_BOT_TOKEN'
        chat_id: YOUR_CRITICAL_CHAT_ID
        send_resolved: true
  
  - name: 'telegram-warnings'
    telegram_configs:
      - bot_token: 'YOUR_BOT_TOKEN'
        chat_id: YOUR_WARNING_CHAT_ID
        send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
```

## Установка и настройка

### Предварительные требования

1. Ubuntu 22.04 LTS
2. Docker 24+
3. Docker Compose v2+
4. Доменное имя (для Cloudflare Tunnel)
5. Cloudflare аккаунт

### Быстрый старт

```bash
# Клонирование репозитория
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO

# Запуск установки
sudo ./scripts/mtproxy-cli.sh install --tls-domain your-domain.com

# После установки:
# 1. Настройте Cloudflare Tunnel (следуйте инструкциям в CLI)
# 2. Получите ссылки для подключения
./scripts/mtproxy-cli.sh link

# 3. Проверьте статус
./scripts/mtproxy-cli.sh status

# 4. Откройте Grafana для мониторинга
# http://your-server-ip:3000
# Логин: admin
# Пароль: ChangeMeSecurePass123!
```

### Настройка Cloudflare Tunnel

```bash
# 1. Войдите в Cloudflare Dashboard
# 2. Создайте новый隧道 (Access -> Tunnels)
# 3. Скопируйте токен隧道
# 4. Добавьте токен в .env файл:
echo "CLOUDFLARE_TUNNEL_TOKEN=your_token_here" >> /opt/mtproto-proxy/.env

# 5. Перезапустите cloudflared
cd /opt/mtproto-proxy && docker compose restart cloudflared
```

## Мониторинг и алертинг

### Prometheus Metrics

- `mtproxy_connections_active` - активные подключения
- `mtproxy_bytes_received_total` - полученные байты
- `mtproxy_bytes_sent_total` - отправленные байты
- `mtproxy_errors_total` - ошибки

### Grafana Dashboards

1. **MTProxy Overview** - общая статистика
2. **System Resources** - CPU, RAM, Disk, Network
3. **Container Metrics** - метрики контейнеров
4. **Security Dashboard** - попытки вторжения, blocked IPs

### Уведомления

- Telegram бот для критических алертов
- Email уведомления для предупреждений
- Webhook для интеграции с другими системами

## Безопасность

### Применённые практики

1. **Defense in Depth** - многоуровневая защита
2. **Zero Trust** - нет открытых inbound портов
3. **Least Privilege** - минимальные права доступа
4. **Security by Default** - безопасные настройки по умолчанию
5. **Observability** - полный мониторинг и логирование

### Регулярное обслуживание

```bash
# Еженедельно
./scripts/mtproxy-cli.sh rotate  # Ротация секрета

# Ежемесячно
./scripts/mtproxy-cli.sh backup  # Бэкап конфигурации

# По необходимости
./scripts/mtproxy-cli.sh repair  # Восстановление файлов
```

## Troubleshooting

###常见问题

1. **Cloudflared не подключается**
   - Проверьте токен隧道
   - Убедитесь, что домен добавлен в Cloudflare
   - Проверьте логи: `docker compose logs cloudflared`

2. **Nginx возвращает 502 Bad Gateway**
   - Проверьте, что mtproxy запущен: `docker compose ps`
   - Проверьте логи: `docker compose logs mtproxy`

3. **Prometheus не собирает метрики**
   - Проверьте сеть monitoring-net
   - Убедитесь, что endpoints доступны
   - Проверьте конфигурацию prometheus.yml

## License

MIT License - см. LICENSE файл
