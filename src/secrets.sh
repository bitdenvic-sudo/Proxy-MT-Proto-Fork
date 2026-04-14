#!/bin/bash
################################################################################
# Secrets Module - Secure secret generation and management
# License: MIT
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Default secrets file location
SECRETS_DIR="${SECRETS_DIR:-/opt/mtproto-proxy}"
ENV_FILE="${SECRETS_DIR}/.env"

# Read variable from .env file safely
get_env_value() {
    local env_file="$1"
    local variable="$2"

    awk -F'=' -v key="$variable" '$1 == key {print $2; exit}' "$env_file" | tr -d '[:space:]'
}

# Generate MTProto secret (32 hex characters)
generate_mtproxy_secret() {
    local length="${1:-16}"
    generate_hex_secret "$length"
}

# Generate TAG for MTProxy
generate_tag() {
    # Standard tag format: 4 bytes in hex
    echo "d00df00d"
}

# Create .env file with secure permissions
create_env_file() {
    local install_dir="$1"
    local port="${2:-443}"
    local secret="${3:-$(generate_mtproxy_secret)}"
    local tag="${4:-$(generate_tag)}"
    local tls_domain="${5:-www.telegram.org}"
    
    # Ensure directory exists
    mkdir -p "$install_dir"
    
    local env_content="PORT=${port}
SECRET=${secret}
TAG=${tag}
TLS_DOMAIN=${tls_domain}"
    
    create_secure_file "${install_dir}/.env" "$env_content" 600
    
    log "$LOG_INFO" "Environment file created at ${install_dir}/.env"
}

# Read secret from env file
get_secret() {
    local env_file="${1:-$ENV_FILE}"
    
    if [[ ! -f "$env_file" ]]; then
        log "$LOG_ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    get_env_value "$env_file" "SECRET"
}

# Read port from env file
get_port() {
    local env_file="${1:-$ENV_FILE}"
    
    if [[ ! -f "$env_file" ]]; then
        log "$LOG_ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    get_env_value "$env_file" "PORT"
}

# Rotate secret in env file
rotate_secret() {
    local env_file="${1:-$ENV_FILE}"
    local new_secret="${2:-$(generate_mtproxy_secret)}"
    
    if [[ ! -f "$env_file" ]]; then
        log "$LOG_ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    # Backup old env file
    local backup_file="${env_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$env_file" "$backup_file"
    chmod 600 "$backup_file"

    # Capture ownership and mode so atomic replacement keeps file accessible
    local original_uid original_gid original_mode
    original_uid=$(stat -c "%u" "$env_file")
    original_gid=$(stat -c "%g" "$env_file")
    original_mode=$(stat -c "%a" "$env_file")

    # Update secret atomically
    local tmp_file
    tmp_file="$(mktemp "${env_file}.tmp.XXXXXX")"
    awk -v secret="$new_secret" '
        BEGIN {updated=0}
        /^SECRET=/ {print "SECRET=" secret; updated=1; next}
        {print}
        END {if (updated == 0) print "SECRET=" secret}
    ' "$env_file" > "$tmp_file"

    chmod "$original_mode" "$tmp_file"
    if [[ $(id -u) -eq 0 ]]; then
        chown "${original_uid}:${original_gid}" "$tmp_file"
    fi

    mv -f "$tmp_file" "$env_file"

    # Ensure metadata remains correct after replacement
    chmod "$original_mode" "$env_file"
    if [[ $(id -u) -eq 0 ]]; then
        chown "${original_uid}:${original_gid}" "$env_file"
    fi
    
    log "$LOG_INFO" "Secret rotated successfully"
    echo "$new_secret"
}

# Validate secret format
validate_secret() {
    local secret="$1"
    local expected_length="${2:-32}"
    
    # Check if it's a valid hex string
    if ! [[ "$secret" =~ ^[0-9a-fA-F]+$ ]]; then
        return 1
    fi
    
    # Check length
    if [[ ${#secret} -ne $expected_length ]]; then
        return 1
    fi
    
    return 0
}

# Securely delete secrets file
secure_delete() {
    local file="$1"
    
    if [[ -f "$file" ]]; then
        # Overwrite with random data before deletion
        dd if=/dev/urandom of="$file" bs=1 count=$(stat -c%s "$file") conv=notrunc 2>/dev/null
        rm -f "$file"
        log "$LOG_INFO" "File securely deleted: $file"
    fi
}

# Backup secrets with encryption (if openssl available)
backup_secrets() {
    local source_dir="$1"
    local backup_dir="${2:-/var/backups/mtproxy}"
    local password="${3:-}"
    
    mkdir -p "$backup_dir"
    local backup_file="${backup_dir}/secrets_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    if [[ -n "$password" ]] && command_exists openssl; then
        tar czf - -C "$(dirname "$source_dir")" "$(basename "$source_dir")" | \
            openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$password" -out "$backup_file"
        log "$LOG_INFO" "Encrypted backup created: $backup_file"
    else
        tar czf "$backup_file" -C "$(dirname "$source_dir")" "$(basename "$source_dir")"
        log "$LOG_WARN" "Unencrypted backup created (provide password for encryption): $backup_file"
    fi
    
    chmod 600 "$backup_file"
    echo "$backup_file"
}

# Generate connection link
generate_connection_link() {
    local ip="$1"
    local port="$2"
    local secret="$3"
    
    if [[ -z "$ip" ]] || [[ -z "$port" ]] || [[ -z "$secret" ]]; then
        log "$LOG_ERROR" "Missing required parameters for connection link"
        return 1
    fi
    
    echo "tg://proxy?server=${ip}&port=${port}&secret=${secret}"
    echo "https://t.me/proxy?server=${ip}&port=${port}&secret=${secret}"
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

# Validate environment file exists and has correct permissions
validate_env_file() {
    local env_file="${1:-$ENV_FILE}"
    local errors=0
    
    if [[ ! -f "$env_file" ]]; then
        log "$LOG_ERROR" "Environment file not found: $env_file"
        ((errors++))
    else
        # Check permissions
        local perms
        perms=$(stat -c "%a" "$env_file")
        if [[ "$perms" != "600" ]]; then
            log "$LOG_WARN" "Environment file has insecure permissions: $perms (should be 600)"
            ((errors++))
        fi
        
        # Check required variables
        for var in PORT SECRET TAG TLS_DOMAIN; do
            if ! grep -q "^${var}=" "$env_file"; then
                log "$LOG_ERROR" "Missing required variable: $var"
                ((errors++))
            fi
        done
    fi
    
    if ((errors > 0)); then
        return 1
    fi
    return 0
}
