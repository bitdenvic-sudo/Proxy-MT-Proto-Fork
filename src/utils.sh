#!/bin/bash
################################################################################
# Utils Module - Common utilities for MTProxy installer
# License: MIT
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log levels
LOG_INFO="INFO"
LOG_WARN="WARN"
LOG_ERROR="ERROR"
LOG_DEBUG="DEBUG"

# Logging function with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "$LOG_INFO")  echo -e "${BLUE}[$timestamp] [INFO]${NC} $message" ;;
        "$LOG_WARN")  echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" ;;
        "$LOG_ERROR") echo -e "${RED}[$timestamp] [ERROR]${NC} $message" ;;
        "$LOG_DEBUG") [[ "${DEBUG:-0}" == "1" ]] && echo -e "[$timestamp] [DEBUG] $message" ;;
    esac
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log "$LOG_ERROR" "Please run as root (sudo bash $0)"
        exit 1
    fi
}

# Validate IP address format
validate_ip() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ ! $ip =~ $regex ]]; then
        return 1
    fi
    
    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if ((octet < 0 || octet > 255)); then
            return 1
        fi
    done
    return 0
}

# Get public IP with fallback mechanisms
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
    
    # Fallback: try to get from network interface
    ip=$(hostname -I | awk '{print $1}' 2>/dev/null)
    if validate_ip "$ip"; then
        echo "$ip"
        return 0
    fi
    
    log "$LOG_ERROR" "Failed to determine public IP address"
    return 1
}

# Generate random hex string
generate_hex_secret() {
    local length="${1:-16}"
    if command_exists xxd; then
        head -c "$length" /dev/urandom | xxd -p | tr -d '\n'
    else
        # Fallback using od if xxd is not available
        head -c "$length" /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

# Generate random alphanumeric string
generate_random_string() {
    local length="${1:-32}"
    LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length" || true
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

# Wait for condition with timeout
wait_for_condition() {
    local condition_cmd="$1"
    local timeout="${2:-30}"
    local interval="${3:-1}"
    local elapsed=0
    
    while ! eval "$condition_cmd" &>/dev/null; do
        if ((elapsed >= timeout)); then
            return 1
        fi
        sleep "$interval"
        ((elapsed += interval))
    done
    return 0
}

# Auto-detect available RAM in MB
detect_available_ram() {
    local total_ram_kb
    total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    echo $((total_ram_kb / 1024))
}

# Calculate recommended memory limit based on available RAM
calculate_memory_limit() {
    local total_ram
    total_ram=$(detect_available_ram)
    
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

# Trim whitespace from string
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# Ask yes/no question
ask_yes_no() {
    local question="$1"
    local default="${2:-y}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -rp "$question [Y/n]: " response
            response=${response:-y}
        else
            read -rp "$question [y/N]: " response
            response=${response:-n}
        fi
        
        case "$response" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}
