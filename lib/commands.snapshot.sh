#!/usr/bin/env bash
# Snapshot Command - Save and restore slot state
# ============================================================================
# Commands: snapshot [name], snapshot list, snapshot restore, snapshot export

readonly SNAPSHOT_DIR="${CLAUDEBOX_HOME}/snapshots"

_cmd_snapshot() {
    local subcmd="${1:-}"
    shift || true

    case "$subcmd" in
        list|ls)    _snapshot_list ;;
        restore)    _snapshot_restore "$@" ;;
        export)     _snapshot_export "$@" ;;
        "")         _snapshot_create "" ;;
        *)
            # If it looks like a subcommand, error. Otherwise treat as name.
            if [[ "$subcmd" == -* ]]; then
                error "Unknown snapshot option: $subcmd"
            fi
            _snapshot_create "$subcmd"
            ;;
    esac
}

_snapshot_create() {
    local name="${1:-}"
    local datestamp
    datestamp=$(date +%Y%m%d-%H%M%S)

    # Determine which slot to snapshot
    local parent_dir
    parent_dir=$(get_parent_dir "$PROJECT_DIR")
    local slot_dir="${PROJECT_SLOT_DIR:-}"

    if [[ -z "$slot_dir" ]] || [[ ! -d "$slot_dir" ]]; then
        # Try to find any existing slot
        local max_slot
        max_slot=$(read_counter "$parent_dir" 2>/dev/null || printf '0')
        for ((idx=1; idx<=max_slot; idx++)); do
            local sname
            sname=$(generate_container_name "$PROJECT_DIR" "$idx")
            local sdir="$parent_dir/$sname"
            if [[ -d "$sdir/.claude" ]]; then
                slot_dir="$sdir"
                break
            fi
        done
    fi

    if [[ -z "$slot_dir" ]] || [[ ! -d "$slot_dir/.claude" ]]; then
        error "No slot with .claude directory found to snapshot"
    fi

    # Build snapshot name
    if [[ -z "$name" ]]; then
        local project_name
        project_name=$(basename "$PROJECT_DIR")
        name="${project_name}"
    fi
    local snapshot_file="${SNAPSHOT_DIR}/${name}-${datestamp}.tar.gz"

    mkdir -p "$SNAPSHOT_DIR"

    # Collect files to tar
    local tar_args=()
    tar_args+=("-czf" "$snapshot_file")
    tar_args+=("-C" "$slot_dir")

    # Include .claude/ (excluding .cache/)
    if [[ -d "$slot_dir/.claude" ]]; then
        tar_args+=("--exclude=.cache")
        tar_args+=(".claude")
    fi

    # Include profiles.ini and resources.conf from parent
    if [[ -f "$parent_dir/profiles.ini" ]]; then
        cp "$parent_dir/profiles.ini" "$slot_dir/.snapshot_profiles.ini"
        tar_args+=(".snapshot_profiles.ini")
    fi
    if [[ -f "${CLAUDEBOX_HOME}/resources.conf" ]]; then
        cp "${CLAUDEBOX_HOME}/resources.conf" "$slot_dir/.snapshot_resources.conf"
        tar_args+=(".snapshot_resources.conf")
    fi

    tar "${tar_args[@]}" || error "Failed to create snapshot"

    # Clean up temp copies
    rm -f "$slot_dir/.snapshot_profiles.ini" "$slot_dir/.snapshot_resources.conf"

    local size
    size=$(du -sh "$snapshot_file" 2>/dev/null | cut -f1 || printf 'N/A')
    success "Snapshot created: $snapshot_file ($size)"
}

_snapshot_list() {
    mkdir -p "$SNAPSHOT_DIR"

    local snapshots
    snapshots=$(find "$SNAPSHOT_DIR" -maxdepth 1 -name "*.tar.gz" -type f 2>/dev/null | sort -r)

    if [[ -z "$snapshots" ]]; then
        info "No snapshots found in $SNAPSHOT_DIR"
        exit 0
    fi

    logo_small
    printf '\n'
    cecho "Saved Snapshots" "$CYAN"
    printf '\n'
    printf "  %-40s  %8s  %s\n" "Name" "Size" "Date"
    printf "  %-40s  %8s  %s\n" "────" "────" "────"

    while IFS= read -r snap; do
        if [[ -z "$snap" ]]; then
            continue
        fi
        local bname
        bname=$(basename "$snap" .tar.gz)
        local fsize
        fsize=$(du -sh "$snap" 2>/dev/null | cut -f1 || printf '?')
        local fdate
        fdate=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$snap" 2>/dev/null || stat -c "%y" "$snap" 2>/dev/null | cut -d. -f1 || printf 'N/A')
        printf "  %-40s  %8s  %s\n" "$bname" "$fsize" "$fdate"
    done <<< "$snapshots"

    printf '\n'
    printf "  Snapshot directory: %s\n" "$SNAPSHOT_DIR"
    printf '\n'
    exit 0
}

_snapshot_restore() {
    local name="${1:-}"
    local target_slot="${2:-}"

    if [[ -z "$name" ]]; then
        error "Usage: claudebox snapshot restore <name> [--slot N]"
    fi

    # Handle --slot flag
    if [[ "$target_slot" == "--slot" ]]; then
        target_slot="${3:-}"
        if [[ -z "$target_slot" ]]; then
            error "Usage: claudebox snapshot restore <name> --slot <N>"
        fi
    fi

    # Find snapshot file
    local snapshot_file=""
    if [[ -f "$name" ]]; then
        snapshot_file="$name"
    elif [[ -f "${SNAPSHOT_DIR}/${name}.tar.gz" ]]; then
        snapshot_file="${SNAPSHOT_DIR}/${name}.tar.gz"
    else
        # Try partial match
        snapshot_file=$(find "$SNAPSHOT_DIR" -maxdepth 1 -name "${name}*.tar.gz" -type f 2>/dev/null | sort -r | head -1)
    fi

    if [[ -z "$snapshot_file" ]] || [[ ! -f "$snapshot_file" ]]; then
        error "Snapshot not found: $name\nRun 'claudebox snapshot list' to see available snapshots"
    fi

    # Determine target slot directory
    local parent_dir
    parent_dir=$(get_parent_dir "$PROJECT_DIR")
    local slot_dir=""

    if [[ -n "$target_slot" ]]; then
        local sname
        sname=$(generate_container_name "$PROJECT_DIR" "$target_slot")
        slot_dir="$parent_dir/$sname"
        if [[ ! -d "$slot_dir" ]]; then
            error "Slot $target_slot does not exist. Create it first with 'claudebox create'"
        fi
    else
        slot_dir="${PROJECT_SLOT_DIR:-}"
        if [[ -z "$slot_dir" ]] || [[ ! -d "$slot_dir" ]]; then
            error "No active slot found. Use --slot N to specify a target"
        fi
    fi

    # Check container is not running for this slot
    local slot_name
    slot_name=$(basename "$slot_dir")
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^claudebox-.*-${slot_name}$"; then
        error "Slot is currently running. Stop the container first"
    fi

    info "Restoring snapshot to $slot_dir ..."

    # Extract .claude/ contents
    tar -xzf "$snapshot_file" -C "$slot_dir" || error "Failed to extract snapshot"

    # Move profiles.ini back to parent if present
    if [[ -f "$slot_dir/.snapshot_profiles.ini" ]]; then
        cp "$slot_dir/.snapshot_profiles.ini" "$parent_dir/profiles.ini"
        rm -f "$slot_dir/.snapshot_profiles.ini"
        info "Restored profiles.ini"
    fi
    if [[ -f "$slot_dir/.snapshot_resources.conf" ]]; then
        cp "$slot_dir/.snapshot_resources.conf" "${CLAUDEBOX_HOME}/resources.conf"
        rm -f "$slot_dir/.snapshot_resources.conf"
        info "Restored resources.conf"
    fi

    success "Snapshot restored to: $slot_dir"
}

_snapshot_export() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        error "Usage: claudebox snapshot export <name>"
    fi

    # Find snapshot file
    local snapshot_file=""
    if [[ -f "${SNAPSHOT_DIR}/${name}.tar.gz" ]]; then
        snapshot_file="${SNAPSHOT_DIR}/${name}.tar.gz"
    else
        snapshot_file=$(find "$SNAPSHOT_DIR" -maxdepth 1 -name "${name}*.tar.gz" -type f 2>/dev/null | sort -r | head -1)
    fi

    if [[ -z "$snapshot_file" ]] || [[ ! -f "$snapshot_file" ]]; then
        error "Snapshot not found: $name\nRun 'claudebox snapshot list' to see available snapshots"
    fi

    local dest
    dest="$(pwd)/$(basename "$snapshot_file")"
    cp "$snapshot_file" "$dest" || error "Failed to copy snapshot"
    success "Exported snapshot to: $dest"
}

export -f _cmd_snapshot _snapshot_create _snapshot_list _snapshot_restore _snapshot_export
