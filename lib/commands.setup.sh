#!/usr/bin/env bash
# Setup Command - Interactive setup wizard
# ============================================================================
# Command: setup
# Guides users through initial ClaudeBox configuration

# Read a single character of input (portable)
_setup_read_char() {
    local char=""
    IFS= read -r -n 1 char 2>/dev/null || true
    printf '%s' "$char"
}

# Ask a yes/no question, return 0 for yes, 1 for no
_setup_ask_yn() {
    local prompt="$1"
    local default="${2:-n}"
    local hint="y/N"
    if [[ "$default" == "y" ]]; then
        hint="Y/n"
    fi

    printf "  %s [%s] " "$prompt" "$hint"
    local answer
    IFS= read -r answer 2>/dev/null || true
    answer="${answer:-$default}"

    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# Print a section header
_setup_header() {
    local step="$1"
    local total="$2"
    local title="$3"
    printf '\n'
    printf "  ${CYAN}Step %s of %s: %s${NC}\n" "$step" "$total" "$title"
    printf "  ${DIM}────────────────────────────────────────────────────────────────${NC}\n"
    printf '\n'
}

# Interactive profile selector
_setup_profiles() {
    _setup_header 1 5 "Development Profiles"

    printf "  Select profiles to install. Type profile names separated by spaces,\n"
    printf "  or press Enter to skip.\n"
    printf '\n'

    # Show available profiles in columns
    local profiles=()
    while IFS= read -r p; do
        if [[ -n "$p" ]]; then
            profiles+=("$p")
        fi
    done < <(_builtin_profile_names | tr ' ' '\n')

    for profile in "${profiles[@]}"; do
        local desc
        desc=$(get_profile_description "$profile")
        printf "    ${GREEN}%-15s${NC} %s\n" "$profile" "$desc"
    done

    # Show custom profiles if any
    local custom_names
    custom_names=$(get_custom_profile_names 2>/dev/null || true)
    if [[ -n "$custom_names" ]]; then
        printf '\n'
        printf "  ${DIM}Custom profiles:${NC}\n"
        for profile in $custom_names; do
            local desc
            desc=$(get_custom_profile_description "$profile")
            printf "    ${GREEN}%-15s${NC} %s\n" "$profile" "$desc"
        done
    fi

    printf '\n'
    printf "  ${WHITE}Profiles to add:${NC} "
    local input
    IFS= read -r input 2>/dev/null || true

    if [[ -n "$input" ]]; then
        local valid_profiles=()
        local invalid_profiles=()
        for name in $input; do
            if profile_exists "$name"; then
                valid_profiles+=("$name")
            else
                invalid_profiles+=("$name")
            fi
        done

        if [[ ${#invalid_profiles[@]} -gt 0 ]]; then
            warn "  Unknown profiles (skipped): ${invalid_profiles[*]}"
        fi

        if [[ ${#valid_profiles[@]} -gt 0 ]]; then
            # Add profiles to the project
            init_project_dir "$PROJECT_DIR"
            local profile_file
            profile_file=$(get_profile_file_path)
            update_profile_section "$profile_file" "profiles" "${valid_profiles[@]}"
            success "  Added profiles: ${valid_profiles[*]}"
        fi
    else
        printf "  ${DIM}Skipped${NC}\n"
    fi
}

# Create first slot
_setup_create_slot() {
    _setup_header 2 5 "Create Container Slot"

    printf "  A slot is an authenticated Claude instance. You need at least one\n"
    printf "  to use ClaudeBox. You can create more later with 'claudebox create'.\n"
    printf '\n'

    if _setup_ask_yn "Create your first slot now?" "y"; then
        printf '\n'
        local slot_name
        slot_name=$(create_container "$PROJECT_DIR")
        printf '\n'
        success "  Slot created: $slot_name"
        printf "  ${DIM}Run 'claudebox' to authenticate and start using Claude.${NC}\n"
    else
        printf '\n'
        printf "  ${DIM}Skipped. Run 'claudebox create' when you're ready.${NC}\n"
    fi
}

# Cloudflare tunnel configuration
_setup_tunnel() {
    _setup_header 3 5 "Cloudflare Tunnel (optional)"

    printf "  If you need containers to access services on a private network\n"
    printf "  via Cloudflare Access, configure it here.\n"
    printf '\n'

    if ! _setup_ask_yn "Set up Cloudflare tunnel access?"; then
        printf '\n'
        printf "  ${DIM}Skipped. Run 'claudebox tunnel' later if needed.${NC}\n"
        return 0
    fi

    printf '\n'
    local tunnel_env="$HOME/.claudebox/tunnel.env"
    local cf_creds_dir="$HOME/.claudebox/cloudflared"

    # Hostname
    printf "  ${WHITE}Access-protected hostname${NC} (e.g. internal.example.com)\n"
    printf "  ${WHITE}Hostname:${NC} "
    local hostname
    IFS= read -r hostname 2>/dev/null || true

    if [[ -z "$hostname" ]]; then
        warn "  No hostname provided, skipping tunnel setup."
        return 0
    fi

    mkdir -p "$HOME/.claudebox" "$cf_creds_dir"
    printf 'CF_ACCESS_HOSTNAME=%s\n' "$hostname" > "$tunnel_env"

    # Service token
    printf '\n'
    printf "  ${DIM}Service tokens enable headless auth (no browser needed).${NC}\n"
    printf "  ${DIM}Create one in: Cloudflare Zero Trust > Access > Service Auth > Service Tokens${NC}\n"
    printf '\n'

    if _setup_ask_yn "Add a service token?"; then
        printf "  ${WHITE}Client ID:${NC} "
        local token_id
        IFS= read -r token_id 2>/dev/null || true

        printf "  ${WHITE}Client Secret:${NC} "
        local token_secret
        IFS= read -r token_secret 2>/dev/null || true

        if [[ -n "$token_id" ]] && [[ -n "$token_secret" ]]; then
            {
                cat "$tunnel_env"
                printf 'CF_ACCESS_SERVICE_TOKEN_ID=%s\n' "$token_id"
                printf 'CF_ACCESS_SERVICE_TOKEN_SECRET=%s\n' "$token_secret"
            } > "${tunnel_env}.tmp" && mv "${tunnel_env}.tmp" "$tunnel_env"
            chmod 600 "$tunnel_env"
            success "  Service token saved"
        else
            warn "  Incomplete token, skipping."
        fi
    fi

    # TCP forward
    printf '\n'
    if _setup_ask_yn "Set up TCP port forwarding?"; then
        printf "  ${DIM}Format: local-port:remote-host:remote-port${NC}\n"
        printf "  ${DIM}Example: 8080:api.internal:443${NC}\n"
        printf "  ${WHITE}Forward:${NC} "
        local forward_spec
        IFS= read -r forward_spec 2>/dev/null || true

        if [[ -n "$forward_spec" ]]; then
            {
                cat "$tunnel_env"
                printf 'CF_ACCESS_TCP_FORWARD=%s\n' "$forward_spec"
            } > "${tunnel_env}.tmp" && mv "${tunnel_env}.tmp" "$tunnel_env"
            success "  TCP forward configured: $forward_spec"
        fi
    fi

    # Auto-add tunnel profile
    printf '\n'
    init_project_dir "$PROJECT_DIR"
    local profile_file
    profile_file=$(get_profile_file_path)
    local current
    current=$(get_current_profiles 2>/dev/null || true)

    if ! printf '%s' "$current" | grep -q 'tunnel'; then
        if _setup_ask_yn "Add the 'tunnel' profile to install cloudflared?" "y"; then
            update_profile_section "$profile_file" "profiles" "tunnel"
            success "  Tunnel profile added"
        fi
    else
        printf "  ${DIM}Tunnel profile already enabled.${NC}\n"
    fi
}

# Plugin recommendations
_setup_plugins() {
    _setup_header 4 5 "Plugins (optional)"

    printf "  Claude Code has 100+ plugins available. Here are some popular ones:\n"
    printf '\n'
    printf "    ${GREEN}%-24s${NC} %s\n" "commit-commands" "Git commit, push, and PR creation"
    printf "    ${GREEN}%-24s${NC} %s\n" "github" "Official GitHub MCP server"
    printf "    ${GREEN}%-24s${NC} %s\n" "typescript-lsp" "TypeScript/JavaScript intelligence"
    printf "    ${GREEN}%-24s${NC} %s\n" "pyright-lsp" "Python type checking"
    printf "    ${GREEN}%-24s${NC} %s\n" "context7" "Version-specific library docs"
    printf "    ${GREEN}%-24s${NC} %s\n" "security-guidance" "Security issue warnings"
    printf '\n'
    printf "  ${DIM}Type plugin names separated by spaces to install, or Enter to skip.${NC}\n"
    printf "  ${DIM}Run 'claudebox agent popular' later to see more options.${NC}\n"
    printf '\n'
    printf "  ${WHITE}Plugins to install:${NC} "
    local input
    IFS= read -r input 2>/dev/null || true

    if [[ -n "$input" ]]; then
        for plugin_name in $input; do
            printf "  Installing %s...\n" "$plugin_name"
            _agent_run_in_container "install" "$plugin_name" 2>/dev/null || true
        done
        success "  Plugin installation complete"
    else
        printf "  ${DIM}Skipped. Run 'claudebox agent install <name>' later.${NC}\n"
    fi
}

# Default settings
_setup_defaults() {
    _setup_header 5 5 "Default Settings"

    local flags_to_save=()

    if _setup_ask_yn "Enable sudo in containers by default?"; then
        flags_to_save+=("--enable-sudo")
    fi

    printf '\n'
    if _setup_ask_yn "Disable firewall by default?"; then
        flags_to_save+=("--disable-firewall")
    fi

    if [[ ${#flags_to_save[@]} -gt 0 ]]; then
        local flags_file="$HOME/.claudebox/default-flags"
        mkdir -p "$HOME/.claudebox"
        printf '%s\n' "${flags_to_save[@]}" > "$flags_file"
        printf '\n'
        success "  Saved default flags: ${flags_to_save[*]}"
    else
        printf '\n'
        printf "  ${DIM}Using default settings.${NC}\n"
    fi
}

# Main setup wizard
_cmd_setup() {
    logo_small
    printf '\n'
    cecho "  ClaudeBox Setup Wizard" "$WHITE"
    printf "  ${DIM}Configure your development environment step by step.${NC}\n"
    printf "  ${DIM}Press Enter at any prompt to skip that step.${NC}\n"

    # Ensure project dir is initialized for profile operations
    init_project_dir "$PROJECT_DIR"
    PROJECT_PARENT_DIR=$(get_parent_dir "$PROJECT_DIR")
    export PROJECT_PARENT_DIR

    _setup_profiles
    _setup_create_slot
    _setup_tunnel
    _setup_plugins
    _setup_defaults

    # Done
    printf '\n'
    printf "  ${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
    printf '\n'
    success "  Setup complete!"
    printf '\n'
    printf "  ${WHITE}Next steps:${NC}\n"
    printf "    ${CYAN}claudebox${NC}          Launch Claude\n"
    printf "    ${CYAN}claudebox help${NC}     See all commands\n"
    printf "    ${CYAN}claudebox setup${NC}    Re-run this wizard anytime\n"
    printf '\n'

    exit 0
}

export -f _cmd_setup _setup_read_char _setup_ask_yn _setup_header
export -f _setup_profiles _setup_create_slot _setup_tunnel _setup_plugins _setup_defaults
