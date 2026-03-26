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
#
# Strategy: apt first (provides system libs), then all package
# managers run in parallel as background jobs.
# ============================================================

BOOTSTRAP_START=$(date +%s)
PIDS=()

log() { echo "=== Bootstrap: $1 ==="; }

# Detect the user Claude Code will run as (not necessarily root)
# Cloud VMs typically use 'user' or 'ubuntu'; we write config for whoever owns /home
if [ -d /home/user ]; then
	CLAUDE_USER="user"
elif [ -d /home/ubuntu ]; then
	CLAUDE_USER="ubuntu"
else
	CLAUDE_USER="root"
fi
CLAUDE_HOME=$(eval echo "~${CLAUDE_USER}")
log "Running as $(whoami), writing config for ${CLAUDE_USER} (${CLAUDE_HOME})"

# Track background jobs; fail the bootstrap if any critical one fails
track() { PIDS+=("$!:$1"); }

wait_all() {
	local failed=0
	for entry in "${PIDS[@]}"; do
		local pid="${entry%%:*}"
		local name="${entry#*:}"
		if ! wait "$pid"; then
			echo "WARNING: $name failed (non-fatal)" >&2
			failed=$((failed + 1))
		fi
	done
	PIDS=()
	return 0 # non-fatal — individual steps use || true for optional bits
}

# ============================================================
# Phase 1: System packages (must complete before parallel phase)
# ============================================================
log "System packages"
apt-get update -qq
apt-get install -y -qq \
	build-essential cmake pkg-config autoconf automake libtool \
	jq ripgrep fd-find unzip zip \
	curl wget \
	libssl-dev libsqlite3-dev zlib1g-dev libffi-dev libopenblas-dev \
	python3-pip python3-venv python3-dev \
	shellcheck \
	clangd clang-format \
	sqlite3 \
	htop strace \
	tree file less \
	tmux \
	bat \
	gh \
	fzf \
	>/dev/null 2>&1

# ============================================================
# Phase 2: Parallel installs — all independent of each other
#
# After apt, these four tracks have no shared state:
#   A) npm global packages  (LSP servers, tracemeld)
#   B) pip global packages  (Python LSP tools, cozempic, textual-mcp)
#   C) Binary downloads     (shfmt, terraform-ls, delta, ripvec)
#   D) Claude Code config   (instant writes, no network)
# ============================================================

# --- Track A: npm globals -----------------------------------
install_npm() {
	log "npm globals"

	# Ensure node exists (usually pre-installed)
	if ! command -v node &>/dev/null; then
		curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
		apt-get install -y -qq nodejs >/dev/null 2>&1
	fi

	# LSP servers (one npm install for speed)
	npm install -g \
		bash-language-server \
		@vtsls/language-server \
		vscode-langservers-extracted \
		yaml-language-server \
		unified-language-server \
		sql-language-server \
		dockerfile-language-server-nodejs \
		>/dev/null 2>&1 || true

	# MCP servers + CLI tools
	npm install -g \
		tracemeld@latest \
		>/dev/null 2>&1
}
install_npm </dev/null &
track "$!" "npm globals"

# --- Track B: pip globals -----------------------------------
install_pip() {
	log "pip globals"

	# Ensure uv exists (usually pre-installed)
	if ! command -v uv &>/dev/null; then
		curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
		export PATH="$HOME/.local/bin:$PATH"
	fi

	# Python LSP + dev tools
	pip install --break-system-packages -q \
		pyright ruff black isort mypy bandit pytest \
		>/dev/null 2>&1

	# Cozempic (context weight-loss tool)
	pip install --break-system-packages -q cozempic >/dev/null 2>&1 || true

	# Textual-MCP (Textual TUI framework MCP server)
	pip install --break-system-packages -q textual-mcp-server >/dev/null 2>&1 || true
}
install_pip </dev/null &
track "$!" "pip globals"

# --- Track C: Binary downloads ------------------------------
install_binaries() {
	log "Binary downloads"

	# shfmt (shell formatter, not in Ubuntu repos)
	if ! command -v shfmt &>/dev/null; then
		curl -fsSL "https://github.com/mvdan/sh/releases/download/v3.10.0/shfmt_v3.10.0_linux_amd64" \
			-o /usr/local/bin/shfmt && chmod +x /usr/local/bin/shfmt
	fi

	# terraform-ls
	if ! command -v terraform-ls &>/dev/null; then
		curl -fsSL https://releases.hashicorp.com/terraform-ls/0.34.3/terraform-ls_0.34.3_linux_amd64.zip \
			-o /tmp/terraform-ls.zip &&
			unzip -o /tmp/terraform-ls.zip -d /usr/local/bin/ >/dev/null 2>&1 &&
			rm /tmp/terraform-ls.zip || true
	fi

	# delta (better git diff)
	if ! command -v delta &>/dev/null; then
		local delta_ver="0.18.2"
		curl -fsSL "https://github.com/dandavison/delta/releases/download/${delta_ver}/delta-${delta_ver}-x86_64-unknown-linux-gnu.tar.gz" \
			-o /tmp/delta.tar.gz &&
			tar -xzf /tmp/delta.tar.gz -C /tmp/ &&
			cp "/tmp/delta-${delta_ver}-x86_64-unknown-linux-gnu/delta" /usr/local/bin/ &&
			rm -rf /tmp/delta* || true
	fi

	# hyperfine (benchmarking)
	if ! command -v hyperfine &>/dev/null; then
		local hf_ver="1.19.0"
		curl -fsSL "https://github.com/sharkdp/hyperfine/releases/download/v${hf_ver}/hyperfine-v${hf_ver}-x86_64-unknown-linux-gnu.tar.gz" \
			-o /tmp/hyperfine.tar.gz &&
			tar -xzf /tmp/hyperfine.tar.gz -C /tmp/ &&
			cp "/tmp/hyperfine-v${hf_ver}-x86_64-unknown-linux-gnu/hyperfine" /usr/local/bin/ &&
			rm -rf /tmp/hyperfine* || true
	fi

	# tokei (code statistics)
	if ! command -v tokei &>/dev/null; then
		local tokei_ver="13.0.0-alpha.7"
		curl -fsSL "https://github.com/XAMPPRocky/tokei/releases/download/v${tokei_ver}/tokei-x86_64-unknown-linux-gnu.tar.gz" \
			-o /tmp/tokei.tar.gz &&
			tar -xzf /tmp/tokei.tar.gz -C /usr/local/bin/ tokei &&
			rm /tmp/tokei.tar.gz || true
	fi

	# ripvec (code embedding + MCP server)
	if ! command -v ripvec-mcp &>/dev/null; then
		local target="x86_64-unknown-linux-gnu"
		local tarball
		tarball=$(curl -fsSL "https://api.github.com/repos/fnordpig/ripvec/releases/latest" |
			jq -r ".assets[] | select(.name | test(\"${target}\")) | .browser_download_url")
		if [ -n "$tarball" ]; then
			curl -fsSL "$tarball" -o /tmp/ripvec.tar.gz
			tar xzf /tmp/ripvec.tar.gz -C /tmp/
			cp /tmp/ripvec-*/ripvec /usr/local/bin/ 2>/dev/null || true
			cp /tmp/ripvec-*/ripvec-mcp /usr/local/bin/ 2>/dev/null || true
			rm -rf /tmp/ripvec*
		fi
	fi
}
install_binaries </dev/null &
track "$!" "binary downloads"

# --- Track D: Claude Code config (instant, no network) ------
write_claude_config() {
	log "Claude Code config"
	mkdir -p "${CLAUDE_HOME}/.claude/commands"

	# ---- settings.json (user-level, does NOT carry over to cloud) ----
	# Mirrors local ~/.claude/settings.json
	# Bash(*) is intentional — the cloud sandbox is the security boundary
	cat >"${CLAUDE_HOME}/.claude/settings.json" <<'SETTINGS_EOF'
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
    "document-skills@anthropic-agent-skills": true,
    "superpowers@superpowers-marketplace": true,
    "astral@astral-sh": true,
    "typescript-lsp@claude-plugins-official": true,
    "yaml-language-server@claude-code-lsps": true,
    "superpowers-developing-for-claude-code@superpowers-marketplace": true,
    "plugin-dev@claude-plugins-official": true,
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
  "model": "opus"
}
SETTINGS_EOF

	# ---- Statusline (Catppuccin Mocha) ----
	cat >"${CLAUDE_HOME}/.claude/statusline-command.sh" <<'STATUSLINE_EOF'
#!/usr/bin/env bash
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
        if (n > 4) { printf "..."; for (i = n-3; i <= n; i++) printf "/%s", $i }
        else print $0
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
[ -n "$git_branch" ] && printf "  ${BLUE} %s${RESET}" "$git_branch"
[ -n "$model" ] && printf "  ${TEAL}%s${RESET}" "$model"
[ -n "$session_name" ] && printf "  ${DIM}[%s]${RESET}" "$session_name"
if [ -n "$used_pct" ]; then
    pct_int=${used_pct%.*}
    [ "${pct_int:-0}" -ge 75 ] && ctx_color="$PEACH" || ctx_color="$GREEN"
    printf "  ${ctx_color}ctx:%.0f%%${RESET}" "$used_pct"
fi
printf '\n'
STATUSLINE_EOF
	chmod +x "${CLAUDE_HOME}/.claude/statusline-command.sh"

	# ---- Cozempic command ----
	cat >"${CLAUDE_HOME}/.claude/commands/cozempic.md" <<'COZEMPIC_EOF'
---
description: Diagnose and prune bloated Claude Code context. Supports treat, reload, guard mode, and doctor.
argument-hint: "[diagnose|treat|guard|doctor]"
---

You are the Cozempic context weight-loss agent. Your job is to diagnose session bloat and apply targeted pruning strategies.

Cozempic is installed as a CLI tool. If `cozempic` is not found, install with `pip install cozempic`.

## On Bare Invocation (no args)

1. Run `cozempic current 2>/dev/null` silently.
2. Present summary and menu via `AskUserQuestion`:
   - **Diagnose** — Analyze bloat sources (read-only)
   - **Treat & Reload** (Recommended) — Diagnose, prune, auto-open new terminal
   - **Treat Only** — Prune in-place (resume manually with `claude --resume`)
   - **Guard Mode** — Background sentinel that auto-prunes before compaction

## On Invocation With Args

Skip menu, go directly to the relevant section.

## Diagnose

```bash
cozempic current --diagnose
```

Recommend: under 5MB → `gentle`, 5-20MB → `standard`, over 20MB → `aggressive`.

## Treat & Reload

1. `cozempic current --diagnose`
2. `cozempic treat current -rx <prescription>` (dry-run)
3. On confirmation: `cozempic reload -rx <prescription>`
   **Do NOT run `treat --execute` before `reload`** — reload treats internally.

## Treat Only

`cozempic treat current -rx <prescription> --execute`

## Guard Mode

`cozempic guard --threshold 50 -rx standard --interval 30`

## Doctor

`cozempic doctor` / `cozempic doctor --fix`
COZEMPIC_EOF

	# ---- Global CLAUDE.md ----
	cat >"${CLAUDE_HOME}/.claude/CLAUDE.md" <<'CLAUDEMD_EOF'
# Global Claude Instructions

Be concise. Prefer editing existing files over creating new ones.

## Shell Aliases to Know

- `grep` is aliased to `rg` (ripgrep) in interactive shells. When writing new shell code, always use `rg` directly with rg-native flags — never bare `grep`. Key differences: grep `-E` (extended regex) doesn't exist in rg (rg uses extended regex by default); grep `-oE 'pattern'` → rg `-o 'pattern'`; grep `-q` → rg `-q`.
CLAUDEMD_EOF

	# ---- MCP config ----
	cat >"${CLAUDE_HOME}/.claude/.mcp.json" <<'MCP_EOF'
{
  "mcpServers": {
    "Textual-MCP": {
      "command": "uv",
      "args": ["run", "--with", "textual-mcp-server", "textual-mcp"],
      "env": {}
    },
    "ripvec": {
      "command": "/usr/local/bin/ripvec-mcp",
      "args": []
    }
  }
}
MCP_EOF

	# Fix ownership if writing to another user's home
	if [ "${CLAUDE_USER}" != "root" ]; then
		chown -R "${CLAUDE_USER}:${CLAUDE_USER}" "${CLAUDE_HOME}/.claude"
	fi
}
write_claude_config </dev/null &
track "$!" "Claude config"

# ============================================================
# Wait for all parallel tracks
# ============================================================
log "Waiting for parallel installs"
wait_all

# ============================================================
# Verify critical tools landed
# ============================================================
for cmd in ripvec-mcp node pyright rg shfmt jq; do
	command -v "$cmd" >/dev/null 2>&1 || echo "WARNING: $cmd not found" >&2
done
[ -f "${CLAUDE_HOME}/.claude/settings.json" ] || echo "WARNING: settings.json not written" >&2
[ -f "${CLAUDE_HOME}/.claude/.mcp.json" ] || echo "WARNING: .mcp.json not written" >&2

# ============================================================
# Timing
# ============================================================
BOOTSTRAP_END=$(date +%s)
log "Complete in $((BOOTSTRAP_END - BOOTSTRAP_START))s"
