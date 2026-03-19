#!/usr/bin/env bash
# Agent Commands - Plugin and agent management
# ============================================================================
# Command: agent
# Manages Claude Code plugins and ClaudeBox command agents
#
# Wraps Claude Code's native plugin system to work with ClaudeBox's
# ephemeral container model. Plugins are installed into the shared
# slot directory so they persist across container restarts.

# Shared plugin directory for cross-slot persistence
_agent_shared_dir() {
    local parent_dir
    parent_dir=$(get_parent_dir "$PROJECT_DIR")
    printf '%s' "$parent_dir/plugins"
}

# Run a claude plugin command inside a temporary container and commit
_agent_run_in_container() {
    local plugin_cmd="$1"
    shift

    # Need an image to run in
    if [[ -z "${IMAGE_NAME:-}" ]]; then
        IMAGE_NAME=$(get_image_name 2>/dev/null || echo "")
    fi
    if [[ -z "$IMAGE_NAME" ]] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        error "No Docker image found. Run 'claudebox' first to build the image."
    fi

    local project_folder_name
    project_folder_name=$(get_project_folder_name "$PROJECT_DIR" 2>/dev/null || echo "NONE")
    if [[ "$project_folder_name" == "NONE" ]]; then
        error "No slots found. Create a slot first with 'claudebox create'"
    fi

    local temp_container="claudebox-agent-$$"

    # Run the claude plugin command inside a container
    run_claudebox_container "$temp_container" "detached" "plugin" "$plugin_cmd" "$@" >/dev/null

    fillbar
    docker wait "$temp_container" >/dev/null
    fillbar stop

    # Show output
    docker logs "$temp_container" 2>&1

    # Commit changes
    docker commit "$temp_container" "$IMAGE_NAME" >/dev/null
    docker stop "$temp_container" >/dev/null 2>&1 || true
    docker rm "$temp_container" >/dev/null 2>&1 || true
}

# Sync plugin state from one slot to all other slots
_agent_sync_plugins() {
    local parent_dir
    parent_dir=$(get_parent_dir "$PROJECT_DIR")
    local max
    max=$(read_counter "$parent_dir")
    local source_slot="${1:-}"

    if [[ -z "$source_slot" ]]; then
        # Find first slot with plugins
        for ((idx=1; idx<=max; idx++)); do
            local name
            name=$(generate_container_name "$PROJECT_DIR" "$idx")
            local slot_dir="$parent_dir/$name"
            if [[ -d "$slot_dir/.claude/plugins" ]]; then
                source_slot="$name"
                break
            fi
        done
    fi

    if [[ -z "$source_slot" ]]; then
        info "No plugins found to sync."
        return 0
    fi

    local source_dir="$parent_dir/$source_slot/.claude/plugins"
    if [[ ! -d "$source_dir" ]]; then
        info "No plugins directory in source slot."
        return 0
    fi

    local synced=0
    for ((idx=1; idx<=max; idx++)); do
        local name
        name=$(generate_container_name "$PROJECT_DIR" "$idx")
        local slot_dir="$parent_dir/$name"

        # Skip source slot and non-existent slots
        if [[ "$name" == "$source_slot" ]]; then
            continue
        fi
        if [[ ! -d "$slot_dir" ]]; then
            continue
        fi

        # Sync plugins directory
        mkdir -p "$slot_dir/.claude/plugins"
        rsync -a --delete "$source_dir/" "$slot_dir/.claude/plugins/" 2>/dev/null || \
            cp -a "$source_dir/." "$slot_dir/.claude/plugins/" 2>/dev/null || true

        # Also sync plugin settings from settings.json if present
        if [[ -f "$parent_dir/$source_slot/.claude/settings.json" ]]; then
            if [[ ! -f "$slot_dir/.claude/settings.json" ]]; then
                cp "$parent_dir/$source_slot/.claude/settings.json" "$slot_dir/.claude/settings.json"
            fi
        fi

        ((synced++)) || true
    done

    if [[ $synced -gt 0 ]]; then
        success "Synced plugins to $synced slot(s)"
    fi
}

# List installed plugins by reading slot directory
_agent_list_installed() {
    local parent_dir
    parent_dir=$(get_parent_dir "$PROJECT_DIR")
    local project_folder_name
    project_folder_name=$(get_project_folder_name "$PROJECT_DIR" 2>/dev/null || echo "NONE")

    if [[ "$project_folder_name" == "NONE" ]]; then
        printf "  ${DIM}No slots found. Create one with 'claudebox create'${NC}\n"
        return 0
    fi

    local slot_dir="$parent_dir/$project_folder_name"
    local plugins_dir="$slot_dir/.claude/plugins"
    local settings_file="$slot_dir/.claude/settings.json"

    printf '\n'
    cecho "Installed Plugins:" "$CYAN"
    printf '\n'

    local found=false

    # Check plugins cache directory
    if [[ -d "$plugins_dir/cache" ]]; then
        for plugin_dir in "$plugins_dir/cache"/*/; do
            if [[ -d "$plugin_dir" ]]; then
                local plugin_name
                plugin_name=$(basename "$plugin_dir")
                # Try to get description from plugin.json
                local desc=""
                if [[ -f "$plugin_dir/.claude-plugin/plugin.json" ]]; then
                    desc=$(grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' "$plugin_dir/.claude-plugin/plugin.json" 2>/dev/null | head -1 | sed 's/"description"[[:space:]]*:[[:space:]]*"//;s/"$//' || true)
                fi
                if [[ -n "$desc" ]]; then
                    printf "    ${GREEN}%-30s${NC} %s\n" "$plugin_name" "$desc"
                else
                    printf "    ${GREEN}%-30s${NC}\n" "$plugin_name"
                fi
                found=true
            fi
        done
    fi

    if [[ "$found" == "false" ]]; then
        printf "    ${DIM}No plugins installed yet.${NC}\n"
    fi

    # Show bundled ClaudeBox commands
    printf '\n'
    cecho "Bundled ClaudeBox Commands:" "$CYAN"
    printf '\n'

    local cbox_commands="${CLAUDEBOX_SCRIPT_DIR:-${SCRIPT_DIR}}/commands"
    if [[ -d "$cbox_commands" ]]; then
        for cmd_file in "$cbox_commands"/*.md; do
            if [[ -f "$cmd_file" ]]; then
                local cmd_name
                cmd_name=$(basename "$cmd_file" .md)
                # Get first line that looks like a title or description
                local desc
                desc=$(head -5 "$cmd_file" | grep -m1 '^#' | sed 's/^#\+[[:space:]]*//' || true)
                if [[ -z "$desc" ]]; then
                    desc=$(head -3 "$cmd_file" | grep -v '^$' | head -1 || true)
                fi
                printf "    ${GREEN}%-30s${NC} %s\n" "$cmd_name" "$desc"
            fi
        done
        # Show subdirectories
        for cmd_dir in "$cbox_commands"/*/; do
            if [[ -d "$cmd_dir" ]]; then
                local dir_name
                dir_name=$(basename "$cmd_dir")
                local file_count
                file_count=$(find "$cmd_dir" -name "*.md" -type f | wc -l | tr -d ' ')
                printf "    ${GREEN}%-30s${NC} ${DIM}(%s commands)${NC}\n" "$dir_name/" "$file_count"
            fi
        done
    fi

    printf '\n'
}

# Show popular/recommended plugins
_agent_show_popular() {
    printf '\n'
    cecho "Popular Plugins:" "$CYAN"
    printf '\n'
    cecho "  Code Intelligence (LSP):" "$YELLOW"
    printf "    ${GREEN}%-28s${NC} %s\n" "typescript-lsp" "TypeScript/JavaScript language server"
    printf "    ${GREEN}%-28s${NC} %s\n" "pyright-lsp" "Python type checking and language server"
    printf "    ${GREEN}%-28s${NC} %s\n" "rust-analyzer-lsp" "Rust language server"
    printf "    ${GREEN}%-28s${NC} %s\n" "gopls-lsp" "Go language server"
    printf '\n'
    cecho "  Development Workflows:" "$YELLOW"
    printf "    ${GREEN}%-28s${NC} %s\n" "commit-commands" "Git commit, push, and PR creation"
    printf "    ${GREEN}%-28s${NC} %s\n" "code-review" "Automated PR review with confidence scoring"
    printf "    ${GREEN}%-28s${NC} %s\n" "feature-dev" "Comprehensive feature development workflow"
    printf "    ${GREEN}%-28s${NC} %s\n" "plugin-dev" "Toolkit for creating Claude Code plugins"
    printf '\n'
    cecho "  Integrations:" "$YELLOW"
    printf "    ${GREEN}%-28s${NC} %s\n" "github" "Official GitHub MCP server"
    printf "    ${GREEN}%-28s${NC} %s\n" "gitlab" "GitLab DevOps platform"
    printf "    ${GREEN}%-28s${NC} %s\n" "linear" "Linear issue tracking"
    printf "    ${GREEN}%-28s${NC} %s\n" "slack" "Slack workspace integration"
    printf "    ${GREEN}%-28s${NC} %s\n" "sentry" "Error monitoring and debugging"
    printf "    ${GREEN}%-28s${NC} %s\n" "context7" "Version-specific library documentation"
    printf '\n'
    cecho "  Productivity:" "$YELLOW"
    printf "    ${GREEN}%-28s${NC} %s\n" "security-guidance" "Security issue warnings during editing"
    printf "    ${GREEN}%-28s${NC} %s\n" "hookify" "Custom hooks to prevent unwanted behaviors"
    printf "    ${GREEN}%-28s${NC} %s\n" "playground" "Interactive HTML playgrounds"
    printf '\n'
    printf "  ${DIM}Install with: claudebox agent install <name>${NC}\n"
    printf "  ${DIM}Browse all with: claudebox agent browse${NC}\n"
    printf '\n'
}

# Main agent command dispatcher
_cmd_agent() {
    local subcmd="${1:-}"
    shift || true

    case "$subcmd" in
        install|add)
            local plugin_name="${1:-}"
            if [[ -z "$plugin_name" ]]; then
                error "Usage: claudebox agent install <plugin-name>\n\nExamples:\n  claudebox agent install commit-commands\n  claudebox agent install github\n  claudebox agent install typescript-lsp\n\nRun 'claudebox agent popular' to see recommended plugins."
            fi

            info "Installing plugin: $plugin_name"
            printf '\n'
            _agent_run_in_container "install" "$plugin_name"
            printf '\n'

            # Offer to sync to other slots
            local parent_dir
            parent_dir=$(get_parent_dir "$PROJECT_DIR")
            local max
            max=$(read_counter "$parent_dir")
            if [[ $max -gt 1 ]]; then
                printf '\n'
                printf "  ${WHITE}Sync this plugin to all %d slots? [Y/n]${NC} " "$max"
                local answer
                IFS= read -r answer 2>/dev/null || true
                answer="${answer:-y}"
                case "$answer" in
                    [yY]|[yY][eE][sS])
                        _agent_sync_plugins
                        ;;
                esac
            fi
            ;;

        remove|uninstall|rm)
            local plugin_name="${1:-}"
            if [[ -z "$plugin_name" ]]; then
                error "Usage: claudebox agent remove <plugin-name>"
            fi

            info "Removing plugin: $plugin_name"
            printf '\n'
            _agent_run_in_container "uninstall" "$plugin_name"
            ;;

        list|ls)
            _agent_list_installed
            ;;

        popular|recommended)
            logo_small
            _agent_show_popular
            ;;

        browse)
            # Open interactive plugin browser inside container
            info "Opening plugin browser..."
            printf "  ${DIM}Use Tab to navigate, Enter to select, q to quit.${NC}\n"
            printf '\n'

            # Need a running container for interactive use
            if [[ -z "${IMAGE_NAME:-}" ]]; then
                IMAGE_NAME=$(get_image_name 2>/dev/null || echo "")
            fi
            if [[ -z "$IMAGE_NAME" ]] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
                error "No Docker image found. Run 'claudebox' first to build the image."
            fi

            # Run claude with /plugin command interactively
            run_claudebox_container "" "interactive" "-p" "/plugin"
            ;;

        marketplace|market)
            local market_subcmd="${1:-}"
            shift || true

            case "$market_subcmd" in
                add)
                    local repo="${1:-}"
                    if [[ -z "$repo" ]]; then
                        printf '\n'
                        cecho "Add a Plugin Marketplace" "$CYAN"
                        printf '\n'
                        printf "  Usage: claudebox agent marketplace add <source>\n"
                        printf '\n'
                        cecho "  Sources:" "$YELLOW"
                        printf "    ${GREEN}owner/repo${NC}              GitHub repository\n"
                        printf "    ${GREEN}https://...${NC}             Git URL or marketplace.json URL\n"
                        printf "    ${GREEN}./local-path${NC}            Local directory\n"
                        printf '\n'
                        cecho "  Popular Marketplaces:" "$YELLOW"
                        printf "    ${GREEN}anthropics/claude-code${NC}          Anthropic demo plugins\n"
                        printf "    ${GREEN}hyperskill/claude-code-marketplace${NC}  Hyperskill curated collection\n"
                        printf '\n'
                        printf "  ${DIM}The official Anthropic marketplace is available by default.${NC}\n"
                        printf '\n'
                        exit 1
                    fi

                    info "Adding marketplace: $repo"
                    printf '\n'
                    _agent_run_in_container "marketplace" "add" "$repo"
                    ;;

                list|ls)
                    _agent_run_in_container "marketplace" "list"
                    ;;

                remove|rm)
                    local repo="${1:-}"
                    if [[ -z "$repo" ]]; then
                        error "Usage: claudebox agent marketplace remove <name>"
                    fi
                    _agent_run_in_container "marketplace" "remove" "$repo"
                    ;;

                update)
                    local repo="${1:-}"
                    if [[ -n "$repo" ]]; then
                        _agent_run_in_container "marketplace" "update" "$repo"
                    else
                        info "Updating all marketplaces..."
                        _agent_run_in_container "marketplace" "update"
                    fi
                    ;;

                *)
                    logo_small
                    printf '\n'
                    cecho "Plugin Marketplace Management:" "$CYAN"
                    printf '\n'
                    printf "  ${GREEN}agent marketplace add <source>${NC}    Add a marketplace\n"
                    printf "  ${GREEN}agent marketplace list${NC}            List configured marketplaces\n"
                    printf "  ${GREEN}agent marketplace update${NC}          Update marketplace listings\n"
                    printf "  ${GREEN}agent marketplace remove <name>${NC}   Remove a marketplace\n"
                    printf '\n'
                    printf "  ${DIM}The official Anthropic marketplace (100+ plugins) is available by default.${NC}\n"
                    printf "  ${DIM}Add community marketplaces with 'claudebox agent marketplace add owner/repo'${NC}\n"
                    printf '\n'
                    ;;
            esac
            ;;

        sync)
            info "Syncing plugins across all slots..."
            _agent_sync_plugins
            ;;

        search)
            local query="${1:-}"
            if [[ -z "$query" ]]; then
                error "Usage: claudebox agent search <query>"
            fi
            # Search through known plugins
            printf '\n'
            cecho "Searching for: $query" "$CYAN"
            printf '\n'
            printf "  ${DIM}For full search, use 'claudebox agent browse' to open the interactive browser.${NC}\n"
            printf '\n'
            # Basic local search through popular plugins
            local found=false
            local query_lower
            query_lower=$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')

            # Search through a curated list
            _agent_search_match() {
                local name="$1"
                local desc="$2"
                local name_lower
                name_lower=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
                local desc_lower
                desc_lower=$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')
                if [[ "$name_lower" == *"$query_lower"* ]] || [[ "$desc_lower" == *"$query_lower"* ]]; then
                    printf "    ${GREEN}%-28s${NC} %s\n" "$name" "$desc"
                    found=true
                fi
            }

            # LSP
            _agent_search_match "typescript-lsp" "TypeScript/JavaScript language server"
            _agent_search_match "pyright-lsp" "Python type checking and language server"
            _agent_search_match "rust-analyzer-lsp" "Rust language server"
            _agent_search_match "gopls-lsp" "Go language server"
            _agent_search_match "clangd-lsp" "C/C++ language server"
            _agent_search_match "jdtls-lsp" "Java language server"
            _agent_search_match "ruby-lsp" "Ruby language server"
            _agent_search_match "swift-lsp" "Swift language server"
            _agent_search_match "php-lsp" "PHP language server"
            _agent_search_match "kotlin-lsp" "Kotlin language server"
            _agent_search_match "csharp-lsp" "C# language server"
            _agent_search_match "lua-lsp" "Lua language server"
            # Development
            _agent_search_match "commit-commands" "Git commit workflows and PR creation"
            _agent_search_match "code-review" "Automated PR review with confidence scoring"
            _agent_search_match "pr-review-toolkit" "Specialized PR review agents"
            _agent_search_match "feature-dev" "Comprehensive feature development workflow"
            _agent_search_match "frontend-design" "Production-grade frontend UI design"
            _agent_search_match "plugin-dev" "Toolkit for creating Claude Code plugins"
            _agent_search_match "agent-sdk-dev" "Development kit for Claude Agent SDK"
            _agent_search_match "security-guidance" "Security issue warnings during editing"
            _agent_search_match "hookify" "Custom hooks to prevent unwanted behaviors"
            _agent_search_match "playground" "Interactive HTML playgrounds"
            _agent_search_match "code-simplifier" "Code refactoring for clarity"
            _agent_search_match "superpowers" "Brainstorming, subagent dev, TDD workflow"
            # Integrations
            _agent_search_match "github" "Official GitHub MCP server"
            _agent_search_match "gitlab" "GitLab DevOps platform"
            _agent_search_match "linear" "Linear issue tracking"
            _agent_search_match "slack" "Slack workspace integration"
            _agent_search_match "sentry" "Error monitoring and debugging"
            _agent_search_match "context7" "Version-specific library documentation"
            _agent_search_match "notion" "Notion workspace integration"
            _agent_search_match "asana" "Asana project management"
            _agent_search_match "atlassian" "Jira and Confluence integration"
            _agent_search_match "figma" "Figma design file integration"
            _agent_search_match "discord" "Discord messaging bridge"
            _agent_search_match "telegram" "Telegram messaging bridge"
            _agent_search_match "zapier" "Connect 8,000+ apps to workflow"
            # Infrastructure
            _agent_search_match "firebase" "Firebase backend services"
            _agent_search_match "supabase" "Supabase backend platform"
            _agent_search_match "vercel" "Vercel deployment platform"
            _agent_search_match "railway" "Railway app deployment"
            _agent_search_match "terraform" "Terraform Infrastructure as Code"
            _agent_search_match "neon" "Neon PostgreSQL management"
            _agent_search_match "planetscale" "PlanetScale MySQL hosting"
            _agent_search_match "pinecone" "Pinecone vector database"
            _agent_search_match "posthog" "PostHog analytics and feature flags"
            _agent_search_match "playwright" "Browser automation and E2E testing"
            _agent_search_match "firecrawl" "Web scraping into LLM-ready markdown"
            _agent_search_match "semgrep" "Real-time security vulnerability detection"

            if [[ "$found" == "false" ]]; then
                printf "    ${DIM}No matches found in local index.${NC}\n"
                printf "    ${DIM}Try 'claudebox agent browse' for the full interactive catalog.${NC}\n"
            fi
            printf '\n'
            ;;

        *)
            logo_small
            printf '\n'
            cecho "  Agent & Plugin Management" "$WHITE"
            printf '\n'
            cecho "  Install & Manage:" "$YELLOW"
            printf "    ${GREEN}agent install <name>${NC}        Install a plugin from the marketplace\n"
            printf "    ${GREEN}agent remove <name>${NC}         Remove an installed plugin\n"
            printf "    ${GREEN}agent list${NC}                  List installed plugins and agents\n"
            printf "    ${GREEN}agent sync${NC}                  Sync plugins across all slots\n"
            printf '\n'
            cecho "  Discover:" "$YELLOW"
            printf "    ${GREEN}agent popular${NC}               Show recommended plugins\n"
            printf "    ${GREEN}agent search <query>${NC}        Search available plugins\n"
            printf "    ${GREEN}agent browse${NC}                Interactive plugin browser\n"
            printf '\n'
            cecho "  Marketplaces:" "$YELLOW"
            printf "    ${GREEN}agent marketplace add <repo>${NC}  Add a community marketplace\n"
            printf "    ${GREEN}agent marketplace list${NC}        List configured marketplaces\n"
            printf "    ${GREEN}agent marketplace update${NC}      Refresh marketplace listings\n"
            printf '\n'
            cecho "  Quick Start:" "$CYAN"
            printf "    ${DIM}claudebox agent install commit-commands${NC}   Git workflow automation\n"
            printf "    ${DIM}claudebox agent install github${NC}            GitHub integration\n"
            printf "    ${DIM}claudebox agent install typescript-lsp${NC}    TypeScript intelligence\n"
            printf '\n'
            printf "  ${DIM}Plugins persist across container restarts and can be synced${NC}\n"
            printf "  ${DIM}across all slots. 100+ plugins available from the official${NC}\n"
            printf "  ${DIM}Anthropic marketplace, plus community marketplaces.${NC}\n"
            printf '\n'
            ;;
    esac
}

export -f _cmd_agent _agent_shared_dir _agent_run_in_container _agent_sync_plugins
export -f _agent_list_installed _agent_show_popular
