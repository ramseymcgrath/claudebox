#!/usr/bin/env bash
# Auth & Tunnel Commands - Persistent authentication and tunnel management
# ============================================================================
# Commands: auth, tunnel
# Manages persistent auth tokens and Cloudflare tunnel configuration

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

_cmd_tunnel() {
    local tunnel_config="$HOME/.claudebox/tunnel.yml"
    local cf_creds_dir="$HOME/.claudebox/cloudflared"
    local tunnel_env="$HOME/.claudebox/tunnel.env"

    case "${1:-}" in
        setup)
            shift
            local tunnel_url="${1:-}"

            if [[ -z "$tunnel_url" ]]; then
                printf "Usage: claudebox tunnel setup <hostname>\n"
                printf '\n'
                printf "Examples:\n"
                printf "  claudebox tunnel setup myapp.example.com\n"
                printf "  claudebox tunnel setup ssh.internal.example.com\n"
                printf '\n'
                printf '%s\n' "The hostname of your Cloudflare Access-protected application."
                printf '%s\n' "cloudflared access commands will use this as the target."
                exit 1
            fi

            mkdir -p "$HOME/.claudebox" "$cf_creds_dir"

            # Save tunnel hostname
            {
                printf 'CF_ACCESS_HOSTNAME=%s\n' "$tunnel_url"
                # Preserve existing service token values if set
                if [[ -f "$tunnel_env" ]]; then
                    grep '^CF_ACCESS_SERVICE_TOKEN_ID=' "$tunnel_env" 2>/dev/null || true
                    grep '^CF_ACCESS_SERVICE_TOKEN_SECRET=' "$tunnel_env" 2>/dev/null || true
                    grep '^CF_ACCESS_TCP_FORWARD=' "$tunnel_env" 2>/dev/null || true
                fi
            } > "${tunnel_env}.tmp" && mv "${tunnel_env}.tmp" "$tunnel_env"

            cecho "Tunnel configured:" "$GREEN"
            printf "  Hostname: %s\n" "$tunnel_url"
            printf '\n'
            printf '%s\n' "Next steps:"
            printf "  ${CYAN}claudebox tunnel service-token <id> <secret>${NC}  Set service token for headless auth\n"
            printf "  ${CYAN}claudebox add tunnel${NC}                         Install cloudflared in containers\n"
            printf '\n'
            ;;

        service-token)
            shift
            local token_id="${1:-}"
            local token_secret="${2:-}"

            if [[ -z "$token_id" ]] || [[ -z "$token_secret" ]]; then
                printf "Usage: claudebox tunnel service-token <client-id> <client-secret>\n"
                printf '\n'
                printf '%s\n' "Create a Service Token in Cloudflare Zero Trust dashboard:"
                printf '%s\n' "  Access > Service Auth > Service Tokens > Create"
                printf '\n'
                printf '%s\n' "Service tokens allow headless authentication from Docker containers"
                printf '%s\n' "without needing a browser. The token ID and secret are passed as"
                printf '%s\n' "CF-Access-Client-Id and CF-Access-Client-Secret headers."
                exit 1
            fi

            mkdir -p "$HOME/.claudebox"

            # Update or create the tunnel env file
            local existing=""
            if [[ -f "$tunnel_env" ]]; then
                existing=$(grep -v '^CF_ACCESS_SERVICE_TOKEN_ID=' "$tunnel_env" | grep -v '^CF_ACCESS_SERVICE_TOKEN_SECRET=' || true)
            fi
            {
                if [[ -n "$existing" ]]; then
                    printf '%s\n' "$existing"
                fi
                printf 'CF_ACCESS_SERVICE_TOKEN_ID=%s\n' "$token_id"
                printf 'CF_ACCESS_SERVICE_TOKEN_SECRET=%s\n' "$token_secret"
            } > "${tunnel_env}.tmp" && mv "${tunnel_env}.tmp" "$tunnel_env"
            chmod 600 "$tunnel_env"

            cecho "Service token saved" "$GREEN"
            printf '%s\n' "Containers will authenticate using these credentials automatically."
            printf '%s\n' "Use 'cloudflared access' commands inside the container, or"
            printf '%s\n' "set up TCP forwarding with 'claudebox tunnel forward'."
            ;;

        forward)
            shift
            local forward_spec="${1:-}"

            if [[ -z "$forward_spec" ]]; then
                printf "Usage: claudebox tunnel forward <local-port>:<remote-host>:<remote-port>\n"
                printf '\n'
                printf "Examples:\n"
                printf "  claudebox tunnel forward 8080:internal-api.lan:443\n"
                printf "  claudebox tunnel forward 5432:db.internal:5432\n"
                printf '\n'
                printf '%s\n' "Sets up cloudflared access tcp to forward a local port in the"
                printf '%s\n' "container to a remote host through your Cloudflare tunnel."
                printf '%s\n' "The forward starts automatically when the container launches."
                exit 1
            fi

            mkdir -p "$HOME/.claudebox"

            # Update or create the tunnel env file
            local existing=""
            if [[ -f "$tunnel_env" ]]; then
                existing=$(grep -v '^CF_ACCESS_TCP_FORWARD=' "$tunnel_env" || true)
            fi
            {
                if [[ -n "$existing" ]]; then
                    printf '%s\n' "$existing"
                fi
                printf 'CF_ACCESS_TCP_FORWARD=%s\n' "$forward_spec"
            } > "${tunnel_env}.tmp" && mv "${tunnel_env}.tmp" "$tunnel_env"

            cecho "TCP forward configured: $forward_spec" "$GREEN"
            printf '%s\n' "On next container start, cloudflared will proxy this connection."
            ;;

        token)
            shift
            local token="${1:-}"
            if [[ -z "$token" ]]; then
                printf "Usage: claudebox tunnel token <cloudflared-token>\n"
                printf '\n'
                printf '%s\n' "Provide the tunnel connector token from your Cloudflare dashboard."
                printf '%s\n' "This is for running a tunnel connector (cloudflared tunnel run)."
                printf '%s\n' "For Access authentication, use 'claudebox tunnel service-token' instead."
                exit 1
            fi

            mkdir -p "$cf_creds_dir"
            printf '%s' "$token" > "$cf_creds_dir/tunnel-token"
            chmod 600 "$cf_creds_dir/tunnel-token"
            cecho "Tunnel connector token saved" "$GREEN"
            ;;

        status)
            printf '\n'
            cecho "Cloudflare Tunnel & Access Configuration:" "$CYAN"
            printf '\n'

            # Hostname
            if [[ -f "$tunnel_env" ]]; then
                local hostname
                hostname=$(grep '^CF_ACCESS_HOSTNAME=' "$tunnel_env" 2>/dev/null | cut -d= -f2- || true)
                if [[ -n "$hostname" ]]; then
                    printf "  Access hostname: %s\n" "$hostname"
                fi
            fi

            # Service token
            if [[ -f "$tunnel_env" ]] && grep -q '^CF_ACCESS_SERVICE_TOKEN_ID=' "$tunnel_env" 2>/dev/null; then
                cecho "  Service token:   saved" "$GREEN"
            else
                cecho "  Service token:   not set" "$YELLOW"
            fi

            # TCP forward
            if [[ -f "$tunnel_env" ]]; then
                local forward
                forward=$(grep '^CF_ACCESS_TCP_FORWARD=' "$tunnel_env" 2>/dev/null | cut -d= -f2- || true)
                if [[ -n "$forward" ]]; then
                    printf "  TCP forward:     %s\n" "$forward"
                else
                    cecho "  TCP forward:     not configured" "$YELLOW"
                fi
            fi

            # Tunnel connector token
            if [[ -f "$cf_creds_dir/tunnel-token" ]]; then
                cecho "  Connector token: saved" "$GREEN"
            else
                cecho "  Connector token: not set (optional)" "$DIM"
            fi

            # Config file
            if [[ -f "$tunnel_config" ]]; then
                printf "  Config file:     %s\n" "$tunnel_config"
            fi

            # Profile status
            local has_tunnel=false
            local profiles
            profiles=$(get_current_profiles 2>/dev/null || printf '')
            if printf '%s' "$profiles" | grep -q 'tunnel'; then
                has_tunnel=true
            fi

            if [[ "$has_tunnel" == "true" ]]; then
                cecho "  Tunnel profile:  enabled" "$GREEN"
            else
                cecho "  Tunnel profile:  not added (run 'claudebox add tunnel')" "$YELLOW"
            fi
            printf '\n'
            ;;

        clear)
            rm -f "$tunnel_config"
            rm -f "$tunnel_env"
            rm -rf "$cf_creds_dir"
            cecho "Tunnel configuration cleared" "$YELLOW"
            ;;

        *)
            logo_small
            printf '\n'
            cecho "Cloudflare Tunnel & Access:" "$CYAN"
            printf '\n'
            cecho "Setup:" "$YELLOW"
            printf "  ${GREEN}tunnel setup <hostname>${NC}                  Set Access-protected hostname\n"
            printf "  ${GREEN}tunnel service-token <id> <secret>${NC}      Set service token (headless auth)\n"
            printf "  ${GREEN}tunnel forward <local>:<host>:<port>${NC}    Auto-forward TCP port in container\n"
            printf "  ${GREEN}tunnel token <connector-token>${NC}          Set tunnel connector token\n"
            printf '\n'
            cecho "Management:" "$YELLOW"
            printf "  ${GREEN}tunnel status${NC}                           Show configuration\n"
            printf "  ${GREEN}tunnel clear${NC}                            Remove all tunnel config\n"
            printf '\n'
            cecho "How it works:" "$CYAN"
            printf '%s\n' "  Containers with the 'tunnel' profile get cloudflared installed."
            printf '%s\n' "  Service tokens enable headless auth (no browser needed)."
            printf '%s\n' "  Inside the container you can use all cloudflared access commands:"
            printf '\n'
            printf "    ${DIM}cloudflared access tcp --hostname app.example.com --url localhost:8080${NC}\n"
            printf "    ${DIM}cloudflared access curl https://internal.example.com/api${NC}\n"
            printf "    ${DIM}cloudflared access ssh --hostname ssh.example.com${NC}\n"
            printf '\n'
            cecho "Quick start:" "$YELLOW"
            printf "  1. ${CYAN}claudebox tunnel setup internal.example.com${NC}\n"
            printf "  2. ${CYAN}claudebox tunnel service-token <id> <secret>${NC}\n"
            printf "  3. ${CYAN}claudebox tunnel forward 8080:internal.example.com:443${NC}  (optional)\n"
            printf "  4. ${CYAN}claudebox add tunnel${NC}\n"
            printf "  5. ${CYAN}claudebox rebuild${NC}\n"
            printf '\n'
            ;;
    esac
}

export -f _cmd_auth _cmd_tunnel
