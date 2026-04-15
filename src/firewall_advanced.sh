#!/bin/bash
################################################################################
# Advanced Firewall Module - UFW with rate limiting and Fail2Ban integration
# License: MIT
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Default firewall configuration with advanced security
configure_ufw() {
    local proxy_port="${1:-443}"
    local ssh_port="${2:-22}"
    local expose_proxy_port="${3:-false}"
    
    log "$LOG_INFO" "Configuring UFW firewall with advanced security..."
    
    # Check if UFW is installed
    if ! command_exists ufw; then
        log "$LOG_ERROR" "UFW is not installed. Installing..."
        apt-get install -y ufw
    fi
    
    # Set default policies - Defense in Depth
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH with rate limiting (prevent brute force)
    ufw limit "$ssh_port"/tcp comment "SSH with rate limiting"
    
    # Allow Nginx HTTP/HTTPS (for reverse proxy mode)
    ufw allow 80/tcp comment "Nginx HTTP"
    ufw allow 443/tcp comment "Nginx HTTPS"
    
    # Allow MTProxy port only for legacy/public-edge topology
    # In tunnel mode, MTProxy stays private behind nginx/cloudflared
    if [[ "$expose_proxy_port" == "true" ]]; then
        ufw allow "$proxy_port"/tcp comment "MTProto Proxy (Legacy Mode)"
    else
        log "$LOG_INFO" "Skipping inbound ${proxy_port}/tcp rule (Tunnel/Nginx mode enabled)"
    fi
    
    # Log denied packets for security monitoring
    ufw logging on
    ufw logging medium
    
    # Enable UFW (non-interactive)
    ufw --force enable
    
    # Show status
    ufw status verbose
    
    log "$LOG_INFO" "Firewall configured successfully with advanced security"
}

# Install and configure Fail2Ban
install_fail2ban() {
    log "$LOG_INFO" "Installing Fail2Ban for intrusion prevention..."
    
    if ! command_exists fail2ban; then
        apt-get install -y fail2ban
    fi
    
    # Create custom jail for nginx
    cat > /etc/fail2ban/jail.d/mtproxy.conf << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = auto

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
EOF
    
    # Enable and start Fail2Ban
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log "$LOG_INFO" "Fail2Ban installed and configured"
}

# Add a new allowed port with optional rate limiting
add_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local comment="${3:-Custom port}"
    local rate_limit="${4:-false}"
    
    if [[ "$rate_limit" == "true" ]]; then
        ufw limit "$port"/"$protocol" comment "$comment"
        log "$LOG_INFO" "Port $port/$protocol opened with rate limiting"
    else
        ufw allow "$port"/"$protocol" comment "$comment"
        log "$LOG_INFO" "Port $port/$protocol opened"
    fi
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

# Get blocked IPs from Fail2Ban
get_blocked_ips() {
    fail2ban-client status | grep "Jail list" | sed "s/ //g" | awk -F: '{print $2}' | tr ',' '\n' | while read -r jail; do
        fail2ban-client status "$jail" | grep "Currently banned" | awk '{print $NF}'
    done
}

# Unblock all IPs (emergency use only)
unblock_all() {
    log "$LOG_WARN" "Unblocking all IPs from Fail2Ban..."
    fail2ban-client reload
    log "$LOG_INFO" "All IPs unblocked"
}

# Show firewall and Fail2Ban status
show_security_status() {
    echo "=== UFW Status ==="
    ufw status verbose
    echo ""
    echo "=== Fail2Ban Status ==="
    fail2ban-client status
    echo ""
    echo "=== Blocked IPs ==="
    get_blocked_ips
}
