#!/usr/bin/env bats

################################################################################
# Bats Tests for Utils Module
# License: MIT
################################################################################

load "../src/utils"

@test "check_root should pass when running as root" {
    skip "Requires root privileges - manual test only"
    run check_root
    [ "$status" -eq 0 ]
}

@test "validate_ip should accept valid IPv4 addresses" {
    run validate_ip "192.168.1.1"
    [ "$status" -eq 0 ]
    
    run validate_ip "10.0.0.1"
    [ "$status" -eq 0 ]
    
    run validate_ip "255.255.255.255"
    [ "$status" -eq 0 ]
}

@test "validate_ip should reject invalid IPv4 addresses" {
    run validate_ip "256.1.1.1"
    [ "$status" -eq 1 ]
    
    run validate_ip "192.168.1"
    [ "$status" -eq 1 ]
    
    run validate_ip "invalid"
    [ "$status" -eq 1 ]
    
    run validate_ip ""
    [ "$status" -eq 1 ]
}

@test "generate_hex_secret should produce valid hex string" {
    run generate_hex_secret 16
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]+$ ]]
    [ ${#output} -eq 32 ]
}

@test "generate_hex_secret default length" {
    run generate_hex_secret
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]+$ ]]
}

@test "generate_random_string should produce alphanumeric string" {
    run generate_random_string 32
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[a-zA-Z0-9]+$ ]]
    [ ${#output} -eq 32 ]
}

@test "create_secure_file should create file with correct permissions" {
    local test_file="/tmp/test_secure_$$"
    run create_secure_file "$test_file" "test content" "600"
    [ "$status" -eq 0 ]
    [ -f "$test_file" ]
    
    local perms
    perms=$(stat -c "%a" "$test_file")
    [ "$perms" = "600" ]
    
    rm -f "$test_file"
}

@test "command_exists should detect installed commands" {
    run command_exists "bash"
    [ "$status" -eq 0 ]
    
    run command_exists "ls"
    [ "$status" -eq 0 ]
}

@test "command_exists should return false for non-existent commands" {
    run command_exists "nonexistent_command_xyz"
    [ "$status" -eq 1 ]
}

@test "trim should remove leading and trailing whitespace" {
    result=$(trim "  hello world  ")
    [ "$result" = "hello world" ]
    
    result=$(trim "no_spaces")
    [ "$result" = "no_spaces" ]
}

@test "detect_available_ram should return positive integer" {
    run detect_available_ram
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -gt 0 ]
}

@test "calculate_memory_limit should return valid memory string" {
    run calculate_memory_limit
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+[MG]$ ]]
}

@test "calculate_cpu_limit should return valid CPU string" {
    run calculate_cpu_limit
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "ask_yes_no should handle yes response" {
    skip "Interactive test - manual verification required"
    # This test requires interactive input
    echo "y" | ask_yes_no "Test question?"
    [ "$status" -eq 0 ]
}

@test "log should output colored messages" {
    run log "INFO" "Test message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ \[INFO\] ]]
    
    run log "ERROR" "Error message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ \[ERROR\] ]]
}

@test "wait_for_condition should timeout correctly" {
    run wait_for_condition "false" 2 1
    [ "$status" -eq 1 ]
}

@test "get_public_ip should return valid IP or fail gracefully" {
    # This test may fail in isolated environments
    run get_public_ip
    if [ "$status" -eq 0 ]; then
        [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        [[ "$output" =~ : ]] # IPv6
    fi
}
