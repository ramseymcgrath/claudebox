#!/usr/bin/env bash
# Self-management Commands - Install, reinstall, uninstall ClaudeBox
# ============================================================================
# Commands: reinstall, uninstall

_cmd_reinstall() {
    logo_small
    printf '\n'
    cecho "Reinstalling ClaudeBox..." "$CYAN"
    printf '\n'

    # Step 1: Clean all Docker resources
    info "Removing Docker resources..."
    local containers
    containers=$(docker ps -a --format "{{.Names}}" 2>/dev/null | grep "^claudebox-" || true)
    if [[ -n "$containers" ]]; then
        printf '%s\n' "$containers" | xargs -r docker rm -f 2>/dev/null || true
    fi

    local images
    images=$(docker images --filter "reference=claudebox*" -q 2>/dev/null || true)
    if [[ -n "$images" ]]; then
        docker images --filter "reference=claudebox-*" -q | xargs -r docker rmi -f 2>/dev/null || true
        docker images --filter "reference=claudebox" -q | xargs -r docker rmi -f 2>/dev/null || true
    fi

    # Remove core image
    docker rmi -f claudebox-core 2>/dev/null || true

    # Prune build cache
    docker builder prune -af 2>/dev/null || true

    # Step 2: Remove source directory (will be re-extracted on next run)
    local source_dir="$HOME/.claudebox/source"
    if [[ -d "$source_dir" ]]; then
        rm -rf "$source_dir"
        info "Removed source directory"
    fi

    # Step 3: Remove cached archive so it re-extracts
    rm -f "$HOME/.claudebox/archive.tar.gz"

    # Step 4: Remove docker build context
    rm -rf "$HOME/.claudebox/docker-build-context"

    # Step 5: Remove layer checksums so images rebuild
    find "$HOME/.claudebox/projects" -name ".docker_layer_checksums" -delete 2>/dev/null || true

    # Step 6: Remove installed marker so welcome shows again if desired
    rm -f "$HOME/.claudebox/.installed"

    printf '\n'
    success "ClaudeBox reinstalled successfully"
    printf '\n'
    printf "  Run ${CYAN}claudebox${NC} to rebuild and start fresh.\n"
    printf "  Your projects, slots, and settings have been preserved.\n"
    printf '\n'
    exit 0
}

_cmd_uninstall() {
    logo_small
    printf '\n'
    cecho "Uninstall ClaudeBox" "$YELLOW"
    printf '\n'

    # Count what will be removed
    local project_count=0
    if [[ -d "$HOME/.claudebox/projects" ]]; then
        project_count=$(find "$HOME/.claudebox/projects" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    fi
    local image_count
    image_count=$(docker images --filter "reference=claudebox*" -q 2>/dev/null | wc -l | tr -d ' ')

    printf "  This will remove:\n"
    printf "    - ClaudeBox symlink (%s)\n" "$LINK_TARGET"
    printf "    - ClaudeBox data directory (~/.claudebox)\n"
    printf "    - %s project(s) and all slot data\n" "$project_count"
    printf "    - %s Docker image(s)\n" "$image_count"
    printf "    - All containers, build cache, and volumes\n"
    printf '\n'
    printf "  ${RED}This action is irreversible.${NC}\n"
    printf '\n'
    printf "  Type 'yes' to confirm: "
    local confirm
    IFS= read -r confirm 2>/dev/null || true

    if [[ "$confirm" != "yes" ]]; then
        printf '\n'
        info "Uninstall cancelled"
        printf '\n'
        exit 0
    fi

    printf '\n'

    # Step 1: Stop and remove all containers
    info "Removing containers..."
    local containers
    containers=$(docker ps -a --format "{{.Names}}" 2>/dev/null | grep "^claudebox-" || true)
    if [[ -n "$containers" ]]; then
        printf '%s\n' "$containers" | xargs -r docker rm -f 2>/dev/null || true
    fi

    # Step 2: Remove all images
    info "Removing Docker images..."
    docker images --filter "reference=claudebox-*" -q 2>/dev/null | xargs -r docker rmi -f 2>/dev/null || true
    docker images --filter "reference=claudebox" -q 2>/dev/null | xargs -r docker rmi -f 2>/dev/null || true
    docker rmi -f claudebox-core 2>/dev/null || true

    # Step 3: Remove volumes
    docker volume ls -q --filter "name=claudebox" 2>/dev/null | xargs -r docker volume rm 2>/dev/null || true

    # Step 4: Prune build cache
    docker builder prune -af 2>/dev/null || true

    # Step 5: Remove symlink
    if [[ -L "$LINK_TARGET" ]]; then
        rm -f "$LINK_TARGET"
        info "Removed symlink: $LINK_TARGET"
    fi

    # Step 6: Remove data directory
    if [[ -d "$HOME/.claudebox" ]]; then
        rm -rf "$HOME/.claudebox"
        info "Removed data directory: ~/.claudebox"
    fi

    printf '\n'
    success "ClaudeBox has been uninstalled"
    printf '\n'
    printf "  Your project source code is untouched.\n"
    printf "  To reinstall, run the installer script again.\n"
    printf '\n'
    exit 0
}

export -f _cmd_reinstall _cmd_uninstall
