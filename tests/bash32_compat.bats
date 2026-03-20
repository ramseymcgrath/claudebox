#!/usr/bin/env bats
# Tests for Bash 3.2 compatibility across ALL library files
# Scans for known Bash 4+ features that break on macOS default bash

load test_helper

LIB_DIR="$ROOT_DIR/lib"

# =============================================================================
# No associative arrays (declare -A) - Bash 4.0+
# =============================================================================

@test "no associative arrays in any lib file" {
    local violations=""
    for f in "$LIB_DIR"/*.sh; do
        if grep -n 'declare -A' "$f" 2>/dev/null; then
            violations="${violations}$(basename "$f"): uses declare -A\n"
        fi
    done
    [[ -z "$violations" ]] || {
        printf "Bash 4+ associative arrays found:\n%b" "$violations"
        return 1
    }
}

# =============================================================================
# No ${var^^} or ${var,,} case conversion - Bash 4.0+
# =============================================================================

@test "no uppercase expansion in any lib file" {
    local violations=""
    for f in "$LIB_DIR"/*.sh; do
        if grep -n '\${[^}]*\^\^}' "$f" 2>/dev/null; then
            violations="${violations}$(basename "$f"): uses \${var^^}\n"
        fi
        if grep -n '\${[^}]*,,}' "$f" 2>/dev/null; then
            violations="${violations}$(basename "$f"): uses \${var,,}\n"
        fi
    done
    [[ -z "$violations" ]] || {
        printf "Bash 4+ case conversion found:\n%b" "$violations"
        return 1
    }
}

# =============================================================================
# No [[ -v var ]] variable testing - Bash 4.2+
# =============================================================================

@test "no [[ -v var ]] in any lib file" {
    local violations=""
    for f in "$LIB_DIR"/*.sh; do
        if grep -n '\[\[.*-v ' "$f" 2>/dev/null; then
            violations="${violations}$(basename "$f"): uses [[ -v ]]\n"
        fi
    done
    [[ -z "$violations" ]] || {
        printf "Bash 4.2+ [[ -v ]] found:\n%b" "$violations"
        return 1
    }
}

# =============================================================================
# No nameref (declare -n) - Bash 4.3+
# =============================================================================

@test "no nameref in any lib file" {
    local violations=""
    for f in "$LIB_DIR"/*.sh; do
        if grep -n 'declare -n' "$f" 2>/dev/null; then
            violations="${violations}$(basename "$f"): uses declare -n\n"
        fi
    done
    [[ -z "$violations" ]] || {
        printf "Bash 4.3+ nameref found:\n%b" "$violations"
        return 1
    }
}

# =============================================================================
# No readarray/mapfile - Bash 4.0+
# =============================================================================

@test "no readarray or mapfile in any lib file" {
    local violations=""
    for f in "$LIB_DIR"/*.sh; do
        if grep -n '\breadarray\b\|mapfile\b' "$f" 2>/dev/null; then
            violations="${violations}$(basename "$f"): uses readarray/mapfile\n"
        fi
    done
    [[ -z "$violations" ]] || {
        printf "Bash 4+ readarray/mapfile found:\n%b" "$violations"
        return 1
    }
}

# =============================================================================
# No &>> redirect - Bash 4.0+
# =============================================================================

@test "no &>> redirect in any lib file" {
    local violations=""
    for f in "$LIB_DIR"/*.sh; do
        if grep -n '&>>' "$f" 2>/dev/null; then
            violations="${violations}$(basename "$f"): uses &>>\n"
        fi
    done
    [[ -z "$violations" ]] || {
        printf "Bash 4+ &>> redirect found:\n%b" "$violations"
        return 1
    }
}

# =============================================================================
# No coproc - Bash 4.0+
# =============================================================================

@test "no coproc in any lib file" {
    local violations=""
    for f in "$LIB_DIR"/*.sh; do
        if grep -n '\bcoproc\b' "$f" 2>/dev/null; then
            violations="${violations}$(basename "$f"): uses coproc\n"
        fi
    done
    [[ -z "$violations" ]] || {
        printf "Bash 4+ coproc found:\n%b" "$violations"
        return 1
    }
}

# =============================================================================
# Main script checks
# =============================================================================

@test "no associative arrays in main script" {
    ! grep -q 'declare -A' "$ROOT_DIR/claudebox.sh" 2>/dev/null || \
    ! grep -q 'declare -A' "$ROOT_DIR/main.sh" 2>/dev/null
}
