#!/usr/bin/env bats

################################################################################
# Bats Tests for Secrets Module
# License: MIT
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"

load "${SRC_DIR}/utils"
load "${SRC_DIR}/secrets"

@test "generate_mtproxy_secret should produce 32-char hex string" {
    run generate_mtproxy_secret
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-fA-F]+$ ]]
    [ ${#output} -eq 32 ]
}

@test "generate_tag should return valid tag" {
    run generate_tag
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-fA-F]+$ ]]
}

@test "validate_secret should accept valid secrets" {
    run validate_secret "0123456789abcdef0123456789abcdef"
    [ "$status" -eq 0 ]
    
    run validate_secret "ABCDEF0123456789ABCDEF0123456789"
    [ "$status" -eq 0 ]
}

@test "validate_secret should reject invalid secrets" {
    run validate_secret "invalid_secret_with_underscores"
    [ "$status" -eq 1 ]
    
    run validate_secret "tooshort"
    [ "$status" -eq 1 ]
    
    run validate_secret ""
    [ "$status" -eq 1 ]
}

@test "create_env_file should create file with correct content" {
    local test_dir="/tmp/test_mtproxy_$$"
    mkdir -p "$test_dir"
    
    run create_env_file "$test_dir" "443" "abcdef0123456789abcdef0123456789" "d00df00d" "www.telegram.org"
    [ "$status" -eq 0 ]
    [ -f "${test_dir}/.env" ]
    
    # Check permissions
    local perms
    perms=$(stat -c "%a" "${test_dir}/.env")
    [ "$perms" = "600" ]
    
    # Check content
    grep -q "^PORT=443$" "${test_dir}/.env"
    grep -q "^SECRET=abcdef0123456789abcdef0123456789$" "${test_dir}/.env"
    grep -q "^TAG=d00df00d$" "${test_dir}/.env"
    grep -q "^TLS_DOMAIN=www.telegram.org$" "${test_dir}/.env"
    
    rm -rf "$test_dir"
}

@test "get_secret should read from env file" {
    local test_dir="/tmp/test_mtproxy_get_$$"
    mkdir -p "$test_dir"
    
    echo "SECRET=testsecret123" > "${test_dir}/.env"
    
    run get_secret "${test_dir}/.env"
    [ "$status" -eq 0 ]
    [ "$output" = "testsecret123" ]
    
    rm -rf "$test_dir"
}

@test "get_port should read from env file" {
    local test_dir="/tmp/test_mtproxy_port_$$"
    mkdir -p "$test_dir"
    
    echo "PORT=8443" > "${test_dir}/.env"
    
    run get_port "${test_dir}/.env"
    [ "$status" -eq 0 ]
    [ "$output" = "8443" ]
    
    rm -rf "$test_dir"
}

@test "get_env_value should return empty when variable is missing" {
    local test_dir="/tmp/test_mtproxy_env_var_$$"
    mkdir -p "$test_dir"
    echo "PORT=8443" > "${test_dir}/.env"

    run get_env_value "${test_dir}/.env" "SECRET"
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    rm -rf "$test_dir"
}

@test "rotate_secret should update secret in env file" {
    local test_dir="/tmp/test_mtproxy_rotate_$$"
    mkdir -p "$test_dir"
    
    echo "SECRET=oldsecret12345678901234567890" > "${test_dir}/.env"
    chmod 600 "${test_dir}/.env"
    
    run rotate_secret "${test_dir}/.env"
    [ "$status" -eq 0 ]
    
    # Verify new secret is different
    local new_secret
    new_secret=$(get_secret "${test_dir}/.env")
    [ "$new_secret" != "oldsecret12345678901234567890" ]
    
    # Verify backup was created
    ls "${test_dir}/.env.backup."* >/dev/null 2>&1
    
    rm -rf "$test_dir"
}

@test "rotate_secret should preserve env ownership metadata" {
    local test_dir="/tmp/test_mtproxy_rotate_owner_$$"
    mkdir -p "$test_dir"

    echo "SECRET=oldsecret12345678901234567890" > "${test_dir}/.env"
    chmod 600 "${test_dir}/.env"

    local original_owner
    original_owner=$(stat -c "%u:%g" "${test_dir}/.env")

    run rotate_secret "${test_dir}/.env" "abcdef0123456789abcdef0123456789"
    [ "$status" -eq 0 ]

    local rotated_owner
    rotated_owner=$(stat -c "%u:%g" "${test_dir}/.env")
    [ "$rotated_owner" = "$original_owner" ]

    rm -rf "$test_dir"
}

@test "rotate_secret should append SECRET if missing" {
    local test_dir="/tmp/test_mtproxy_rotate_missing_$$"
    mkdir -p "$test_dir"

    cat > "${test_dir}/.env" <<EOF
PORT=443
TAG=d00df00d
EOF
    chmod 600 "${test_dir}/.env"

    run rotate_secret "${test_dir}/.env" "abcdef0123456789abcdef0123456789"
    [ "$status" -eq 0 ]
    grep -q "^SECRET=abcdef0123456789abcdef0123456789$" "${test_dir}/.env"

    rm -rf "$test_dir"
}

@test "mask_secret should hide most of the secret" {
    run mask_secret "abcdef0123456789abcdef0123456789"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^abcd\.\.\.6789$ ]]
}

@test "mask_secret should handle short secrets" {
    run mask_secret "short"
    [ "$status" -eq 0 ]
    [ "$output" = "****" ]
}

@test "generate_connection_link should produce valid links" {
    run generate_connection_link "192.168.1.1" "443" "abcdef0123456789abcdef0123456789"
    [ "$status" -eq 0 ]
    [[ "$output" =~ tg://proxy\?server=192\.168\.1\.1\&port=443\&secret=abcdef0123456789abcdef0123456789 ]]
    [[ "$output" =~ https://t\.me/proxy\?server=192\.168\.1\.1\&port=443\&secret=abcdef0123456789abcdef0123456789 ]]
}

@test "validate_env_file should detect missing file" {
    run validate_env_file "/nonexistent/.env"
    [ "$status" -ne 0 ]
}

@test "validate_env_file should detect missing variables" {
    local test_dir="/tmp/test_mtproxy_validate_$$"
    mkdir -p "$test_dir"
    
    echo "PORT=443" > "${test_dir}/.env"
    chmod 600 "${test_dir}/.env"
    
    run validate_env_file "${test_dir}/.env"
    [ "$status" -ne 0 ]
    
    rm -rf "$test_dir"
}

@test "secure_delete should remove file" {
    local test_file="/tmp/test_secure_delete_$$"
    echo "sensitive data" > "$test_file"
    
    run secure_delete "$test_file"
    [ "$status" -eq 0 ]
    [ ! -f "$test_file" ]
}
