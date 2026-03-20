# ClaudeBox

[![Docker](https://img.shields.io/badge/Docker-Required-blue.svg)](https://www.docker.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Docker-based development environment for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Runs Claude in isolated containers with development profiles, MCP server management, multi-slot parallel instances, and Cloudflare AI Gateway support.

## Install

```bash
# Self-extracting installer
wget https://github.com/ramseymcgrath/claudebox/releases/latest/download/claudebox.run
chmod +x claudebox.run && ./claudebox.run
```

Or clone and run directly:
```bash
git clone https://github.com/ramseymcgrath/claudebox.git
cd claudebox && ./main.sh
```

Add `~/.local/bin` to your PATH if the `claudebox` command isn't found.

## Quick Start

```bash
cd ~/your-project
claudebox create        # Create a container slot
claudebox               # Launch Claude
```

## Profiles

Pre-configured language stacks installed as Docker layers. Add them per-project:

```bash
claudebox profiles              # List all available profiles
claudebox add python rust       # Add profiles
claudebox remove rust           # Remove a profile
```

| Profile | What it installs |
|---------|-----------------|
| `core` | gcc, g++, make, git, pkg-config, OpenSSL, tmux |
| `build-tools` | CMake, Ninja, autoconf, automake, libtool |
| `shell` | rsync, SSH, man, gnupg, fzf, file |
| `networking` | iptables, ipset, iproute2, DNS utils |
| `c` | gdb, valgrind, clang, cppcheck, Boost, ncurses, cmocka |
| `rust` | Rust toolchain via rustup |
| `python` | Python via uv (venv + dev tools managed at runtime) |
| `go` | Go from upstream tarball |
| `javascript` | Node.js via nvm, TypeScript, ESLint, Prettier |
| `java` | Latest LTS via SDKMan, Maven, Gradle, Ant |
| `ruby` | Ruby, gems, native extension deps |
| `php` | PHP, extensions, Composer |
| `flutter` | Flutter via fvm |
| `openwrt` | Cross toolchain, QEMU, distro tools |
| `database` | PostgreSQL, MySQL, SQLite, Redis, MongoDB clients |
| `devops` | Docker, kubectl, Helm, Terraform, Ansible, AWS CLI |
| `web` | nginx, Apache bench, HTTPie |
| `embedded` | ARM GCC, GDB multiarch, OpenOCD, PlatformIO |
| `datascience` | R, Jupyter, NumPy, pandas, scikit-learn (via uv) |
| `security` | nmap, tcpdump, Wireshark, netcat, John, Hashcat |
| `ml` | PyTorch, transformers, scikit-learn (via uv) |

### Custom Profiles

Drop `.sh` files into `~/.claudebox/custom-profiles/`. Each file contains Dockerfile instructions. The first `#` comment line becomes the description.

```bash
# ~/.claudebox/custom-profiles/mytools.sh
# My custom development tools
RUN apt-get update && apt-get install -y htop ncdu && apt-get clean
```

Then: `claudebox add mytools`

## MCP Servers

Install MCP servers directly into the Docker image:

```bash
claudebox mcp install memory          # Knowledge graph memory
claudebox mcp install filesystem -- /workspace
claudebox mcp install datadog         # Datadog monitoring
claudebox mcp install context7        # Library docs
claudebox mcp install @org/custom-mcp # Any npm package

claudebox mcp list                    # Show known + installed
claudebox mcp remove memory           # Uninstall
claudebox mcp status                  # Show config
```

Installed servers persist across container restarts. Their configs are automatically passed to Claude via `--mcp-config`.

**Known servers:** filesystem, memory, fetch, brave-search, github, gitlab, google-maps, slack, postgres, sqlite, puppeteer, sequential-thinking, git, time, everything, context7, datadog, aws-kb, sentry, linear.

## VM & Resources

ClaudeBox auto-manages [Colima](https://github.com/abiosoft/colima) as a lightweight Docker VM. If Docker isn't running when you launch ClaudeBox, it will install and start Colima with sensible resource defaults (half your CPUs/RAM).

```bash
claudebox vm status                        # Show VM and resource info
claudebox vm set --memory 8192 --cpus 4    # Resize VM (MB for memory)
claudebox vm set --max-containers 2        # Limit concurrency
claudebox vm set --container-memory 2048m  # Per-container memory cap
claudebox vm start                         # Manually start VM
claudebox vm stop                          # Stop VM
claudebox vm reset                         # Reset to auto-detected defaults
```

Every container gets automatic memory and CPU limits based on VM size and expected concurrency. This prevents OOM kills when running multiple slots in tmux.

## Plugins & Agents

Manage Claude Code plugins from the host. Plugins persist across container restarts and can be synced across slots.

```bash
claudebox agent popular                    # See recommended plugins
claudebox agent install commit-commands    # Install a plugin
claudebox agent install github             # GitHub integration
claudebox agent install typescript-lsp     # TypeScript intelligence
claudebox agent search security            # Search available plugins
claudebox agent browse                     # Interactive plugin browser
claudebox agent list                       # Show installed plugins
claudebox agent sync                       # Sync plugins across all slots
claudebox agent marketplace add owner/repo # Add community marketplace
```

100+ plugins available from the official Anthropic marketplace including LSP servers, integrations (GitHub, Slack, Linear, Sentry), development workflows, and more.

## Multi-Slot Containers

Run multiple authenticated Claude instances in the same project:

```bash
claudebox create                # Create a new slot
claudebox create                # Create another
claudebox slots                 # List all slots with auth status
claudebox slot 2                # Launch a specific slot
```

Each slot has its own authentication, config, and cache. Containers are ephemeral (auto-cleanup via `--rm`), but slot data persists.

### Tmux Multi-Pane

```bash
claudebox tmux 3                # Launch 3 Claude instances in tmux panes
claudebox tmux 2 1              # 2 panes in window 1, 1 in window 2
claudebox tmux conf             # Install ClaudeBox tmux config
```

## Persistent Auth

Save your authentication token once and share it across all containers:

```bash
claudebox auth save             # Save current slot's token
claudebox auth status           # Check token status
claudebox auth clear            # Remove saved token
```

## Cloudflare AI Gateway

Route all Claude API traffic through Cloudflare AI Gateway for caching, rate limiting, cost tracking, and logging:

```bash
claudebox gateway setup <account-id> <gateway-id>   # Configure AI Gateway
claudebox gateway status                             # Show configuration
claudebox gateway clear                              # Remove gateway config
```

Or set a custom API proxy URL directly:

```bash
claudebox gateway url https://my-proxy.example.com/v1
```

Create an AI Gateway in your Cloudflare dashboard under AI > AI Gateway. The account ID is in your Cloudflare dashboard URL; the gateway ID is the name you chose when creating the gateway.

## Commands

```
claudebox setup                     Interactive setup wizard
claudebox vm                        VM and resource management
claudebox agent                     Plugin and agent management
claudebox                           Launch Claude interactively
claudebox <claude-args>             Pass arguments through to Claude
claudebox shell                     Open a zsh shell in the container
claudebox shell admin               Shell with sudo enabled

claudebox profiles                  List available profiles
claudebox add <profiles...>         Add development profiles
claudebox remove <profiles...>      Remove profiles
claudebox install <packages...>     Install apt packages

claudebox mcp install <server>      Install an MCP server
claudebox mcp remove <server>       Remove an MCP server
claudebox mcp list                  List known/installed servers

claudebox create                    Create a new container slot
claudebox slots                     List all slots
claudebox slot <n>                  Launch specific slot
claudebox kill [all|hash]           Stop containers

claudebox auth save                 Save auth token persistently
claudebox gateway setup <id> <gw>   Configure Cloudflare AI Gateway
claudebox gateway url <url>        Set custom API proxy URL

claudebox info                      Show project/system info
claudebox projects                  List all ClaudeBox projects
claudebox project <name>            Open project by name
claudebox allowlist                 View/edit firewall rules

claudebox save [flags...]           Save default CLI flags
claudebox rebuild                   Force Docker image rebuild
claudebox update                    Update Claude CLI
claudebox tmux [layout]             Launch with tmux
claudebox clean                     Cleanup menu
```

### Flags

```
--verbose               Detailed debug output
--enable-sudo           Enable passwordless sudo in container
--disable-firewall      Disable network restrictions
```

## How It Works

ClaudeBox builds two Docker image layers:

1. **`claudebox-core`** -- Debian bookworm base with Node.js (nvm), uv, Claude CLI, zsh, gh, fzf, delta, tmux
2. **`claudebox-<project>`** -- Project-specific layer with installed profiles

Containers mount your project at `/workspace`, slot data from `~/.claudebox/projects/`, and SSH keys read-only. Each slot gets isolated `.claude/`, `.config/`, and `.cache/` directories.

Named containers use `--rm` for automatic cleanup. Slot directories on the host are the persistent state; Docker container names serve as locks (no lock files).

### Directory Layout

```
~/.claudebox/
  projects/<project-hash>/
    profiles.ini                    # Active profiles
    <slot-hash>/                    # Per-slot data
      .claude/                      # Auth, settings, commands
      .config/                      # Tool configs
      .cache/                       # Caches
  auth/credentials.json             # Persistent auth token
  gateway.env                       # AI Gateway configuration
  mcp-config.json                   # Installed MCP server configs
  mcp-servers.ini                   # Installed server tracking
  custom-profiles/                  # User-defined profiles
  default-flags                     # Saved CLI flags
```

## Troubleshooting

**Docker permission issues:** ClaudeBox adds you to the docker group automatically. Log out and back in, or run `newgrp docker`.

**Profile changes not applied:** ClaudeBox detects profile hash changes and rebuilds automatically. Force it with `claudebox rebuild`.

**Python venv issues:** The venv is created at container startup via uv. Run `claudebox shell` and check `which python`.

**Build failures:** `claudebox clean --cache` clears Docker build cache. `claudebox clean --all` for a full reset.

## License

MIT. See [LICENSE](LICENSE).

---

**Maintained by:** [ramseymcgrath](https://github.com/ramseymcgrath)
