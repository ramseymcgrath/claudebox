#!/usr/bin/env bash
# Dashboard Command - Interactive container management
# ============================================================================
# Commands: dash
# Shows all ClaudeBox containers across all projects with actions

# Gather all containers across all projects into parallel arrays
# Sets: DASH_PROJECTS, DASH_SLOTS, DASH_HASHES, DASH_AUTHS, DASH_STATUSES,
#       DASH_CONTAINERS, DASH_PATHS, DASH_COUNT
_dash_gather_containers() {
    DASH_PROJECTS=()
    DASH_SLOTS=()
    DASH_HASHES=()
    DASH_AUTHS=()
    DASH_STATUSES=()
    DASH_CONTAINERS=()
    DASH_PATHS=()
    DASH_COUNT=0

    for parent_dir in "$HOME/.claudebox/projects"/*/ ; do
        if [[ ! -d "$parent_dir" ]]; then
            continue
        fi

        local parent_name
        parent_name=$(basename "$parent_dir")

        # Read project path if stored
        local project_path="$parent_name"
        if [[ -f "$parent_dir/.project_path" ]]; then
            project_path=$(cat "$parent_dir/.project_path")
        fi

        local max=0
        if [[ -f "$parent_dir/.project_container_counter" ]]; then
            read -r max < "$parent_dir/.project_container_counter"
        fi

        if [[ $max -eq 0 ]]; then
            continue
        fi

        # We need the original path to generate container names via CRC chain
        # Use stored project path for name generation
        local orig_path="$project_path"

        for ((idx=1; idx<=max; idx++)); do
            local name
            name=$(generate_container_name "$orig_path" "$idx")
            local dir="$parent_dir/$name"

            # Skip dead slots
            if [[ ! -d "$dir" ]]; then
                continue
            fi

            local auth="Unauthenticated"
            if [[ -f "$dir/.claude/.credentials.json" ]]; then
                auth="Authenticated"
            fi

            local status="Inactive"
            local full_container="claudebox-${parent_name}-${name}"
            if docker ps --format "{{.Names}}" | grep -q "^${full_container}$"; then
                status="Active"
            fi

            DASH_PROJECTS+=("$project_path")
            DASH_SLOTS+=("$idx")
            DASH_HASHES+=("$name")
            DASH_AUTHS+=("$auth")
            DASH_STATUSES+=("$status")
            DASH_CONTAINERS+=("$full_container")
            DASH_PATHS+=("$parent_dir")
            DASH_COUNT=$((DASH_COUNT + 1))
        done
    done
}

# Display the dashboard table
_dash_display() {
    printf "\033[2J\033[H"
    logo_small
    printf '\n'
    cecho "Dashboard - All Containers" "$CYAN"
    printf '\n'

    if [[ $DASH_COUNT -eq 0 ]]; then
        printf '  %s\n' "No containers found across any project."
        printf '\n'
        printf '  %s\n' "Run 'claudebox create' in a project directory to get started."
        printf '\n'
        return 1
    fi

    # Header
    printf "  ${WHITE}%-4s  %-7s  %-16s  %-10s  %s${NC}\n" "#" "Status" "Auth" "Slot" "Project"
    printf "  %-4s  %-7s  %-16s  %-10s  %s\n" "---" "-------" "----------------" "----------" "-------"

    local i=0
    while [[ $i -lt $DASH_COUNT ]]; do
        local num=$((i + 1))
        local status="${DASH_STATUSES[$i]}"
        local auth="${DASH_AUTHS[$i]}"
        local slot_label="Slot ${DASH_SLOTS[$i]}"
        local project="${DASH_PROJECTS[$i]}"

        # Truncate long project paths
        if [[ ${#project} -gt 40 ]]; then
            project="...${project: -37}"
        fi

        local status_color="$RED"
        local status_icon="*"
        if [[ "$status" == "Active" ]]; then
            status_color="$GREEN"
            status_icon="*"
        fi

        local auth_color="$YELLOW"
        if [[ "$auth" == "Authenticated" ]]; then
            auth_color="$GREEN"
        fi

        printf "  ${WHITE}%-4s${NC}  ${status_color}%-7s${NC}  ${auth_color}%-16s${NC}  %-10s  %s\n" \
            "$num" "$status" "$auth" "$slot_label" "$project"

        i=$((i + 1))
    done

    printf '\n'
}

# Show action menu for a selected container
_dash_action_menu() {
    local idx="$1"
    local status="${DASH_STATUSES[$idx]}"
    local container="${DASH_CONTAINERS[$idx]}"
    local hash="${DASH_HASHES[$idx]}"
    local slot="${DASH_SLOTS[$idx]}"
    local project="${DASH_PROJECTS[$idx]}"
    local parent_dir="${DASH_PATHS[$idx]}"

    printf '\n'
    cecho "  Selected: Slot ${slot} - ${project}" "$WHITE"
    printf "  Container: %s\n" "$container"
    printf "  Hash: %s\n" "$hash"
    printf '\n'

    # Build action list based on container state
    local actions=()
    local action_labels=()

    if [[ "$status" == "Active" ]]; then
        actions+=("attach")
        action_labels+=("Connect (attach to running container)")
        actions+=("kill")
        action_labels+=("Kill (forcefully stop container)")
    else
        actions+=("launch")
        action_labels+=("Launch (start this slot)")
    fi

    actions+=("info")
    action_labels+=("Info (show slot details)")
    actions+=("delete")
    action_labels+=("Delete (revoke this slot)")
    actions+=("back")
    action_labels+=("Back to dashboard")

    local a=0
    while [[ $a -lt ${#actions[@]} ]]; do
        local label="${action_labels[$a]}"
        local letter=""
        case "${actions[$a]}" in
            attach)  letter="c" ;;
            launch)  letter="l" ;;
            kill)    letter="k" ;;
            info)    letter="i" ;;
            delete)  letter="d" ;;
            back)    letter="b" ;;
        esac
        printf "  [${CYAN}%s${NC}] %s\n" "$letter" "$label"
        a=$((a + 1))
    done
    printf '\n'

    local choice=""
    printf "  Action: "
    read -r choice

    case "$choice" in
        c)
            if [[ "$status" == "Active" ]]; then
                printf '\n'
                info "Attaching to $container..."
                docker attach "$container"
                return 2
            fi
            ;;
        l)
            if [[ "$status" != "Active" ]]; then
                printf '\n'
                info "Launching slot ${slot}..."
                # Change to the project directory and run
                if cd "$project" 2>/dev/null; then
                    run_claudebox_container "$container" "interactive"
                    return 2
                else
                    warn "Cannot access project directory: $project"
                fi
            fi
            ;;
        k)
            if [[ "$status" == "Active" ]]; then
                printf '\n'
                warn "Killing container: $container"
                if docker kill "$container" >/dev/null 2>&1; then
                    success "Container killed"
                else
                    warn "Failed to kill container"
                fi
                sleep 1
            fi
            ;;
        i)
            printf '\n'
            _dash_show_slot_info "$idx"
            printf '\n'
            printf "  Press Enter to continue..."
            read -r
            ;;
        d)
            _dash_delete_slot "$idx"
            sleep 1
            ;;
        b|"")
            return 0
            ;;
        *)
            warn "  Unknown action: $choice"
            sleep 1
            ;;
    esac
    return 0
}

# Show detailed info for a slot
_dash_show_slot_info() {
    local idx="$1"
    local status="${DASH_STATUSES[$idx]}"
    local container="${DASH_CONTAINERS[$idx]}"
    local hash="${DASH_HASHES[$idx]}"
    local slot="${DASH_SLOTS[$idx]}"
    local project="${DASH_PROJECTS[$idx]}"
    local parent_dir="${DASH_PATHS[$idx]}"
    local slot_dir="${parent_dir}/${hash}"

    cecho "  Slot Details" "$CYAN"
    printf "  %-14s %s\n" "Project:" "$project"
    printf "  %-14s %s\n" "Slot:" "$slot"
    printf "  %-14s %s\n" "Hash:" "$hash"
    printf "  %-14s %s\n" "Container:" "$container"
    printf "  %-14s %s\n" "Status:" "$status"
    printf "  %-14s %s\n" "Auth:" "${DASH_AUTHS[$idx]}"
    printf "  %-14s %s\n" "Slot Dir:" "$slot_dir"

    # Show resource usage if active
    if [[ "$status" == "Active" ]]; then
        local stats
        stats=$(docker stats --no-stream --format "CPU: {{.CPUPerc}}, Mem: {{.MemUsage}}" "$container" 2>/dev/null || echo "")
        if [[ -n "$stats" ]]; then
            printf "  %-14s %s\n" "Resources:" "$stats"
        fi
        local uptime
        uptime=$(docker inspect --format '{{.State.StartedAt}}' "$container" 2>/dev/null | cut -d'.' -f1 || echo "")
        if [[ -n "$uptime" ]]; then
            printf "  %-14s %s\n" "Started:" "$uptime"
        fi
    fi

    # Show slot directory size
    if [[ -d "$slot_dir" ]]; then
        local dir_size
        dir_size=$(du -sh "$slot_dir" 2>/dev/null | cut -f1 || echo "unknown")
        printf "  %-14s %s\n" "Disk:" "$dir_size"
    fi
}

# Delete (revoke) a slot
_dash_delete_slot() {
    local idx="$1"
    local status="${DASH_STATUSES[$idx]}"
    local container="${DASH_CONTAINERS[$idx]}"
    local hash="${DASH_HASHES[$idx]}"
    local slot="${DASH_SLOTS[$idx]}"
    local parent_dir="${DASH_PATHS[$idx]}"
    local slot_dir="${parent_dir}/${hash}"

    if [[ "$status" == "Active" ]]; then
        warn "  Cannot delete an active container. Kill it first."
        return 1
    fi

    printf '\n'
    printf "  ${YELLOW}Delete slot %s (%s)?${NC} [y/N] " "$slot" "$hash"
    local confirm=""
    read -r confirm

    if [[ "$confirm" == "y" ]] || [[ "$confirm" == "Y" ]]; then
        if rm -rf "$slot_dir"; then
            success "  Slot $slot deleted"
        else
            warn "  Failed to delete slot"
        fi
    else
        info "  Cancelled"
    fi
}

# Main dashboard command - interactive loop
_cmd_dash() {
    # Check if any projects exist
    if [[ ! -d "$HOME/.claudebox/projects" ]]; then
        logo_small
        printf '\n'
        printf '  %s\n' "No ClaudeBox projects found."
        printf '\n'
        printf '  %s\n' "Run 'claudebox' in a project directory to get started."
        printf '\n'
        exit 0
    fi

    while true; do
        _dash_gather_containers

        _dash_display
        if [[ $DASH_COUNT -eq 0 ]]; then
            exit 0
        fi

        printf "  Select container [1-%d] or [${CYAN}q${NC}]uit: " "$DASH_COUNT"
        local selection=""
        read -r selection

        # Handle quit
        if [[ "$selection" == "q" ]] || [[ "$selection" == "Q" ]]; then
            printf '\n'
            exit 0
        fi

        # Validate selection
        if [[ ! "$selection" =~ ^[0-9]+$ ]]; then
            continue
        fi

        if [[ $selection -lt 1 ]] || [[ $selection -gt $DASH_COUNT ]]; then
            warn "  Invalid selection"
            sleep 1
            continue
        fi

        local container_idx=$((selection - 1))
        local action_result=0
        _dash_action_menu "$container_idx" || action_result=$?

        # Return code 2 means we launched/attached - exit dashboard
        if [[ $action_result -eq 2 ]]; then
            exit 0
        fi
    done
}

export -f _cmd_dash _dash_gather_containers _dash_display _dash_action_menu
export -f _dash_show_slot_info _dash_delete_slot
