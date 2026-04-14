#!/bin/bash
################################################################################
# Docker Module - Docker installation and container management
# License: MIT
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Package cache directory for optimization
PACKAGE_CACHE_DIR="/var/cache/apt/archives"

# Install Docker Engine
install_docker() {
    log "$LOG_INFO" "Installing Docker Engine..."
    export DEBIAN_FRONTEND=noninteractive

    if check_docker_status; then
        log "$LOG_INFO" "Docker Engine is already installed and running"
        return 0
    fi
    
    # Remove old versions
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
        apt-get remove -y "$pkg" 2>/dev/null || true
    done
    
    # Create keyrings directory
    install -m 0755 -d /etc/apt/keyrings

    # Add Docker GPG key (current Docker docs format)
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository in deb822 format
    local distro_codename
    distro_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}")"
    if [[ -z "$distro_codename" ]]; then
        log "$LOG_ERROR" "Unable to detect Ubuntu codename for Docker repository"
        return 1
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
    
    # Update and install
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    log "$LOG_INFO" "Docker installed successfully"
}

# Add user to docker group
add_user_to_docker_group() {
    local user="${1:-${SUDO_USER:-$USER}}"
    
    usermod -aG docker "$user"
    log "$LOG_INFO" "User $user added to docker group"
}

# Check if Docker is installed and running
check_docker_status() {
    if ! command_exists docker; then
        return 1
    fi
    
    if ! systemctl is-active --quiet docker; then
        return 1
    fi
    
    return 0
}

# Create Docker network
create_network() {
    local network_name="$1"
    local driver="${2:-bridge}"
    
    if ! docker network inspect "$network_name" &>/dev/null; then
        docker network create --driver "$driver" "$network_name"
        log "$LOG_INFO" "Docker network '$network_name' created"
    else
        log "$LOG_DEBUG" "Docker network '$network_name' already exists"
    fi
}

# Remove Docker network
remove_network() {
    local network_name="$1"
    
    docker network rm "$network_name" 2>/dev/null || true
    log "$LOG_INFO" "Docker network '$network_name' removed"
}

# Prune unused Docker resources
prune_docker() {
    local all="${1:-false}"
    
    if [[ "$all" == "true" ]]; then
        docker system prune -a -f
    else
        docker system prune -f
    fi
    
    log "$LOG_INFO" "Docker pruning complete"
}

# Get container status
get_container_status() {
    local container_name="$1"
    
    docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "not_found"
}

# Wait for container to be healthy
wait_for_container() {
    local container_name="$1"
    local timeout="${2:-60}"
    
    log "$LOG_INFO" "Waiting for container $container_name to be healthy..."
    
    if wait_for_condition "docker inspect -f '{{.State.Running}}' $container_name 2>/dev/null | grep -q true" "$timeout"; then
        log "$LOG_INFO" "Container $container_name is running"
        return 0
    else
        log "$LOG_ERROR" "Container $container_name failed to start within ${timeout}s"
        return 1
    fi
}

# Enable caching for apt packages
enable_apt_cache() {
    if [[ ! -d "$PACKAGE_CACHE_DIR" ]]; then
        mkdir -p "$PACKAGE_CACHE_DIR"
    fi
    
    # Configure apt to keep package cache
    echo 'DPkg::Post-Invoke { "mkdir -p /var/cache/apt/archives"; };' > /etc/apt/apt.conf.d/02cache
    
    log "$LOG_INFO" "APT caching enabled"
}

# Get Docker image digest
get_image_digest() {
    local image="$1"

    if ! docker inspect --format='{{index .RepoDigests 0}}' "$image" 2>/dev/null; then
        docker pull "$image" >/dev/null 2>&1
        docker inspect --format='{{index .RepoDigests 0}}' "$image" 2>/dev/null
    fi
}

# Run container with security options
run_secure_container() {
    local image="$1"
    local name="$2"
    shift 2
    
    docker run -d \
        --name "$name" \
        --security-opt no-new-privileges:true \
        --read-only \
        --tmpfs /tmp \
        --cap-drop ALL \
        "$@" \
        "$image"
    
    log "$LOG_INFO" "Container $name started with security hardening"
}
