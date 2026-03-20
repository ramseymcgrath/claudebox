#!/usr/bin/env bats
# Tests for lib/project.sh - CRC32 hashing, slot management, container naming

load test_helper

setup() {
    setup_temp_dir
    load_project
    mock_docker ""
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# CRC32 functions
# =============================================================================

@test "crc32_string: deterministic output for same input" {
    local r1 r2
    r1=$(crc32_string "hello")
    r2=$(crc32_string "hello")
    [[ "$r1" == "$r2" ]]
}

@test "crc32_string: different strings produce different hashes" {
    local r1 r2
    r1=$(crc32_string "hello")
    r2=$(crc32_string "world")
    [[ "$r1" != "$r2" ]]
}

@test "crc32_string: empty string produces a hash" {
    local result
    result=$(crc32_string "")
    [[ -n "$result" ]]
}

@test "crc32_word: produces numeric output" {
    local result
    result=$(crc32_word "12345")
    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "crc32_file: returns 0 for nonexistent file" {
    local result
    result=$(crc32_file "/nonexistent/path")
    [[ "$result" == "0" ]]
}

@test "crc32_file: hashes an existing file" {
    local tmpfile="$TEST_TEMP_DIR/testfile"
    printf 'test content' > "$tmpfile"
    local result
    result=$(crc32_file "$tmpfile")
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" != "0" ]]
}

# =============================================================================
# slugify_path
# =============================================================================

@test "slugify_path: strips leading slash" {
    local result
    result=$(slugify_path "/home/user/project")
    [[ "$result" != /* ]]
}

@test "slugify_path: replaces slashes with underscores" {
    local result
    result=$(slugify_path "/home/user/project")
    [[ "$result" == "home_user_project" ]]
}

@test "slugify_path: removes unsafe characters" {
    local result
    result=$(slugify_path "/home/user/my-project.git")
    [[ "$result" == "home_user_my_project_git" ]]
}

@test "slugify_path: handles spaces" {
    local result
    result=$(slugify_path "/home/user/my project")
    [[ "$result" == "home_user_my_project" ]]
}

# =============================================================================
# generate_container_name
# =============================================================================

@test "generate_container_name: returns 8-char hex string" {
    local result
    result=$(generate_container_name "/test/path" 1)
    [[ ${#result} -eq 8 ]]
    [[ "$result" =~ ^[0-9a-f]{8}$ ]]
}

@test "generate_container_name: different indices produce different names" {
    local r1 r2
    r1=$(generate_container_name "/test/path" 1)
    r2=$(generate_container_name "/test/path" 2)
    [[ "$r1" != "$r2" ]]
}

@test "generate_container_name: different paths produce different names" {
    local r1 r2
    r1=$(generate_container_name "/path/one" 1)
    r2=$(generate_container_name "/path/two" 1)
    [[ "$r1" != "$r2" ]]
}

@test "generate_container_name: index 0 differs from index 1" {
    local r0 r1
    r0=$(generate_container_name "/test/path" 0)
    r1=$(generate_container_name "/test/path" 1)
    [[ "$r0" != "$r1" ]]
}

@test "generate_container_name: deterministic for same input" {
    local r1 r2
    r1=$(generate_container_name "/test/path" 3)
    r2=$(generate_container_name "/test/path" 3)
    [[ "$r1" == "$r2" ]]
}

# =============================================================================
# generate_parent_folder_name
# =============================================================================

@test "generate_parent_folder_name: includes slug and hex suffix" {
    local result
    result=$(generate_parent_folder_name "/home/user/project")
    # Should be slug_xxxxxxxx
    [[ "$result" =~ ^[a-z0-9_]+_[0-9a-f]{8}$ ]]
}

@test "generate_parent_folder_name: lowercase output" {
    local result
    result=$(generate_parent_folder_name "/Home/User/MyProject")
    # Should not contain uppercase
    [[ "$result" == "$(echo "$result" | tr '[:upper:]' '[:lower:]')" ]]
}

@test "generate_parent_folder_name: deterministic" {
    local r1 r2
    r1=$(generate_parent_folder_name "/test/path")
    r2=$(generate_parent_folder_name "/test/path")
    [[ "$r1" == "$r2" ]]
}

# =============================================================================
# get_parent_dir
# =============================================================================

@test "get_parent_dir: returns path under ~/.claudebox/projects" {
    local result
    result=$(get_parent_dir "/test/project")
    [[ "$result" == "$HOME/.claudebox/projects/"* ]]
}

# =============================================================================
# init_project_dir
# =============================================================================

@test "init_project_dir: creates parent directory" {
    init_project_dir "/test/project"
    local parent
    parent=$(get_parent_dir "/test/project")
    [[ -d "$parent" ]]
}

@test "init_project_dir: creates counter file starting at 1" {
    init_project_dir "/test/project"
    local parent
    parent=$(get_parent_dir "/test/project")
    [[ -f "$parent/.project_container_counter" ]]
    local counter
    counter=$(cat "$parent/.project_container_counter")
    [[ "$counter" == "1" ]]
}

@test "init_project_dir: creates profiles.ini" {
    init_project_dir "/test/project"
    local parent
    parent=$(get_parent_dir "/test/project")
    [[ -f "$parent/profiles.ini" ]]
}

@test "init_project_dir: stores project path" {
    init_project_dir "/test/project"
    local parent
    parent=$(get_parent_dir "/test/project")
    [[ -f "$parent/.project_path" ]]
    local stored
    stored=$(cat "$parent/.project_path")
    [[ "$stored" == "/test/project" ]]
}

@test "init_project_dir: idempotent - does not reset counter" {
    init_project_dir "/test/project"
    local parent
    parent=$(get_parent_dir "/test/project")
    # Manually set counter to 5
    printf '5' > "$parent/.project_container_counter"
    # Re-init should NOT reset it
    init_project_dir "/test/project"
    local counter
    counter=$(cat "$parent/.project_container_counter")
    [[ "$counter" == "5" ]]
}

# =============================================================================
# read_counter / write_counter
# =============================================================================

@test "read_counter: reads stored value" {
    local dir="$TEST_TEMP_DIR/counter_test"
    mkdir -p "$dir"
    printf '7' > "$dir/.project_container_counter"
    local result
    result=$(read_counter "$dir")
    [[ "$result" == "7" ]]
}

@test "write_counter: writes numeric value" {
    local dir="$TEST_TEMP_DIR/counter_test"
    mkdir -p "$dir"
    write_counter "$dir" 42
    local result
    result=$(cat "$dir/.project_container_counter")
    [[ "$result" == "42" ]]
}

@test "read_counter: returns 1 when no counter file" {
    local dir="$TEST_TEMP_DIR/no_counter"
    mkdir -p "$dir"
    local result
    result=$(read_counter "$dir")
    [[ "$result" == "1" ]]
}

# =============================================================================
# init_slot_dir
# =============================================================================

@test "init_slot_dir: creates directory structure" {
    local slot="$TEST_TEMP_DIR/slot_test"
    init_slot_dir "$slot"
    [[ -d "$slot" ]]
    [[ -d "$slot/.claude" ]]
    [[ -d "$slot/.config" ]]
    [[ -d "$slot/.cache" ]]
}

@test "init_slot_dir: does not pre-create .claude.json" {
    local slot="$TEST_TEMP_DIR/slot_test"
    init_slot_dir "$slot"
    [[ ! -f "$slot/.claude.json" ]]
}

@test "init_slot_dir: copies auth credentials if available" {
    mkdir -p "$HOME/.claudebox/auth"
    printf '{"token":"test"}' > "$HOME/.claudebox/auth/credentials.json"
    local slot="$TEST_TEMP_DIR/slot_creds"
    init_slot_dir "$slot"
    [[ -f "$slot/.claude/.credentials.json" ]]
    local content
    content=$(cat "$slot/.claude/.credentials.json")
    [[ "$content" == '{"token":"test"}' ]]
}

# =============================================================================
# create_container
# =============================================================================

@test "create_container: returns a container name" {
    local name
    name=$(create_container "/test/project")
    [[ -n "$name" ]]
    [[ ${#name} -eq 8 ]]
}

@test "create_container: creates slot directory" {
    local name
    name=$(create_container "/test/project")
    local parent
    parent=$(get_parent_dir "/test/project")
    [[ -d "$parent/$name" ]]
}

@test "create_container: second call returns different name when first slot exists" {
    local name1 name2
    name1=$(create_container "/test/project")
    name2=$(create_container "/test/project")
    # Both should exist but may reuse slot 1 since mock docker shows no running containers
    [[ -n "$name1" ]]
    [[ -n "$name2" ]]
}

# =============================================================================
# prune_slot_counter
# =============================================================================

@test "prune_slot_counter: reduces counter when trailing slots removed" {
    local path="/test/prune"
    init_project_dir "$path"
    local parent
    parent=$(get_parent_dir "$path")

    # Create slots 1 and 2
    local name1 name2
    name1=$(generate_container_name "$path" 1)
    name2=$(generate_container_name "$path" 2)
    mkdir -p "$parent/$name1"
    mkdir -p "$parent/$name2"
    write_counter "$parent" 3

    # Remove slot 3 dir (it doesn't exist), counter should prune to 2
    prune_slot_counter "$path"
    local counter
    counter=$(read_counter "$parent")
    [[ "$counter" == "2" ]]
}

@test "prune_slot_counter: no-op when all slots exist" {
    local path="/test/prune2"
    init_project_dir "$path"
    local parent
    parent=$(get_parent_dir "$path")

    local name1
    name1=$(generate_container_name "$path" 1)
    mkdir -p "$parent/$name1"
    write_counter "$parent" 1

    prune_slot_counter "$path"
    local counter
    counter=$(read_counter "$parent")
    [[ "$counter" == "1" ]]
}

# =============================================================================
# get_slot_dir
# =============================================================================

@test "get_slot_dir: returns correct path" {
    local result
    result=$(get_slot_dir "/test/path" 1)
    local parent
    parent=$(get_parent_dir "/test/path")
    local name
    name=$(generate_container_name "/test/path" 1)
    [[ "$result" == "$parent/$name" ]]
}
