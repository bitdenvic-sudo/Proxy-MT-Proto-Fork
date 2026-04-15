#!/bin/bash
################################################################################
# Docker Security Module - Hardened container configuration
# Based on mtproto-org/proxy recommendations
# License: MIT
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Create seccomp profile for MTProxy
create_seccomp_profile() {
    local profile_path="${1:-/opt/mtproto-proxy/seccomp.json}"
    
    cat > "$profile_path" << 'EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "archMap": [
    {
      "architecture": "SCMP_ARCH_X86_64",
      "subArchitectures": ["SCMP_ARCH_X86", "SCMP_ARCH_X32"]
    },
    {
      "architecture": "SCMP_ARCH_AARCH64",
      "subArchitectures": ["SCMP_ARCH_ARM"]
    }
  ],
  "syscalls": [
    {
      "names": ["accept", "accept4", "access", "alarm", "bind", "brk", "capget", "capset", "chdir", "chmod", "chown", "chown32", "clock_getres", "clock_gettime", "clock_nanosleep", "close", "connect", "copy_file_range", "creat", "dup", "dup2", "dup3", "epoll_create", "epoll_create1", "epoll_ctl", "epoll_pwait", "epoll_wait", "eventfd", "eventfd2", "execve", "execveat", "exit", "exit_group", "faccessat", "fadvise64", "fallocate", "fchdir", "fchmod", "fchmodat", "fchown", "fchown32", "fchownat", "fcntl", "fcntl64", "fdatasync", "fgetxattr", "flistxattr", "flock", "fork", "fremovexattr", "fsetxattr", "fstat", "fstat64", "fstatat64", "fstatfs", "fstatfs64", "fsync", "ftruncate", "ftruncate64", "futex", "futimesat", "getcpu", "getcwd", "getdents", "getdents64", "getegid", "getegid32", "geteuid", "geteuid32", "getgid", "getgid32", "getgroups", "getgroups32", "getitimer", "getpeername", "getpgid", "getpgrp", "getpid", "getppid", "getpriority", "getrandom", "getresgid", "getresgid32", "getresuid", "getresuid32", "getrlimit", "get_robust_list", "getrusage", "getsid", "getsockname", "getsockopt", "get_thread_area", "gettid", "gettimeofday", "getuid", "getuid32", "getxattr", "inotify_add_watch", "inotify_init", "inotify_init1", "inotify_rm_watch", "io_cancel", "ioctl", "io_destroy", "io_getevents", "ioprio_get", "ioprio_set", "io_setup", "io_submit", "kill", "lchown", "lchown32", "lgetxattr", "link", "linkat", "listen", "listxattr", "llistxattr", "_llseek", "lremovexattr", "lseek", "lsetxattr", "lstat", "lstat64", "madvise", "memfd_create", "mincore", "mkdir", "mkdirat", "mknod", "mknodat", "mlock", "mlock2", "mlockall", "mmap", "mmap2", "mprotect", "mq_getsetattr", "mq_notify", "mq_open", "mq_timedreceive", "mq_timedsend", "mq_unlink", "mremap", "msgctl", "msgget", "msgrcv", "msgsnd", "msync", "munlock", "munlockall", "munmap", "nanosleep", "newfstatat", "_newselect", "open", "openat", "pause", "pipe", "pipe2", "poll", "ppoll", "prctl", "pread64", "preadv", "prlimit64", "pselect6", "pwrite64", "pwritev", "read", "readahead", "readlink", "readlinkat", "readv", "recv", "recvfrom", "recvmmsg", "recvmsg", "remap_file_pages", "removexattr", "rename", "renameat", "renameat2", "restart_syscall", "rmdir", "rt_sigaction", "rt_sigpending", "rt_sigprocmask", "rt_sigqueueinfo", "rt_sigreturn", "rt_sigsuspend", "rt_sigtimedwait", "rt_tgsigqueueinfo", "sched_getaffinity", "sched_getattr", "sched_getparam", "sched_get_priority_max", "sched_get_priority_min", "sched_getscheduler", "sched_rr_get_interval", "sched_setaffinity", "sched_setattr", "sched_setparam", "sched_setscheduler", "sched_yield", "seccomp", "select", "semctl", "semget", "semop", "semtimedop", "send", "sendfile", "sendfile64", "sendmmsg", "sendmsg", "sendto", "setfsgid", "setfsgid32", "setfsuid", "setfsuid32", "setgid", "setgid32", "setgroups", "setgroups32", "setitimer", "setpgid", "setpriority", "setregid", "setregid32", "setresgid", "setresgid32", "setresuid", "setresuid32", "setreuid", "setreuid32", "setrlimit", "set_robust_list", "setsid", "setsockopt", "set_thread_area", "set_tid_address", "setuid", "setuid32", "setxattr", "shmat", "shmctl", "shmdt", "shmget", "shutdown", "sigaltstack", "signalfd", "signalfd4", "socket", "socketcall", "socketpair", "splice", "stat", "stat64", "statfs", "statfs64", "statx", "symlink", "symlinkat", "sync", "sync_file_range", "syncfs", "sysinfo", "tee", "tgkill", "time", "timer_create", "timer_delete", "timerfd_create", "timerfd_gettime", "timerfd_settime", "timer_getoverrun", "timer_gettime", "timer_settime", "times", "tkill", "truncate", "truncate64", "ugetrlimit", "umask", "uname", "unlink", "unlinkat", "utime", "utimensat", "utimes", "vfork", "vmsplice", "wait4", "waitid", "waitpid", "write", "writev"],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
    
    log "$LOG_INFO" "Seccomp profile created at $profile_path"
}

# Create AppArmor profile for MTProxy
create_apparmor_profile() {
    local profile_name="${1:-mtproxy}"
    local profile_path="/etc/apparmor.d/$profile_name"
    
    cat > "$profile_path" << 'EOF'
#include <tunables/global>

profile mtproxy flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  
  network inet tcp,
  network inet udp,
  network inet6 tcp,
  network inet6 udp,
  
  /config/** r,
  /data/** rw,
  /tmp/** rw,
  
  deny @{PROC}/* w,
  deny /sys/* w,
  
  capability net_bind_service,
  
  /usr/bin/mtproxy-server ix,
}
EOF
    
    # Load the profile
    apparmor_parser -r "$profile_path" || true
    
    log "$LOG_INFO" "AppArmor profile created and loaded"
}

# Run MTProxy container with maximum security
run_secure_mtproxy() {
    local image="$1"
    local name="${2:-mtproxy}"
    local port="${3:-3128}"
    local secret="$4"
    local tag="$5"
    local tls_domain="${6:-ok.ru}"
    
    docker run -d \
        --name "$name" \
        --restart unless-stopped \
        --expose "$port" \
        --env PORT="$port" \
        --env SECRET="$secret" \
        --env TAG="$tag" \
        --env TLS_DOMAIN="$tls_domain" \
        --volume ./config:/config:ro \
        --volume ./data:/data \
        --network mtproxy-net \
        --security-opt no-new-privileges:true \
        --security-opt apparmor:docker-default \
        --read-only \
        --tmpfs /tmp:noexec,nosuid,size=64m \
        --cap-drop ALL \
        --cap-add NET_BIND_SERVICE \
        --pids-limit 50 \
        --memory 512m \
        --cpus 1.0 \
        --health-cmd "nc -z localhost $port" \
        --health-interval 30s \
        --health-timeout 10s \
        --health-retries 3 \
        --health-start-period 10s \
        --label "prometheus.scrape=true" \
        --label "monitoring.enabled=true" \
        "$image"
    
    log "$LOG_INFO" "Container $name started with maximum security hardening"
}

# Verify container security settings
verify_container_security() {
    local container_name="$1"
    
    log "$LOG_INFO" "Verifying security settings for container: $container_name"
    
    # Check if running as non-root
    local user
    user=$(docker inspect -f '{{.Config.User}}' "$container_name" 2>/dev/null || echo "root")
    if [[ "$user" == "root" || -z "$user" ]]; then
        log "$LOG_WARN" "Container is running as root"
    else
        log "$LOG_INFO" "Container running as user: $user ✓"
    fi
    
    # Check read-only filesystem
    local read_only
    read_only=$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$container_name")
    if [[ "$read_only" == "true" ]]; then
        log "$LOG_INFO" "Read-only root filesystem ✓"
    else
        log "$LOG_WARN" "Root filesystem is not read-only"
    fi
    
    # Check capabilities
    local cap_drop
    cap_drop=$(docker inspect -f '{{.HostConfig.CapDrop}}' "$container_name")
    if [[ "$cap_drop" == *"ALL"* ]]; then
        log "$LOG_INFO" "All capabilities dropped ✓"
    else
        log "$LOG_WARN" "Not all capabilities are dropped"
    fi
    
    # Check no-new-privileges
    local no_new_privs
    no_new_privs=$(docker inspect -f '{{.HostConfig.SecurityOpt}}' "$container_name" | grep -c "no-new-privileges" || echo "0")
    if [[ "$no_new_privs" -gt 0 ]]; then
        log "$LOG_INFO" "No-new-privileges enabled ✓"
    else
        log "$LOG_WARN" "No-new-privileges not enabled"
    fi
    
    # Check PID limit
    local pids_limit
    pids_limit=$(docker inspect -f '{{.HostConfig.PidsLimit}}' "$container_name")
    if [[ "$pids_limit" -gt 0 ]]; then
        log "$LOG_INFO" "PID limit set: $pids_limit ✓"
    else
        log "$LOG_WARN" "No PID limit set"
    fi
}

# Create isolated Docker network
create_isolated_network() {
    local network_name="${1:-mtproxy-net}"
    local subnet="${2:-172.28.0.0/16}"
    
    if ! docker network inspect "$network_name" &>/dev/null; then
        docker network create \
            --driver bridge \
            --subnet "$subnet" \
            --opt com.docker.network.bridge.enable_icc=false \
            "$network_name"
        log "$LOG_INFO" "Isolated network '$network_name' created"
    else
        log "$LOG_DEBUG" "Network '$network_name' already exists"
    fi
}

# Create monitoring network (internal only)
create_monitoring_network() {
    local network_name="${1:-monitoring-net}"
    local subnet="${2:-172.29.0.0/16}"
    
    if ! docker network inspect "$network_name" &>/dev/null; then
        docker network create \
            --driver bridge \
            --internal \
            --subnet "$subnet" \
            "$network_name"
        log "$LOG_INFO" "Internal monitoring network '$network_name' created"
    else
        log "$LOG_DEBUG" "Network '$network_name' already exists"
    fi
}

# Security audit for all containers
security_audit() {
    log "$LOG_INFO" "Running security audit..."
    
    local containers
    containers=$(docker ps --format "{{.Names}}")
    
    for container in $containers; do
        echo ""
        echo "=== Container: $container ==="
        verify_container_security "$container"
    done
}
