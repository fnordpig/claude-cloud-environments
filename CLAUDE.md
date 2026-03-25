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

## When editing bootstrap scripts

- Keep installs quiet (`>/dev/null 2>&1`) but log section headers for debugging.
- Guard installs with `command -v` checks to skip what's already on the cloud image.
- Non-critical installs get `|| true` to avoid blocking session startup.
- The cloud image already has: Node.js LTS, Python 3.x, pip, common build tools, git, PostgreSQL 16, Redis 7. Run `check-tools` in a cloud session to verify.
- Test locally with `bash -n boot.sh` (syntax check) and `shellcheck boot.sh`.

## Adding a new bootstrap profile

1. Create a new directory: `<profile-name>/`
2. Add `boot.sh` (executable, starts with `#!/bin/bash` and `set -euo pipefail`)
3. The cloud UI setup script field uses:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/fnordpig/claude-cloud-environments/main/<profile-name>/boot.sh | bash
   ```
