#!/usr/bin/env bats
# Tests for lib/config.sh - Profile system, INI helpers, consolidated installations

load test_helper

setup() {
    setup_temp_dir
    load_config
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Profile packages
# =============================================================================

@test "get_profile_packages: core returns expected packages" {
    local result
    result=$(get_profile_packages "core")
    [[ "$result" == *"gcc"* ]]
    [[ "$result" == *"git"* ]]
    [[ "$result" == *"tmux"* ]]
}

@test "get_profile_packages: python returns empty (managed by uv)" {
    local result
    result=$(get_profile_packages "python")
    [[ -z "$result" ]]
}

@test "get_profile_packages: rust returns empty (managed by rustup)" {
    local result
    result=$(get_profile_packages "rust")
    [[ -z "$result" ]]
}

@test "get_profile_packages: unknown profile returns empty" {
    local result
    result=$(get_profile_packages "nonexistent")
    [[ -z "$result" ]]
}

@test "get_profile_packages: c returns debugger packages" {
    local result
    result=$(get_profile_packages "c")
    [[ "$result" == *"gdb"* ]]
    [[ "$result" == *"valgrind"* ]]
}

@test "get_profile_packages: shell includes vim and nano" {
    local result
    result=$(get_profile_packages "shell")
    [[ "$result" == *"vim"* ]]
    [[ "$result" == *"nano"* ]]
}

@test "get_profile_packages: networking includes ping and traceroute" {
    local result
    result=$(get_profile_packages "networking")
    [[ "$result" == *"iputils-ping"* ]]
    [[ "$result" == *"traceroute"* ]]
    [[ "$result" == *"netcat-openbsd"* ]]
    [[ "$result" == *"net-tools"* ]]
}

# =============================================================================
# Profile descriptions
# =============================================================================

@test "get_profile_description: core has description" {
    local result
    result=$(get_profile_description "core")
    [[ -n "$result" ]]
    [[ "$result" == *"Core"* ]]
}

@test "get_profile_description: every builtin profile has a description" {
    for p in $(_builtin_profile_names); do
        local desc
        desc=$(get_profile_description "$p")
        [[ -n "$desc" ]] || {
            echo "Profile '$p' has no description"
            return 1
        }
    done
}

@test "get_profile_description: unknown profile returns empty" {
    local result
    result=$(get_profile_description "nonexistent")
    [[ -z "$result" ]]
}

# =============================================================================
# Profile listing and existence
# =============================================================================

@test "get_all_profile_names: returns at least 17 profiles" {
    local result
    result=$(get_all_profile_names)
    local count
    count=$(echo "$result" | wc -w | tr -d ' ')
    [[ $count -ge 17 ]]
}

@test "get_all_profile_names: does not include removed profiles" {
    local result
    result=$(get_all_profile_names)
    [[ "$result" != *" openwrt "* ]]
    [[ "$result" != *" web "* ]]
    [[ "$result" != *" security "* ]]
    [[ "$result" != *" datascience "* ]]
}

@test "profile_exists: core exists" {
    profile_exists "core"
}

@test "profile_exists: python exists" {
    profile_exists "python"
}

@test "profile_exists: nonexistent does not exist" {
    ! profile_exists "this_does_not_exist"
}

@test "profile_exists: removed profiles still return true for graceful migration" {
    profile_exists "openwrt"
    profile_exists "web"
    profile_exists "security"
    profile_exists "datascience"
}

# =============================================================================
# Removed profiles graceful migration
# =============================================================================

@test "_is_removed_profile: identifies removed profiles" {
    _is_removed_profile "openwrt"
    _is_removed_profile "web"
    _is_removed_profile "security"
    _is_removed_profile "datascience"
}

@test "_is_removed_profile: does not flag active profiles" {
    ! _is_removed_profile "core"
    ! _is_removed_profile "rust"
    ! _is_removed_profile "python"
}

# =============================================================================
# Consolidated profile installations
# =============================================================================

@test "generate_consolidated_profile_installations: merges apt packages" {
    local result
    result=$(generate_consolidated_profile_installations "core" "shell")
    # Should produce a single apt-get line with packages from both profiles
    local apt_lines
    apt_lines=$(printf '%s\n' "$result" | grep -c '^RUN apt-get')
    [[ $apt_lines -eq 1 ]]
}

@test "generate_consolidated_profile_installations: deduplicates packages" {
    local result
    result=$(generate_consolidated_profile_installations "core" "core")
    # git appears in core; should only appear once in the deduplicated output
    local git_count
    git_count=$(printf '%s\n' "$result" | grep -o ' git ' | wc -l | tr -d ' ')
    [[ $git_count -le 1 ]]
}

@test "generate_consolidated_profile_installations: skips removed profiles with warning" {
    local result stderr_output
    stderr_output=$(generate_consolidated_profile_installations "core" "openwrt" 2>&1 1>/dev/null)
    [[ "$stderr_output" == *"removed"* ]]
    [[ "$stderr_output" == *"openwrt"* ]]
}

@test "generate_consolidated_profile_installations: handles empty input" {
    local result
    result=$(generate_consolidated_profile_installations)
    [[ -z "$result" ]]
}

# =============================================================================
# _read_ini
# =============================================================================

@test "_read_ini: reads value from INI section" {
    local ini_file="$TEST_TEMP_DIR/test.ini"
    cat > "$ini_file" << 'EOF'
[section1]
key1 = value1
key2 = value2

[section2]
key3 = value3
EOF
    local result
    result=$(_read_ini "$ini_file" "section1" "key1")
    [[ "$result" == "value1" ]]
}

@test "_read_ini: returns correct section" {
    local ini_file="$TEST_TEMP_DIR/test.ini"
    cat > "$ini_file" << 'EOF'
[section1]
name = alice

[section2]
name = bob
EOF
    local result
    result=$(_read_ini "$ini_file" "section2" "name")
    [[ "$result" == "bob" ]]
}

@test "_read_ini: returns empty for missing key" {
    local ini_file="$TEST_TEMP_DIR/test.ini"
    cat > "$ini_file" << 'EOF'
[section1]
key1 = value1
EOF
    local result
    result=$(_read_ini "$ini_file" "section1" "missing")
    [[ -z "$result" ]]
}

@test "_read_ini: returns empty for missing file" {
    local result
    result=$(_read_ini "/nonexistent" "section" "key" || true)
    [[ -z "$result" ]]
}

# =============================================================================
# read_config_value
# =============================================================================

@test "read_config_value: reads value from config" {
    local config="$TEST_TEMP_DIR/config.ini"
    cat > "$config" << 'EOF'
[resources]
memory = 4g
cpus = 2
EOF
    local result
    result=$(read_config_value "$config" "resources" "memory")
    [[ "$result" == "4g" ]]
}

@test "read_config_value: returns failure for missing file" {
    ! read_config_value "/nonexistent" "section" "key"
}

# =============================================================================
# read_profile_section / update_profile_section
# =============================================================================

@test "read_profile_section: reads items from section" {
    local pf="$TEST_TEMP_DIR/profiles.ini"
    cat > "$pf" << 'EOF'
[profiles]
python
rust
go
EOF
    local result
    result=$(read_profile_section "$pf" "profiles")
    [[ "$result" == *"python"* ]]
    [[ "$result" == *"rust"* ]]
    [[ "$result" == *"go"* ]]
}

@test "read_profile_section: returns empty for missing section" {
    local pf="$TEST_TEMP_DIR/profiles.ini"
    printf '[other]\nfoo\n' > "$pf"
    local result
    result=$(read_profile_section "$pf" "profiles")
    [[ -z "$result" ]]
}

@test "update_profile_section: adds items to new section" {
    local pf="$TEST_TEMP_DIR/profiles.ini"
    touch "$pf"
    update_profile_section "$pf" "profiles" "python" "rust"
    local result
    result=$(read_profile_section "$pf" "profiles")
    [[ "$result" == *"python"* ]]
    [[ "$result" == *"rust"* ]]
}

@test "update_profile_section: deduplicates items" {
    local pf="$TEST_TEMP_DIR/profiles.ini"
    cat > "$pf" << 'EOF'
[profiles]
python
EOF
    update_profile_section "$pf" "profiles" "python" "rust"
    local count
    count=$(grep -c "python" "$pf")
    [[ "$count" == "1" ]]
}

# =============================================================================
# Custom profiles
# =============================================================================

@test "get_custom_profile_names: returns nothing when no custom dir" {
    local result
    result=$(get_custom_profile_names)
    [[ -z "$result" ]]
}

@test "custom_profile_exists: returns false for nonexistent" {
    ! custom_profile_exists "myprofile"
}

@test "custom_profile_exists: returns true when file exists" {
    mkdir -p "$HOME/.claudebox/custom-profiles"
    printf '# My custom profile\nRUN echo hello\n' > "$HOME/.claudebox/custom-profiles/myprofile.sh"
    custom_profile_exists "myprofile"
}

@test "get_custom_profile_description: extracts first comment line" {
    mkdir -p "$HOME/.claudebox/custom-profiles"
    printf '# My awesome tools\nRUN apt-get install -y foo\n' > "$HOME/.claudebox/custom-profiles/mytools.sh"
    local result
    result=$(get_custom_profile_description "mytools")
    [[ "$result" == "My awesome tools" ]]
}

@test "profile_exists: finds custom profiles" {
    mkdir -p "$HOME/.claudebox/custom-profiles"
    printf '# test\n' > "$HOME/.claudebox/custom-profiles/customtest.sh"
    profile_exists "customtest"
}

@test "get_all_profile_names: includes custom profiles" {
    mkdir -p "$HOME/.claudebox/custom-profiles"
    printf '# test\n' > "$HOME/.claudebox/custom-profiles/customtest.sh"
    local result
    result=$(get_all_profile_names)
    [[ "$result" == *"customtest"* ]]
}
