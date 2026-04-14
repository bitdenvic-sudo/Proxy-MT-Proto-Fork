#!/bin/bash
################################################################################
# Firewall Module - UFW configuration for MTProxy
# License: MIT
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Default firewall configuration
configure_ufw() {
    local proxy_port="${1:-443}"
    local ssh_port="${2:-22}"
    local expose_proxy_port="${3:-false}"
    
    log "$LOG_INFO" "Configuring UFW firewall..."
    
    # Check if UFW is installed
    if ! command_exists ufw; then
        log "$LOG_ERROR" "UFW is not installed. Installing..."
        apt-get install -y ufw
    fi
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow "$ssh_port"/tcp comment "SSH Access"
    
    # Allow MTProxy port only for legacy/public-edge topology.
    # In tunnel topology MTProxy stays private behind cloudflared.
    if [[ "$expose_proxy_port" == "true" ]]; then
        ufw allow "$proxy_port"/tcp comment "MTProto Proxy"
    else
        log "$LOG_INFO" "Skipping inbound ${proxy_port}/tcp rule (Tunnel mode enabled)"
    fi
    
    # Enable UFW (non-interactive)
    ufw --force enable
    
    # Show status
    ufw status verbose
    
    log "$LOG_INFO" "Firewall configured successfully"
}

# Add a new allowed port
add_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local comment="${3:-Custom port}"
    
    ufw allow "$port"/"$protocol" comment "$comment"
    log "$LOG_INFO" "Port $port/$protocol opened"
}

# Remove a port from firewall
remove_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    ufw delete allow "$port"/"$protocol"
    log "$LOG_INFO" "Port $port/$protocol closed"
}

# Check if port is open
is_port_open() {
    local port="$1"
    ufw status | grep -q "$port.*ALLOW"
}

# Reset firewall to defaults
reset_firewall() {
    log "$LOG_WARN" "Resetting firewall to defaults..."
    ufw --force reset
    log "$LOG_INFO" "Firewall reset complete"
}

# Backup current firewall rules
backup_rules() {
    local backup_file="${1:-/etc/ufw/rules.backup.$(date +%Y%m%d_%H%M%S)}"
    
    if [[ -f /etc/ufw/user.rules ]]; then
        cp /etc/ufw/user.rules "$backup_file"
        chmod 600 "$backup_file"
        log "$LOG_INFO" "Firewall rules backed up to: $backup_file"
        echo "$backup_file"
    else
        log "$LOG_ERROR" "No firewall rules found to backup"
        return 1
    fi
}

# Restore firewall rules from backup
restore_rules() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log "$LOG_ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    cp "$backup_file" /etc/ufw/user.rules
    log "$LOG_INFO" "Firewall rules restored from: $backup_file"
}

# Validate port number
validate_port() {
    local port="$1"
    
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    if ((port < 1 || port > 65535)); then
        return 1
    fi
    
    return 0
}
