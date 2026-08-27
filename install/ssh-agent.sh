#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

workspace_install_file "$WORKSPACE_ROOT/bin/workspace-ssh-agent" "$HOME/.local/bin/workspace-ssh-agent" 0755
workspace_install_file "$WORKSPACE_ROOT/bin/workspace-tmux-agent" "$HOME/.local/bin/workspace-tmux-agent" 0755

# Older setup_workspace versions created ~/.ssh/rc to refresh a shared-home
# agent symlink. Replace those exact files with the managed hook. Arbitrary
# user SSH rc files are never overwritten.
old_rc="$HOME/.ssh/rc"
managed_marker='setup_workspace SSH agent hook'
install_managed_rc=0

is_legacy_ssh_rc() {
  local file="$1"
  local expected_current expected_compact
  expected_current="$(mktemp)"
  expected_compact="$(mktemp)"
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

  if cmp -s -- "$file" "$expected_current" || cmp -s -- "$file" "$expected_compact"; then
    rm -f -- "$expected_current" "$expected_compact"
    return 0
  fi
  rm -f -- "$expected_current" "$expected_compact"
  return 1
}

if [[ ! -e "$old_rc" ]]; then
  install_managed_rc=1
elif is_legacy_ssh_rc "$old_rc"; then
  workspace_move_aside "$old_rc"
  workspace_log "replaced legacy setup_workspace ~/.ssh/rc"
  install_managed_rc=1
elif grep -Fq "$managed_marker" "$old_rc"; then
  install_managed_rc=1
else
  workspace_warn "$old_rc exists and is not a setup_workspace file; leaving it unchanged"
  workspace_warn "non-interactive SSH (IDEs, ansible) will not refresh the agent or host-local JetBrains dirs unless this rc calls workspace-ssh-agent publish and workspace-jetbrains-local ensure"
fi

if [[ "$install_managed_rc" -eq 1 ]]; then
  mkdir -p -- "$HOME/.ssh"
  chmod 700 -- "$HOME/.ssh" 2>/dev/null || true
  workspace_install_file "$WORKSPACE_ROOT/configs/ssh.rc" "$old_rc" 0600
fi

# Publish only a live forwarded agent. Calling the helper with an empty
# SSH_AUTH_SOCK still creates /tmp/setup-workspace-ssh-agent-$UID, which
# would retarget the host socket during tests or a user-phase run without
# forwarding. ~/.ssh/rc and interactive shells publish later when a socket
# actually exists. WORKSPACE_SSH_AGENT_DIR, when set, is honored by the helper.
if [[ -S "${SSH_AUTH_SOCK:-}" ]]; then
  stable="$("$HOME/.local/bin/workspace-ssh-agent" publish "$SSH_AUTH_SOCK")"
  workspace_log "SSH agent stable socket: $stable"
else
  workspace_log "no live SSH_AUTH_SOCK; skipping agent publish"
fi
