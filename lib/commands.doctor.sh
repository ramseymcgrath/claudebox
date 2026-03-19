#!/usr/bin/env bash
# Doctor Command - Comprehensive diagnostic checklist
# ============================================================================
# Runs health checks on Docker, images, slots, disk, network, and version.

_cmd_doctor() {
    logo_small
    printf '\n'
    cecho "ClaudeBox Doctor" "$CYAN"
    printf '\n'

    local pass_count=0
    local warn_count=0
    local fail_count=0

    # Helper: print check result
    _doc_pass() { printf "  ${GREEN}✔${NC}  %s\n" "$1"; ((pass_count++)) || true; }
    _doc_warn() { printf "  ${YELLOW}⚠${NC}  %s\n" "$1"; ((warn_count++)) || true; }
    _doc_fail() { printf "  ${RED}✘${NC}  %s\n" "$1"; ((fail_count++)) || true; }

    # ---- 1. Docker connectivity ----
    printf '%s\n' "Docker"
    if command -v docker >/dev/null 2>&1; then
        _doc_pass "Docker CLI found: $(command -v docker)"
    else
        _doc_fail "Docker CLI not found — install Docker or add it to PATH"
        # Can't continue without docker
        printf '\n'
        _doctor_summary "$pass_count" "$warn_count" "$fail_count"
        exit 1
    fi

    if docker info >/dev/null 2>&1; then
        local runtime
        runtime=$(_docker_runtime)
        _doc_pass "Docker daemon running (runtime: $runtime)"
    else
        _doc_fail "Docker daemon not responding — start Docker or Colima"
        printf '\n'
        _doctor_summary "$pass_count" "$warn_count" "$fail_count"
        exit 1
    fi

    # ---- 2. VM resources (macOS only) ----
    if [[ "$HOST_OS" == "macOS" ]]; then
        printf '\n%s\n' "VM Resources"
        local host_mem
        host_mem=$(_get_host_memory_mb)
        local host_cpus
        host_cpus=$(_get_host_cpus)
        _doc_pass "Host: ${host_mem}MB RAM, ${host_cpus} CPUs"

        if _colima_installed && _colima_running; then
            local colima_mem
            colima_mem=$(colima status 2>/dev/null | grep -i memory | grep -o '[0-9]*' | head -1 || printf '0')
            local colima_cpus
            colima_cpus=$(colima status 2>/dev/null | grep -i cpu | grep -o '[0-9]*' | head -1 || printf '0')
            if [[ $colima_mem -gt 0 ]]; then
                _doc_pass "Colima VM: ${colima_mem}GB RAM, ${colima_cpus} CPUs"
            else
                _doc_warn "Could not read Colima resource info"
            fi
        fi
    fi

    # ---- 3. Core image ----
    printf '\n%s\n' "Images"
    if docker image inspect "claudebox-core" >/dev/null 2>&1; then
        local core_created
        core_created=$(docker inspect "claudebox-core" --format '{{.Created}}' 2>/dev/null | cut -dT -f1)
        _doc_pass "Core image exists (created: $core_created)"
    else
        _doc_warn "Core image not built — will be created on first run"
    fi

    # ---- 4. Project image ----
    local project_folder_name
    project_folder_name=$(generate_parent_folder_name "$PROJECT_DIR" 2>/dev/null || printf '')
    if [[ -n "$project_folder_name" ]]; then
        local proj_image="claudebox-${project_folder_name}"
        if docker image inspect "$proj_image" >/dev/null 2>&1; then
            local proj_created
            proj_created=$(docker inspect "$proj_image" --format '{{.Created}}' 2>/dev/null | cut -dT -f1)
            _doc_pass "Project image exists: $proj_image (created: $proj_created)"

            # Check staleness
            local parent_dir
            parent_dir=$(get_parent_dir "$PROJECT_DIR")
            if [[ -d "$parent_dir" ]]; then
                if needs_docker_rebuild "$PROJECT_DIR" "$proj_image" 2>/dev/null; then
                    _doc_warn "Project image is stale — run 'claudebox rebuild' or just launch claudebox"
                else
                    _doc_pass "Project image checksums match"
                fi
            fi
        else
            _doc_warn "No project image for current directory — will be built on first run"
        fi
    fi

    # ---- 5. Slot health ----
    printf '\n%s\n' "Slots"
    local parent_dir
    parent_dir=$(get_parent_dir "$PROJECT_DIR" 2>/dev/null || printf '')
    if [[ -d "$parent_dir" ]]; then
        local max_slot
        max_slot=$(read_counter "$parent_dir" 2>/dev/null || printf '0')
        local total_slots=0
        local auth_slots=0
        local active_slots=0
        local orphan_slots=0

        for ((idx=1; idx<=max_slot; idx++)); do
            local slot_name
            slot_name=$(generate_container_name "$PROJECT_DIR" "$idx")
            local slot_dir="$parent_dir/$slot_name"

            if [[ ! -d "$slot_dir" ]]; then
                continue
            fi
            ((total_slots++)) || true

            if [[ -f "$slot_dir/.claude/.credentials.json" ]]; then
                ((auth_slots++)) || true
            fi

            if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^claudebox-.*-${slot_name}$"; then
                ((active_slots++)) || true
            fi

            # Orphan: slot dir exists but no .claude subdirectory
            if [[ ! -d "$slot_dir/.claude" ]]; then
                ((orphan_slots++)) || true
            fi
        done

        _doc_pass "Slots: $total_slots total, $auth_slots authenticated, $active_slots active"

        if [[ $orphan_slots -gt 0 ]]; then
            _doc_warn "$orphan_slots orphaned slot(s) (missing .claude directory)"
        fi
    else
        _doc_warn "No project directory found for $PROJECT_DIR"
    fi

    # ---- 6. Running containers ----
    printf '\n%s\n' "Containers"
    local running_containers
    running_containers=$(docker ps --filter "name=^claudebox-" --format "{{.Names}}" 2>/dev/null || printf '')
    if [[ -n "$running_containers" ]]; then
        local container_count
        container_count=$(printf '%s\n' "$running_containers" | wc -l | tr -d ' ')
        _doc_pass "$container_count running ClaudeBox container(s)"

        # Check memory usage of running containers
        while IFS= read -r cname; do
            if [[ -z "$cname" ]]; then
                continue
            fi
            local mem_usage
            mem_usage=$(docker stats --no-stream --format "{{.MemUsage}}" "$cname" 2>/dev/null || printf 'N/A')
            local uptime
            uptime=$(docker inspect --format '{{.State.StartedAt}}' "$cname" 2>/dev/null | cut -dT -f1 || printf 'N/A')
            _doc_pass "  $cname — mem: $mem_usage, started: $uptime"
        done <<< "$running_containers"
    else
        _doc_pass "No running ClaudeBox containers"
    fi

    # ---- 7. Disk usage ----
    printf '\n%s\n' "Disk"
    local image_count
    image_count=$(docker images --filter "reference=claudebox-*" --format "{{.Repository}}" 2>/dev/null | wc -l | tr -d ' ')
    local total_image_size
    total_image_size=$(docker images --filter "reference=claudebox-*" --format "{{.Size}}" 2>/dev/null | head -5 | tr '\n' ', ' || printf 'N/A')
    _doc_pass "ClaudeBox images: $image_count ($total_image_size)"

    if [[ -d "$HOME/.claudebox" ]]; then
        local claudebox_size
        claudebox_size=$(du -sh "$HOME/.claudebox" 2>/dev/null | cut -f1 || printf 'N/A')
        _doc_pass "~/.claudebox data: $claudebox_size"
    fi

    local cache_size
    cache_size=$(docker system df --format "{{.Size}}" 2>/dev/null | tail -1 || printf 'N/A')
    if [[ -n "$cache_size" ]]; then
        _doc_pass "Docker build cache: $cache_size"
    fi

    # ---- 8. Network / firewall ----
    printf '\n%s\n' "Network"
    if [[ -n "${parent_dir:-}" ]] && [[ -f "$parent_dir/allowlist" ]]; then
        local rule_count
        rule_count=$(grep -cve '^\s*$' -e '^\s*#' "$parent_dir/allowlist" 2>/dev/null || printf '0')
        _doc_pass "Allowlist present ($rule_count rules)"
    else
        _doc_warn "No allowlist found for this project"
    fi

    # ---- 9. Version ----
    printf '\n%s\n' "Version"
    _doc_pass "ClaudeBox v${CLAUDEBOX_VERSION}"

    # Non-blocking remote version check
    local latest_version=""
    if command -v curl >/dev/null 2>&1; then
        latest_version=$(curl -sS --max-time 3 "https://raw.githubusercontent.com/ramseymcgrath/claudebox/main/main.sh" 2>/dev/null | grep -m1 'CLAUDEBOX_VERSION=' | sed 's/.*"\(.*\)".*/\1/' || printf '')
    fi
    if [[ -n "$latest_version" ]]; then
        if [[ "$latest_version" == "$CLAUDEBOX_VERSION" ]]; then
            _doc_pass "Up to date (v${CLAUDEBOX_VERSION})"
        else
            _doc_warn "Update available: v${CLAUDEBOX_VERSION} -> v${latest_version} (run: claudebox update all)"
        fi
    fi

    # ---- 10. PATH / symlink ----
    printf '\n%s\n' "Installation"
    if [[ -L "$LINK_TARGET" ]]; then
        local link_dest
        link_dest=$(readlink "$LINK_TARGET" 2>/dev/null || printf 'unknown')
        if [[ -f "$link_dest" ]]; then
            _doc_pass "Symlink valid: $LINK_TARGET -> $link_dest"
        else
            _doc_fail "Symlink broken: $LINK_TARGET -> $link_dest (target missing)"
        fi
    else
        _doc_warn "No symlink at $LINK_TARGET"
    fi

    if [[ ":$PATH:" == *":$(dirname "$LINK_TARGET"):"* ]]; then
        _doc_pass "$(dirname "$LINK_TARGET") is in PATH"
    else
        _doc_fail "$(dirname "$LINK_TARGET") is NOT in PATH — add to ~/.zshrc or ~/.bashrc"
    fi

    # ---- Summary ----
    printf '\n'
    _doctor_summary "$pass_count" "$warn_count" "$fail_count"
    exit 0
}

_doctor_summary() {
    local pass="$1" warn="$2" fail="$3"
    printf '%s\n' "────────────────────────────────"
    printf "  ${GREEN}%d passed${NC}  ${YELLOW}%d warnings${NC}  ${RED}%d failed${NC}\n" "$pass" "$warn" "$fail"
    printf '\n'
    if [[ $fail -gt 0 ]]; then
        cecho "Some checks failed. See above for fix suggestions." "$RED"
    elif [[ $warn -gt 0 ]]; then
        cecho "System is functional with minor warnings." "$YELLOW"
    else
        cecho "All checks passed. ClaudeBox is healthy!" "$GREEN"
    fi
    printf '\n'
}

export -f _cmd_doctor _doctor_summary
