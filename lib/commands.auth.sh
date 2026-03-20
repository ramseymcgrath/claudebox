#!/usr/bin/env bash
# Auth & Gateway Commands - Persistent authentication and API gateway management
# ============================================================================
# Commands: auth, gateway
# Manages persistent auth tokens and Cloudflare AI Gateway configuration

_auth_propagate_to_slots() {
    # Propagate saved credentials to all existing unauthenticated slots
    local auth_creds="$1"
    local parent_dir
    parent_dir=$(get_parent_dir "$PROJECT_DIR")
    local max
    max=$(read_counter "$parent_dir")
    local propagated=0

    for ((idx=1; idx<=max; idx++)); do
        local name
        name=$(generate_container_name "$PROJECT_DIR" "$idx")
        local dir="$parent_dir/$name"
        if [[ -d "$dir/.claude" ]] && [[ ! -f "$dir/.claude/.credentials.json" ]]; then
            cp "$auth_creds" "$dir/.claude/.credentials.json"
            ((propagated++)) || true
        fi
    done

    if [[ $propagated -gt 0 ]]; then
        printf '%s\n' "Credentials propagated to $propagated existing slot(s)."
    fi
}

_cmd_auth() {
    local auth_dir="$HOME/.claudebox/auth"

    case "${1:-}" in
        save|store)
            # Save auth token from a slot to persistent storage
            shift
            local slot_name="${1:-}"

            if [[ -z "$slot_name" ]]; then
                # Try to find the current project's slot
                init_project_dir "$PROJECT_DIR"
                local parent_dir
                parent_dir=$(get_parent_dir "$PROJECT_DIR")
                local project_folder
                project_folder=$(get_project_folder_name "$PROJECT_DIR")

                if [[ "$project_folder" == "NONE" ]]; then
                    error "No slots found. Create a slot first with 'claudebox create'"
                fi

                local creds_file="$parent_dir/$project_folder/.claude/.credentials.json"
                if [[ ! -f "$creds_file" ]]; then
                    error "No credentials found in slot. Authenticate first by running 'claudebox'"
                fi

                mkdir -p "$auth_dir"
                cp "$creds_file" "$auth_dir/credentials.json"
                cecho "Auth token saved to persistent storage" "$GREEN"
                printf '%s\n' "Token will be shared across all new containers."
                _auth_propagate_to_slots "$auth_dir/credentials.json"
            else
                # Save from a specific slot path
                init_project_dir "$PROJECT_DIR"
                local parent_dir
                parent_dir=$(get_parent_dir "$PROJECT_DIR")
                local creds_file="$parent_dir/$slot_name/.claude/.credentials.json"

                if [[ ! -f "$creds_file" ]]; then
                    error "No credentials found in slot '$slot_name'"
                fi

                mkdir -p "$auth_dir"
                cp "$creds_file" "$auth_dir/credentials.json"
                cecho "Auth token saved from slot '$slot_name' to persistent storage" "$GREEN"
                _auth_propagate_to_slots "$auth_dir/credentials.json"
            fi
            ;;

        clear|remove)
            if [[ -f "$auth_dir/credentials.json" ]]; then
                rm -f "$auth_dir/credentials.json"
                cecho "Persistent auth token removed" "$YELLOW"
            else
                printf '%s\n' "No persistent auth token found."
            fi
            ;;

        status)
            printf '\n'
            cecho "Auth Token Status:" "$CYAN"
            printf '\n'

            if [[ -f "$auth_dir/credentials.json" ]]; then
                cecho "  Persistent token: saved" "$GREEN"
                local token_date
                token_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$auth_dir/credentials.json" 2>/dev/null || \
                             stat -c "%y" "$auth_dir/credentials.json" 2>/dev/null | cut -d. -f1 || \
                             printf 'unknown')
                printf "  Last saved: %s\n" "$token_date"
            else
                cecho "  Persistent token: not saved" "$YELLOW"
            fi
            printf '\n'
            ;;

        *)
            logo_small
            printf '\n'
            cecho "Auth Token Management:" "$CYAN"
            printf '\n'
            printf "  ${GREEN}auth save${NC}           Save current slot's auth token for reuse\n"
            printf "  ${GREEN}auth save <slot>${NC}    Save a specific slot's auth token\n"
            printf "  ${GREEN}auth clear${NC}          Remove persistent auth token\n"
            printf "  ${GREEN}auth status${NC}         Show auth token status\n"
            printf '\n'
            printf '%s\n' "Persistent tokens are shared across all new containers,"
            printf '%s\n' "so you only need to authenticate once."
            printf '\n'
            ;;
    esac
}

_cmd_gateway() {
    local gateway_env="$HOME/.claudebox/gateway.env"

    case "${1:-}" in
        setup)
            shift
            local account_id="${1:-}"
            local gateway_id="${2:-}"

            if [[ -z "$account_id" ]] || [[ -z "$gateway_id" ]]; then
                printf "Usage: claudebox gateway setup <account-id> <gateway-id>\n"
                printf '\n'
                printf "Examples:\n"
                printf "  claudebox gateway setup abc123def456 my-gateway\n"
                printf '\n'
                printf '%s\n' "Find these in your Cloudflare dashboard under AI > AI Gateway."
                printf '%s\n' "The account ID is in your Cloudflare URL; the gateway ID is the name"
                printf '%s\n' "you gave when creating the gateway."
                printf '\n'
                printf '%s\n' "You will also need a Cloudflare API token with AI Gateway permissions."
                printf '%s\n' "Create one at: dash.cloudflare.com > My Profile > API Tokens"
                exit 1
            fi

            local base_url="https://gateway.ai.cloudflare.com/v1/${account_id}/${gateway_id}/anthropic"

            mkdir -p "$HOME/.claudebox"

            # Check for existing token
            local existing_token=""
            if [[ -f "$gateway_env" ]]; then
                existing_token=$(grep '^CF_AIG_TOKEN=' "$gateway_env" 2>/dev/null | cut -d= -f2- || true)
            fi

            # Prompt for API token if not already set
            if [[ -z "$existing_token" ]]; then
                printf '\n'
                printf '%s\n' "Cloudflare API token (with AI Gateway Read/Edit permissions):"
                printf '%s\n' "Create at: dash.cloudflare.com > My Profile > API Tokens"
                printf "  Token: "
                local token
                IFS= read -r token 2>/dev/null || true

                if [[ -z "$token" ]]; then
                    warn "No token provided. Gateway authentication will fail."
                    printf '%s\n' "Set it later with: claudebox gateway token <token>"
                fi
            else
                token="$existing_token"
            fi

            {
                printf 'ANTHROPIC_BASE_URL=%s\n' "$base_url"
                printf 'ENABLE_TOOL_SEARCH=true\n'
                if [[ -n "${token:-}" ]]; then
                    printf 'CF_AIG_TOKEN=%s\n' "$token"
                fi
            } > "$gateway_env"
            chmod 600 "$gateway_env"

            cecho "AI Gateway configured:" "$GREEN"
            printf "  URL: %s\n" "$base_url"
            if [[ -n "${token:-}" ]]; then
                cecho "  Auth token:  saved" "$GREEN"
            fi
            printf '\n'
            printf '%s\n' "All containers will route API traffic through Cloudflare AI Gateway."
            printf '%s\n' "Restart running containers for the change to take effect."
            ;;

        token)
            shift
            local token="${1:-}"

            if [[ -z "$token" ]]; then
                printf "Usage: claudebox gateway token <cloudflare-api-token>\n"
                printf '\n'
                printf '%s\n' "Set the Cloudflare API token for AI Gateway authentication."
                printf '%s\n' "Create a token with AI Gateway Read/Edit permissions at:"
                printf '%s\n' "  dash.cloudflare.com > My Profile > API Tokens"
                exit 1
            fi

            mkdir -p "$HOME/.claudebox"

            if [[ -f "$gateway_env" ]]; then
                # Preserve existing settings, update token
                local existing
                existing=$(grep -v '^CF_AIG_TOKEN=' "$gateway_env" || true)
                {
                    if [[ -n "$existing" ]]; then
                        printf '%s\n' "$existing"
                    fi
                    printf 'CF_AIG_TOKEN=%s\n' "$token"
                } > "${gateway_env}.tmp" && mv "${gateway_env}.tmp" "$gateway_env"
            else
                printf 'CF_AIG_TOKEN=%s\n' "$token" > "$gateway_env"
            fi
            chmod 600 "$gateway_env"

            cecho "Gateway auth token saved" "$GREEN"
            ;;

        url)
            shift
            local custom_url="${1:-}"

            if [[ -z "$custom_url" ]]; then
                printf "Usage: claudebox gateway url <base-url>\n"
                printf '\n'
                printf "Examples:\n"
                printf "  claudebox gateway url https://gateway.ai.cloudflare.com/v1/abc123/my-gw/anthropic\n"
                printf "  claudebox gateway url https://my-proxy.example.com/v1\n"
                printf '\n'
                printf '%s\n' "Set a custom ANTHROPIC_BASE_URL for any proxy or gateway."
                exit 1
            fi

            mkdir -p "$HOME/.claudebox"

            # Preserve existing token if set
            local existing_token=""
            if [[ -f "$gateway_env" ]]; then
                existing_token=$(grep '^CF_AIG_TOKEN=' "$gateway_env" 2>/dev/null | cut -d= -f2- || true)
            fi

            {
                printf 'ANTHROPIC_BASE_URL=%s\n' "$custom_url"
                printf 'ENABLE_TOOL_SEARCH=true\n'
                if [[ -n "$existing_token" ]]; then
                    printf 'CF_AIG_TOKEN=%s\n' "$existing_token"
                fi
            } > "$gateway_env"
            chmod 600 "$gateway_env"

            cecho "API gateway configured:" "$GREEN"
            printf "  URL: %s\n" "$custom_url"
            ;;

        status)
            printf '\n'
            cecho "Cloudflare AI Gateway Configuration:" "$CYAN"
            printf '\n'

            if [[ -f "$gateway_env" ]]; then
                local base_url
                base_url=$(grep '^ANTHROPIC_BASE_URL=' "$gateway_env" 2>/dev/null | cut -d= -f2- || true)
                if [[ -n "$base_url" ]]; then
                    printf "  Base URL:        %s\n" "$base_url"
                    cecho "  Status:          active" "$GREEN"
                else
                    cecho "  Status:          not configured" "$YELLOW"
                fi

                local has_token
                has_token=$(grep '^CF_AIG_TOKEN=' "$gateway_env" 2>/dev/null | cut -d= -f2- || true)
                if [[ -n "$has_token" ]]; then
                    cecho "  Auth token:      saved" "$GREEN"
                else
                    cecho "  Auth token:      not set" "$YELLOW"
                fi

                local tool_search
                tool_search=$(grep '^ENABLE_TOOL_SEARCH=' "$gateway_env" 2>/dev/null | cut -d= -f2- || true)
                if [[ -n "$tool_search" ]]; then
                    printf "  Tool search:     %s\n" "$tool_search"
                fi
            else
                cecho "  Status:          not configured (using direct Anthropic API)" "$DIM"
            fi
            printf '\n'
            ;;

        clear)
            rm -f "$gateway_env"
            cecho "Gateway configuration cleared" "$YELLOW"
            printf '%s\n' "Containers will connect directly to Anthropic API."
            ;;

        *)
            logo_small
            printf '\n'
            cecho "Cloudflare AI Gateway:" "$CYAN"
            printf '\n'
            cecho "Setup:" "$YELLOW"
            printf "  ${GREEN}gateway setup <account-id> <gateway-id>${NC}  Configure AI Gateway\n"
            printf "  ${GREEN}gateway token <api-token>${NC}               Set Cloudflare auth token\n"
            printf "  ${GREEN}gateway url <base-url>${NC}                  Set custom API proxy URL\n"
            printf '\n'
            cecho "Management:" "$YELLOW"
            printf "  ${GREEN}gateway status${NC}                          Show configuration\n"
            printf "  ${GREEN}gateway clear${NC}                           Remove gateway config\n"
            printf '\n'
            cecho "How it works:" "$CYAN"
            printf '%s\n' "  Routes all Claude API traffic through Cloudflare AI Gateway."
            printf '%s\n' "  Provides caching, rate limiting, cost tracking, and logging."
            printf '%s\n' "  Requires a Cloudflare API token with AI Gateway permissions."
            printf '\n'
            cecho "Quick start:" "$YELLOW"
            printf "  1. Create an AI Gateway in Cloudflare dashboard (AI > AI Gateway)\n"
            printf "  2. Create an API token at: My Profile > API Tokens\n"
            printf "     ${DIM}(Permissions: AI Gateway Read + Edit)${NC}\n"
            printf "  3. ${CYAN}claudebox gateway setup <account-id> <gateway-id>${NC}\n"
            printf "  4. ${CYAN}claudebox rebuild${NC}\n"
            printf '\n'
            ;;
    esac
}

export -f _cmd_auth _cmd_gateway _auth_propagate_to_slots
