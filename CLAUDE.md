# Claude Cloud Environments

This repo holds bootstrap scripts for Claude Code cloud environments. Each subdirectory (e.g., `default-bootstrap/`) is a self-contained environment profile with a `boot.sh` that runs at cloud session start.

## How cloud environments work

Read `skills/cloud-environment-primer.md` for the complete reference on cloud VMs, setup scripts, SessionStart hooks, `.mcp.json`, network policies, and the full boot flow.

## Repo structure

```
├── CLAUDE.md                          # You are here
├── .claude/settings.json              # Project-level permissions
├── skills/
│   └── cloud-environment-primer.md    # Full cloud environment reference
├── default-bootstrap/
│   └── boot.sh                        # Default environment (full stack)
└── <future-profile>/
    └── boot.sh
```

## Key constraints

- Setup scripts run as **root on Ubuntu 24.04** before Claude Code launches.
- User-level `~/.claude/settings.json` does **not** carry over to cloud — the bootstrap must write it.
- Only repo-level `.claude/settings.json` and hooks committed to the repo run in cloud.
- If the setup script exits non-zero, the session fails to start. Use `|| true` for non-critical steps.
- Setup scripts only run on **new** sessions, not resume.

## Bootstrap architecture

The default bootstrap uses a two-phase strategy:

1. **Phase 1 (serial)**: `apt-get` — installs system packages. Must complete first since everything else depends on system libs.
2. **Phase 2 (parallel)**: Five independent tracks run as background jobs:
   - **Track A** — npm globals (LSP servers, tracemeld)
   - **Track B** — pip globals (Python LSP tools, cozempic, textual-mcp)
   - **Track C** — Rust toolchain + ripvec build from source
   - **Track D** — Binary downloads (shfmt, terraform-ls, delta, hyperfine, tokei)
   - **Track E** — Claude Code config writes (instant, no network)

All tracks are waited on before the script exits. Failures in any track are logged but non-fatal.

## Default bootstrap toolkit

### System packages (apt)

| Package | Why |
|---------|-----|
| `build-essential` `cmake` `pkg-config` `autoconf` `automake` `libtool` | C/C++/Rust compilation, native extensions |
| `jq` | JSON processing, used by statusline and hooks |
| `ripgrep` | Fast code search (`rg`), required by Claude Code and LSP hooks |
| `fd-find` | Fast file finder, complements ripgrep |
| `curl` `wget` | HTTP requests, downloading binaries |
| `unzip` `zip` | Archive handling (terraform-ls, etc.) |
| `libssl-dev` `libsqlite3-dev` `zlib1g-dev` `libffi-dev` | Native extension build deps (Rust, Python) |
| `python3-pip` `python3-venv` `python3-dev` | Python package management and native builds |
| `shellcheck` | Shell script linter, used by bash-lsp hooks |
| `clangd` `clang-format` | C/C++ LSP and formatting |
| `sqlite3` | Database CLI (ripvec uses SQLite) |
| `htop` `strace` | Process monitoring, syscall tracing |
| `tree` `file` `less` | File inspection basics |
| `tmux` | Terminal multiplexer for long sessions |
| `bat` | Syntax-highlighted file viewer |
| `gh` | GitHub CLI for PRs, issues, API |
| `fzf` | Fuzzy finder for interactive selection |

### Binary downloads

| Tool | Why |
|------|-----|
| `shfmt` | Shell formatter, used by bash-lsp hooks |
| `terraform-ls` | Terraform LSP, used by terraform-lsp plugin |
| `delta` | Better git diffs with syntax highlighting |
| `hyperfine` | CLI benchmarking tool |
| `tokei` | Code statistics (lines, languages, blanks) |

### npm globals

| Package | Why |
|---------|-----|
| `bash-language-server` | LSP for bash-lsp plugin |
| `@vtsls/language-server` | LSP for typescript-lsp plugin |
| `vscode-langservers-extracted` | JSON/HTML/CSS LSPs |
| `yaml-language-server` | LSP for yaml-lsp plugin |
| `unified-language-server` | LSP for markdown-lsp plugin |
| `sql-language-server` | LSP for sql-lsp plugin |
| `dockerfile-language-server-nodejs` | LSP for dockerfile-lsp plugin |
| `tracemeld` | Performance profiling MCP server + CLI |

### pip globals

| Package | Why |
|---------|-----|
| `pyright` | Python type checker, used by python-lsp plugin |
| `ruff` `black` `isort` | Python formatting, used by python-lsp hooks |
| `mypy` `bandit` `pytest` | Python type checking, security, testing |
| `cozempic` | Context weight-loss tool (`/cozempic` command) |
| `textual-mcp-server` | Textual TUI framework MCP server |

### Rust

| What | Why |
|------|-----|
| `rustup` + `rust-analyzer` | Rust toolchain + LSP for rust-lsp plugin |
| `cargo-audit` `cargo-deny` `cargo-outdated` `cargo-machete` | Rust dev tools used by rust-lsp hooks |
| `ripvec` + `ripvec-mcp` | Code embedding tool + MCP server (built from source) |

## When editing bootstrap scripts

- Keep installs quiet (`>/dev/null 2>&1`) but log section headers for debugging.
- Guard installs with `command -v` checks to skip what's already on the cloud image.
- Non-critical installs get `|| true` to avoid blocking session startup.
- Background jobs with `&` must be tracked and `wait`-ed before the script exits.
- The cloud image already has: Node.js LTS, Python 3.x, pip, common build tools, git, PostgreSQL 16, Redis 7. Run `check-tools` in a cloud session to verify.
- Test locally with `bash -n boot.sh` (syntax check) and `shellcheck boot.sh`.

## Adding a new bootstrap profile

1. Create a new directory: `<profile-name>/`
2. Add `boot.sh` (executable, starts with `#!/bin/bash` and `set -euo pipefail`)
3. The cloud UI setup script field uses:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/fnordpig/claude-cloud-environments/main/<profile-name>/boot.sh | bash
   ```
