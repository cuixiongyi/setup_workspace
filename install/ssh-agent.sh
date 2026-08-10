#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

workspace_install_file "$WORKSPACE_ROOT/bin/workspace-ssh-agent" "$HOME/.local/bin/workspace-ssh-agent" 0755
workspace_install_file "$WORKSPACE_ROOT/bin/workspace-tmux-agent" "$HOME/.local/bin/workspace-tmux-agent" 0755

# Older setup_workspace versions created ~/.ssh/rc to refresh a shared-home
# agent symlink. Remove it only when it is byte-for-byte the old generated file.
# Arbitrary user SSH rc files are never overwritten.
old_rc="$HOME/.ssh/rc"
if [[ -f "$old_rc" ]]; then
  expected_current="$(mktemp)"
  expected_compact="$(mktemp)"
  trap 'rm -f -- "$expected_current" "$expected_compact"' EXIT
  cat > "$expected_current" <<'OLD_RC'
#!/bin/sh

agent_dir="$HOME/.tmp/ssh-agent"
agent_host="$(hostname -f 2>/dev/null || hostname)"
stable_socket="$agent_dir/$agent_host.sock"

umask 077
mkdir -p "$agent_dir"
chmod 700 "$agent_dir" 2>/dev/null || true

# SSH_AUTH_SOCK is provided by sshd when agent forwarding is enabled.
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    ln -sfn "$SSH_AUTH_SOCK" "$stable_socket"
fi
OLD_RC

  cat > "$expected_compact" <<'OLD_RC'
#!/bin/sh
agent_dir="$HOME/.tmp/ssh-agent"
agent_host="$(hostname -f 2>/dev/null || hostname)"
stable_socket="$agent_dir/$agent_host.sock"

umask 077
mkdir -p "$agent_dir"
chmod 700 "$agent_dir" 2>/dev/null || true
# SSH_AUTH_SOCK is provided by sshd when agent forwarding is enabled.
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    ln -sfn "$SSH_AUTH_SOCK" "$stable_socket"
fi
OLD_RC

  if cmp -s -- "$old_rc" "$expected_current" || cmp -s -- "$old_rc" "$expected_compact"; then
    workspace_move_aside "$old_rc"
    workspace_log "removed legacy setup_workspace ~/.ssh/rc"
  else
    workspace_warn "$old_rc exists and is not the legacy setup_workspace file; leaving it unchanged"
  fi
fi

stable="$("$HOME/.local/bin/workspace-ssh-agent" refresh "${SSH_AUTH_SOCK:-}")"
workspace_log "SSH agent stable socket: $stable"
