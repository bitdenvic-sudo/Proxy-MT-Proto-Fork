# 📘 User Guide: MTProto Proxy Deployment

**Версия 2.0** — Подробное руководство администратора по развёртыванию, настройке и обслуживанию MTProto прокси на Ubuntu 22.04.

## 📋 Оглавление

1. [Архитектура](#архитектура)
2. [Требования](#требования)
3. [Автоматическая установка (CLI)](#автоматическая-установка-cli)
4. [Ручная установка (Step-by-Step)](#ручная-установка)
   - [Подготовка ОС](#подготовка-ос)
   - [Установка Docker](#установка-docker)
   - [Конфигурация и секреты](#конфигурация-и-секреты)
   - [Запуск](#запуск)
5. [Управление через CLI](#управление-через-cli)
6. [Безопасность (Hardening)](#безопасность)
7. [Мониторинг и логирование](#мониторинг-и-логирование)
8. [Устранение неполадок](#устранение-неполадок)

---

## 🏗 Архитектура

Решение базируется на официальном образе `telegrammessenger/proxy` с модульной архитектурой v2.0.

```text
[Telegram Client] 
       ⬇️ (Зашифрованный трафик MTProto over Fake TLS)
[Ubuntu 22.04 Server] :443
       ⬇️ (UFW Firewall)
[Docker Container] (mtproxy)
       ⬇️ (Resource Limits: авто-расчёт по RAM/CPU)
[Host System]
```

Ключевые компоненты:

- **Port 443**: Стандартный порт HTTPS. Прокси маскирует свой трафик под посещение сайта www.telegram.org
- **Docker Compose**: Оркестрация контейнера с параметрами безопасности
- **Модульная система**: 4 bash-модуля (utils.sh, firewall.sh, docker.sh, secrets.sh)
- **CLI утилита**: mtproxy-cli.sh с 12 командами управления
- **Bats тесты**: 33 модульных теста для валидации компонентов

## 🛠 Требования

| Параметр | Значение |
|----------|----------|
| **ОС** | Ubuntu 22.04 LTS (чистая установка рекомендуется) |
| **Доступ** | Root или пользователь с правами sudo |
| **Сеть** | Статический IP адрес |
| **Порты** | 22/tcp (SSH), 443/tcp (MTProxy) |
| **RAM** | Минимум 512 MB (авто-лимитирование) |
| **CPU** | Минимум 1 ядро (авто-лимитирование) |
| **Диск** | ~1 GB свободного места |

---

## 🚀 Автоматическая установка (CLI)

### Быстрый старт

Используйте CLI утилиту для автоматизированного развёртывания:

```bash
# Клонируйте репозиторий
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO

# Запустите установку
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
```

### CLI утилита выведет:
- ✅ Публичный IPv4 сервера (4 внешних источника + локальный fallback)
- ✅ Ссылку для подключения в Telegram
- ✅ QR-код для быстрого подключения
- ✅ Инструкцию по управлению

---

## 📖 Ручная установка

Если вы предпочитаете контролировать каждый этап или хотите понять процесс глубже.

### Подготовка ОС

**1. Обновление пакетов:**

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git ufw fail2ban openssl xxd jq bats
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
sudo ufw allow 443/tcp comment "MTProxy"
sudo ufw --force enable
sudo ufw status verbose
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

# Добавление репозитория
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

### Конфигурация и секреты

**1. Создание директории:**

```bash
mkdir -p /opt/mtproto-proxy/{config,data,backup}
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
PORT=443
SECRET=${SECRET}
TAG=d00df00d
TLS_DOMAIN=www.telegram.org
MEMORY_LIMIT=512M
CPU_LIMIT=1.0
EOF

chmod 600 .env
ls -la .env
```

**4. Создание docker-compose.yml:**

```yaml
version: "3.9"
services:
  mtproxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproxy
    restart: unless-stopped
    network_mode: host
    env_file: .env
    environment:
      - PORT=${PORT}
      - SECRET=${SECRET}
      - TAG=${TAG}
      - TLS_DOMAIN=${TLS_DOMAIN}
    volumes:
      - ./config:/config
      - ./data:/data
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
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "${PORT:-443}"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=9090"
```

### Запуск

```bash
docker compose up -d
docker compose ps
docker stats mtproxy
```

Для автообновления установите Watchtower:

```bash
docker run -d \
  --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --interval 86400 \
  --cleanup \
  mtproxy
```

---

## 🎛 Управление через CLI

### Основные команды

| Команда | Описание |
|---------|----------|
| `./scripts/mtproxy-cli.sh install` | Полная установка MTProxy |
| `./scripts/mtproxy-cli.sh init` | Инициализация конфигурации |
| `./scripts/mtproxy-cli.sh start` | Запуск контейнера |
| `./scripts/mtproxy-cli.sh stop` | Остановка контейнера |
| `./scripts/mtproxy-cli.sh restart` | Перезапуск контейнера |
| `./scripts/mtproxy-cli.sh status` | Показать статус и метрики |
| `./scripts/mtproxy-cli.sh link` | Получить ссылку для подключения |
| `./scripts/mtproxy-cli.sh rotate` | Ротация секрета с бэкапом |
| `./scripts/mtproxy-cli.sh logs` | Просмотр логов в реальном времени |
| `./scripts/mtproxy-cli.sh backup` | Бэкап конфигурации |
| `./scripts/mtproxy-cli.sh uninstall` | Удаление MTProxy |
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
```

---

## 🔒 Безопасность

### Применённые практики:

| # | Практика | Реализация |
|---|----------|------------|
| 1 | Ограничение ресурсов | Авто-расчёт лимитов по RAM/CPU |
| 2 | No-New-Privileges | `security_opt: no-new-privileges:true` |
| 3 | Файрвол | UFW default deny, порты 22, 443 |
| 4 | Изоляция секретов | `.env` с правами 600 |
| 5 | Маскировка в логах | `mask_secret()` показывает `abcd...ef90` |
| 6 | Логирование с ротацией | 3 файла × 10MB = 30MB максимум |
| 7 | Валидация ввода | `validate_ip()`, `validate_port()`, `validate_secret()` |
| 8 | Fallback для IP | 4 внешних источника: api.ipify.org, ifconfig.me, icanhazip.com, ident.me + `hostname -I` |

---

## 📊 Мониторинг и логирование

### Prometheus интеграция

```yaml
labels:
  - "prometheus.scrape=true"
  - "prometheus.port=9090"
```

### Просмотр логов

```bash
./scripts/mtproxy-cli.sh logs
docker logs -f mtproxy
docker logs --tail 100 mtproxy
```

### Метрики

```bash
docker stats mtproxy
docker inspect mtproxy
docker inspect --format='{{.State.Health.Status}}' mtproxy
```

---

## 🛠 Устранение неполадок

### Контейнер не запускается

```bash
docker logs mtproxy
docker compose ps
docker inspect mtproxy
```

| Проблема | Решение |
|----------|---------|
| Порт 443 занят | `sudo lsof -i :443` → остановить конфликтующий сервис |
| Недостаточно RAM | Увеличьте лимит в `.env`: `MEMORY_LIMIT=1G` |
| Ошибка секрета | Проверьте формат: 32 hex символа |

### Telegram не подключается

```bash
sudo ufw status verbose
nc -zv localhost 443
curl api.ipify.org || curl ifconfig.me/ip || curl icanhazip.com || curl ident.me
```

### Ошибка "Secret not found"

```bash
cd /opt/mtproto-proxy
ls -la .env
stat -c "%a %U %G" .env  # Должно быть: 600 root root
```

### Сервер тормозит

```bash
docker stats
# Отредактируйте .env: MEMORY_LIMIT=1G CPU_LIMIT=2.0
docker compose down
docker compose up -d
```

### Тестирование компонентов

```bash
./tests/run_tests.sh
bats tests/test_utils.bats
bats tests/test_secrets.bats
```

---

## 📜 Лицензия

MIT License. См. корневой файл [LICENSE](LICENSE).

## 🤝 Поддержка

- **Документация**: [docs/RECOMMENDATIONS.md](docs/RECOMMENDATIONS.md)
- **Issues**: GitHub Issues репозитория
- **Roadmap v3.0**: См. раздел "Рекомендации" в документации
