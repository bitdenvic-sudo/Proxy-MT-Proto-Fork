#!/bin/bash

################################################################################
# MTProto Proxy Auto-Installer for Ubuntu 22.04
# License: MIT
# Description: Автоматическая установка Docker, настройка UFW и развёртывание MTProxy
################################################################################

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Ошибка: Пожалуйста, запустите скрипт от имени root (sudo bash install_mtproxy.sh)${NC}"
  exit 1
fi

echo -e "${BLUE}=========================================="
echo -e "🚀 Установка MTProto Proxy (Ubuntu 22.04)"
echo -e "==========================================${NC}"

# 1. Обновление системы
echo -e "${YELLOW}📦 [1/6] Обновление пакетов системы...${NC}"
apt update && apt upgrade -y
apt install -y curl wget git ufw fail2ban openssl xxd jq apache2-utils

# 2. Настройка пользователя (опционально)
echo -e "${YELLOW}👤 [2/6] Настройка пользователя...${NC}"
if id "proxyadmin" &>/dev/null; then
    echo -e "${GREEN}ℹ️ Пользователь 'proxyadmin' уже существует.${NC}"
else
    read -p "Создать непривилегированного пользователя 'proxyadmin'? (y/n): " create_user
    if [[ "$create_user" =~ ^[Yy]$ ]]; then
        adduser --disabled-password --gecos "" proxyadmin
        usermod -aG sudo proxyadmin
        echo "proxyadmin ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/proxyadmin > /dev/null
        echo -e "${GREEN}✅ Пользователь 'proxyadmin' создан.${NC}"
    else
        echo -e "⏭️ Пропущено создание пользователя."
    fi
fi

# 3. Настройка файрвола
echo -e "${YELLOW}🔥 [3/6] Настройка UFW...${NC}"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment "SSH Access"
ufw allow 443/tcp comment "MTProto Proxy"

echo "y" | ufw enable
ufw status verbose
echo -e "${GREEN}✅ Файрвол настроен.${NC}"

# 4. Установка Docker
echo -e "${YELLOW}🐳 [4/6] Установка Docker Engine...${NC}"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
    apt-get remove -y $pkg 2>/dev/null || true
done

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

RUN_USER=${SUDO_USER:-$USER}
usermod -aG docker $RUN_USER
echo -e "${GREEN}✅ Docker установлен.${NC}"

# 5. Создание конфигурации
echo -e "${YELLOW}⚙️ [5/6] Генерация конфигурации и секретов...${NC}"
INSTALL_DIR="/opt/mtproto-proxy"
mkdir -p ${INSTALL_DIR}/{config,data}
cd ${INSTALL_DIR}

SECRET=$(head -c 16 /dev/urandom | xxd -p | tr -d '\n')

cat > .env <<EOF
PORT=443
SECRET=${SECRET}
TAG=d00df00d
TLS_DOMAIN=ok.ru
EOF
chmod 600 .env
chown -R $RUN_USER:$RUN_USER ${INSTALL_DIR}

cat > docker-compose.yml <<'EOF'
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
      - .//data
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '1.0'
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
EOF

cat > manage.sh <<'MANAGE_SCRIPT'
#!/bin/bash
ENV_FILE=".env"
COMPOSE_CMD="docker compose"

generate_secret() { head -c 16 /dev/urandom | xxd -p | tr -d '\n'; }
get_secret() { grep "^SECRET=" "$ENV_FILE" | cut -d'=' -f2; }
get_port() { grep "^PORT=" "$ENV_FILE" | cut -d'=' -f2; }

get_link() {
    local secret=$(get_secret)
    local port=$(get_port)
    local ip=$(curl -s ifconfig.me)
    if [ -z "$secret" ]; then 
        echo -e "\033[0;31mОшибка: Секрет не найден в .env\033[0m"
        exit 1
    fi
    echo -e "\n\033[0;32mСсылка для подключения:\033[0m"
    echo "tg://proxy?server=${ip}&port=${port}&secret=${secret}"
    echo "https://t.me/proxy?server=${ip}&port=${port}&secret=${secret}"
}

case "$1" in
    init)
        if [ -z "$(get_secret)" ]; then
            echo "Генерация нового секрета..."
            NEW_SECRET=$(generate_secret)
            sed -i "s/^SECRET=.*/SECRET=${NEW_SECRET}/" "$ENV_FILE"
            $COMPOSE_CMD up -d
            echo -e "\033[0;32m✅ Инициализировано и запущено.\033[0m"
        else
            echo -e "\033[1;33mℹ️ Конфигурация уже существует.\033[0m"
            $COMPOSE_CMD up -d
        fi
        ;;
    link) get_link ;;
    rotate)
        echo "🔄 Ротация секрета..."
        NEW_SECRET=$(generate_secret)
        sed -i "s/^SECRET=.*/SECRET=${NEW_SECRET}/" "$ENV_FILE"
        $COMPOSE_CMD restart mtproxy
        echo -e "\033[0;32m✅ Секрет обновлен.\033[0m"
        $0 link
        ;;
    logs) $COMPOSE_CMD logs -f mtproxy ;;
    stop) $COMPOSE_CMD down ;;
    start) $COMPOSE_CMD up -d ;;
    *) 
        echo "Использование: $0 {init|link|rotate|logs|start|stop}"
        exit 1
        ;;
esac
MANAGE_SCRIPT

chmod +x manage.sh
chown $RUN_USER:$RUN_USER manage.sh

echo -e "${GREEN}✅ Конфигурация создана в ${INSTALL_DIR}${NC}"

# 6. Запуск сервисов
echo -e "${YELLOW}🚀 [6/6] Запуск контейнеров...${NC}"
docker compose up -d

echo -e "${YELLOW}⏱️ Установка Watchtower для автообновления...${NC}"
docker run -d \
  --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --interval 86400 \
  --cleanup \
  mtproxy

# Финальный вывод
IP_ADDR=$(curl -s ifconfig.me)
CURRENT_SECRET=$(grep "^SECRET=" .env | cut -d'=' -f2)

clear
echo -e "${GREEN}=========================================="
echo -e "✅ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!"
echo -e "==========================================${NC}"
echo -e "📍 Директория: ${YELLOW}${INSTALL_DIR}${NC}"
echo -e "🌍 IP адрес: ${BLUE}${IP_ADDR}${NC}"
echo -e "🔌 Порт: ${BLUE}443${NC}"
echo -e "🔑 Секрет: ${YELLOW}${CURRENT_SECRET}${NC}"
echo -e "\n📲 ${GREEN}Ссылка для подключения:${NC}"
echo -e "tg://proxy?server=${IP_ADDR}&port=443&secret=${CURRENT_SECRET}"
echo -e "https://t.me/proxy?server=${IP_ADDR}&port=443&secret=${CURRENT_SECRET}"
echo -e "\n🛠 ${GREEN}Управление:${NC}"
echo -e "  cd ${INSTALL_DIR} && ./manage.sh <command>"
echo -e "${GREEN}==========================================${NC}"
