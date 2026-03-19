#!/usr/bin/env bash
# Configuration management including INI files and profile definitions.

# -------- INI file helpers ----------------------------------------------------
_read_ini() {               # $1=file $2=section $3=key
  awk -F' *= *' -v s="[$2]" -v k="$3" '
    $0==s {in=1; next}
    /^\[/ {in=0}
    in && $1==k {print $2; exit}
  ' "$1" 2>/dev/null
}


# -------- Profile functions (Bash 3.2 compatible) -----------------------------
get_profile_packages() {
    case "$1" in
        core) echo "gcc g++ make git pkg-config libssl-dev libffi-dev zlib1g-dev tmux" ;;
        build-tools) echo "cmake ninja-build autoconf automake libtool" ;;
        shell) echo "rsync openssh-client man-db gnupg2 aggregate file" ;;
        networking) echo "iptables ipset iproute2 dnsutils" ;;
        c) echo "gdb valgrind clang clang-format clang-tidy cppcheck doxygen libboost-all-dev libcmocka-dev libcmocka0 lcov libncurses5-dev libncursesw5-dev" ;;
        openwrt) echo "rsync libncurses5-dev zlib1g-dev gawk gettext xsltproc libelf-dev ccache subversion swig time qemu-system-arm qemu-system-aarch64 qemu-system-mips qemu-system-x86 qemu-utils" ;;
        rust) echo "" ;;  # Rust installed via rustup
        python) echo "" ;;  # Managed via uv
        go) echo "" ;;  # Installed from tarball
        flutter) echo "" ;;  # Installed from source
        javascript) echo "" ;;  # Installed via nvm
        java) echo "" ;;  # Java installed via SDKMan, build tools in profile function
        ruby) echo "ruby-full ruby-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev libcurl4-openssl-dev software-properties-common" ;;
        php) echo "php php-cli php-fpm php-mysql php-pgsql php-sqlite3 php-curl php-gd php-mbstring php-xml php-zip composer" ;;
        database) echo "postgresql-client mysql-client sqlite3 redis-tools mongodb-clients" ;;
        devops) echo "docker.io docker-compose kubectl helm terraform ansible awscli" ;;
        web) echo "nginx apache2-utils httpie" ;;
        embedded) echo "gcc-arm-none-eabi gdb-multiarch openocd picocom minicom screen" ;;
        datascience) echo "r-base" ;;
        security) echo "nmap tcpdump wireshark-common netcat-openbsd john hashcat hydra" ;;
        ml) echo "" ;;  # Just cmake needed, comes from build-tools now
        tunnel) echo "" ;;  # Installed via deb package
        *) echo "" ;;
    esac
}

get_profile_description() {
    case "$1" in
        core) echo "Core Development Utilities (compilers, VCS, shell tools)" ;;
        build-tools) echo "Build Tools (CMake, autotools, Ninja)" ;;
        shell) echo "Optional Shell Tools (fzf, SSH, man, rsync, file)" ;;
        networking) echo "Network Tools (IP stack, DNS, route tools)" ;;
        c) echo "C/C++ Development (debuggers, analyzers, Boost, ncurses, cmocka)" ;;
        openwrt) echo "OpenWRT Development (cross toolchain, QEMU, distro tools)" ;;
        rust) echo "Rust Development (installed via rustup)" ;;
        python) echo "Python Development (managed via uv)" ;;
        go) echo "Go Development (installed from upstream archive)" ;;
        flutter) echo "Flutter Development (installed from fvm)" ;;
        javascript) echo "JavaScript/TypeScript (Node installed via nvm)" ;;
        java) echo "Java Development (latest LTS, Maven, Gradle, Ant via SDKMan)" ;;
        ruby) echo "Ruby Development (gems, native deps, XML/YAML)" ;;
        php) echo "PHP Development (PHP + extensions + Composer)" ;;
        database) echo "Database Tools (clients for major databases)" ;;
        devops) echo "DevOps Tools (Docker, Kubernetes, Terraform, etc.)" ;;
        web) echo "Web Dev Tools (nginx, HTTP test clients)" ;;
        embedded) echo "Embedded Dev (ARM toolchain, serial debuggers)" ;;
        datascience) echo "Data Science (Python, Jupyter, R)" ;;
        security) echo "Security Tools (scanners, crackers, packet tools)" ;;
        ml) echo "Machine Learning (build layer only; Python via uv)" ;;
        *) echo "" ;;
    esac
}

get_all_profile_names() {
    echo "core build-tools shell networking c openwrt rust python go flutter javascript java ruby php database devops web embedded datascience security ml"
}

profile_exists() {
    local profile="$1"
    for p in $(get_all_profile_names); do
        if [[ "$p" == "$profile" ]]; then
            return 0
        fi
    done
    return 1
}

expand_profile() {
    case "$1" in
        c) echo "core build-tools c" ;;
        openwrt) echo "core build-tools openwrt" ;;
        ml) echo "core build-tools ml" ;;
        rust|go|flutter|python|php|ruby|java|database|devops|web|embedded|datascience|security|javascript|tunnel)
            echo "core $1"
            ;;
        shell|networking|build-tools|core)
            echo "$1"
            ;;
        *)
            echo "$1"
            ;;
    esac
}

# -------- Profile file management ---------------------------------------------
get_profile_file_path() {
    # Use the parent directory name, not the slot name
    local parent_name=$(generate_parent_folder_name "$PROJECT_DIR")
    local parent_dir="$HOME/.claudebox/projects/$parent_name"
    mkdir -p "$parent_dir"
    echo "$parent_dir/profiles.ini"
}

read_config_value() {
    local config_file="$1"
    local section="$2"
    local key="$3"

    [[ -f "$config_file" ]] || return 1

    awk -F ' *= *' -v section="[$section]" -v key="$key" '
        $0 == section { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && $1 == key { print $2; exit }
    ' "$config_file"
}

read_profile_section() {
    local profile_file="$1"
    local section="$2"
    local result=()

    if [[ -f "$profile_file" ]] && grep -q "^\[$section\]" "$profile_file"; then
        while IFS= read -r line; do
            if [[ -z "$line" ]] || [[ "$line" =~ ^\[.*\]$ ]]; then
                break
            fi
            result+=("$line")
        done < <(sed -n "/^\[$section\]/,/^\[/p" "$profile_file" | tail -n +2 | grep -v '^\[')
    fi

    if [[ ${#result[@]} -gt 0 ]]; then
        printf '%s\n' "${result[@]}"
    fi
}

update_profile_section() {
    local profile_file="$1"
    local section="$2"
    shift 2
    local new_items=("$@")

    local existing_items=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            existing_items+=("$line")
        fi
    done < <(read_profile_section "$profile_file" "$section")

    local all_items=()
    if [[ ${#existing_items[@]} -gt 0 ]]; then
        for item in "${existing_items[@]}"; do
            if [[ -n "$item" ]]; then
                all_items+=("$item")
            fi
        done
    fi

    for item in "${new_items[@]}"; do
        local found=false
        if [[ ${#all_items[@]} -gt 0 ]]; then
            for existing in "${all_items[@]}"; do
                if [[ "$existing" == "$item" ]]; then
                    found=true
                    break
                fi
            done
        fi
        if [[ "$found" == "false" ]]; then
            all_items+=("$item")
        fi
    done

    {
        if [[ -f "$profile_file" ]]; then
            awk -v sect="$section" '
                BEGIN { in_section=0; skip_section=0 }
                /^\[/ {
                    if ($0 == "[" sect "]") { skip_section=1; in_section=1 }
                    else { skip_section=0; in_section=0 }
                }
                !skip_section { print }
                /^\[/ && !skip_section && in_section { in_section=0 }
            ' "$profile_file"
        fi

        echo "[$section]"
        for item in "${all_items[@]}"; do
            echo "$item"
        done
        echo ""
    } > "${profile_file}.tmp" && mv "${profile_file}.tmp" "$profile_file"
}

get_current_profiles() {
    local profiles_file="${PROJECT_PARENT_DIR:-$HOME/.claudebox/projects/$(generate_parent_folder_name "$PWD")}/profiles.ini"
    local current_profiles=()

    if [[ -f "$profiles_file" ]]; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                current_profiles+=("$line")
            fi
        done < <(read_profile_section "$profiles_file" "profiles")
    fi

    if [[ ${#current_profiles[@]} -gt 0 ]]; then
        printf '%s\n' "${current_profiles[@]}"
    fi
}

# -------- Profile installation functions for Docker builds -------------------
get_profile_core() {
    local packages=$(get_profile_packages "core")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_build_tools() {
    local packages=$(get_profile_packages "build-tools")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_shell() {
    local packages=$(get_profile_packages "shell")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_networking() {
    local packages=$(get_profile_packages "networking")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_c() {
    local packages=$(get_profile_packages "c")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_openwrt() {
    local packages=$(get_profile_packages "openwrt")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_rust() {
    cat << 'EOF'
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/claude/.cargo/bin:$PATH"
EOF
}

get_profile_python() {
    cat << 'EOF'
# Python profile - uv already installed in base image
# Python venv and dev tools are managed via entrypoint flag system
EOF
}

get_profile_go() {
    cat << 'EOF'
RUN wget -O go.tar.gz https://golang.org/dl/go1.21.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz
ENV PATH="/usr/local/go/bin:$PATH"
EOF
}

get_profile_flutter() {
    local flutter_version="${FLUTTER_SDK_VERSION:-stable}"
    cat << EOF
USER claude
RUN curl -fsSL https://fvm.app/install.sh | bash
ENV PATH="/usr/local/bin:$PATH"
RUN fvm install $flutter_version
RUN fvm global $flutter_version
ENV PATH="/home/claude/fvm/default/bin:$PATH"
RUN flutter doctor
USER root
EOF
}

get_profile_javascript() {
    cat << 'EOF'
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
ENV NVM_DIR="/home/claude/.nvm"
RUN . $NVM_DIR/nvm.sh && nvm install --lts
USER claude
RUN bash -c "source $NVM_DIR/nvm.sh && npm install -g typescript eslint prettier yarn pnpm"
USER root
EOF
}

get_profile_java() {
    cat << 'EOF'
USER claude
RUN curl -s "https://get.sdkman.io?ci=true" | bash
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && sdk install java && sdk install maven && sdk install gradle && sdk install ant"
USER root
# Create symlinks for all Java tools in system PATH
RUN for tool in java javac jar jshell; do \
        ln -sf /home/claude/.sdkman/candidates/java/current/bin/$tool /usr/local/bin/$tool; \
    done && \
    ln -sf /home/claude/.sdkman/candidates/maven/current/bin/mvn /usr/local/bin/mvn && \
    ln -sf /home/claude/.sdkman/candidates/gradle/current/bin/gradle /usr/local/bin/gradle && \
    ln -sf /home/claude/.sdkman/candidates/ant/current/bin/ant /usr/local/bin/ant
# Set JAVA_HOME environment variable
ENV JAVA_HOME="/home/claude/.sdkman/candidates/java/current"
ENV PATH="/home/claude/.sdkman/candidates/java/current/bin:$PATH"
EOF
}

get_profile_ruby() {
    local packages=$(get_profile_packages "ruby")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_php() {
    local packages=$(get_profile_packages "php")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_database() {
    local packages=$(get_profile_packages "database")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_devops() {
    local packages=$(get_profile_packages "devops")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_web() {
    local packages=$(get_profile_packages "web")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_embedded() {
    local packages=$(get_profile_packages "embedded")
    if [[ -n "$packages" ]]; then
        cat << 'EOF'
RUN apt-get update && apt-get install -y gcc-arm-none-eabi gdb-multiarch openocd picocom minicom screen && apt-get clean
USER claude
RUN ~/.local/bin/uv tool install platformio
USER root
EOF
    fi
}

get_profile_datascience() {
    local packages=$(get_profile_packages "datascience")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_security() {
    local packages=$(get_profile_packages "security")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_ml() {
    # ML profile just needs build tools which are dependencies
    printf '%s\n' "# ML profile uses build-tools for compilation"
}

get_profile_tunnel() {
    cat << 'EOF'
# Install cloudflared for Cloudflare Tunnel access
RUN curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb && \
    dpkg -i /tmp/cloudflared.deb && \
    rm -f /tmp/cloudflared.deb
EOF
}

# -------- Custom profile support -----------------------------------------------
# Users can add custom profiles as shell scripts in ~/.claudebox/custom-profiles/
# Each file should be named <profile-name>.sh and contain a function body that
# outputs Dockerfile RUN instructions (same format as get_profile_* functions).
# Example: ~/.claudebox/custom-profiles/mytools.sh
#   RUN apt-get update && apt-get install -y mypackage && apt-get clean

get_custom_profile_names() {
    local custom_dir="$HOME/.claudebox/custom-profiles"
    if [[ -d "$custom_dir" ]]; then
        for f in "$custom_dir"/*.sh; do
            if [[ -f "$f" ]]; then
                local name
                name=$(basename "$f" .sh)
                printf '%s ' "$name"
            fi
        done
    fi
}

custom_profile_exists() {
    local profile="$1"
    local custom_dir="$HOME/.claudebox/custom-profiles"
    [[ -f "$custom_dir/${profile}.sh" ]]
}

get_custom_profile() {
    local profile="$1"
    local custom_dir="$HOME/.claudebox/custom-profiles"
    local profile_file="$custom_dir/${profile}.sh"
    if [[ -f "$profile_file" ]]; then
        cat "$profile_file"
    fi
}

get_custom_profile_description() {
    local profile="$1"
    local custom_dir="$HOME/.claudebox/custom-profiles"
    local profile_file="$custom_dir/${profile}.sh"
    if [[ -f "$profile_file" ]]; then
        # First line starting with # is the description
        local desc
        desc=$(head -1 "$profile_file" | sed 's/^#[[:space:]]*//')
        if [[ -n "$desc" ]] && [[ "$desc" != "$(head -1 "$profile_file")" ]]; then
            printf '%s' "$desc"
        else
            printf 'Custom profile: %s' "$profile"
        fi
    fi
}

# Override profile_exists to also check custom profiles
_builtin_profile_exists() {
    local profile="$1"
    for p in $(get_all_profile_names); do
        if [[ "$p" == "$profile" ]]; then
            return 0
        fi
    done
    return 1
}

# Re-define profile_exists to check both built-in and custom
profile_exists() {
    local profile="$1"
    if _builtin_profile_exists "$profile"; then
        return 0
    fi
    if custom_profile_exists "$profile"; then
        return 0
    fi
    return 1
}

# Override get_all_profile_names to include custom profiles
_builtin_profile_names() {
    printf '%s' "core build-tools shell networking c openwrt rust python go flutter javascript java ruby php database devops web embedded datascience security ml tunnel"
}

get_all_profile_names() {
    local names
    names=$(_builtin_profile_names)
    local custom
    custom=$(get_custom_profile_names)
    if [[ -n "$custom" ]]; then
        printf '%s %s' "$names" "$custom"
    else
        printf '%s' "$names"
    fi
}

# Override get_profile_description to handle custom profiles
_builtin_profile_description() {
    case "$1" in
        core) printf '%s' "Core Development Utilities (compilers, VCS, shell tools)" ;;
        build-tools) printf '%s' "Build Tools (CMake, autotools, Ninja)" ;;
        shell) printf '%s' "Optional Shell Tools (fzf, SSH, man, rsync, file)" ;;
        networking) printf '%s' "Network Tools (IP stack, DNS, route tools)" ;;
        c) printf '%s' "C/C++ Development (debuggers, analyzers, Boost, ncurses, cmocka)" ;;
        openwrt) printf '%s' "OpenWRT Development (cross toolchain, QEMU, distro tools)" ;;
        rust) printf '%s' "Rust Development (installed via rustup)" ;;
        python) printf '%s' "Python Development (managed via uv)" ;;
        go) printf '%s' "Go Development (installed from upstream archive)" ;;
        flutter) printf '%s' "Flutter Development (installed from fvm)" ;;
        javascript) printf '%s' "JavaScript/TypeScript (Node installed via nvm)" ;;
        java) printf '%s' "Java Development (latest LTS, Maven, Gradle, Ant via SDKMan)" ;;
        ruby) printf '%s' "Ruby Development (gems, native deps, XML/YAML)" ;;
        php) printf '%s' "PHP Development (PHP + extensions + Composer)" ;;
        database) printf '%s' "Database Tools (clients for major databases)" ;;
        devops) printf '%s' "DevOps Tools (Docker, Kubernetes, Terraform, etc.)" ;;
        web) printf '%s' "Web Dev Tools (nginx, HTTP test clients)" ;;
        embedded) printf '%s' "Embedded Dev (ARM toolchain, serial debuggers)" ;;
        datascience) printf '%s' "Data Science (Python, Jupyter, R)" ;;
        security) printf '%s' "Security Tools (scanners, crackers, packet tools)" ;;
        ml) printf '%s' "Machine Learning (build layer only; Python via uv)" ;;
        tunnel) printf '%s' "Cloudflare Tunnel (cloudflared for private network access)" ;;
        *) printf '' ;;
    esac
}

get_profile_description() {
    local desc
    desc=$(_builtin_profile_description "$1")
    if [[ -n "$desc" ]]; then
        printf '%s' "$desc"
    else
        get_custom_profile_description "$1"
    fi
}

export -f _read_ini get_profile_packages get_profile_description get_all_profile_names profile_exists expand_profile
export -f get_profile_file_path read_config_value read_profile_section update_profile_section get_current_profiles
export -f get_profile_core get_profile_build_tools get_profile_shell get_profile_networking get_profile_c get_profile_openwrt
export -f get_profile_rust get_profile_python get_profile_go get_profile_flutter get_profile_javascript get_profile_java get_profile_ruby
export -f get_profile_php get_profile_database get_profile_devops get_profile_web get_profile_embedded get_profile_datascience
export -f get_profile_security get_profile_ml get_profile_tunnel
export -f get_custom_profile_names custom_profile_exists get_custom_profile get_custom_profile_description
export -f _builtin_profile_exists _builtin_profile_names _builtin_profile_description