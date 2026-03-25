#!/bin/bash
set -euo pipefail

# ============================================================
# Claude Code Cloud Environment Bootstrap — default
# Replicates fnordpig's local environment on cloud VMs.
#
# Cloud environment setup script (one-liner for the UI):
#   curl -fsSL https://raw.githubusercontent.com/fnordpig/claude-cloud-environments/main/default-bootstrap/boot.sh | bash
#
# Runs as root on Ubuntu 24.04 BEFORE Claude Code launches.
# Only runs on new sessions (skipped on resume).
# ============================================================

BOOTSTRAP_START=$(date +%s)

log() { echo "=== Bootstrap: $1 ==="; }

# ============================================================
# 1. System packages
# ============================================================
log "System packages"
apt-get update -qq
apt-get install -y -qq \
	build-essential cmake pkg-config \
	jq ripgrep fd-find unzip \
	libssl-dev libsqlite3-dev \
	python3-pip python3-venv \
	shellcheck \
	clangd \
	>/dev/null 2>&1

# shfmt (not in Ubuntu repos, grab binary)
if ! command -v shfmt &>/dev/null; then
	curl -fsSL "https://github.com/mvdan/sh/releases/latest/download/shfmt_v3.10.0_linux_amd64" \
		-o /usr/local/bin/shfmt && chmod +x /usr/local/bin/shfmt
fi

# ============================================================
# 2. Node.js / npm (usually pre-installed on cloud image)
# ============================================================
if ! command -v node &>/dev/null; then
	log "Node.js"
	curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
	apt-get install -y -qq nodejs >/dev/null 2>&1
fi

# ============================================================
# 3. uv (Python package manager, likely pre-installed)
# ============================================================
if ! command -v uv &>/dev/null; then
	log "uv"
	curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
	export PATH="$HOME/.local/bin:$PATH"
fi

# ============================================================
# 4. Rust toolchain (for building ripvec-mcp)
# ============================================================
if ! command -v cargo &>/dev/null; then
	log "Rust toolchain"
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/null 2>&1
	# shellcheck source=/dev/null
	source "$HOME/.cargo/env"
fi
# Ensure cargo is on PATH for the rest of the script
export PATH="$HOME/.cargo/bin:$PATH"

# rust-analyzer for the Rust LSP plugin
rustup component add rust-analyzer >/dev/null 2>&1 || true

# ============================================================
# 5. LSP servers (for zircote-lsp plugins)
# ============================================================
log "LSP servers"

# Python: pyright, ruff, black, isort, mypy, bandit
pip install --break-system-packages -q \
	pyright ruff black isort mypy bandit pytest \
	>/dev/null 2>&1

# Bash: bash-language-server
npm install -g bash-language-server >/dev/null 2>&1

# TypeScript: vtsls
npm install -g @vtsls/language-server >/dev/null 2>&1

# JSON/YAML/Markdown: vscode language servers
npm install -g \
	vscode-langservers-extracted \
	yaml-language-server \
	unified-language-server \
	>/dev/null 2>&1

# SQL: sql-language-server
npm install -g sql-language-server >/dev/null 2>&1 || true

# Dockerfile: dockerfile-language-server
npm install -g dockerfile-language-server-nodejs >/dev/null 2>&1 || true

# Terraform: terraform-ls
if ! command -v terraform-ls &>/dev/null; then
	curl -fsSL https://releases.hashicorp.com/terraform-ls/0.34.3/terraform-ls_0.34.3_linux_amd64.zip \
		-o /tmp/terraform-ls.zip &&
		unzip -o /tmp/terraform-ls.zip -d /usr/local/bin/ >/dev/null 2>&1 &&
		rm /tmp/terraform-ls.zip || true
fi

# Rust cargo tools (optional, used by rust-lsp hooks on-demand)
cargo install cargo-audit cargo-deny cargo-outdated cargo-machete \
	>/dev/null 2>&1 || true

# ============================================================
# 6. Cozempic (context weight-loss tool)
# ============================================================
log "Cozempic"
pip install --break-system-packages -q cozempic >/dev/null 2>&1 || true

# ============================================================
# 7. tracemeld (npm MCP server + CLI)
# ============================================================
log "tracemeld"
npm install -g tracemeld@latest >/dev/null 2>&1

# ============================================================
# 7b. Textual-MCP (Textual TUI framework MCP server)
# ============================================================
log "Textual-MCP"
pip install --break-system-packages -q textual-mcp-server >/dev/null 2>&1 ||
	uv pip install --system textual-mcp-server >/dev/null 2>&1 || true

# ============================================================
# 8. ripvec (build from source)
# ============================================================
log "ripvec"
RIPVEC_DIR="/opt/ripvec"
if [ ! -d "$RIPVEC_DIR" ]; then
	git clone --depth 1 https://github.com/fnordpig/ripvec.git "$RIPVEC_DIR" >/dev/null 2>&1
	cd "$RIPVEC_DIR"
	cargo build --release >/dev/null 2>&1
	# Install the MCP server binary
	cp target/release/ripvec-mcp /usr/local/bin/ 2>/dev/null || true
	# Install the main ripvec binary
	cp target/release/ripvec /usr/local/bin/ 2>/dev/null || true
	cd /
fi

# ============================================================
# 9. Write ~/.claude/settings.json
#    (user-level settings do NOT carry over to cloud sessions)
# ============================================================
log "Claude Code settings"
mkdir -p ~/.claude

cat >~/.claude/settings.json <<'SETTINGS_EOF'
{
  "permissions": {
    "allow": [
      "Read",
      "Edit",
      "Write",
      "Glob",
      "Grep",
      "Bash(*)",
      "WebSearch",
      "WebFetch",
      "mcp__*"
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "claude-code-setup@claude-plugins-official": true,
    "code-simplifier@claude-plugins-official": true,
    "commit-commands@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "skill-creator@claude-plugins-official": true,
    "ralph-loop@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true,
    "plugin-dev@claude-plugins-official": true,
    "document-skills@anthropic-agent-skills": true,
    "superpowers@superpowers-marketplace": true,
    "superpowers-developing-for-claude-code@superpowers-marketplace": true,
    "astral@astral-sh": true,
    "tracemeld@my-claude-plugins": true,
    "plannotator@plannotator": true,
    "bash-lsp@zircote-lsp": true,
    "cpp-lsp@zircote-lsp": true,
    "dockerfile-lsp@zircote-lsp": true,
    "json-lsp@zircote-lsp": true,
    "lsp-tools@zircote-lsp": true,
    "markdown-lsp@zircote-lsp": true,
    "python-lsp@zircote-lsp": true,
    "sql-lsp@zircote-lsp": true,
    "terraform-lsp@zircote-lsp": true,
    "yaml-lsp@zircote-lsp": true,
    "rust-lsp@zircote-lsp": true
  },
  "extraKnownMarketplaces": {
    "my-claude-plugins": {
      "source": {
        "source": "github",
        "repo": "fnordpig/my-claude-plugins"
      },
      "autoUpdate": true
    },
    "astral-sh": {
      "source": {
        "source": "github",
        "repo": "astral-sh/claude-code-plugins"
      }
    },
    "claude-code-lsps": {
      "source": {
        "source": "github",
        "repo": "boostvolt/claude-code-lsps"
      }
    },
    "plannotator": {
      "source": {
        "source": "github",
        "repo": "backnotprop/plannotator"
      }
    },
    "zircote-lsp": {
      "source": {
        "source": "github",
        "repo": "zircote/lsp-marketplace"
      },
      "autoUpdate": true
    }
  },
  "effortLevel": "high",
  "model": "opus[1m]"
}
SETTINGS_EOF

# ============================================================
# 10. Statusline script (Catppuccin Mocha theme)
# ============================================================
log "Statusline"
cat >~/.claude/statusline-command.sh <<'STATUSLINE_EOF'
#!/usr/bin/env bash
# Claude Code status line — Catppuccin Mocha prompt style.
# Receives JSON via stdin; uses jq to extract session context.

MAUVE='\033[38;5;183m'
PINK='\033[38;5;218m'
BLUE='\033[38;5;111m'
TEAL='\033[38;5;116m'
PEACH='\033[38;5;216m'
GREEN='\033[38;5;150m'
DIM='\033[2m'
RESET='\033[0m'

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
session_name=$(echo "$input" | jq -r '.session_name // empty')

if [ -n "$cwd" ]; then
    short_cwd="${cwd/#$HOME/~}"
    short_cwd=$(echo "$short_cwd" | awk -F'/' '{
        n = NF
        if (n > 4) {
            printf "..."
            for (i = n-3; i <= n; i++) printf "/%s", $i
        } else print $0
    }')
else
    short_cwd=$(pwd | sed "s|^$HOME|~|")
fi

git_branch=""
if git -C "${cwd:-$PWD}" rev-parse --is-inside-work-tree --no-optional-locks >/dev/null 2>&1; then
    git_branch=$(git -C "${cwd:-$PWD}" symbolic-ref --short HEAD 2>/dev/null \
        || git -C "${cwd:-$PWD}" rev-parse --short HEAD 2>/dev/null)
fi

printf "${MAUVE}%s@%s${RESET}" "$(whoami)" "$(hostname -s)"
printf "  ${PINK}%s${RESET}" "$short_cwd"
if [ -n "$git_branch" ]; then
    printf "  ${BLUE} %s${RESET}" "$git_branch"
fi
if [ -n "$model" ]; then
    printf "  ${TEAL}%s${RESET}" "$model"
fi
if [ -n "$session_name" ]; then
    printf "  ${DIM}[%s]${RESET}" "$session_name"
fi
if [ -n "$used_pct" ]; then
    pct_int=${used_pct%.*}
    if [ "${pct_int:-0}" -ge 75 ]; then
        ctx_color="$PEACH"
    else
        ctx_color="$GREEN"
    fi
    printf "  ${ctx_color}ctx:%.0f%%${RESET}" "$used_pct"
fi
printf '\n'
STATUSLINE_EOF
chmod +x ~/.claude/statusline-command.sh

# ============================================================
# 11. Custom commands
# ============================================================
log "Custom commands"
mkdir -p ~/.claude/commands

# Cozempic command
cat >~/.claude/commands/cozempic.md <<'COZEMPIC_EOF'
---
description: Diagnose and prune bloated Claude Code context. Supports treat, reload, guard mode, and doctor.
argument-hint: "[diagnose|treat|guard|doctor]"
---

You are the Cozempic context weight-loss agent. Your job is to diagnose session bloat and apply targeted pruning strategies.

Cozempic is installed as a CLI tool. If `cozempic` is not found, install with `pip install cozempic`.

## On Bare Invocation (no args)

When the user runs `/cozempic` with no arguments:

1. **First**, run a quick size check silently:
   ```bash
   cozempic current 2>/dev/null
   ```

2. **Then** present this summary and menu. Output something like:

   > **Cozempic** — Context Weight-Loss Tool
   >
   > Current session: **X.XX MB** (N messages), **XX.XK tokens** (XX% context)
   >
   > Cozempic prunes bloated Claude Code sessions by collapsing progress ticks,
   > deduplicating file reads, stripping metadata, and more. Prescriptions range
   > from `gentle` (safe, ~50% savings) to `aggressive` (~90% savings).

3. **Then** use `AskUserQuestion` with:

**Question:** "What would you like to do?"
**Header:** "Cozempic"
**Options:**

1. **Diagnose** — "Analyze bloat sources and recommend a prescription (read-only, no changes)"
2. **Treat & Reload** (Recommended) — "Diagnose, prune session, and auto-open a new terminal with clean context"
3. **Treat Only** — "Diagnose and prune session in-place (you resume manually with claude --resume)"
4. **Guard Mode** — "Start a background sentinel that auto-prunes before compaction kills agent teams"

Then follow the appropriate section below based on their choice.

## On Invocation With Args

If the user passes arguments (e.g., `/cozempic diagnose`, `/cozempic treat`, `/cozempic guard`), skip the menu and go directly to the relevant section.

If the user passes a prescription name (e.g., `/cozempic aggressive`), go to Treat & Reload with that prescription.

---

## Diagnose

Run diagnosis and show results:
```bash
cozempic current --diagnose
```
The output includes **Tokens** (exact or heuristic estimate) and a **Context** bar showing % of the 200K context window used. Always surface both to the user.

After showing results, suggest a prescription:
- `gentle` — Safe, minimal: progress collapse + file-history dedup + metadata strip
- `standard` — Recommended: + thinking blocks, tool trim, stale reads, system reminders
- `aggressive` — Maximum: + error collapse, document dedup, mega-block trim, envelope strip

Recommend based on session size:
- Under 5MB: `gentle`
- 5-20MB: `standard`
- Over 20MB: `aggressive`

Ask if they'd like to treat.

## Treat & Reload

1. Run diagnosis first:
   ```bash
   cozempic current --diagnose
   ```
   **Important:** The output includes token count and context % bar — always surface these to the user.

2. Recommend a prescription based on bloat profile, then dry-run:
   ```bash
   cozempic treat current -rx <prescription>
   ```

3. Show the dry-run results, then ask confirmation to apply. On confirmation, run `reload`:
   ```bash
   cozempic reload -rx <prescription>
   ```
   **Do NOT run `cozempic treat --execute` before `cozempic reload`** — reload already treats internally.

4. Tell the user: *"Treatment applied. Type `/exit` — a new Terminal window will open automatically with the pruned session."*

## Treat Only

Same as Treat & Reload but without the auto-resume.

1. Diagnose, dry-run, confirm, then:
   ```bash
   cozempic treat current -rx <prescription> --execute
   ```

2. Tell the user: *"Treatment applied. To resume with the pruned session, exit and run `claude --resume`."*

## Guard Mode

For sessions running agent teams, **always recommend guard mode**.

```bash
cozempic guard --threshold 50 -rx standard --interval 30
```

Tell the user: *"Guard is watching your session. If it crosses the threshold, it will auto-prune (protecting team state) and reload."*

## Doctor

```bash
cozempic doctor        # Diagnose
cozempic doctor --fix  # Auto-fix where possible
```
COZEMPIC_EOF

# ============================================================
# 12. Global CLAUDE.md
# ============================================================
log "Global CLAUDE.md"
cat >~/.claude/CLAUDE.md <<'CLAUDEMD_EOF'
# Global Claude Instructions

Be concise. Prefer editing existing files over creating new ones.

## Shell Aliases to Know

- `grep` is aliased to `rg` (ripgrep) in interactive shells. When writing new shell code, always use `rg` directly with rg-native flags — never bare `grep`. Key differences: grep `-E` (extended regex) doesn't exist in rg (rg uses extended regex by default); grep `-oE 'pattern'` → rg `-o 'pattern'`; grep `-q` → rg `-q`.
CLAUDEMD_EOF

# ============================================================
# 13. MCP config (global fallback for non-project sessions)
# ============================================================
log "MCP config"
cat >~/.claude/.mcp.json <<'MCP_EOF'
{
  "mcpServers": {
    "CodSpeed": {
      "type": "http",
      "url": "https://mcp.codspeed.io/mcp"
    },
    "Textual-MCP": {
      "command": "uv",
      "args": ["run", "--with", "textual-mcp-server", "textual-mcp-server"],
      "env": {}
    }
  }
}
MCP_EOF

# ============================================================
# 14. Timing
# ============================================================
BOOTSTRAP_END=$(date +%s)
log "Complete in $((BOOTSTRAP_END - BOOTSTRAP_START))s"
