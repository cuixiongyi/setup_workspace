#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Each agent-skills/<name> folder is one skill in the shared SKILL.md format.
# Claude Code reads ~/.claude/skills and Codex reads ~/.agents/skills; both
# follow symlinks, so one checkout serves both and updates with a git pull.
skills_root="$WORKSPACE_ROOT/agent-skills"
install_deps="${WORKSPACE_INSTALL_SKILL_DEPS:-1}"

for skill in "$skills_root"/*/; do
  skill="${skill%/}"
  [[ -f "$skill/SKILL.md" ]] || continue
  name="$(basename -- "$skill")"
  workspace_safe_symlink "$skill" "$HOME/.claude/skills/$name"
  workspace_safe_symlink "$skill" "$HOME/.agents/skills/$name"

  [[ -f "$skill/package-lock.json" && "$install_deps" == "1" ]] || continue
  if ! command -v npm >/dev/null 2>&1; then
    workspace_warn "npm not found; skipped dependencies for skill $name (run npm ci in $skill later)"
    continue
  fi
  workspace_log "installing dependencies for skill $name"
  npm ci --prefix "$skill" --no-audit --no-fund --no-update-notifier --loglevel=error
done

if [[ -d "$skills_root/code-path-explorer/node_modules/playwright" ]]; then
  workspace_log "code-path-explorer: run 'npx playwright install chromium' in $skills_root/code-path-explorer, or set CHROMIUM_PATH, before its browser check"
fi
