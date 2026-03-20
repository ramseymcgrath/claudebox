#!/usr/bin/env bats
# Tests for lib/os.sh - OS detection, MD5 helpers

load test_helper

setup() {
    setup_temp_dir
    load_os
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# OS detection
# =============================================================================

@test "HOST_OS: is set to macOS or linux" {
    [[ "$HOST_OS" == "macOS" ]] || [[ "$HOST_OS" == "linux" ]]
}

# =============================================================================
# MD5 command detection
# =============================================================================

@test "set_md5_command: MD5_CMD is set" {
    [[ -n "$MD5_CMD" ]]
}

@test "set_md5_command: MD5_EXTRACT is set" {
    [[ -n "$MD5_EXTRACT" ]]
}

# =============================================================================
# md5_file
# =============================================================================

@test "md5_file: returns hash for existing file" {
    local tmpfile="$TEST_TEMP_DIR/md5test"
    printf 'hello world' > "$tmpfile"
    local result
    result=$(md5_file "$tmpfile")
    [[ -n "$result" ]]
    # MD5 should be 32 hex chars
    [[ ${#result} -eq 32 ]]
    [[ "$result" =~ ^[0-9a-f]{32}$ ]]
}

@test "md5_file: returns empty for missing file" {
    local result
    result=$(md5_file "/nonexistent/file")
    [[ -z "$result" ]]
}

@test "md5_file: deterministic for same content" {
    local f1="$TEST_TEMP_DIR/f1" f2="$TEST_TEMP_DIR/f2"
    printf 'same content' > "$f1"
    printf 'same content' > "$f2"
    local r1 r2
    r1=$(md5_file "$f1")
    r2=$(md5_file "$f2")
    [[ "$r1" == "$r2" ]]
}

@test "md5_file: different content produces different hash" {
    local f1="$TEST_TEMP_DIR/f1" f2="$TEST_TEMP_DIR/f2"
    printf 'content a' > "$f1"
    printf 'content b' > "$f2"
    local r1 r2
    r1=$(md5_file "$f1")
    r2=$(md5_file "$f2")
    [[ "$r1" != "$r2" ]]
}

# =============================================================================
# md5_string
# =============================================================================

@test "md5_string: returns 32 hex chars" {
    local result
    result=$(md5_string "test")
    [[ ${#result} -eq 32 ]]
    [[ "$result" =~ ^[0-9a-f]{32}$ ]]
}

@test "md5_string: deterministic" {
    local r1 r2
    r1=$(md5_string "hello")
    r2=$(md5_string "hello")
    [[ "$r1" == "$r2" ]]
}

@test "md5_string: different strings produce different hashes" {
    local r1 r2
    r1=$(md5_string "alpha")
    r2=$(md5_string "beta")
    [[ "$r1" != "$r2" ]]
}

@test "md5_string: known MD5 of empty string" {
    local result
    result=$(md5_string "")
    # MD5 of empty string is d41d8cd98f00b204e9800998ecf8427e
    [[ "$result" == "d41d8cd98f00b204e9800998ecf8427e" ]]
}
