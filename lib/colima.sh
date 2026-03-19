#!/usr/bin/env bash
# Colima VM management and resource configuration
# ============================================================================
# Manages Colima as the preferred Docker runtime for ClaudeBox.
# Handles VM lifecycle, resource sizing, and container-level limits.

# Resource config file
readonly RESOURCES_CONF="${CLAUDEBOX_HOME}/resources.conf"

# ============================================================================
# Host resource detection (cross-platform)
# ============================================================================

# Get total host memory in MB
_get_host_memory_mb() {
    local mem_bytes=0
    case "$HOST_OS" in
        macOS)
            mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || printf '0')
            ;;
        linux)
            local mem_kb
            mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
            if [[ -n "$mem_kb" ]]; then
                mem_bytes=$((mem_kb * 1024))
            fi
            ;;
    esac
    printf '%s' "$((mem_bytes / 1024 / 1024))"
}

# Get total host CPU cores
_get_host_cpus() {
    local cpus=0
    case "$HOST_OS" in
        macOS)
            cpus=$(sysctl -n hw.ncpu 2>/dev/null || printf '4')
            ;;
        linux)
            cpus=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || printf '4')
            ;;
    esac
    printf '%s' "$cpus"
}

# ============================================================================
# Resource configuration
# ============================================================================

# Read a value from resources.conf
_read_resource_conf() {
    local key="$1"
    local default="$2"
    if [[ -f "$RESOURCES_CONF" ]]; then
        local val
        val=$(grep "^${key}=" "$RESOURCES_CONF" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')
        if [[ -n "$val" ]]; then
            printf '%s' "$val"
            return 0
        fi
    fi
    printf '%s' "$default"
}

# Write a value to resources.conf
_write_resource_conf() {
    local key="$1"
    local value="$2"
    mkdir -p "$CLAUDEBOX_HOME"

    if [[ -f "$RESOURCES_CONF" ]]; then
        # Remove existing key
        local existing
        existing=$(grep -v "^${key}=" "$RESOURCES_CONF" 2>/dev/null || true)
        printf '%s\n' "$existing" > "${RESOURCES_CONF}.tmp"
    else
        : > "${RESOURCES_CONF}.tmp"
    fi
    printf '%s=%s\n' "$key" "$value" >> "${RESOURCES_CONF}.tmp"
    # Remove blank lines
    grep -v '^$' "${RESOURCES_CONF}.tmp" > "$RESOURCES_CONF" 2>/dev/null || mv "${RESOURCES_CONF}.tmp" "$RESOURCES_CONF"
    rm -f "${RESOURCES_CONF}.tmp"
}

# Calculate smart defaults for VM sizing
# Allocates half of host resources, capped at sane maximums
_default_vm_cpus() {
    local host_cpus
    host_cpus=$(_get_host_cpus)
    local vm_cpus=$((host_cpus / 2))
    if [[ $vm_cpus -lt 2 ]]; then
        vm_cpus=2
    fi
    if [[ $vm_cpus -gt 8 ]]; then
        vm_cpus=8
    fi
    printf '%s' "$vm_cpus"
}

_default_vm_memory() {
    local host_mem
    host_mem=$(_get_host_memory_mb)
    # Give VM half of host memory, min 4GB, max 16GB
    local vm_mem=$((host_mem / 2))
    if [[ $vm_mem -lt 4096 ]]; then
        vm_mem=4096
    fi
    if [[ $vm_mem -gt 16384 ]]; then
        vm_mem=16384
    fi
    printf '%s' "$vm_mem"
}

_default_vm_disk() {
    printf '60'
}

# Calculate per-container memory limit based on VM size and slot count
_default_container_memory() {
    local vm_mem
    vm_mem=$(_read_resource_conf "vm_memory" "$(_default_vm_memory)")
    # Reserve 512MB for VM overhead, divide rest among max expected containers
    local max_containers
    max_containers=$(_read_resource_conf "max_containers" "4")
    local available=$((vm_mem - 512))
    local per_container=$((available / max_containers))
    # Floor at 768MB (Claude needs at least this)
    if [[ $per_container -lt 768 ]]; then
        per_container=768
    fi
    printf '%s' "${per_container}m"
}

# Calculate per-container CPU limit
_default_container_cpus() {
    local vm_cpus
    vm_cpus=$(_read_resource_conf "vm_cpus" "$(_default_vm_cpus)")
    local max_containers
    max_containers=$(_read_resource_conf "max_containers" "4")
    # Each container gets a proportional share, minimum 0.5
    local per_container
    # Use awk for floating point since bash can't do it
    per_container=$(awk "BEGIN { v = $vm_cpus / $max_containers; if (v < 0.5) v = 0.5; printf \"%.1f\", v }")
    printf '%s' "$per_container"
}

# Get configured resource values (with smart defaults)
get_vm_cpus() {
    _read_resource_conf "vm_cpus" "$(_default_vm_cpus)"
}

get_vm_memory() {
    _read_resource_conf "vm_memory" "$(_default_vm_memory)"
}

get_vm_disk() {
    _read_resource_conf "vm_disk" "$(_default_vm_disk)"
}

get_container_memory() {
    _read_resource_conf "container_memory" "$(_default_container_memory)"
}

get_container_cpus() {
    _read_resource_conf "container_cpus" "$(_default_container_cpus)"
}

get_max_containers() {
    _read_resource_conf "max_containers" "4"
}

# ============================================================================
# Colima lifecycle management
# ============================================================================

# Check if Colima is installed
_colima_installed() {
    command -v colima >/dev/null 2>&1
}

# Check if Colima VM is running
_colima_running() {
    colima status 2>/dev/null | grep -q "Running" 2>/dev/null
}

# Get the active Docker context/runtime
_docker_runtime() {
    # Check if Docker is accessible at all
    if ! command -v docker >/dev/null 2>&1; then
        printf 'none'
        return
    fi

    # Check current Docker context
    local context
    context=$(docker context show 2>/dev/null || printf '')

    if [[ "$context" == *"colima"* ]]; then
        printf 'colima'
    elif docker info 2>/dev/null | grep -qi "docker desktop"; then
        printf 'desktop'
    elif docker info >/dev/null 2>&1; then
        printf 'docker'
    else
        printf 'stopped'
    fi
}

# Install Colima (macOS via Homebrew, Linux via binary)
_install_colima() {
    case "$HOST_OS" in
        macOS)
            if command -v brew >/dev/null 2>&1; then
                info "Installing Colima and Docker CLI via Homebrew..."
                brew install colima docker docker-compose
            else
                error "Homebrew is required to install Colima on macOS.\nInstall it from https://brew.sh"
            fi
            ;;
        linux)
            info "Installing Colima..."
            local arch
            arch=$(uname -m)
            case "$arch" in
                x86_64)  arch="amd64" ;;
                aarch64) arch="arm64" ;;
            esac
            local colima_url="https://github.com/abiosoft/colima/releases/latest/download/colima-$(uname -s)-${arch}"
            if command -v curl >/dev/null 2>&1; then
                sudo curl -fsSL -o /usr/local/bin/colima "$colima_url"
            elif command -v wget >/dev/null 2>&1; then
                sudo wget -qO /usr/local/bin/colima "$colima_url"
            else
                error "curl or wget required to install Colima"
            fi
            sudo chmod +x /usr/local/bin/colima

            # Ensure docker CLI is available
            if ! command -v docker >/dev/null 2>&1; then
                info "Installing Docker CLI..."
                case "$HOST_OS" in
                    linux)
                        if command -v apt-get >/dev/null 2>&1; then
                            sudo apt-get update
                            sudo apt-get install -y docker.io
                        elif command -v dnf >/dev/null 2>&1; then
                            sudo dnf install -y docker-ce-cli
                        elif command -v pacman >/dev/null 2>&1; then
                            sudo pacman -S --noconfirm docker
                        fi
                        ;;
                esac
            fi
            ;;
    esac
    success "Colima installed!"
}

# Start Colima with configured resources
_start_colima() {
    local cpus
    cpus=$(get_vm_cpus)
    local memory
    memory=$(get_vm_memory)
    local disk
    disk=$(get_vm_disk)

    # Convert memory from MB to GB for Colima (rounds up)
    local memory_gb=$(( (memory + 1023) / 1024 ))

    info "Starting Colima VM (${cpus} CPUs, ${memory_gb}GB RAM, ${disk}GB disk)..."

    # Determine VM type - prefer vz on Apple Silicon macOS
    local vm_type="qemu"
    if [[ "$HOST_OS" == "macOS" ]]; then
        local arch
        arch=$(uname -m)
        if [[ "$arch" == "arm64" ]]; then
            vm_type="vz"
        fi
    fi

    local colima_args=(
        start
        --cpu "$cpus"
        --memory "$memory_gb"
        --disk "$disk"
        --vm-type "$vm_type"
    )

    # Use virtiofs on macOS with vz for much better file I/O
    if [[ "$vm_type" == "vz" ]]; then
        colima_args+=(--mount-type virtiofs)
    fi

    colima "${colima_args[@]}" || error "Failed to start Colima"
    success "Colima VM running"
}

# Stop Colima
_stop_colima() {
    if _colima_running; then
        info "Stopping Colima VM..."
        colima stop
        success "Colima stopped"
    else
        info "Colima is not running"
    fi
}

# Resize a running Colima VM (requires restart)
_resize_colima() {
    local cpus="$1"
    local memory="$2"
    local disk="${3:-}"

    if [[ -n "$cpus" ]]; then
        _write_resource_conf "vm_cpus" "$cpus"
    fi
    if [[ -n "$memory" ]]; then
        _write_resource_conf "vm_memory" "$memory"
    fi
    if [[ -n "$disk" ]]; then
        _write_resource_conf "vm_disk" "$disk"
    fi

    if _colima_running; then
        warn "Colima needs to restart to apply new resource limits."
        printf "  Restart now? [Y/n] "
        local answer
        IFS= read -r answer 2>/dev/null || true
        answer="${answer:-y}"
        case "$answer" in
            [yY]|[yY][eE][sS])
                _stop_colima
                _start_colima
                ;;
            *)
                info "Run 'claudebox vm restart' to apply changes later."
                ;;
        esac
    else
        info "Settings saved. They'll be used next time Colima starts."
    fi
}

# ============================================================================
# Docker startup integration
# ============================================================================

# Ensure Docker is available, using Colima as preferred runtime
# Replaces the Docker check logic in main.sh
ensure_docker_running() {
    # 1. Check if docker CLI exists
    if ! command -v docker >/dev/null 2>&1; then
        # No docker at all - offer Colima installation
        if [[ "$HOST_OS" == "macOS" ]]; then
            warn "Docker is not installed."
            printf "  ClaudeBox can install Colima (lightweight Docker VM) for you.\n"
            printf "  Install Colima? [Y/n] "
            local answer
            IFS= read -r answer 2>/dev/null || true
            answer="${answer:-y}"
            case "$answer" in
                [yY]|[yY][eE][sS])
                    _install_colima
                    _start_colima
                    return 0
                    ;;
                *)
                    error "Docker is required. Install Docker or Colima to continue."
                    ;;
            esac
        else
            # Linux - try standard Docker install first, offer Colima as alternative
            install_docker
            return $?
        fi
    fi

    # 2. Docker CLI exists - check if daemon is running
    if docker info >/dev/null 2>&1; then
        # Docker is running (via Colima, Desktop, or native)
        if [[ "$VERBOSE" == "true" ]]; then
            printf '[DEBUG] Docker runtime: %s\n' "$(_docker_runtime)" >&2
        fi
        return 0
    fi

    # 3. Docker not running - try to start it
    if _colima_installed; then
        # Colima is installed but not running
        if _colima_running; then
            # Colima says it's running but docker can't connect - context issue
            warn "Colima is running but Docker can't connect."
            info "Trying to set Docker context..."
            docker context use colima 2>/dev/null || true
            if docker info >/dev/null 2>&1; then
                return 0
            fi
            error "Could not connect to Colima Docker socket. Try 'colima restart'."
        fi

        _start_colima
        return 0
    fi

    # 4. No Colima, Docker not running
    case "$HOST_OS" in
        macOS)
            # Offer Colima over Docker Desktop
            warn "Docker is installed but not running."
            printf '\n'
            printf "  ${WHITE}1.${NC} Install & start Colima (recommended, lightweight)\n"
            printf "  ${WHITE}2.${NC} Start Docker Desktop manually\n"
            printf '\n'
            printf "  Choice [1]: "
            local choice
            IFS= read -r choice 2>/dev/null || true
            choice="${choice:-1}"
            case "$choice" in
                1)
                    _install_colima
                    _start_colima
                    return 0
                    ;;
                2)
                    error "Please start Docker Desktop from Applications, then run claudebox again."
                    ;;
                *)
                    error "Invalid choice."
                    ;;
            esac
            ;;
        linux)
            warn "Docker is installed but not running."
            warn "Starting Docker requires sudo privileges..."
            sudo systemctl start docker 2>/dev/null || true
            if docker info >/dev/null 2>&1; then
                return 0
            fi
            docker ps >/dev/null 2>&1 || configure_docker_nonroot
            ;;
    esac
}

# ============================================================================
# Container resource limit arguments
# ============================================================================

# Return docker run args for resource limits
get_container_resource_args() {
    local args=()
    local mem
    mem=$(get_container_memory)
    local cpus
    cpus=$(get_container_cpus)

    if [[ -n "$mem" ]] && [[ "$mem" != "0" ]]; then
        args+=(--memory "$mem")
        # Set swap to same as memory (no extra swap)
        args+=(--memory-swap "$mem")
    fi

    if [[ -n "$cpus" ]] && [[ "$cpus" != "0" ]]; then
        args+=(--cpus "$cpus")
    fi

    # PID limit to prevent fork bombs
    args+=(--pids-limit 512)

    printf '%s\n' "${args[@]}"
}

# ============================================================================
# VM command
# ============================================================================

_cmd_vm() {
    local subcmd="${1:-}"
    shift || true

    case "$subcmd" in
        start)
            if ! _colima_installed; then
                _install_colima
            fi
            _start_colima
            ;;

        stop)
            _stop_colima
            ;;

        restart)
            _stop_colima
            _start_colima
            ;;

        status)
            logo_small
            printf '\n'
            cecho "  VM & Resource Status" "$WHITE"
            printf '\n'

            # Runtime detection
            local runtime
            runtime=$(_docker_runtime)
            printf "  ${CYAN}Runtime:${NC}          "
            case "$runtime" in
                colima)  cecho "Colima" "$GREEN" ;;
                desktop) cecho "Docker Desktop" "$YELLOW" ;;
                docker)  cecho "Docker Engine" "$GREEN" ;;
                stopped) cecho "Not running" "$RED" ;;
                none)    cecho "Not installed" "$RED" ;;
            esac

            if _colima_installed; then
                if _colima_running; then
                    printf "  ${CYAN}Colima:${NC}           "
                    cecho "Running" "$GREEN"

                    # Show Colima VM specs
                    local colima_info
                    colima_info=$(colima list 2>/dev/null | grep -v "^PROFILE" | head -1 || true)
                    if [[ -n "$colima_info" ]]; then
                        local vm_cpus vm_mem vm_disk
                        vm_cpus=$(printf '%s' "$colima_info" | awk '{print $3}')
                        vm_mem=$(printf '%s' "$colima_info" | awk '{print $4}')
                        vm_disk=$(printf '%s' "$colima_info" | awk '{print $5}')
                        printf "  ${CYAN}VM Resources:${NC}     %s CPUs, %s RAM, %s disk\n" "$vm_cpus" "$vm_mem" "$vm_disk"
                    fi
                else
                    printf "  ${CYAN}Colima:${NC}           "
                    cecho "Stopped" "$YELLOW"
                fi
            fi

            # Host resources
            printf '\n'
            cecho "  Host:" "$YELLOW"
            local host_mem
            host_mem=$(_get_host_memory_mb)
            local host_cpus
            host_cpus=$(_get_host_cpus)
            printf "  ${CYAN}Memory:${NC}           %s MB (%s GB)\n" "$host_mem" "$((host_mem / 1024))"
            printf "  ${CYAN}CPUs:${NC}             %s\n" "$host_cpus"

            # Configured limits
            printf '\n'
            cecho "  Container Limits:" "$YELLOW"
            printf "  ${CYAN}Memory/container:${NC} %s\n" "$(get_container_memory)"
            printf "  ${CYAN}CPUs/container:${NC}   %s\n" "$(get_container_cpus)"
            printf "  ${CYAN}Max containers:${NC}   %s\n" "$(get_max_containers)"

            # Running containers
            if docker info >/dev/null 2>&1; then
                local running
                running=$(docker ps --filter "name=^claudebox-" --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' ')
                printf "  ${CYAN}Running now:${NC}      %s\n" "$running"
            fi

            printf '\n'
            printf "  ${DIM}Configure with: claudebox vm set --memory 8192 --cpus 4${NC}\n"
            printf '\n'
            ;;

        set)
            local new_cpus=""
            local new_memory=""
            local new_disk=""
            local new_max=""
            local new_container_mem=""
            local new_container_cpus=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --cpus)          new_cpus="$2"; shift 2 ;;
                    --memory)        new_memory="$2"; shift 2 ;;
                    --disk)          new_disk="$2"; shift 2 ;;
                    --max-containers) new_max="$2"; shift 2 ;;
                    --container-memory) new_container_mem="$2"; shift 2 ;;
                    --container-cpus)   new_container_cpus="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done

            if [[ -z "$new_cpus" ]] && [[ -z "$new_memory" ]] && [[ -z "$new_disk" ]] && \
               [[ -z "$new_max" ]] && [[ -z "$new_container_mem" ]] && [[ -z "$new_container_cpus" ]]; then
                printf '\n'
                cecho "Configure VM & Container Resources" "$CYAN"
                printf '\n'
                cecho "  VM Settings (requires Colima restart):" "$YELLOW"
                printf "    ${GREEN}--cpus <n>${NC}              VM CPU cores (current: %s)\n" "$(get_vm_cpus)"
                printf "    ${GREEN}--memory <mb>${NC}           VM memory in MB (current: %s)\n" "$(get_vm_memory)"
                printf "    ${GREEN}--disk <gb>${NC}             VM disk in GB (current: %s)\n" "$(get_vm_disk)"
                printf '\n'
                cecho "  Container Settings (immediate):" "$YELLOW"
                printf "    ${GREEN}--container-memory <mb>${NC} Per-container memory limit (current: %s)\n" "$(get_container_memory)"
                printf "    ${GREEN}--container-cpus <n>${NC}    Per-container CPU limit (current: %s)\n" "$(get_container_cpus)"
                printf "    ${GREEN}--max-containers <n>${NC}    Expected max concurrent containers (current: %s)\n" "$(get_max_containers)"
                printf '\n'
                cecho "  Examples:" "$DIM"
                printf "    claudebox vm set --memory 8192 --cpus 4\n"
                printf "    claudebox vm set --container-memory 2048m --max-containers 3\n"
                printf '\n'
                return 0
            fi

            # Apply container-level settings immediately
            if [[ -n "$new_max" ]]; then
                _write_resource_conf "max_containers" "$new_max"
                success "Max containers: $new_max"
            fi
            if [[ -n "$new_container_mem" ]]; then
                _write_resource_conf "container_memory" "$new_container_mem"
                success "Container memory: $new_container_mem"
            fi
            if [[ -n "$new_container_cpus" ]]; then
                _write_resource_conf "container_cpus" "$new_container_cpus"
                success "Container CPUs: $new_container_cpus"
            fi

            # Apply VM-level settings (may need restart)
            if [[ -n "$new_cpus" ]] || [[ -n "$new_memory" ]] || [[ -n "$new_disk" ]]; then
                _resize_colima "${new_cpus:-}" "${new_memory:-}" "${new_disk:-}"
            fi
            ;;

        reset)
            rm -f "$RESOURCES_CONF"
            success "Resource configuration reset to defaults"
            printf "  ${DIM}Run 'claudebox vm status' to see current defaults.${NC}\n"
            ;;

        *)
            logo_small
            printf '\n'
            cecho "  VM & Resource Management" "$WHITE"
            printf '\n'
            cecho "  Lifecycle:" "$YELLOW"
            printf "    ${GREEN}vm start${NC}           Start the Colima VM\n"
            printf "    ${GREEN}vm stop${NC}            Stop the Colima VM\n"
            printf "    ${GREEN}vm restart${NC}         Restart with current settings\n"
            printf "    ${GREEN}vm status${NC}          Show VM and resource info\n"
            printf '\n'
            cecho "  Configuration:" "$YELLOW"
            printf "    ${GREEN}vm set${NC}             Configure VM and container resources\n"
            printf "    ${GREEN}vm reset${NC}           Reset to auto-detected defaults\n"
            printf '\n'
            cecho "  Quick Examples:" "$DIM"
            printf "    claudebox vm set --memory 8192 --cpus 4    ${DIM}# Resize VM${NC}\n"
            printf "    claudebox vm set --max-containers 2        ${DIM}# Limit concurrency${NC}\n"
            printf "    claudebox vm set --container-memory 2048m  ${DIM}# Per-container limit${NC}\n"
            printf '\n'
            printf "  ${DIM}ClaudeBox auto-starts Colima when Docker is needed.${NC}\n"
            printf "  ${DIM}Resource limits are applied automatically to all containers.${NC}\n"
            printf '\n'
            ;;
    esac
}

# Export functions
export -f _get_host_memory_mb _get_host_cpus
export -f _read_resource_conf _write_resource_conf
export -f _default_vm_cpus _default_vm_memory _default_vm_disk
export -f _default_container_memory _default_container_cpus
export -f get_vm_cpus get_vm_memory get_vm_disk get_container_memory get_container_cpus get_max_containers
export -f _colima_installed _colima_running _docker_runtime
export -f _install_colima _start_colima _stop_colima _resize_colima
export -f ensure_docker_running get_container_resource_args
export -f _cmd_vm
