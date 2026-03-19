#!/usr/bin/env bash
# MCP Commands - MCP server installation and management
# ============================================================================
# Command: mcp
# Installs MCP servers persistently into the Docker image

# Known MCP server registry - maps short names to npm packages and configs
_mcp_resolve_server() {
    local name="$1"
    # Returns: package_name|command|args_template
    # args_template uses {ARGS} as placeholder for user-provided arguments
    case "$name" in
        # Official Anthropic / ModelContextProtocol servers
        filesystem)
            printf '%s' "@modelcontextprotocol/server-filesystem|npx|-y @modelcontextprotocol/server-filesystem {ARGS}" ;;
        memory)
            printf '%s' "@modelcontextprotocol/server-memory|npx|-y @modelcontextprotocol/server-memory" ;;
        fetch)
            printf '%s' "@anthropic-ai/mcp-server-fetch|npx|-y @anthropic-ai/mcp-server-fetch" ;;
        brave-search)
            printf '%s' "@modelcontextprotocol/server-brave-search|npx|-y @modelcontextprotocol/server-brave-search" ;;
        github)
            printf '%s' "@modelcontextprotocol/server-github|npx|-y @modelcontextprotocol/server-github" ;;
        gitlab)
            printf '%s' "@modelcontextprotocol/server-gitlab|npx|-y @modelcontextprotocol/server-gitlab" ;;
        google-maps)
            printf '%s' "@modelcontextprotocol/server-google-maps|npx|-y @modelcontextprotocol/server-google-maps" ;;
        slack)
            printf '%s' "@modelcontextprotocol/server-slack|npx|-y @modelcontextprotocol/server-slack" ;;
        postgres)
            printf '%s' "@modelcontextprotocol/server-postgres|npx|-y @modelcontextprotocol/server-postgres {ARGS}" ;;
        sqlite)
            printf '%s' "@modelcontextprotocol/server-sqlite|npx|-y @modelcontextprotocol/server-sqlite {ARGS}" ;;
        puppeteer)
            printf '%s' "@modelcontextprotocol/server-puppeteer|npx|-y @modelcontextprotocol/server-puppeteer" ;;
        sequential-thinking)
            printf '%s' "@modelcontextprotocol/server-sequential-thinking|npx|-y @modelcontextprotocol/server-sequential-thinking" ;;
        everything)
            printf '%s' "@modelcontextprotocol/server-everything|npx|-y @modelcontextprotocol/server-everything" ;;
        git)
            printf '%s' "@modelcontextprotocol/server-git|npx|-y @modelcontextprotocol/server-git {ARGS}" ;;
        time)
            printf '%s' "@modelcontextprotocol/server-time|npx|-y @modelcontextprotocol/server-time" ;;
        # Community / vendor servers
        context7)
            printf '%s' "@upstash/context7-mcp|npx|-y @upstash/context7-mcp" ;;
        datadog)
            printf '%s' "@anthropic-ai/mcp-server-datadog|npx|-y @anthropic-ai/mcp-server-datadog" ;;
        aws-kb)
            printf '%s' "@modelcontextprotocol/server-aws-kb-retrieval|npx|-y @modelcontextprotocol/server-aws-kb-retrieval" ;;
        sentry)
            printf '%s' "@sentry/mcp-server-sentry|npx|-y @sentry/mcp-server-sentry" ;;
        linear)
            printf '%s' "@anthropic-ai/mcp-server-linear|npx|-y @anthropic-ai/mcp-server-linear" ;;
        # Catch-all: treat as npm package name
        @*|*/*)
            printf '%s' "$name|npx|-y $name {ARGS}" ;;
        *)
            printf '' ;;
    esac
}

_mcp_list_known() {
    printf "  ${GREEN}%-25s${NC} %s\n" "filesystem"          "Local file system access"
    printf "  ${GREEN}%-25s${NC} %s\n" "memory"              "Knowledge graph memory"
    printf "  ${GREEN}%-25s${NC} %s\n" "fetch"               "Web content fetching"
    printf "  ${GREEN}%-25s${NC} %s\n" "brave-search"        "Brave search API"
    printf "  ${GREEN}%-25s${NC} %s\n" "github"              "GitHub API integration"
    printf "  ${GREEN}%-25s${NC} %s\n" "gitlab"              "GitLab API integration"
    printf "  ${GREEN}%-25s${NC} %s\n" "google-maps"         "Google Maps API"
    printf "  ${GREEN}%-25s${NC} %s\n" "slack"               "Slack workspace access"
    printf "  ${GREEN}%-25s${NC} %s\n" "postgres"            "PostgreSQL database"
    printf "  ${GREEN}%-25s${NC} %s\n" "sqlite"              "SQLite database"
    printf "  ${GREEN}%-25s${NC} %s\n" "puppeteer"           "Browser automation"
    printf "  ${GREEN}%-25s${NC} %s\n" "sequential-thinking" "Chain-of-thought reasoning"
    printf "  ${GREEN}%-25s${NC} %s\n" "git"                 "Git repository operations"
    printf "  ${GREEN}%-25s${NC} %s\n" "time"                "Time and timezone utilities"
    printf "  ${GREEN}%-25s${NC} %s\n" "everything"          "Demo/testing server"
    printf '\n'
    cecho "  Vendor / Community:" "$DIM"
    printf "  ${GREEN}%-25s${NC} %s\n" "context7"            "Library documentation lookup"
    printf "  ${GREEN}%-25s${NC} %s\n" "datadog"             "Datadog monitoring integration"
    printf "  ${GREEN}%-25s${NC} %s\n" "aws-kb"              "AWS Knowledge Base retrieval"
    printf "  ${GREEN}%-25s${NC} %s\n" "sentry"              "Sentry error tracking"
    printf "  ${GREEN}%-25s${NC} %s\n" "linear"              "Linear issue tracking"
}

_mcp_get_installed() {
    local mcp_ini="$HOME/.claudebox/mcp-servers.ini"
    if [[ -f "$mcp_ini" ]]; then
        while IFS='=' read -r name _; do
            if [[ -n "$name" ]] && [[ "$name" != \[* ]] && [[ "$name" != \#* ]]; then
                printf '%s\n' "$name"
            fi
        done < "$mcp_ini"
    fi
}

_cmd_mcp() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        install|add)
            _mcp_install "$@"
            ;;
        remove|uninstall)
            _mcp_remove "$@"
            ;;
        list|ls)
            _mcp_list "$@"
            ;;
        status)
            _mcp_status
            ;;
        *)
            # If subcmd looks like a server name, treat as install
            if [[ -n "$subcmd" ]] && [[ "$subcmd" != -* ]]; then
                local resolved
                resolved=$(_mcp_resolve_server "$subcmd")
                if [[ -n "$resolved" ]]; then
                    _mcp_install "$subcmd" "$@"
                    return
                fi
            fi

            # Default: pass through to Claude's mcp command via _cmd_special
            if [[ -n "$subcmd" ]]; then
                _cmd_special "mcp" "$subcmd" "$@"
                return
            fi

            # Show help
            logo_small
            printf '\n'
            cecho "MCP Server Management:" "$CYAN"
            printf '\n'
            cecho "Install & manage:" "$YELLOW"
            printf "  ${GREEN}mcp install <server>${NC}       Install an MCP server into the image\n"
            printf "  ${GREEN}mcp install <server> -- <args>${NC}  Install with default arguments\n"
            printf "  ${GREEN}mcp remove <server>${NC}        Remove an MCP server\n"
            printf "  ${GREEN}mcp list${NC}                   List known MCP servers\n"
            printf "  ${GREEN}mcp status${NC}                 Show installed servers\n"
            printf '\n'
            cecho "Known servers:" "$YELLOW"
            printf '\n'
            _mcp_list_known
            printf '\n'
            printf '%s\n' "You can also install any npm package directly:"
            printf "  ${CYAN}claudebox mcp install @org/my-mcp-server${NC}\n"
            printf '\n'
            printf '%s\n' "Other mcp subcommands are passed to Claude Code inside the container."
            printf '\n'
            ;;
    esac
}

_mcp_install() {
    if [[ $# -eq 0 ]]; then
        error "Usage: claudebox mcp install <server-name> [-- <default-args>]\nRun 'claudebox mcp list' to see available servers"
    fi

    local server_name="$1"
    shift

    # Collect extra args (after --)
    local extra_args=""
    local collecting_args=false
    for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then
            collecting_args=true
            continue
        fi
        if [[ "$collecting_args" == "true" ]]; then
            if [[ -n "$extra_args" ]]; then
                extra_args="$extra_args $arg"
            else
                extra_args="$arg"
            fi
        fi
    done

    # Resolve server
    local resolved
    resolved=$(_mcp_resolve_server "$server_name")
    if [[ -z "$resolved" ]]; then
        error "Unknown MCP server: $server_name\nRun 'claudebox mcp list' to see available servers\nOr use the full npm package name: claudebox mcp install @org/package"
    fi

    local pkg_name="${resolved%%|*}"
    local remaining="${resolved#*|}"
    local cmd_name="${remaining%%|*}"
    local args_template="${remaining#*|}"

    # Substitute user args into template
    if [[ -n "$extra_args" ]]; then
        args_template="${args_template//\{ARGS\}/$extra_args}"
    else
        args_template="${args_template//\{ARGS\}/}"
        # Clean trailing whitespace
        args_template=$(printf '%s' "$args_template" | sed 's/[[:space:]]*$//')
    fi

    info "Installing MCP server: $server_name ($pkg_name)"

    # Check Docker image exists
    if [[ -z "${IMAGE_NAME:-}" ]]; then
        IMAGE_NAME=$(get_image_name)
    fi
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        error "No Docker image found. Run 'claudebox' first to build the image."
    fi

    # Create temp container, install the npm package, commit
    local project_folder_name
    project_folder_name=$(get_project_folder_name "$PROJECT_DIR" 2>/dev/null || printf 'temp')
    local temp_container="claudebox-mcp-install-$$"

    # Run installation in a temporary container
    docker run --rm --name "$temp_container" \
        "$IMAGE_NAME" bash -c "
            source \$HOME/.nvm/nvm.sh
            nvm use default >/dev/null 2>&1
            npm install -g $pkg_name
        " || error "Failed to install $pkg_name"

    # Now run again without --rm so we can commit
    docker run -d --name "$temp_container" \
        "$IMAGE_NAME" bash -c "
            source \$HOME/.nvm/nvm.sh
            nvm use default >/dev/null 2>&1
            npm install -g $pkg_name
            sleep 2
        " >/dev/null

    # Wait for install to finish
    docker wait "$temp_container" >/dev/null 2>&1

    # Commit the changes to the image
    docker commit "$temp_container" "$IMAGE_NAME" >/dev/null
    docker rm -f "$temp_container" >/dev/null 2>&1

    # Save to mcp-servers.ini for tracking
    local mcp_ini="$HOME/.claudebox/mcp-servers.ini"
    mkdir -p "$HOME/.claudebox"

    # Add or update entry
    if [[ -f "$mcp_ini" ]] && grep -q "^${server_name}=" "$mcp_ini" 2>/dev/null; then
        # Update existing entry
        local tmp_ini="${mcp_ini}.tmp"
        grep -v "^${server_name}=" "$mcp_ini" > "$tmp_ini" || true
        printf '%s=%s\n' "$server_name" "$pkg_name" >> "$tmp_ini"
        mv "$tmp_ini" "$mcp_ini"
    else
        printf '%s=%s\n' "$server_name" "$pkg_name" >> "$mcp_ini"
    fi

    # Now configure Claude to use this server
    # Build the MCP server config entry
    local mcp_config_file="$HOME/.claudebox/mcp-config.json"

    # Create or update the MCP config
    if [[ -f "$mcp_config_file" ]]; then
        # Merge new server into existing config
        local tmp_config
        tmp_config=$(mktemp)
        jq --arg name "$server_name" \
           --arg cmd "$cmd_name" \
           --arg args "$args_template" \
           '.mcpServers[$name] = {
                "command": $cmd,
                "args": ($args | split(" "))
            }' "$mcp_config_file" > "$tmp_config"
        mv "$tmp_config" "$mcp_config_file"
    else
        # Create new config
        jq -n --arg name "$server_name" \
              --arg cmd "$cmd_name" \
              --arg args "$args_template" \
              '{mcpServers: {($name): {
                    "command": $cmd,
                    "args": ($args | split(" "))
                }}}' > "$mcp_config_file"
    fi

    cecho "MCP server '$server_name' installed" "$GREEN"
    printf "  Package: %s\n" "$pkg_name"
    printf "  Command: %s %s\n" "$cmd_name" "$args_template"
    printf '\n'
    printf '%s\n' "The server will be available in all containers for this project."
    printf '%s\n' "You may need to enable it in your Claude settings."
}

_mcp_remove() {
    if [[ $# -eq 0 ]]; then
        error "Usage: claudebox mcp remove <server-name>"
    fi

    local server_name="$1"
    local mcp_ini="$HOME/.claudebox/mcp-servers.ini"
    local mcp_config_file="$HOME/.claudebox/mcp-config.json"

    # Check if installed
    if [[ ! -f "$mcp_ini" ]] || ! grep -q "^${server_name}=" "$mcp_ini" 2>/dev/null; then
        error "MCP server '$server_name' is not installed"
    fi

    # Get package name before removing
    local pkg_name
    pkg_name=$(grep "^${server_name}=" "$mcp_ini" | cut -d= -f2-)

    # Remove from ini
    local tmp_ini="${mcp_ini}.tmp"
    grep -v "^${server_name}=" "$mcp_ini" > "$tmp_ini" || true
    mv "$tmp_ini" "$mcp_ini"

    # Remove from MCP config
    if [[ -f "$mcp_config_file" ]]; then
        local tmp_config
        tmp_config=$(mktemp)
        jq --arg name "$server_name" 'del(.mcpServers[$name])' "$mcp_config_file" > "$tmp_config"
        mv "$tmp_config" "$mcp_config_file"
    fi

    # Uninstall from image
    if [[ -n "${IMAGE_NAME:-}" ]] || IMAGE_NAME=$(get_image_name); then
        if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
            local temp_container="claudebox-mcp-remove-$$"
            docker run -d --name "$temp_container" \
                "$IMAGE_NAME" bash -c "
                    source \$HOME/.nvm/nvm.sh
                    nvm use default >/dev/null 2>&1
                    npm uninstall -g $pkg_name 2>/dev/null || true
                    sleep 1
                " >/dev/null

            docker wait "$temp_container" >/dev/null 2>&1
            docker commit "$temp_container" "$IMAGE_NAME" >/dev/null
            docker rm -f "$temp_container" >/dev/null 2>&1
        fi
    fi

    cecho "MCP server '$server_name' removed" "$YELLOW"
}

_mcp_list() {
    logo_small
    printf '\n'
    cecho "Known MCP Servers:" "$CYAN"
    printf '\n'
    _mcp_list_known
    printf '\n'

    # Show installed
    local installed
    installed=$(_mcp_get_installed)
    if [[ -n "$installed" ]]; then
        cecho "Currently installed:" "$GREEN"
        printf '\n'
        while IFS= read -r name; do
            if [[ -n "$name" ]]; then
                printf "  ${GREEN}%-25s${NC} ✓\n" "$name"
            fi
        done <<< "$installed"
        printf '\n'
    fi

    printf '%s\n' "Install any npm MCP server package:"
    printf "  ${CYAN}claudebox mcp install <name>${NC}\n"
    printf "  ${CYAN}claudebox mcp install @org/custom-server${NC}\n"
    printf '\n'
}

_mcp_status() {
    printf '\n'
    cecho "MCP Server Status:" "$CYAN"
    printf '\n'

    local mcp_ini="$HOME/.claudebox/mcp-servers.ini"
    local mcp_config_file="$HOME/.claudebox/mcp-config.json"

    # Show installed servers
    if [[ -f "$mcp_ini" ]]; then
        local has_servers=false
        while IFS='=' read -r name pkg; do
            if [[ -n "$name" ]] && [[ "$name" != \[* ]] && [[ "$name" != \#* ]]; then
                has_servers=true
                printf "  ${GREEN}%-20s${NC} → %s\n" "$name" "$pkg"
            fi
        done < "$mcp_ini"

        if [[ "$has_servers" == "false" ]]; then
            printf "  %s\n" "No MCP servers installed"
        fi
    else
        printf "  %s\n" "No MCP servers installed"
    fi
    printf '\n'

    # Show config file status
    if [[ -f "$mcp_config_file" ]]; then
        local server_count
        server_count=$(jq '.mcpServers | length' "$mcp_config_file" 2>/dev/null || printf '0')
        printf "  Config: %s server(s) configured in %s\n" "$server_count" "$mcp_config_file"
    fi
    printf '\n'
}

export -f _cmd_mcp _mcp_install _mcp_remove _mcp_list _mcp_status
export -f _mcp_resolve_server _mcp_list_known _mcp_get_installed
