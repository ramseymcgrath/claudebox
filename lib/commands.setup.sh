#!/usr/bin/env bash
# Setup Command - Interactive setup wizard
# ============================================================================
# Command: setup
# Launches the Python TUI wizard, then applies the selected configuration.
# Falls back to a minimal Bash flow if Python 3 is not available.

# ── Apply results from the Python wizard ──────────────────────
# Reads KEY=value lines from a file and executes the corresponding actions.
_setup_apply_results() {
    local result_file="$1"

    # Parse result file into variables
    local profiles="" create_slot="" gateway_enabled=""
    local gateway_account_id="" gateway_id="" gateway_token=""
    local plugins="" enable_sudo="" disable_firewall=""

    while IFS='=' read -r key value; do
        case "$key" in
            PROFILES)           profiles="$value" ;;
            CREATE_SLOT)        create_slot="$value" ;;
            GATEWAY_ENABLED)    gateway_enabled="$value" ;;
            GATEWAY_ACCOUNT_ID) gateway_account_id="$value" ;;
            GATEWAY_ID)         gateway_id="$value" ;;
            GATEWAY_TOKEN)      gateway_token="$value" ;;
            PLUGINS)            plugins="$value" ;;
            ENABLE_SUDO)        enable_sudo="$value" ;;
            DISABLE_FIREWALL)   disable_firewall="$value" ;;
        esac
    done < "$result_file"

    # 1) Profiles
    if [[ -n "$profiles" ]]; then
        init_project_dir "$PROJECT_DIR"
        local profile_file
        profile_file=$(get_profile_file_path)
        # shellcheck disable=SC2086
        update_profile_section "$profile_file" "profiles" $profiles
        success "  Added profiles: $profiles"
    fi

    # 2) Create slot
    if [[ "$create_slot" == "yes" ]]; then
        local slot_name
        slot_name=$(create_container "$PROJECT_DIR")
        success "  Slot created: $slot_name"
    fi

    # 3) AI Gateway
    if [[ "$gateway_enabled" == "yes" ]] && [[ -n "$gateway_account_id" ]] && [[ -n "$gateway_id" ]]; then
        local gateway_env="$HOME/.claudebox/gateway.env"
        mkdir -p "$HOME/.claudebox"

        local base_url="https://gateway.ai.cloudflare.com/v1/${gateway_account_id}/${gateway_id}/anthropic"
        {
            printf 'ANTHROPIC_BASE_URL=%s\n' "$base_url"
            printf 'ENABLE_TOOL_SEARCH=true\n'
            if [[ -n "$gateway_token" ]]; then
                printf 'CF_AIG_TOKEN=%s\n' "$gateway_token"
            fi
        } > "$gateway_env"
        chmod 600 "$gateway_env"

        success "  AI Gateway configured: $base_url"
    fi

    # 4) Plugins
    if [[ -n "$plugins" ]]; then
        for plugin_name in $plugins; do
            printf "  Installing plugin: %s\n" "$plugin_name"
            _agent_run_in_container "install" "$plugin_name" 2>/dev/null || true
        done
        success "  Plugins installed"
    fi

    # 5) Default flags
    local flags_to_save=""
    if [[ "$enable_sudo" == "yes" ]]; then
        flags_to_save="--enable-sudo"
    fi
    if [[ "$disable_firewall" == "yes" ]]; then
        if [[ -n "$flags_to_save" ]]; then
            flags_to_save="$flags_to_save --disable-firewall"
        else
            flags_to_save="--disable-firewall"
        fi
    fi

    if [[ -n "$flags_to_save" ]]; then
        local flags_file="$HOME/.claudebox/default-flags"
        mkdir -p "$HOME/.claudebox"
        for flag in $flags_to_save; do
            printf '%s\n' "$flag"
        done > "$flags_file"
        success "  Saved default flags: $flags_to_save"
    fi
}

# ── Build the config blob that the Python wizard reads from stdin ──
_setup_build_config() {
    printf '[profiles]\n'
    for p in $(_builtin_profile_names); do
        if [[ -n "$p" ]]; then
            local desc
            desc=$(get_profile_description "$p")
            printf '%s|%s\n' "$p" "$desc"
        fi
    done

    # Custom profiles
    local custom_names
    custom_names=$(get_custom_profile_names 2>/dev/null || true)
    if [[ -n "$custom_names" ]]; then
        for p in $custom_names; do
            local desc
            desc=$(get_custom_profile_description "$p")
            printf '%s|%s\n' "$p" "$desc"
        done
    fi

    printf '[plugins]\n'
    printf 'commit-commands|Git commit, push, and PR creation\n'
    printf 'github|Official GitHub MCP server\n'
    printf 'typescript-lsp|TypeScript/JavaScript intelligence\n'
    printf 'pyright-lsp|Python type checking\n'
    printf 'context7|Version-specific library docs\n'
    printf 'security-guidance|Security issue warnings\n'
}

# ── Minimal Bash fallback (no Python 3 available) ────────────
_setup_fallback() {
    logo_small
    printf '\n'
    cecho "  ClaudeBox Setup (basic mode)" "$WHITE"
    printf "  ${DIM}Install Python 3 for the full interactive wizard.${NC}\n"
    printf "  ${DIM}Press Enter at any prompt to skip that step.${NC}\n\n"

    # Profiles
    printf "  ${CYAN}Profiles${NC} – enter names separated by spaces:\n"
    local profile_list
    profile_list=$(_builtin_profile_names)
    printf "  ${DIM}Available: %s${NC}\n" "$profile_list"
    printf "  ${WHITE}Selection:${NC} "
    local input
    IFS= read -r input 2>/dev/null || true

    if [[ -n "$input" ]]; then
        init_project_dir "$PROJECT_DIR"
        local profile_file
        profile_file=$(get_profile_file_path)
        # shellcheck disable=SC2086
        update_profile_section "$profile_file" "profiles" $input
        success "  Added profiles: $input"
    fi

    # Slot
    printf '\n  Create your first container slot? [Y/n] '
    local answer
    IFS= read -r answer 2>/dev/null || true
    answer="${answer:-y}"
    case "$answer" in
        [yY]*)
            local slot_name
            slot_name=$(create_container "$PROJECT_DIR")
            success "  Slot created: $slot_name"
            ;;
    esac

    # Settings
    printf '\n  Enable sudo by default? [y/N] '
    IFS= read -r answer 2>/dev/null || true
    local flags=""
    case "$answer" in
        [yY]*) flags="--enable-sudo" ;;
    esac

    printf '  Disable firewall by default? [y/N] '
    IFS= read -r answer 2>/dev/null || true
    case "$answer" in
        [yY]*)
            if [[ -n "$flags" ]]; then
                flags="$flags --disable-firewall"
            else
                flags="--disable-firewall"
            fi
            ;;
    esac

    if [[ -n "$flags" ]]; then
        mkdir -p "$HOME/.claudebox"
        for flag in $flags; do
            printf '%s\n' "$flag"
        done > "$HOME/.claudebox/default-flags"
        success "  Saved default flags: $flags"
    fi

    printf '\n'
    success "  Setup complete!"
    printf '\n'
    printf "  ${CYAN}claudebox${NC}          Launch Claude\n"
    printf "  ${CYAN}claudebox help${NC}     See all commands\n"
    printf "  ${CYAN}claudebox setup${NC}    Re-run this wizard\n"
    printf '\n'
}

# ── Entry point ───────────────────────────────────────────────
_cmd_setup() {
    # Ensure project dir is initialized
    init_project_dir "$PROJECT_DIR"
    PROJECT_PARENT_DIR=$(get_parent_dir "$PROJECT_DIR")
    export PROJECT_PARENT_DIR

    # Check for Python 3
    local python_cmd=""
    if command -v python3 >/dev/null 2>&1; then
        python_cmd="python3"
    elif command -v python >/dev/null 2>&1; then
        # Verify it is Python 3
        if python -c 'import sys; sys.exit(0 if sys.version_info[0]>=3 else 1)' 2>/dev/null; then
            python_cmd="python"
        fi
    fi

    if [[ -z "$python_cmd" ]]; then
        _setup_fallback
        exit 0
    fi

    # Run the Python wizard
    local result_file
    result_file=$(mktemp "${TMPDIR:-/tmp}/claudebox-setup.XXXXXX")

    local wizard_exit=0
    _setup_build_config | "$python_cmd" "${CLAUDEBOX_SCRIPT_DIR}/lib/setup_wizard.py" > "$result_file" || wizard_exit=$?

    if [[ $wizard_exit -ne 0 ]]; then
        rm -f "$result_file"
        exit 0
    fi

    # Check for cancellation
    if grep -q '^CANCELLED=yes' "$result_file" 2>/dev/null; then
        rm -f "$result_file"
        exit 0
    fi

    # Apply the selections
    _setup_apply_results "$result_file"
    rm -f "$result_file"

    printf '\n'
    printf "  ${WHITE}Next steps:${NC}\n"
    printf "    ${CYAN}claudebox${NC}          Launch Claude\n"
    printf "    ${CYAN}claudebox help${NC}     See all commands\n"
    printf "    ${CYAN}claudebox setup${NC}    Re-run this wizard\n"
    printf '\n'

    exit 0
}

export -f _cmd_setup _setup_apply_results _setup_build_config _setup_fallback
