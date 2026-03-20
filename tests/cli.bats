#!/usr/bin/env bats
# Tests for lib/cli.sh - CLI argument parsing and command routing
#
# IMPORTANT: cli.sh uses readonly arrays at file scope. Sourcing it from
# within a function makes those arrays function-local. We must source
# cli.sh directly in each test, not through a wrapper function.

load test_helper

# =============================================================================
# parse_cli_args - four-bucket architecture
# =============================================================================

@test "parse_cli_args: no arguments produces empty buckets" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args
    [[ ${#host_flags[@]} -eq 0 ]]
    [[ ${#control_flags[@]} -eq 0 ]]
    [[ -z "$script_command" ]]
    [[ ${#pass_through[@]} -eq 0 ]]
}

@test "parse_cli_args: --verbose goes to host flags" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args --verbose
    [[ "${host_flags[0]}" == "--verbose" ]]
    [[ -z "$script_command" ]]
}

@test "parse_cli_args: rebuild goes to host flags" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args rebuild
    [[ "${host_flags[0]}" == "rebuild" ]]
    [[ -z "$script_command" ]]
}

@test "parse_cli_args: --enable-sudo goes to control flags" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args --enable-sudo
    [[ "${control_flags[0]}" == "--enable-sudo" ]]
}

@test "parse_cli_args: --disable-firewall goes to control flags" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args --disable-firewall
    [[ "${control_flags[0]}" == "--disable-firewall" ]]
}

@test "parse_cli_args: shell recognized as script command" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args shell
    [[ "$script_command" == "shell" ]]
}

@test "parse_cli_args: help recognized as script command" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args help
    [[ "$script_command" == "help" ]]
}

@test "parse_cli_args: -h recognized as script command" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args -h
    [[ "$script_command" == "-h" ]]
}

@test "parse_cli_args: profiles recognized as script command" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args profiles
    [[ "$script_command" == "profiles" ]]
}

@test "parse_cli_args: unknown args go to pass-through" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args "some-random-arg" "another"
    [[ ${#pass_through[@]} -eq 2 ]]
    [[ "${pass_through[0]}" == "some-random-arg" ]]
    [[ "${pass_through[1]}" == "another" ]]
}

@test "parse_cli_args: only first script command wins" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args shell help
    [[ "$script_command" == "shell" ]]
    [[ "${pass_through[0]}" == "help" ]]
}

@test "parse_cli_args: mixed arguments sorted correctly" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args --verbose shell --enable-sudo "extra-arg"
    [[ "${host_flags[0]}" == "--verbose" ]]
    [[ "$script_command" == "shell" ]]
    [[ "${control_flags[0]}" == "--enable-sudo" ]]
    [[ "${pass_through[0]}" == "extra-arg" ]]
}

@test "parse_cli_args: all script commands are recognized" {
    source "$ROOT_DIR/lib/cli.sh"
    local commands=(shell create slot slots revoke profiles projects profile info help -h --help add remove install allowlist clean save project tmux kill doctor snapshot setup auth gateway vm agent mcp import unlink reinstall uninstall)
    for cmd in "${commands[@]}"; do
        parse_cli_args "$cmd"
        [[ "$script_command" == "$cmd" ]] || {
            echo "Command '$cmd' not recognized as script command"
            return 1
        }
    done
}

# =============================================================================
# process_host_flags
# =============================================================================

@test "process_host_flags: --verbose sets VERBOSE=true" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args --verbose
    CLI_HOST_FLAGS=("${host_flags[@]}")
    VERBOSE=false
    process_host_flags
    [[ "$VERBOSE" == "true" ]]
}

@test "process_host_flags: rebuild sets REBUILD=true" {
    source "$ROOT_DIR/lib/cli.sh"
    parse_cli_args rebuild
    CLI_HOST_FLAGS=("${host_flags[@]}")
    REBUILD=false
    process_host_flags
    [[ "$REBUILD" == "true" ]]
}

# =============================================================================
# get_command_requirements
# =============================================================================

@test "get_command_requirements: help requires none" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "help")" == "none" ]]
}

@test "get_command_requirements: profiles requires none" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "profiles")" == "none" ]]
}

@test "get_command_requirements: projects requires none" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "projects")" == "none" ]]
}

@test "get_command_requirements: clean requires none" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "clean")" == "none" ]]
}

@test "get_command_requirements: info requires image" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "info")" == "image" ]]
}

@test "get_command_requirements: profile requires image" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "profile")" == "image" ]]
}

@test "get_command_requirements: snapshot requires image" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "snapshot")" == "image" ]]
}

@test "get_command_requirements: shell requires docker" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "shell")" == "docker" ]]
}

@test "get_command_requirements: empty command requires docker" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "")" == "docker" ]]
}

@test "get_command_requirements: unknown command requires docker" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "something-unknown")" == "docker" ]]
}

@test "get_command_requirements: agent list requires none" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "agent" "list")" == "none" ]]
}

@test "get_command_requirements: agent search requires none" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "agent" "search")" == "none" ]]
}

@test "get_command_requirements: agent install requires docker" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "agent" "install")" == "docker" ]]
}

@test "get_command_requirements: mcp install requires image" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "mcp" "install")" == "image" ]]
}

@test "get_command_requirements: mcp list requires image" {
    source "$ROOT_DIR/lib/cli.sh"
    [[ "$(get_command_requirements "mcp" "list")" == "image" ]]
}

# =============================================================================
# requires_slot
# =============================================================================

@test "requires_slot: shell needs a slot" {
    source "$ROOT_DIR/lib/cli.sh"
    requires_slot "shell"
}

@test "requires_slot: empty command needs a slot" {
    source "$ROOT_DIR/lib/cli.sh"
    requires_slot ""
}

@test "requires_slot: create needs a slot" {
    source "$ROOT_DIR/lib/cli.sh"
    requires_slot "create"
}

@test "requires_slot: help does not need a slot" {
    source "$ROOT_DIR/lib/cli.sh"
    ! requires_slot "help"
}

@test "requires_slot: profiles does not need a slot" {
    source "$ROOT_DIR/lib/cli.sh"
    ! requires_slot "profiles"
}

@test "requires_slot: info does not need a slot" {
    source "$ROOT_DIR/lib/cli.sh"
    ! requires_slot "info"
}
