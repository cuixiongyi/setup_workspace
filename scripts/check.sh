#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0
while IFS= read -r file; do
  if ! bash -n "$file"; then
    fail=1
  fi
done < <(find "$ROOT_DIR" -type f -name '*.sh' -print | sort)

for file in \
  "$ROOT_DIR/bin/workspace-ssh-agent" \
  "$ROOT_DIR/bin/workspace-tmux-agent" \
  "$ROOT_DIR/bin/workspace-jetbrains-local" \
  "$ROOT_DIR/configs/workspace.bash" \
  "$ROOT_DIR/configs/workspace.profile" \
  "$ROOT_DIR/configs/ssh.rc"; do
  if ! dash -n "$file"; then
    fail=1
  fi
done

if command -v zsh >/dev/null 2>&1; then
  if ! zsh -n "$ROOT_DIR/configs/workspace.zsh"; then
    fail=1
  fi
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -P "$ROOT_DIR/install" \
    "$ROOT_DIR/install.sh" \
    "$ROOT_DIR"/install/*.sh \
    "$ROOT_DIR"/bin/workspace-ssh-agent \
    "$ROOT_DIR"/bin/workspace-tmux-agent \
    "$ROOT_DIR"/bin/workspace-jetbrains-local \
    "$ROOT_DIR"/scripts/check.sh \
    "$ROOT_DIR"/scripts/fix_jetbrains_remote.sh \
    "$ROOT_DIR"/scripts/get_ros_env.sh \
    "$ROOT_DIR"/scripts/test.sh || fail=1
else
  echo "shellcheck not installed; skipped (CI requires it)"
fi

if grep -q '^set -g mouse on$' "$ROOT_DIR/configs/tmux.conf.local" && \
   grep -q 'MouseDragEnd1Pane' "$ROOT_DIR/configs/tmux.conf.local"; then
  echo "tmux custom settings are in configs/tmux.conf.local"
else
  echo "tmux custom settings check failed" >&2
  fail=1
fi

if grep -Fq 'https://github.com/gpakosz/.tmux.git' "$ROOT_DIR/install.sh" && \
   grep -Fq 'https://github.com/gpakosz/.tmux.git' "$ROOT_DIR/install/tmux.sh"; then
  echo "tmux uses the original upstream repository"
else
  echo "tmux upstream repository check failed" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "setup_workspace static checks passed"
