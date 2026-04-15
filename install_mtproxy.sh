#!/bin/bash
################################################################################
# MTProto Proxy Auto-Installer for Ubuntu 22.04
# License: MIT
# Description: Автоматическая установка Docker, настройка UFW и развёртывание MTProxy
# Deprecated: Используйте scripts/mtproxy-cli.sh для новой модульной установки
################################################################################

set -euo pipefail

# Colors for output (unified with utils.sh)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function (consistent with utils.sh)
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${BLUE}[$timestamp] [INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[$timestamp] [ERROR]${NC} $message" ;;
    esac
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log "ERROR" "Please run as root (sudo bash $0)"
        exit 1
    fi
}

# Validate IP address format (optimized regex)
validate_ip() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    [[ ! $ip =~ $regex ]] && return 1
    
    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        ((octet < 0 || octet > 255)) && return 1
    done
    return 0
}

# Get public IPv4 with fallback (optimized version)
get_public_ip() {
    local ip=""
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
        "https://ident.me"
    )
    
    for service in "${services[@]}"; do
        ip=$(curl -s --connect-timeout 5 --max-time 10 "$service" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$ip" ]] && validate_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    done
    
    # Fallback: local interface
    ip=$(hostname -I | awk '{print $1}' 2>/dev/null)
    if validate_ip "$ip"; then
        echo "$ip"
        return 0
    fi
    
    log "ERROR" "Failed to determine public IP address"
    return 1
}

# Generate random hex string (optimized)
generate_hex_secret() {
    local length="${1:-16}"
    if command -v xxd &>/dev/null; then
        head -c "$length" /dev/urandom | xxd -p | tr -d '\n'
    else
        head -c "$length" /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

# Securely create file with restricted permissions
create_secure_file() {
    local file="$1"
    local content="$2"
    local mode="${3:-600}"

    umask 077
    local tmp_file
    tmp_file="$(mktemp "${file}.tmp.XXXXXX")"
    printf '%s\n' "$content" > "$tmp_file"
    chmod "$mode" "$tmp_file"
    mv -f "$tmp_file" "$file"
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Calculate recommended memory limit based on available RAM
calculate_memory_limit() {
    local total_ram_kb
    total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram=$((total_ram_kb / 1024))
    
    if ((total_ram <= 512)); then
        echo "256M"
    elif ((total_ram <= 1024)); then
        echo "512M"
    elif ((total_ram <= 2048)); then
        echo "768M"
    else
        echo "1G"
    fi
}

# Calculate CPU limit based on available cores
calculate_cpu_limit() {
    local cpu_count
    cpu_count=$(nproc 2>/dev/null || echo 1)
    
    if ((cpu_count <= 1)); then
        echo "0.5"
    elif ((cpu_count <= 2)); then
        echo "1.0"
    else
        echo "2.0"
    fi
}

# Mask secret for logging (show first and last 4 chars)
mask_secret() {
    local secret="$1"
    local length=${#secret}
    
    if ((length <= 8)); then
        echo "****"
    else
        echo "${secret:0:4}...${secret: -4}"
    fi
}

################################################################################
# Main Installation Script
################################################################################

check_root

echo -e "${BLUE}=========================================="
echo -e "🚀 Установка MTProto Proxy (Ubuntu 22.04)"
echo -e "==========================================${NC}"

# 1. System update (optimized with noninteractive mode)
log "INFO" "[1/6] Обновление пакетов системы..."
export DEBIAN_FRONTEND=noninteractive
apt update -qq && apt upgrade -y -qq
apt install -y -qq curl wget git ufw fail2ban openssl xxd jq apache2-utils

# 2. User setup (optional)
log "INFO" "[2/6] Настройка пользователя..."
if id "proxyadmin" &>/dev/null; then
    log "INFO" "Пользователь 'proxyadmin' уже существует."
else
    read -p "Создать непривилегированного пользователя 'proxyadmin'? (y/n): " create_user
    if [[ "$create_user" =~ ^[Yy]$ ]]; then
        adduser --disabled-password --gecos "" proxyadmin
        usermod -aG sudo proxyadmin
        echo "proxyadmin ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/proxyadmin > /dev/null
        log "INFO" "Пользователь 'proxyadmin' создан."
    else
        echo "⏭️ Пропущено создание пользователя."
    fi
fi

# 3. Firewall configuration
log "INFO" "[3/6] Настройка UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment "SSH Access"
ufw allow 443/tcp comment "MTProto Proxy"

echo "y" | ufw enable
ufw status verbose
log "INFO" "Файрвол настроен."

# 4. Docker installation (optimized with idempotency check)
log "INFO" "[4/6] Установка Docker Engine..."

# Check if Docker is already installed and running
if command_exists docker && systemctl is-active --quiet docker; then
    log "INFO" "Docker уже установлен и запущен"
else
    # Remove old versions (single apt call for optimization)
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
        apt-get remove -y -qq "$pkg" 2>/dev/null || true
    done

    # Create keyrings directory
    install -m 0755 -d /etc/apt/keyrings

    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository (deb822 format)
    distro_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}")"
    if [[ -z "$distro_codename" ]]; then
        log "ERROR" "Не удалось определить версию Ubuntu"
        exit 1
    fi

    cat > /etc/apt/sources.list.d/docker.sources << EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${distro_codename}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    rm -f /etc/apt/sources.list.d/docker.list

    # Update and install (quiet mode for performance)
    apt update -qq
    apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Add user to docker group
RUN_USER="${SUDO_USER:-$USER}"
usermod -aG docker "$RUN_USER"
log "INFO" "Docker установлен."

# 5. Configuration generation
log "INFO" "[5/6] Генерация конфигурации и секретов..."
INSTALL_DIR="/opt/mtproto-proxy"
mkdir -p "${INSTALL_DIR}"/{config,data}
cd "${INSTALL_DIR}"

SECRET=$(generate_hex_secret 16)
MEMORY_LIMIT=$(calculate_memory_limit)
CPU_LIMIT=$(calculate_cpu_limit)

# Create .env file securely
cat > .env << EOF
PORT=443
SECRET=${SECRET}
TAG=d00df00d
TLS_DOMAIN=ok.ru
MEMORY_LIMIT=${MEMORY_LIMIT}
CPU_LIMIT=${CPU_LIMIT}
EOF
chmod 600 .env

# Create docker-compose.yml with optimized settings
cat > docker-compose.yml << EOF
version: "3.9"

services:
  mtproxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproxy
    restart: unless-stopped
    network_mode: host
    env_file: .env
    environment:
      - PORT=\${PORT}
      - SECRET=\${SECRET}
      - TAG=\${TAG}
      - TLS_DOMAIN=\${TLS_DOMAIN}
    volumes:
      - ./config:/config
      - ./data:/data
    deploy:
      resources:
        limits:
          memory: ${MEMORY_LIMIT}
          cpus: '${CPU_LIMIT}'
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD-SHELL", "bash -ec 'exec 3<>/dev/tcp/127.0.0.1/\${PORT:-443}'"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

chown -R "$RUN_USER":"$RUN_USER" "${INSTALL_DIR}"

# Create management script
cat > manage.sh << 'MANAGE_SCRIPT'
#!/bin/bash
ENV_FILE=".env"
COMPOSE_CMD="docker compose"

generate_secret() { head -c 16 /dev/urandom | xxd -p | tr -d '\n'; }
get_secret() { grep "^SECRET=" "$ENV_FILE" | cut -d'=' -f2; }
get_port() { grep "^PORT=" "$ENV_FILE" | cut -d'=' -f2; }

get_link() {
    local secret=$(get_secret)
    local port=$(get_port)
    local ip=$(curl -s --connect-timeout 5 https://api.ipify.org || curl -s ifconfig.me || hostname -I | awk '{print $1}')
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
    status) $COMPOSE_CMD ps ;;
    *) 
        echo "Использование: $0 {init|link|rotate|logs|start|stop|status}"
        exit 1
        ;;
esac
MANAGE_SCRIPT

chmod +x manage.sh
chown "$RUN_USER":"$RUN_USER" manage.sh

log "INFO" "Конфигурация создана в ${INSTALL_DIR}"

# 6. Start containers
log "INFO" "[6/6] Запуск контейнеров..."
docker compose up -d

# Install Watchtower (idempotent)
log "INFO" "Установка Watchtower для автообновления..."
if ! docker ps --format "{{.Names}}" | grep -qx "watchtower"; then
    docker run -d \
      --name watchtower \
      -v /var/run/docker.sock:/var/run/docker.sock \
      containrrr/watchtower \
      --interval 86400 \
      --cleanup \
      mtproxy >/dev/null
    log "INFO" "Watchtower установлен"
else
    log "INFO" "Watchtower уже запущен"
fi

# Final output
IP_ADDR=$(get_public_ip)
CURRENT_SECRET=$(grep "^SECRET=" .env | cut -d'=' -f2)

clear
echo -e "${GREEN}=========================================="
echo -e "✅ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!"
echo -e "==========================================${NC}"
echo -e "📍 Директория: ${YELLOW}${INSTALL_DIR}${NC}"
echo -e "🌍 IP адрес: ${BLUE}${IP_ADDR}${NC}"
echo -e "🔌 Порт: ${BLUE}443${NC}"
echo -e "🔑 Секрет: ${YELLOW}$(mask_secret "$CURRENT_SECRET")${NC}"
echo -e "\n📲 ${GREEN}Ссылка для подключения:${NC}"
echo -e "tg://proxy?server=${IP_ADDR}&port=443&secret=${CURRENT_SECRET}"
echo -e "https://t.me/proxy?server=${IP_ADDR}&port=443&secret=${CURRENT_SECRET}"
echo -e "\n🛠 ${GREEN}Управление:${NC}"
echo -e "  cd ${INSTALL_DIR} && ./manage.sh <command>"
echo -e "💡 Рекомендуется использовать: ${YELLOW}./scripts/mtproxy-cli.sh${NC}"
echo -e "${GREEN}==========================================${NC}"
