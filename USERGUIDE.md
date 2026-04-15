# 📘 User Guide: MTProto Proxy Deployment

**Версия 6.0** — Подробное руководство администратора по развёртыванию, настройке и обслуживанию MTProto прокси на Ubuntu 22.04 с многоуровневой защитой, Nginx reverse proxy, Cloudflare Tunnel и Observability stack.

## 📋 Оглавление

1. [Архитектура v6.0](#архитектура-v60)
2. [Требования](#требования)
3. [Автоматическая установка (CLI)](#автоматическая-установка-cli)
4. [Ручная установка (Step-by-Step)](#ручная-установка)
   - [Подготовка ОС](#подготовка-ос)
   - [Установка Docker](#установка-docker)
   - [Получение SSL сертификата по IP (acme.sh)](#получение-ssl-сертификата-по-ip-acmesh)
   - [Конфигурация и секреты](#конфигурация-и-секреты)
   - [Запуск](#запуск)
5. [Управление через CLI](#управление-через-cli)
6. [Безопасность (Hardening)](#безопасность)
7. [Мониторинг и логирование](#мониторинг-и-логирование)
8. [Устранение неполадок](#устранение-неполадок)

---

## 🏗 Архитектура v6.0

Решение базируется на официальном образе `telegrammessenger/proxy` с многоуровневой архитектурой защиты трафика.

```text
[Telegram Client] 
       ⬇️ (HTTPS/TLS через Cloudflare Edge)
[Cloudflare CDN] — DDoS защита + WAF
       ⬇️ (Cloudflare Tunnel — no inbound ports)
[Ubuntu 22.04 Server]
       ⬇️ (UFW + Fail2Ban)
[Nginx Reverse Proxy] :443 — TLS termination
       ⬇️ (Internal network)
[Docker Container] (mtproxy:3128)
       ⬇️ (Resource Limits + Security Hardening)
[Host System]
       
[Monitoring Stack]
├── Prometheus (метрики)
├── Grafana (дашборды)
└── Alertmanager (уведомления в Telegram/Email)
```

### Ключевые компоненты v6.0:

- **Cloudflare Tunnel**: Трафик идёт через зашифрованный туннель, нет открытых inbound портов
- **Nginx Reverse Proxy**: TLS termination, rate limiting, security headers
- **Port 443**: Стандартный порт HTTPS с Fake TLS маскировкой
- **Docker Compose**: Multi-service оркестрация (nginx, mtproxy, cloudflared, monitoring)
- **Security Hardening**: Read-only filesystem, drop capabilities, seccomp, apparmor
- **Observability**: Prometheus + Grafana + Alertmanager для полного контроля
- **Модульная система**: 6 bash-модулей (utils.sh, firewall_advanced.sh, docker.sh, docker_security.sh, secrets.sh, monitoring.sh)
- **CLI утилита**: mtproxy-cli.sh с 15+ командами управления
- **Bats тесты**: 40+ модульных теста для валидации компонентов

## 🔐 Получение SSL сертификата по IP (acme.sh)

### Зачем нужен SSL по IP?

Если у вас нет доменного имени, вы можете получить бесплатный SSL сертификат на свой IP адрес используя [acme.sh](https://github.com/acmesh-official/acme.sh). Это позволяет:
- Использовать HTTPS без покупки домена
- Избежать предупреждений браузера о небезопасном соединении
- Соответствовать современным требованиям безопасности

### Поддерживаемые CA для IP сертификатов:

| Certificate Authority | Поддержка IP | Требования |
|----------------------|--------------|------------|
| **ZeroSSL** | ✅ Да | Email верификация |
| **Let's Encrypt** | ❌ Нет | Только домены |
| **BuyPass** | ✅ Да | Email верификация |
| **Google Trust Services** | ✅ Да | DNS верификация |

### Установка acme.sh

```bash
# Установка acme.sh
curl https://get.acme.sh | sh

# Или через git
git clone https://github.com/acmesh-official/acme.sh.git
cd acme.sh
./acme.sh --install

# Добавить в PATH (если не добавлено автоматически)
echo 'alias acme.sh=~/.acme.sh/acme.sh' >> ~/.bashrc
source ~/.bashrc
```

### Получение сертификата на IP адрес

#### Вариант 1: ZeroSSL (рекомендуется)

```bash
# Регистрация аккаунта ZeroSSL (бесплатно)
acme.sh --register-account -m your-email@example.com

# Получение сертификата на IPv4
PUBLIC_IP="YOUR_SERVER_IP"
acme.sh --issue --ip "$PUBLIC_IP" \
    --standalone \
    --ca zero_ssl \
    --keylength ec-256 \
    --days 90

# Сертификаты сохранятся в:
# ~/.acme.sh/YOUR_IP_ecc/
```

#### Вариант 2: BuyPass

```bash
acme.sh --issue --ip "$PUBLIC_IP" \
    --standalone \
    --ca buypass \
    --keylength ec-256 \
    --days 180
```

#### Вариант 3: Google Trust Services (требуется DNS)

```bash
# Требуется настроить DNS TXT запись
export GOOGLE_Application_Credentials="/path/to/google-creds.json"

acme.sh --issue --ip "$PUBLIC_IP" \
    --dns dns_google \
    --ca google \
    --keylength ec-256
```

### Установка сертификата в Nginx

```bash
# Копирование сертификатов
CERT_DIR="/etc/ssl/mtproxy"
mkdir -p "$CERT_DIR"

IP_WITHOUT_DOTS="${PUBLIC_IP//./_}"
acme.sh --install-cert --ip "$PUBLIC_IP" \
    --ecc \
    --cert-file "${CERT_DIR}/fullchain.pem" \
    --key-file "${CERT_DIR}/privkey.pem" \
    --ca-file "${CERT_DIR}/ca.pem" \
    --reloadcmd "systemctl reload nginx"

# Проверка прав доступа
chmod 600 ${CERT_DIR}/privkey.pem
chmod 644 ${CERT_DIR}/fullchain.pem ${CERT_DIR}/ca.pem
chown -R root:root "$CERT_DIR"
```

### Автоматическое обновление сертификата

acme.sh автоматически создаёт cron job для обновления. Проверьте:

```bash
# Просмотр установленных cron задач
crontab -l | grep acme

# Принудительное перевыпуск
acme.sh --renew --ip "$PUBLIC_IP" --ecc --force

# Тестирование обновления
acme.sh --cron --home ~/.acme.sh
```

### Интеграция с mtproxy-cli.sh

```bash
# Установка с автоматическим получением SSL по IP
sudo ./scripts/mtproxy-cli.sh install \
    --ssl-provider zerossl \
    --ssl-email admin@example.com \
    --auto-acme

# Проверка статуса сертификата
./scripts/mtproxy-cli.sh ssl-status

# Перевыпуск сертификата
sudo ./scripts/mtproxy-cli.sh ssl-renew
```

### Структура файлов сертификатов

```
/etc/ssl/mtproxy/
├── fullchain.pem    # Полный цепочек сертификатов
├── privkey.pem      # Приватный ключ (600 permissions)
└── ca.pem           # CA сертификат
```

### Troubleshooting

**Ошибка: "Verification failed"**
```bash
# Проверьте что порт 80 открыт для верификации
sudo ufw allow 80/tcp comment "ACME verification"

# После получения сертификата можно закрыть
sudo ufw delete allow 80/tcp
```

**Ошибка: "Rate limit exceeded"**
```bash
# ZeroSSL позволяет 5 сертификатов в неделю на email
# Используйте другой email или подождите
```

**Проверка срока действия**
```bash
openssl x509 -in /etc/ssl/mtproxy/fullchain.pem -noout -dates
```

---

## 🛠 Требования

| Параметр | Значение |
|----------|----------|
| **ОС** | Ubuntu 22.04 LTS (чистая установка рекомендуется) |
| **Доступ** | Root или пользователь с правами sudo |
| **Сеть** | Статический IP адрес (IPv4 или IPv6) |
| **Порты** | 22/tcp (SSH), 80/tcp (ACME verification), 443/tcp (Nginx/MTProxy) |
| **RAM** | Минимум 1 GB (рекомендуется 2 GB для monitoring stack) |
| **CPU** | Минимум 1 ядро (рекомендуется 2 ядра) |
| **Диск** | ~2 GB свободного места (с учётом monitoring stack) |
| **Домен** | Опционально (поддержка SSL по IP через acme.sh) |

### Дополнительные требования для v6.0:

- **Cloudflare Account**: Бесплатный аккаунт для использования Cloudflare Tunnel
- **Docker Compose**: Версия 2.0+ для multi-service deployment
- **acme.sh**: Для получения SSL сертификатов по IP (опционально)

---

## 🚀 Автоматическая установка (CLI)

### Быстрый старт

Используйте CLI утилиту для автоматизированного развёртывания:

```bash
# Клонируйте репозиторий
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO

# Запустите установку с Cloudflare Tunnel и monitoring
sudo ./scripts/mtproxy-cli.sh install \
    --tunnel-mode cloudflare \
    --enable-monitoring \
    --ssl-provider zerossl \
    --ssl-email admin@example.com

# Или минимальная установка
sudo ./scripts/mtproxy-cli.sh install
```

### Режим Dry Run (предпросмотр)

Перед установкой можно просмотреть все действия без внесения изменений:

```bash
sudo ./scripts/mtproxy-cli.sh --dry-run install
```

### Установка с параметрами

```bash
# С кастомным портом
sudo ./scripts/mtproxy-cli.sh install --port 8443

# С кастомным секретом (32 hex символа)
sudo ./scripts/mtproxy-cli.sh install --secret abcdef0123456789abcdef0123456789

# С предопределёнными лимитами ресурсов
sudo ./scripts/mtproxy-cli.sh install --memory-limit 1G --cpu-limit 2.0

# С автоматическим получением SSL по IP
sudo ./scripts/mtproxy-cli.sh install \
    --auto-acme \
    --ssl-email admin@example.com

# С доменом для FakeTLS
sudo ./scripts/mtproxy-cli.sh install --tls-domain assets.example.com

# Только MTProxy без monitoring
sudo ./scripts/mtproxy-cli.sh install --no-monitoring

# Legacy mode (без Cloudflare Tunnel, открывает inbound порт)
sudo ./scripts/mtproxy-cli.sh install --legacy-edge
```

### CLI утилита выведет:
- ✅ Публичный IPv4 сервера (4 внешних источника + локальный fallback)
- ✅ Ссылку для подключения в Telegram
- ✅ QR-код для быстрого подключения
- ✅ URL Grafana дашборда
- ✅ Инструкцию по управлению
- ✅ Статус SSL сертификата (если используется acme.sh)

---

## 📖 Ручная установка

Если вы предпочитаете контролировать каждый этап или хотите понять процесс глубже.

### Подготовка ОС

**1. Обновление пакетов:**

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git ufw fail2ban openssl xxd jq bats nginx
```

**2. Настройка пользователя (Best Practice):**

Не работайте под root постоянно.

```bash
sudo adduser --disabled-password --gecos "" proxyadmin
sudo usermod -aG sudo proxyadmin
```

**3. Настройка файрвола (UFW):**

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment "SSH"
sudo ufw allow 80/tcp comment "ACME verification"
sudo ufw allow 443/tcp comment "Nginx/MTProxy"
sudo ufw --force enable
sudo ufw status verbose
```

**4. Установка Fail2Ban:**

```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
sudo cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3
EOF
sudo systemctl restart fail2ban
```

### Установка Docker

Устанавливаем официальную версию Docker Engine (избегаем snap-пакетов):

```bash
# Удаление старых версий
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
    sudo apt-get remove -y $pkg
done

# Добавление ключа GPG
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Добавление репозитория (deb822 format)
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

# Добавление пользователя в группу docker
sudo usermod -aG docker $USER
newgrp docker

# Проверка установки
docker --version
docker compose version
```

### Получение SSL сертификата по IP (acme.sh)

Этот шаг опционален, если у вас уже есть SSL сертификат или домен.

```bash
# Установка acme.sh
curl https://get.acme.sh | sh
source ~/.bashrc

# Регистрация на ZeroSSL
acme.sh --register-account -m your-email@example.com

# Получение сертификата на IP
PUBLIC_IP="YOUR_SERVER_IP"
acme.sh --issue --ip "$PUBLIC_IP" \
    --standalone \
    --ca zero_ssl \
    --keylength ec-256

# Установка сертификата
CERT_DIR="/etc/ssl/mtproxy"
sudo mkdir -p "$CERT_DIR"

acme.sh --install-cert --ip "$PUBLIC_IP" \
    --ecc \
    --cert-file "${CERT_DIR}/fullchain.pem" \
    --key-file "${CERT_DIR}/privkey.pem" \
    --ca-file "${CERT_DIR}/ca.pem"

# Права доступа
sudo chmod 600 ${CERT_DIR}/privkey.pem
sudo chmod 644 ${CERT_DIR}/fullchain.pem ${CERT_DIR}/ca.pem
sudo chown -R root:root "$CERT_DIR"
```

### Конфигурация и секреты

**1. Создание директории:**

```bash
mkdir -p /opt/mtproto-proxy/{config,data,backup,certs}
cd /opt/mtproto-proxy
```

**2. Генерация секрета:**

Секрет должен быть hex-строкой (32 символа для 16 байт).

```bash
SECRET=$(head -c 16 /dev/urandom | xxd -p | tr -d '\n')
echo "Сгенерированный секрет: $SECRET"
```

**3. Создание .env файла:**

```bash
cat > .env <<EOF
PORT=3128
SECRET=${SECRET}
TAG=d00df00d
TLS_DOMAIN=www.telegram.org
MEMORY_LIMIT=512M
CPU_LIMIT=1.0
NGINX_PORT=443
CLOUDFLARE_TUNNEL=true
MONITORING_ENABLED=true
GRAFANA_PASSWORD=$(openssl rand -base64 16)
PROMETHEUS_RETENTION_DAYS=15
EOF

chmod 600 .env
ls -la .env
```

**4. Создание docker-compose.yml (v6.0 multi-service):**

```yaml
version: "3.9"

networks:
  mtproxy-net:
    driver: bridge
  monitoring-net:
    driver: bridge

services:
  # Nginx Reverse Proxy
  nginx:
    image: nginx:alpine
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/ssl/mtproxy:/etc/ssl/mtproxy:ro
      - ./nginx/logs:/var/log/nginx
    networks:
      - mtproxy-net
    depends_on:
      mtproxy:
        condition: service_healthy
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'

  # MTProxy Container
  mtproxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproxy
    restart: unless-stopped
    expose:
      - "3128"
    env_file: .env
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
    deploy:
      resources:
        limits:
          memory: ${MEMORY_LIMIT:-512M}
          cpus: '${CPU_LIMIT:-1.0}'
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=64m
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    pids_limit: 50
    healthcheck:
      test: ["CMD-SHELL", "bash -ec 'exec 3<>/dev/tcp/127.0.0.1/3128'"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=9090"
      - "service=mtproxy"

  # Cloudflare Tunnel (optional)
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared-tunnel
    restart: unless-stopped
    command: tunnel run
    volumes:
      - ./cloudflared:/etc/cloudflared:ro
    networks:
      - mtproxy-net
    depends_on:
      - nginx
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.25'
    profiles:
      - cloudflare

  # Prometheus
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
      - '--storage.tsdb.retention.time=${PROMETHEUS_RETENTION_DAYS:-15}d'
      - '--web.enable-lifecycle'
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
    profiles:
      - monitoring

  # Grafana
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/dashboards:/etc/grafana/provisioning/dashboards:ro
      - ./monitoring/datasources:/etc/grafana/provisioning/datasources:ro
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
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
    profiles:
      - monitoring

  # Alertmanager
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
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.25'
    profiles:
      - monitoring

  # Node Exporter
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - monitoring-net
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.25'
    profiles:
      - monitoring

  # cAdvisor
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    networks:
      - monitoring-net
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'
    profiles:
      - monitoring

volumes:
  prometheus_data:
  grafana_data:
  alertmanager_data:
```

### Запуск

```bash
# Запуск MTProxy + Nginx
docker compose up -d nginx mtproxy

# Запуск с Cloudflare Tunnel
docker compose --profile cloudflare up -d

# Запуск полного стека (включая monitoring)
docker compose --profile monitoring --profile cloudflare up -d

# Проверка статуса
docker compose ps
docker stats

# Проверка логов
docker compose logs -f nginx
docker compose logs -f mtproxy
```

Для автообновления установите Watchtower:

```bash
docker run -d \
  --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --interval 86400 \
  --cleanup \
  --label-enable
```

---

## 🎛 Управление через CLI

### Основные команды

| Команда | Описание |
|---------|----------|
| `./scripts/mtproxy-cli.sh install` | Полная установка MTProxy v6.0 |
| `./scripts/mtproxy-cli.sh init` | Инициализация конфигурации |
| `./scripts/mtproxy-cli.sh start` | Запуск контейнеров |
| `./scripts/mtproxy-cli.sh stop` | Остановка контейнеров |
| `./scripts/mtproxy-cli.sh restart` | Перезапуск контейнеров |
| `./scripts/mtproxy-cli.sh status` | Показать статус и метрики |
| `./scripts/mtproxy-cli.sh link` | Получить ссылку для подключения |
| `./scripts/mtproxy-cli.sh rotate` | Ротация секрета с бэкапом |
| `./scripts/mtproxy-cli.sh logs` | Просмотр логов в реальном времени |
| `./scripts/mtproxy-cli.sh repair` | Восстановление runtime-файлов |
| `./scripts/mtproxy-cli.sh backup` | Бэкап конфигурации |
| `./scripts/mtproxy-cli.sh uninstall` | Удаление MTProxy |
| `./scripts/mtproxy-cli.sh ssl-status` | Проверка статуса SSL сертификата |
| `./scripts/mtproxy-cli.sh ssl-renew` | Перевыпуск SSL сертификата |
| `./scripts/mtproxy-cli.sh monitoring-status` | Статус monitoring stack |
| `./scripts/mtproxy-cli.sh --dry-run install` | Предпросмотр установки |

### Примеры использования

```bash
# Получить ссылку для подключения
./scripts/mtproxy-cli.sh link

# Ротация секрета (автоматически создаёт бэкап)
sudo ./scripts/mtproxy-cli.sh rotate

# Просмотр логов
./scripts/mtproxy-cli.sh logs

# Бэкап конфигурации
./scripts/mtproxy-cli.sh backup

# Проверка статуса SSL
./scripts/mtproxy-cli.sh ssl-status

# Перевыпуск SSL
sudo ./scripts/mtproxy-cli.sh ssl-renew

# Статус мониторинга
./scripts/mtproxy-cli.sh monitoring-status

# Безопасное восстановление после ручных правок
sudo ./scripts/mtproxy-cli.sh repair
```

---

## 🔒 Безопасность

### Применённые практики v6.0:

| # | Практика | Реализация |
|---|----------|------------|
| 1 | **Defense in Depth** | Cloudflare → Nginx → MTProxy → Firewall |
| 2 | **Read-only filesystem** | `read_only: true` + tmpfs для /tmp |
| 3 | **Drop capabilities** | `cap_drop: ALL` + `cap_add: NET_BIND_SERVICE` |
| 4 | **PID limit** | `pids_limit: 50` предотвращает fork bombs |
| 5 | **Resource limits** | CPU/RAM limits для каждого сервиса |
| 6 | **No-New-Privileges** | `security_opt: no-new-privileges:true` |
| 7 | **Network isolation** | Изолированные сети (mtproxy-net, monitoring-net) |
| 8 | **UFW + Fail2Ban** | Default deny + rate limiting + auto-ban |
| 9 | **Изоляция секретов** | `.env` с правами 600, secrets в volumes :ro |
| 10 | **Маскировка в логах** | `mask_secret()` показывает `abcd...ef90` |
| 11 | **Логирование с ротацией** | 3 файла × 10MB = 30MB максимум |
| 12 | **Валидация ввода** | `validate_ip()`, `validate_port()`, `validate_secret()` |
| 13 | **IP Fallback** | 4 внешних источника + локальный fallback |
| 14 | **Seccomp/AppArmor** | Опциональные профили безопасности |
| 15 | **TLS 1.3** | Modern cipher suites в Nginx |

### Security Hardening скрипты:

```bash
# Генерация seccomp профиля
./src/docker_security.sh generate-seccomp

# Генерация AppArmor профиля
./src/docker_security.sh generate-apparmor

# Аудит безопасности
./src/docker_security.sh security-audit

# Настройка расширенного firewall
sudo ./src/firewall_advanced.sh setup

# Включение Fail2Ban jail для MTProxy
sudo ./src/firewall_advanced.sh enable-jail mtproxy
```

---

## 📊 Мониторинг и логирование

### Компоненты Observability Stack

| Компонент | Порт | Назначение |
|-----------|------|------------|
| **Prometheus** | 9090 | Сбор и хранение метрик (15 дней) |
| **Grafana** | 3000 | Визуализация и дашборды |
| **Alertmanager** | 9093 | Маршрутизация алертов |
| **Node Exporter** | 9100 | Метрики сервера (CPU, RAM, Disk) |
| **cAdvisor** | 8080 | Метрики контейнеров Docker |

### Prometheus интеграция

Конфигурация в `./monitoring/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - '/etc/prometheus/alerts.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'mtproxy'
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
        filters:
          - name: label
            values: ['prometheus.scrape=true']
    relabel_configs:
      - source_labels: [__meta_docker_container_name]
        target_label: container

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
```

### Alert Rules

Файл `./monitoring/alerts.yml`:

```yaml
groups:
  - name: mtproxy-alerts
    rules:
      - alert: MTProxyDown
        expr: up{service="mtproxy"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "MTProxy сервис недоступен"
          description: "Контейнер {{ $labels.container }} не отвечает более 1 минуты"

      - alert: HighMemoryUsage
        expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Высокое потребление памяти"
          description: "{{ $labels.container }} использует > 90% RAM"

      - alert: HighCPUUsage
        expr: rate(container_cpu_usage_seconds_total[5m]) / container_spec_cpu_quota * container_spec_cpu_period > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Высокое потребление CPU"
          description: "{{ $labels.container }} использует > 80% CPU"

      - alert: TooManyConnections
        expr: mtproxy_connections_total > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Превышено количество подключений"
          description: "Более 1000 активных подключений"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Заканчивается место на диске"
          description: "Свободно менее 10% на {{ $labels.mountpoint }}"

      - alert: ServiceRestarted
        expr: changes(container_last_seen[5m]) > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Частые перезапуски сервиса"
          description: "{{ $labels.container }} перезапускался более 2 раз за 5 минут"
```

### Alertmanager конфигурация

Файл `./monitoring/alertmanager.yml`:

```yaml
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'alertmanager@example.com'
  smtp_auth_username: 'alertmanager@example.com'
  smtp_auth_password: 'your-password'

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default-receiver'
  routes:
    - match:
        severity: critical
      receiver: 'telegram-critical'
    - match:
        severity: warning
      receiver: 'email-warnings'

receivers:
  - name: 'default-receiver'
    email_configs:
      - to: 'admin@example.com'
        send_resolved: true

  - name: 'telegram-critical'
    webhook_configs:
      - url: 'http://alertmanager-telegram-bot:5001/'
        send_resolved: true

  - name: 'email-warnings'
    email_configs:
      - to: 'warnings@example.com'
        send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
```

### Доступ к Grafana

```bash
# Получить пароль администратора
grep GRAFANA_PASSWORD /opt/mtproto-proxy/.env

# Открыть в браузере
# http://YOUR_SERVER_IP:3000
# Логин: admin
# Пароль: из .env файла
```

### Просмотр логов

```bash
./scripts/mtproxy-cli.sh logs
docker compose logs -f nginx
docker compose logs -f mtproxy
docker compose logs -f prometheus
journalctl -u fail2ban -f
```

### Метрики

```bash
# Статистика контейнеров
docker stats

# Health check статус
docker inspect --format='{{.State.Health.Status}}' mtproxy

# Prometheus API
curl http://localhost:9090/api/v1/targets
curl http://localhost:9090/api/v1/rules
```

---

## 🛠 Устранение неполадок

### Контейнер не запускается

```bash
docker compose logs mtproxy
docker compose ps
docker inspect mtproxy
```

| Проблема | Решение |
|----------|---------|
| Порт 443 занят | `sudo lsof -i :443` → остановить конфликтующий сервис (Apache, Nginx) |
| Недостаточно RAM | Увеличьте лимит в `.env`: `MEMORY_LIMIT=1G` или добавьте swap |
| Ошибка секрета | Проверьте формат: 32 hex символа (0-9, a-f) |
| Статус `unhealthy` | Проверьте что port 3128 доступен внутри сети mtproxy-net |
| Cloudflare Tunnel не подключается | Проверьте credentials file в `./cloudflared/creds.json` |
| Prometheus не видит target | Проверьте label `prometheus.scrape=true` в docker-compose |

### Telegram не подключается

```bash
sudo ufw status verbose
nc -zv localhost 3128
curl -I https://YOUR_SERVER_IP

# Проверка Nginx config
docker exec nginx-proxy nginx -t
docker exec nginx-proxy cat /var/log/nginx/error.log
```

### Ошибка "Secret not found"

```bash
cd /opt/mtproto-proxy
ls -la .env
stat -c "%a %U %G" .env  # Должно быть: 600 root root
cat .env | grep SECRET
```

### Сервер тормозит

```bash
docker stats
htop
df -h

# Отредактируйте .env: MEMORY_LIMIT=1G CPU_LIMIT=2.0
docker compose down
docker compose --profile monitoring up -d
```

### Проблемы с SSL сертификатом

```bash
# Проверка срока действия
openssl x509 -in /etc/ssl/mtproxy/fullchain.pem -noout -dates

# Принудительное перевыпуск
acme.sh --renew --ip YOUR_IP --ecc --force

# Проверка cron задачи
crontab -l | grep acme
```

### Monitoring stack не работает

```bash
# Проверка всех сервисов
docker compose --profile monitoring ps

# Логи Prometheus
docker compose logs prometheus

# Логи Grafana
docker compose logs grafana

# Проверка volumes
docker volume ls | grep -E '(prometheus|grafana|alertmanager)'
```

### Тестирование компонентов

```bash
./tests/run_tests.sh
bats tests/test_utils.bats
bats tests/test_secrets.bats
bats tests/test_security.bats
```

### Полезные команды для диагностики

```bash
# Проверка сети между контейнерами
docker network inspect mtproxy-net

# Проверка connections к MTProxy
docker exec mtproxy netstat -tuln

# Проверка потребления ресурсов
docker stats --no-stream

# Проверка логов UFW
sudo tail -f /var/log/ufw.log

# Проверка Fail2Ban
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

---

## 📜 Лицензия

MIT License. См. корневой файл [LICENSE](LICENSE).

## 🤝 Поддержка

- **Документация**: [docs/RECOMMENDATIONS.md](docs/RECOMMENDATIONS.md), [docs/ARCHITECTURE_V6.md](docs/ARCHITECTURE_V6.md)
- **Issues**: GitHub Issues репозитория
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)
