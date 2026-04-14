#!/bin/bash
################################################################################
# MTProxy CLI - Command-line interface for managing MTProto Proxy
# License: MIT
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"

# Source modules
source "${SRC_DIR}/utils.sh"
source "${SRC_DIR}/firewall.sh"
source "${SRC_DIR}/docker.sh"
source "${SRC_DIR}/secrets.sh"

# Configuration
INSTALL_DIR="${INSTALL_DIR:-/opt/mtproto-proxy}"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
ENV_FILE="${INSTALL_DIR}/.env"
MANAGE_SCRIPT="${INSTALL_DIR}/manage.sh"

# Version
VERSION="2.0.0"

# Print usage
print_usage() {
    cat << EOF
MTProxy Manager v${VERSION}

Usage: $0 <command> [options]

Commands:
  install         Full installation of MTProxy
  init            Initialize configuration only
  start           Start MTProxy container
  stop            Stop MTProxy container
  restart         Restart MTProxy container
  status          Show container status
  link            Get connection links
  rotate          Rotate proxy secret
  logs            View container logs
  backup          Backup configuration
  restore         Restore from backup
  uninstall       Remove MTProxy completely
  dry-run         Show what would be done without making changes
  
Options:
  -h, --help      Show this help message
  -v, --version   Show version
  --debug         Enable debug output
  --port PORT     Set proxy port (default: 443)
  --secret SECRET Use custom secret (hex, 32 chars)
  
Examples:
  $0 install                    # Full installation
  $0 install --port 8443        # Install with custom port
  $0 rotate                     # Rotate secret
  $0 link                       # Get connection link
  $0 --dry-run install          # Preview installation

EOF
}

# Print version
print_version() {
    echo "MTProxy Manager v${VERSION}"
}

# Dry run mode
DRY_RUN=false

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -v|--version)
                print_version
                exit 0
                ;;
            --debug)
                export DEBUG=1
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                log "$LOG_WARN" "Dry run mode enabled - no changes will be made"
                shift
                ;;
            --port)
                PROXY_PORT="$2"
                shift 2
                ;;
            --secret)
                CUSTOM_SECRET="$2"
                shift 2
                ;;
            *)
                COMMAND="$1"
                shift
                ;;
        esac
    done
}

# Repair stale Docker apt source entries that use Ubuntu version numbers instead of codenames
repair_docker_apt_source() {
    local docker_list="/etc/apt/sources.list.d/docker.list"

    if [[ ! -f "$docker_list" ]]; then
        return 0
    fi

    local codename
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}")"
    if [[ -z "$codename" ]]; then
        return 0
    fi

    if grep -Eq 'download\.docker\.com/linux/ubuntu[[:space:]]+[0-9]' "$docker_list"; then
        sed -Ei "s#(download\.docker\.com/linux/ubuntu[[:space:]]+)[^[:space:]]+#\1${codename}#" "$docker_list"
        log "$LOG_WARN" "Fixed Docker apt source distribution to '${codename}' in ${docker_list}"
    fi
}

# System update and package installation
update_system() {
    log "$LOG_INFO" "Updating system packages..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "$LOG_INFO" "[DRY RUN] Would run: apt update && apt upgrade -y"
        return 0
    fi

    repair_docker_apt_source

    if ! apt update; then
        local docker_list="/etc/apt/sources.list.d/docker.list"
        if [[ -f "$docker_list" ]] && grep -q 'download.docker.com/linux/ubuntu' "$docker_list"; then
            local disabled_file="${docker_list}.disabled.$(date +%Y%m%d_%H%M%S)"
            mv "$docker_list" "$disabled_file"
            log "$LOG_WARN" "Temporarily disabled broken Docker apt source: ${disabled_file}"
            apt update
        else
            return 1
        fi
    fi

    apt upgrade -y
    apt install -y curl wget git ufw fail2ban openssl xxd jq apache2-utils
}

# Create system user
create_user() {
    local username="${1:-proxyadmin}"
    
    if id "$username" &>/dev/null; then
        log "$LOG_INFO" "User '$username' already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "$LOG_INFO" "[DRY RUN] Would create user: $username"
        return 0
    fi
    
    adduser --disabled-password --gecos "" "$username"
    usermod -aG sudo "$username"
    echo "$username ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/"$username" > /dev/null
    
    log "$LOG_INFO" "User '$username' created"
}

# Setup firewall
setup_firewall() {
    local port="${PROXY_PORT:-443}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "$LOG_INFO" "[DRY RUN] Would configure firewall for port $port"
        return 0
    fi
    
    configure_ufw "$port"
}

# Install Docker
install_docker_engine() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "$LOG_INFO" "[DRY RUN] Would install Docker Engine"
        return 0
    fi
    
    install_docker
    add_user_to_docker_group
}

# Generate configuration files
generate_config() {
    local port="${PROXY_PORT:-443}"
    local secret="${CUSTOM_SECRET:-$(generate_mtproxy_secret)}"
    local tag="$(generate_tag)"
    local tls_domain="www.telegram.org"
    
    # Auto-calculate resource limits
    local memory_limit
    local cpu_limit
    memory_limit=$(calculate_memory_limit)
    cpu_limit=$(calculate_cpu_limit)
    
    log "$LOG_INFO" "Generating configuration..."
    log "$LOG_DEBUG" "Port: $port, Secret: $(mask_secret "$secret"), Memory: $memory_limit, CPU: $cpu_limit"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "$LOG_INFO" "[DRY RUN] Would create directory: $INSTALL_DIR"
        log "$LOG_INFO" "[DRY RUN] Would create .env and docker-compose.yml"
        return 0
    fi
    
    mkdir -p "${INSTALL_DIR}"/{config,data}
    cd "${INSTALL_DIR}"
    
    # Create .env file
    create_env_file "$INSTALL_DIR" "$port" "$secret" "$tag" "$tls_domain"
    
    # Create docker-compose.yml
    cat > "${COMPOSE_FILE}" << EOF
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
          memory: ${memory_limit}
          cpus: '${cpu_limit}'
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "\${PORT}"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

    # Set ownership
    local run_user="${SUDO_USER:-$USER}"
    chown -R "$run_user":"$run_user" "${INSTALL_DIR}"
    
    log "$LOG_INFO" "Configuration generated successfully"
}

# Create management script
create_manage_script() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "$LOG_INFO" "[DRY RUN] Would create manage.sh"
        return 0
    fi
    
    cat > "${MANAGE_SCRIPT}" << 'MANAGE_SCRIPT'
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
        echo -e "\033[0;31mError: Secret not found in .env\033[0m"
        exit 1
    fi
    echo -e "\n\033[0;32mConnection links:\033[0m"
    echo "tg://proxy?server=${ip}&port=${port}&secret=${secret}"
    echo "https://t.me/proxy?server=${ip}&port=${port}&secret=${secret}"
}

case "$1" in
    init)
        if [ -z "$(get_secret)" ]; then
            echo "Generating new secret..."
            NEW_SECRET=$(generate_secret)
            sed -i "s/^SECRET=.*/SECRET=${NEW_SECRET}/" "$ENV_FILE"
            $COMPOSE_CMD up -d
            echo -e "\033[0;32m✅ Initialized and started.\033[0m"
        else
            echo -e "\033[1;33mℹ️ Configuration already exists.\033[0m"
            $COMPOSE_CMD up -d
        fi
        ;;
    link) get_link ;;
    rotate)
        echo "🔄 Rotating secret..."
        NEW_SECRET=$(generate_secret)
        sed -i "s/^SECRET=.*/SECRET=${NEW_SECRET}/" "$ENV_FILE"
        $COMPOSE_CMD restart mtproxy
        echo -e "\033[0;32m✅ Secret updated.\033[0m"
        $0 link
        ;;
    logs) $COMPOSE_CMD logs -f mtproxy ;;
    stop) $COMPOSE_CMD down ;;
    start) $COMPOSE_CMD up -d ;;
    status) $COMPOSE_CMD ps ;;
    *) 
        echo "Usage: $0 {init|link|rotate|logs|start|stop|status}"
        exit 1
        ;;
esac
MANAGE_SCRIPT

    chmod +x "${MANAGE_SCRIPT}"
    chown "${SUDO_USER:-$USER}":"${SUDO_USER:-$USER}" "${MANAGE_SCRIPT}"
    
    log "$LOG_INFO" "Management script created"
}

# Start containers
start_containers() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "$LOG_INFO" "[DRY RUN] Would start Docker containers"
        return 0
    fi
    
    cd "${INSTALL_DIR}"
    docker compose up -d
    
    log "$LOG_INFO" "Waiting for container to start..."
    sleep 5
    
    if get_container_status "mtproxy" | grep -q "running"; then
        log "$LOG_INFO" "Container started successfully"
    else
        log "$LOG_ERROR" "Container failed to start"
        return 1
    fi
}

# Install Watchtower for auto-updates
install_watchtower() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "$LOG_INFO" "[DRY RUN] Would install Watchtower"
        return 0
    fi
    
    log "$LOG_INFO" "Installing Watchtower for automatic updates..."
    
    docker run -d \
      --name watchtower \
      -v /var/run/docker.sock:/var/run/docker.sock \
      containrrr/watchtower \
      --interval 86400 \
      --cleanup \
      mtproxy
    
    log "$LOG_INFO" "Watchtower installed"
}

# Display connection info
show_connection_info() {
    local ip
    ip=$(get_public_ip)
    local secret
    secret=$(get_secret "$ENV_FILE")
    local port
    port=$(get_port "$ENV_FILE")
    
    echo ""
    echo -e "${GREEN}=========================================="
    echo -e "✅ INSTALLATION COMPLETE!"
    echo -e "==========================================${NC}"
    echo -e "📍 Directory: ${YELLOW}${INSTALL_DIR}${NC}"
    echo -e "🌍 IP Address: ${BLUE}${ip}${NC}"
    echo -e "🔌 Port: ${BLUE}${port}${NC}"
    echo -e "🔑 Secret: ${YELLOW}$(mask_secret "$secret")${NC}"
    echo -e "\n📲 ${GREEN}Connection Links:${NC}"
    echo -e "tg://proxy?server=${ip}&port=${port}&secret=${secret}"
    echo -e "https://t.me/proxy?server=${ip}&port=${port}&secret=${secret}"
    echo -e "\n🛠 ${GREEN}Management:${NC}"
    echo -e "  cd ${INSTALL_DIR} && ./manage.sh <command>"
    echo -e "${GREEN}==========================================${NC}"
}

# Main install command
cmd_install() {
    log "$LOG_INFO" "Starting MTProxy installation..."
    
    check_root
    
    update_system
    create_user
    setup_firewall
    install_docker_engine
    generate_config
    create_manage_script
    start_containers
    install_watchtower
    show_connection_info
}

# Initialize config only
cmd_init() {
    check_root
    generate_config
    create_manage_script
    log "$LOG_INFO" "Initialization complete. Run 'start' to launch."
}

# Start command
cmd_start() {
    cd "${INSTALL_DIR}"
    docker compose up -d
    log "$LOG_INFO" "MTProxy started"
}

# Stop command
cmd_stop() {
    cd "${INSTALL_DIR}"
    docker compose down
    log "$LOG_INFO" "MTProxy stopped"
}

# Status command
cmd_status() {
    cd "${INSTALL_DIR}"
    docker compose ps
    docker stats --no-stream mtproxy 2>/dev/null || true
}

# Link command
cmd_link() {
    local ip
    ip=$(get_public_ip)
    local secret
    secret=$(get_secret "$ENV_FILE")
    local port
    port=$(get_port "$ENV_FILE")
    
    generate_connection_link "$ip" "$port" "$secret"
}

# Rotate command
cmd_rotate() {
    log "$LOG_INFO" "Rotating secret..."
    
    local new_secret
    new_secret=$(rotate_secret "$ENV_FILE")
    
    cd "${INSTALL_DIR}"
    docker compose restart mtproxy
    
    log "$LOG_INFO" "Secret rotated successfully"
    cmd_link
}

# Logs command
cmd_logs() {
    cd "${INSTALL_DIR}"
    docker compose logs -f mtproxy
}

# Backup command
cmd_backup() {
    local backup_dir="${1:-/var/backups/mtproxy}"
    backup_secrets "$INSTALL_DIR" "$backup_dir"
    log "$LOG_INFO" "Backup completed"
}

# Uninstall command
cmd_uninstall() {
    check_root
    
    log "$LOG_WARN" "This will remove MTProxy and all data. Continue?"
    if ! ask_yes_no "Are you sure?"; then
        log "$LOG_INFO" "Uninstall cancelled"
        return 0
    fi
    
    cd "${INSTALL_DIR}"
    docker compose down
    docker rm -f watchtower 2>/dev/null || true
    
    rm -rf "${INSTALL_DIR}"
    
    log "$LOG_INFO" "MTProxy uninstalled"
}

# Main entry point
main() {
    parse_args "$@"
    
    case "${COMMAND:-}" in
        install)
            cmd_install
            ;;
        init)
            cmd_init
            ;;
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_stop
            cmd_start
            ;;
        status)
            cmd_status
            ;;
        link)
            cmd_link
            ;;
        rotate)
            cmd_rotate
            ;;
        logs)
            cmd_logs
            ;;
        backup)
            cmd_backup "${@:2}"
            ;;
        restore)
            log "$LOG_ERROR" "Restore not implemented yet"
            ;;
        uninstall)
            cmd_uninstall
            ;;
        dry-run)
            DRY_RUN=true
            cmd_install
            ;;
        "")
            print_usage
            exit 1
            ;;
        *)
            log "$LOG_ERROR" "Unknown command: $COMMAND"
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
