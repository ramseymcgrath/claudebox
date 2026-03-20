#!/usr/bin/env bash
# Shared test helper for bats tests
# Sources library modules with minimal mocked dependencies

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TEST_DIR")"

# Create a temp directory for each test run
setup_temp_dir() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
    export HOME="$TEST_TEMP_DIR/home"
    mkdir -p "$HOME"
    mkdir -p "$HOME/.claudebox/projects"
}

teardown_temp_dir() {
    if [[ -n "${TEST_TEMP_DIR:-}" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Source common.sh (provides cecho, error, warn, etc.)
# Override error() so it doesn't exit during tests
load_common() {
    source "$ROOT_DIR/lib/common.sh"
    # Override error to not exit
    error() { printf "ERROR: %s\n" "$1" >&2; return "${2:-1}"; }
}

# Source config.sh (profile functions)
load_config() {
    load_common
    source "$ROOT_DIR/lib/config.sh"
}

# Source cli.sh (CLI parsing)
# Note: cli.sh uses readonly arrays which can't be exported across bats subshells.
# Each test that calls parse_cli_args must source cli.sh directly.
load_cli() {
    source "$ROOT_DIR/lib/cli.sh"
}

# Source cli.sh fresh in a test function (workaround for readonly arrays)
source_cli() {
    source "$ROOT_DIR/lib/cli.sh"
}

# Source project.sh (slot management, CRC32, etc.)
# Requires some env vars and stubs
load_project() {
    load_common
    export VERBOSE="false"
    export SCRIPT_DIR="$ROOT_DIR"
    export CLAUDEBOX_SCRIPT_DIR="$ROOT_DIR"
    # Stub functions that project.sh calls
    setup_claude_agent_command() { :; }
    sync_commands_to_project() { :; }
    export -f setup_claude_agent_command sync_commands_to_project
    source "$ROOT_DIR/lib/project.sh"
}

# Source os.sh (MD5 helpers, OS detection)
load_os() {
    load_common
    source "$ROOT_DIR/lib/os.sh"
}

# Mock docker command for tests that need it
mock_docker() {
    # $1 = what "docker ps --format" should output (one name per line)
    local running_containers="${1:-}"
    docker() {
        case "$1" in
            ps)
                if [[ "$*" == *"--format"* ]]; then
                    if [[ -n "$running_containers" ]]; then
                        printf '%s\n' "$running_containers"
                    fi
                fi
                ;;
            image)
                if [[ "$2" == "inspect" ]]; then
                    return 1  # image doesn't exist by default
                fi
                ;;
            *)
                command docker "$@"
                ;;
        esac
    }
    export -f docker
}
