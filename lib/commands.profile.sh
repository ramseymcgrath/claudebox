#!/usr/bin/env bash
# Profile Commands - Development profile management
# ============================================================================
# Commands: profiles, profile, add, remove, install
# Manages development tools and packages in containers

_cmd_profiles() {
    # Get current profiles
    local current_profiles=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            current_profiles+=("$line")
        fi
    done < <(get_current_profiles)

    # Show logo first
    logo_small
    printf '\n'

    # Show commands at the top
    printf '%s\n' "Commands:"
    printf "  ${CYAN}claudebox add <profiles...>${NC}    - Add development profiles to your project\n"
    printf "  ${CYAN}claudebox remove <profiles...>${NC} - Remove profiles from your project\n"
    printf '\n'

    # Show currently enabled profiles
    if [[ ${#current_profiles[@]} -gt 0 ]]; then
        cecho "Currently enabled:" "$YELLOW"
        printf "  %s\n" "${current_profiles[*]}"
        printf '\n'
    fi

    # Show available profiles
    cecho "Available profiles:" "$CYAN"
    printf '\n'

    # Show built-in profiles
    for profile in $(_builtin_profile_names | tr ' ' '\n' | sort); do
        local desc
        desc=$(get_profile_description "$profile")
        local is_enabled=false
        if [[ ${#current_profiles[@]} -gt 0 ]]; then
            for enabled in "${current_profiles[@]}"; do
                if [[ "$enabled" == "$profile" ]]; then
                    is_enabled=true
                    break
                fi
            done
        fi
        printf "  ${GREEN}%-15s${NC} " "$profile"
        if [[ "$is_enabled" == "true" ]]; then
            printf "${GREEN}✓${NC} "
        else
            printf "  "
        fi
        printf "%s\n" "$desc"
    done

    # Show custom profiles if any exist
    local custom_names
    custom_names=$(get_custom_profile_names)
    if [[ -n "$custom_names" ]]; then
        printf '\n'
        cecho "Custom profiles (from ~/.claudebox/custom-profiles/):" "$CYAN"
        printf '\n'
        for profile in $custom_names; do
            local desc
            desc=$(get_custom_profile_description "$profile")
            local is_enabled=false
            if [[ ${#current_profiles[@]} -gt 0 ]]; then
                for enabled in "${current_profiles[@]}"; do
                    if [[ "$enabled" == "$profile" ]]; then
                        is_enabled=true
                        break
                    fi
                done
            fi
            printf "  ${GREEN}%-15s${NC} " "$profile"
            if [[ "$is_enabled" == "true" ]]; then
                printf "${GREEN}✓${NC} "
            else
                printf "  "
            fi
            printf "%s\n" "$desc"
        done
    fi

    printf '\n'
    exit 0
}

_cmd_profile() {
    # Profile menu/help
    logo_small
    printf '\n'
    cecho "ClaudeBox Profile Management:" "$CYAN"
    printf '\n'
    printf "  ${GREEN}profiles${NC}                 Show all available profiles\n"
    printf "  ${GREEN}add <names...>${NC}           Add development profiles\n"
    printf "  ${GREEN}remove <names...>${NC}        Remove development profiles\n"
    printf '\n'
    cecho "Custom Profiles:" "$YELLOW"
    printf "  Drop .sh files into ${CYAN}~/.claudebox/custom-profiles/${NC}\n"
    printf "  First comment line becomes the description.\n"
    printf '\n'
    cecho "Examples:" "$YELLOW"
    printf '%s\n' "  claudebox profiles              # See all available profiles"
    printf '%s\n' "  claudebox add python rust       # Add Python and Rust profiles"
    printf '%s\n' "  claudebox remove rust           # Remove Rust profile"
    printf '%s\n' "  claudebox add status            # Check current project's profiles"
    printf '\n'
    exit 0
}

_cmd_add() {
    # Profile management doesn't need a slot, just the parent directory
    init_project_dir "$PROJECT_DIR"
    local profile_file
    profile_file=$(get_profile_file_path)

    # Check for special subcommands
    case "${1:-}" in
        status|--status|-s)
            cecho "Project: $PROJECT_DIR" "$CYAN"
            echo
            if [[ -f "$profile_file" ]]; then
                local current_profiles=()
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then current_profiles+=("$line"); fi
                done < <(read_profile_section "$profile_file" "profiles")
                if [[ ${#current_profiles[@]} -gt 0 ]]; then
                    cecho "Active profiles: ${current_profiles[*]}" "$GREEN"
                else
                    cecho "No profiles installed" "$YELLOW"
                fi

                local current_packages=()
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then current_packages+=("$line"); fi
                done < <(read_profile_section "$profile_file" "packages")
                if [[ ${#current_packages[@]} -gt 0 ]]; then
                    echo "Extra packages: ${current_packages[*]}"
                fi
            else
                cecho "No profiles configured for this project" "$YELLOW"
            fi
            exit 0
            ;;
    esac

    # Process profile names
    local selected=() remaining=()
    while [[ $# -gt 0 ]]; do
        # Stop processing if we hit a flag (starts with -)
        if [[ "$1" == -* ]]; then
            remaining=("$@")
            break
        fi
        
        if profile_exists "$1"; then
            selected+=("$1")
            shift
        else
            remaining=("$@")
            break
        fi
    done

    if [[ ${#selected[@]} -eq 0 ]]; then
        error "No valid profiles specified\nRun 'claudebox profiles' to see available profiles"
    fi

    update_profile_section "$profile_file" "profiles" "${selected[@]}"

    local all_profiles=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            all_profiles+=("$line")
        fi
    done < <(read_profile_section "$profile_file" "profiles")

    cecho "Profile: $PROJECT_DIR" "$CYAN"
    cecho "Adding profiles: ${selected[*]}" "$PURPLE"
    if [[ ${#all_profiles[@]} -gt 0 ]]; then
        cecho "All active profiles: ${all_profiles[*]}" "$GREEN"
    fi
    echo
    
    # Check if any Python-related profiles were added
    local python_profiles_added=false
    for profile in "${selected[@]}"; do
        if [[ "$profile" == "python" ]] || [[ "$profile" == "ml" ]]; then
            python_profiles_added=true
            break
        fi
    done
    
    # If Python profiles were added, remove the pydev flag to trigger reinstall
    if [[ "$python_profiles_added" == "true" ]]; then
        local parent_dir=$(get_parent_dir "$PROJECT_DIR")
        if [[ -f "$parent_dir/.pydev_flag" ]]; then
            rm -f "$parent_dir/.pydev_flag"
            info "Python packages will be updated on next run"
        fi
    fi
    
    # Only show rebuild message for non-Python profiles
    local needs_rebuild=false
    for profile in "${selected[@]}"; do
        if [[ "$profile" != "python" ]] && [[ "$profile" != "ml" ]]; then
            needs_rebuild=true
            break
        fi
    done
    
    if [[ "$needs_rebuild" == "true" ]]; then
        warn "The Docker image will be rebuilt with new profiles on next run."
    fi
    echo

    if [[ ${#remaining[@]} -gt 0 ]]; then
        set -- "${remaining[@]}"
    fi
}

_cmd_remove() {
    # Profile management doesn't need a slot, just the parent directory
    init_project_dir "$PROJECT_DIR"
    local profile_file
    profile_file=$(get_profile_file_path)

    # Read current profiles
    local current_profiles=()
    if [[ -f "$profile_file" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && current_profiles+=("$line")
        done < <(read_profile_section "$profile_file" "profiles")
    fi

    # Show currently enabled profiles if no arguments
    if [[ $# -eq 0 ]]; then
        if [[ ${#current_profiles[@]} -gt 0 ]]; then
            cecho "Currently Enabled Profiles:" "$YELLOW"
            printf "  %s\n" "${current_profiles[*]}"
            printf '\n'
            printf '%s\n' "Usage: claudebox remove <profile1> [profile2] ..."
        else
            printf '%s\n' "No profiles currently enabled."
        fi
        exit 1
    fi

    # Get list of profiles to remove
    local to_remove=()
    while [[ $# -gt 0 ]]; do
        # Stop processing if we hit a flag (starts with -)
        if [[ "$1" == -* ]]; then
            break
        fi
        
        if profile_exists "$1"; then
            to_remove+=("$1")
            shift
        else
            # Also stop if we hit an unknown profile
            # This prevents consuming Claude args as profile names
            break
        fi
    done

    if [[ ${#to_remove[@]} -eq 0 ]]; then
        error "No valid profiles specified to remove"
    fi

    # Remove specified profiles
    local new_profiles=()
    local python_profiles_removed=false
    for profile in "${current_profiles[@]}"; do
        local keep=true
        for remove in "${to_remove[@]}"; do
            if [[ "$profile" == "$remove" ]]; then
                keep=false
                # Check if we're removing a Python-related profile
                if [[ "$profile" == "python" ]] || [[ "$profile" == "ml" ]]; then
                    python_profiles_removed=true
                fi
                break
            fi
        done
        if [[ "$keep" == "true" ]]; then new_profiles+=("$profile"); fi
    done
    
    # Check if any Python-related profiles remain
    local has_python_profiles=false
    for profile in "${new_profiles[@]}"; do
        if [[ "$profile" == "python" ]] || [[ "$profile" == "ml" ]]; then
            has_python_profiles=true
            break
        fi
    done
    
    # If we removed Python profiles and no Python profiles remain, clean up Python flags
    if [[ "$python_profiles_removed" == "true" ]] && [[ "$has_python_profiles" == "false" ]]; then
        init_project_dir "$PROJECT_DIR"
        PROJECT_PARENT_DIR=$(get_parent_dir "$PROJECT_DIR")
        
        # Remove Python flags and venv folder if they exist
        if [[ -f "$PROJECT_PARENT_DIR/.venv_flag" ]]; then
            rm -f "$PROJECT_PARENT_DIR/.venv_flag"
        fi
        if [[ -f "$PROJECT_PARENT_DIR/.pydev_flag" ]]; then
            rm -f "$PROJECT_PARENT_DIR/.pydev_flag"
        fi
        if [[ -d "$PROJECT_PARENT_DIR/.venv" ]]; then
            rm -rf "$PROJECT_PARENT_DIR/.venv"
        fi
        
        cecho "Cleaned up Python environment flags and venv folder" "$YELLOW"
    fi

    # Write back the filtered profiles
    {
        echo "[profiles]"
        for profile in "${new_profiles[@]}"; do
            echo "$profile"
        done
        echo ""
        
        # Preserve packages section if it exists
        if [[ -f "$profile_file" ]] && grep -q "^\[packages\]" "$profile_file"; then
            echo "[packages]"
            while IFS= read -r line; do
                echo "$line"
            done < <(read_profile_section "$profile_file" "packages")
        fi
    } > "${profile_file}.tmp" && mv "${profile_file}.tmp" "$profile_file"

    cecho "Profile: $PROJECT_DIR" "$CYAN"
    cecho "Removed profiles: ${to_remove[*]}" "$PURPLE"
    if [[ ${#new_profiles[@]} -gt 0 ]]; then
        cecho "Remaining profiles: ${new_profiles[*]}" "$GREEN"
    else
        cecho "No profiles remaining" "$YELLOW"
    fi
    echo
    warn "The Docker image will be rebuilt with updated profiles on next run."
    echo
}

_cmd_install() {
    if [[ $# -eq 0 ]]; then
        error "No packages specified. Usage: claudebox install <package1> <package2> ..."
    fi

    local profile_file
    profile_file=$(get_profile_file_path)

    update_profile_section "$profile_file" "packages" "$@"

    local all_packages=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            all_packages+=("$line")
        fi
    done < <(read_profile_section "$profile_file" "packages")

    cecho "Profile: $PROJECT_DIR" "$CYAN"
    cecho "Installing packages: $*" "$PURPLE"
    if [[ ${#all_packages[@]} -gt 0 ]]; then
        cecho "All packages: ${all_packages[*]}" "$GREEN"
    fi
    echo
}

export -f _cmd_profiles _cmd_profile _cmd_add _cmd_remove _cmd_install