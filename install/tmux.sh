#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

workspace_require_cmd git

# The checkout contains only upstream code. All user behavior belongs in
# configs/tmux.conf.local so updating upstream never requires resetting or
# carrying local changes in this managed Git repository.
repo="${WORKSPACE_TMUX_REPO:-https://github.com/gpakosz/.tmux.git}"
ref="${WORKSPACE_TMUX_REF:-latest}"
tmux_dir="${WORKSPACE_TMUX_DIR:-$HOME/.local/share/setup_workspace/tmux}"

mkdir -p -- "$(dirname -- "$tmux_dir")"

if [[ ! -d "$tmux_dir/.git" ]]; then
  if [[ -e "$tmux_dir" ]]; then
    workspace_die "$tmux_dir exists but is not a git checkout"
  fi
  workspace_log "cloning upstream tmux config"
  git clone --origin origin "$repo" "$tmux_dir"
else
  current_origin="$(git -C "$tmux_dir" remote get-url origin 2>/dev/null || true)"
  if [[ "$current_origin" != "$repo" ]]; then
    workspace_warn "updating managed tmux checkout origin: $current_origin -> $repo"
    git -C "$tmux_dir" remote set-url origin "$repo"
  fi

  if [[ -n "$(git -C "$tmux_dir" status --porcelain)" ]]; then
    workspace_die "$tmux_dir contains local changes; move or commit them before updating the managed checkout"
  fi
fi

workspace_log "updating tmux config to $ref"
git -C "$tmux_dir" fetch --prune origin
commit="$(workspace_git_remote_commit "$tmux_dir" "$ref")"
git -C "$tmux_dir" checkout --detach "$commit"

workspace_install_file "$WORKSPACE_ROOT/configs/tmux.conf.local" "$HOME/.config/setup_workspace/tmux.conf.local" 0644
workspace_safe_symlink "$tmux_dir/.tmux.conf" "$HOME/.tmux.conf"
workspace_safe_symlink "$HOME/.config/setup_workspace/tmux.conf.local" "$HOME/.tmux.conf.local"

if [[ -n "${TMUX:-}" ]]; then
  tmux source-file "$HOME/.tmux.conf" || workspace_warn "tmux config reload failed; it will load on the next server start"
fi
