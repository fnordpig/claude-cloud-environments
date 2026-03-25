---
name: cloud-environment-primer
description: Complete reference for Claude Code cloud environments — setup scripts, SessionStart hooks, MCP servers, network policies, and the full VM boot flow. Use when creating or modifying cloud bootstrap scripts.
---

# Claude Code Cloud Environment Primer

## Part 1: The Web UI Configuration

Go to **claude.ai/code** → click the environment selector → **"Add environment"**.

The dialog has four fields:

### 1. Environment Name

A label like `fullstack`, `python-ml`, `rust-tools`. Create multiple and switch with `/remote-env` in terminal or the selector in the web UI.

### 2. Network Access

- **Limited (default)** — Allowlisted domains only. Includes npm, PyPI, crates.io, RubyGems, GitHub, Docker registries, common CDNs. Add custom domains one per line (wildcards: `*.example.com`).
- **Full** — All outbound traffic permitted through the security proxy.
- **Disabled** — Only Anthropic API reachable.

All traffic routes through an HTTP/HTTPS security proxy.

### 3. Environment Variables

Text area accepting `.env` format:

```
GITHUB_TOKEN=ghp_abc123
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=wJal...
MY_API_KEY=sk-xyz
ENABLE_LSP_TOOL=1
```

Injected into the cloud VM at session start. Available to setup script, Claude Code, stdio MCP servers, and hooks. Reference in `.mcp.json` with `${VAR_NAME}`.

### 4. Setup Script

Bash script that runs as root on Ubuntu 24.04 **before Claude Code launches**, only on new session creation (skipped on resume).

Instead of pasting a long script, point at your repo:

```bash
#!/bin/bash
curl -fsSL https://raw.githubusercontent.com/fnordpig/claude-cloud-environments/main/default-bootstrap/boot.sh | bash
```

If the script exits non-zero, the session fails to start. Append `|| true` to non-critical commands.

---

## Part 2: The Cloud VM

### Default Image

Ubuntu 24.04 with pre-installed:

- **Languages**: Python 3.x (pip, poetry), Node.js LTS (npm, yarn, pnpm, bun), Ruby 3.1-3.3 (rbenv), PHP 8.4, OpenJDK (Maven, Gradle), Go (latest), Rust (cargo), C++ (GCC, Clang)
- **Databases**: PostgreSQL 16, Redis 7.0
- **Tools**: git, common build tools, package managers

Run `check-tools` in a cloud session to see exact versions.

### What the bootstrap writes to `~/.claude/`

User-level settings do **not** carry over to cloud sessions. The setup script must write:

| File | Purpose |
|------|---------|
| `~/.claude/settings.json` | Permissions, plugins, marketplaces, statusline, model, effort |
| `~/.claude/statusline-command.sh` | Custom status line script |
| `~/.claude/commands/*.md` | Custom slash commands |
| `~/.claude/.mcp.json` | Global MCP servers (fallback for non-project sessions) |
| `~/.claude/CLAUDE.md` | Global instructions |

### What the repo provides (carried over automatically)

| File | Purpose |
|------|---------|
| `.claude/settings.json` | Project-level permissions, hooks, env |
| `.mcp.json` | Project-level MCP servers |
| `CLAUDE.md` | Project context |

---

## Part 3: Setup Scripts vs. SessionStart Hooks

|               | Setup scripts                                     | SessionStart hooks                                             |
| ------------- | ------------------------------------------------- | -------------------------------------------------------------- |
| Attached to   | The cloud environment (UI)                        | Your repository                                                |
| Configured in | Cloud environment UI                              | `.claude/settings.json` in repo                                |
| Runs          | Before Claude Code launches, new sessions only    | After Claude Code launches, every session including resumed    |
| Scope         | Cloud environments only                           | Both local and cloud                                           |

Use setup scripts for: installing tools, writing `~/.claude/` config, building binaries.
Use SessionStart hooks for: `npm install`, dependency checks, things that should run everywhere.

To scope a SessionStart hook to cloud only, check `$CLAUDE_CODE_REMOTE`:

```bash
#!/bin/bash
if [ "$CLAUDE_CODE_REMOTE" != "true" ]; then
  exit 0
fi
npm install
```

SessionStart hooks can persist env vars by writing to `$CLAUDE_ENV_FILE`.

---

## Part 4: MCP Server Patterns

### Python (FastMCP) — stdio transport

```python
from fastmcp import FastMCP
mcp = FastMCP("MyServer")

@mcp.tool()
def my_tool(query: str) -> str:
    """Tool description Claude sees."""
    return "result"

if __name__ == "__main__":
    mcp.run()
```

**Critical: never print to stdout** — it corrupts the JSON-RPC stream. Use `print(..., file=sys.stderr)` or logging.

`.mcp.json` entry:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "uv",
      "args": ["run", "--project", "./mcp_servers/my-server", "python", "mcp_servers/my-server/server.py"],
      "env": { "PYTHONUNBUFFERED": "1" }
    }
  }
}
```

The `uv run --project` pattern auto-creates a venv and installs deps from `pyproject.toml`.

### Rust (rmcp) — stdio transport

Compiles to a single static binary. No runtime deps needed on the cloud VM.

```rust
use rmcp::{ServerHandler, ServiceExt, model::*, schemars, tool};

#[derive(Clone)]
pub struct MyTools;

#[tool(tool_box)]
impl ServerHandler for MyTools {
    fn get_info(&self) -> ServerInfo { /* ... */ }
}

#[tool(tool_box)]
impl MyTools {
    #[tool(description = "My tool description")]
    async fn my_tool(&self, #[tool(aggr)] input: MyInput) -> Result<CallToolResult, rmcp::Error> {
        Ok(CallToolResult::success(vec![Content::text("result")]))
    }
}
```

**All logging to stderr** — stdout is JSON-RPC.

Distribute via GitHub Releases (fast) or build from source in setup script (2-5 min).

### npm packages

```json
{
  "mcpServers": {
    "my-server": {
      "command": "npx",
      "args": ["-y", "my-mcp-package@latest"]
    }
  }
}
```

### HTTP MCP servers

```json
{
  "mcpServers": {
    "my-server": {
      "type": "http",
      "url": "https://mcp.example.com/mcp"
    }
  }
}
```

---

## Part 5: The Full Boot Flow

```
1. `claude --remote "implement feature X"` or open claude.ai/code

2. Cloud VM boots (Ubuntu 24.04, ephemeral)

3. Env vars from cloud environment panel are injected

4. Setup script runs (boot.sh):
   - Installs system packages, language toolchains
   - Builds/downloads MCP server binaries
   - Writes ~/.claude/settings.json (plugins, marketplaces, permissions)
   - Writes statusline, commands, global CLAUDE.md

5. Repo is cloned into the VM

6. Claude Code launches

7. Claude reads:
   - CLAUDE.md              → project context
   - .claude/settings.json  → project permissions, hooks
   - ~/.claude/settings.json → user-level settings (written by boot.sh)
   - .mcp.json              → spawns all stdio MCP servers

8. SessionStart hooks fire (if configured in repo .claude/settings.json)

9. Plugins auto-install from configured marketplaces

10. Claude begins working with full tooling
```

---

## Part 6: Bootstrap Script Patterns

### Structure

```bash
#!/bin/bash
set -euo pipefail

BOOTSTRAP_START=$(date +%s)
log() { echo "=== Bootstrap: $1 ==="; }

# 1. System packages (apt)
# 2. Language runtimes (if not pre-installed)
# 3. LSP servers (npm/pip globals)
# 4. MCP server binaries (build or download)
# 5. CLI tools (pip/cargo/npm globals)
# 6. Write ~/.claude/settings.json
# 7. Write ~/.claude/statusline-command.sh
# 8. Write ~/.claude/commands/
# 9. Write ~/.claude/CLAUDE.md
# 10. Write ~/.claude/.mcp.json

BOOTSTRAP_END=$(date +%s)
log "Complete in $((BOOTSTRAP_END - BOOTSTRAP_START))s"
```

### Guard patterns

```bash
# Skip if already installed
if ! command -v my-tool &>/dev/null; then
  install my-tool
fi

# Non-critical installs
pip install optional-tool >/dev/null 2>&1 || true

# Quiet but logged
log "Installing X"
apt-get install -y -qq package >/dev/null 2>&1
```

### Cloud environment UI one-liner

```bash
curl -fsSL https://raw.githubusercontent.com/fnordpig/claude-cloud-environments/main/<profile>/boot.sh | bash
```

---

## Part 7: Network & Security

- Each session runs in an isolated, ephemeral VM
- All GitHub operations go through a dedicated proxy with scoped credentials
- All outbound traffic routes through an HTTP/HTTPS security proxy
- Git push is restricted to the current working branch
- Sensitive credentials (git tokens, signing keys) are never inside the sandbox

### Default allowed domains (Limited mode)

Includes: GitHub, npm, PyPI, crates.io, RubyGems, Go proxy, Maven, Docker registries, Ubuntu repos, HashiCorp releases, Anaconda, Kubernetes, cloud platforms (GCP, AWS, Azure), Statsig, Sentry, `*.modelcontextprotocol.io`.

For full list, see https://code.claude.com/docs/en/claude-code-on-the-web.
