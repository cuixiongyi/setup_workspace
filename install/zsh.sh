#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

workspace_install_file "$WORKSPACE_ROOT/configs/shell-common.sh" "$HOME/.config/setup_workspace/shell-common.sh" 0644
workspace_install_file "$WORKSPACE_ROOT/configs/workspace.zsh" "$HOME/.config/setup_workspace/workspace.zsh" 0644
workspace_install_file "$WORKSPACE_ROOT/configs/workspace.bash" "$HOME/.config/setup_workspace/workspace.bash" 0644
workspace_install_file "$WORKSPACE_ROOT/configs/workspace.profile" "$HOME/.config/setup_workspace/workspace.profile" 0644

omz_dir="${ZSH:-$HOME/.oh-my-zsh}"
omz_repo="${WORKSPACE_OMZ_REPO:-https://github.com/ohmyzsh/ohmyzsh.git}"
omz_ref="${WORKSPACE_OMZ_REF:-latest}"

if [[ ! -d "$omz_dir/.git" ]]; then
  if [[ -e "$omz_dir" ]]; then
    workspace_warn "$omz_dir exists but is not a git checkout; leaving it unchanged"
  else
    workspace_log "cloning Oh My Zsh"
    git clone --filter=blob:none "$omz_repo" "$omz_dir"
  fi
else
  current_origin="$(git -C "$omz_dir" remote get-url origin 2>/dev/null || true)"
  if [[ "$current_origin" != "$omz_repo" ]]; then
    workspace_warn "updating Oh My Zsh origin: $current_origin -> $omz_repo"
    git -C "$omz_dir" remote set-url origin "$omz_repo"
  fi

  if [[ -n "$(git -C "$omz_dir" status --porcelain)" ]]; then
    workspace_die "$omz_dir contains local changes; move or commit them before updating Oh My Zsh"
  fi
fi

if [[ -d "$omz_dir/.git" ]]; then
  workspace_log "updating Oh My Zsh to $omz_ref"
  git -C "$omz_dir" fetch --prune origin
  omz_commit="$(workspace_git_remote_commit "$omz_dir" "$omz_ref")"
  git -C "$omz_dir" checkout --detach "$omz_commit"
fi

# Remove the exact legacy block produced by zshrc_setup.py, if present.
workspace_remove_managed_block_if_present \
  "$HOME/.zshrc" \
  '# workspace setup script start----------' \
  '# workspace setup script end----------'

zsh_body="$(mktemp)"
bash_body="$(mktemp)"
profile_body="$(mktemp)"
trap 'rm -f -- "$zsh_body" "$bash_body" "$profile_body"' EXIT

# The file may not exist on a clean account yet.
mkdir -p -- "$(dirname -- "$HOME/.zshrc")"
touch -- "$HOME/.zshrc"

cat > "$zsh_body" <<'ZSH_BODY'
[[ -r "$HOME/.config/setup_workspace/workspace.zsh" ]] && source "$HOME/.config/setup_workspace/workspace.zsh"
ZSH_BODY

if ! awk '
  $0 == "# >>> setup_workspace >>>" { in_block = 1; next }
  $0 == "# <<< setup_workspace <<<" { in_block = 0; next }
  !in_block { print }
' "$HOME/.zshrc" | grep -Eq '^[[:space:]]*(source|\.)[[:space:]].*oh-my-zsh\.sh'; then
  cat >> "$zsh_body" <<'ZSH_BODY'
[[ -r "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"
ZSH_BODY
fi

cat > "$bash_body" <<'BASH_BODY'
[ -r "$HOME/.config/setup_workspace/workspace.bash" ] && . "$HOME/.config/setup_workspace/workspace.bash"
BASH_BODY

cat > "$profile_body" <<'PROFILE_BODY'
[ -r "$HOME/.config/setup_workspace/workspace.profile" ] && . "$HOME/.config/setup_workspace/workspace.profile"
# Login bash does not always source .bashrc. shell-common.sh is idempotent, so
# this is safe when .bashrc also sources workspace.bash.
if [ -n "${BASH_VERSION:-}" ]; then
  [ -r "$HOME/.config/setup_workspace/workspace.bash" ] && . "$HOME/.config/setup_workspace/workspace.bash"
fi
PROFILE_BODY

workspace_prepend_managed_block "$HOME/.zshrc" '# >>> setup_workspace >>>' '# <<< setup_workspace <<<' "$zsh_body"
workspace_replace_managed_block "$HOME/.bashrc" '# >>> setup_workspace >>>' '# <<< setup_workspace <<<' "$bash_body"
workspace_replace_managed_block "$HOME/.profile" '# >>> setup_workspace login >>>' '# <<< setup_workspace login <<<' "$profile_body"
workspace_replace_managed_block "$HOME/.zprofile" '# >>> setup_workspace login >>>' '# <<< setup_workspace login <<<' "$profile_body"
if [[ -e "$HOME/.bash_profile" || -L "$HOME/.bash_profile" ]]; then
  workspace_replace_managed_block \
    "$HOME/.bash_profile" \
    '# >>> setup_workspace login >>>' \
    '# <<< setup_workspace login <<<' \
    "$profile_body"
fi

if [[ "${WORKSPACE_SET_DEFAULT_SHELL:-0}" == "1" ]]; then
  zsh_path="$(command -v zsh)"
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ "$current_shell" != "$zsh_path" ]]; then
    chsh -s "$zsh_path" || workspace_warn "chsh failed; set your login shell to $zsh_path manually"
  fi
fi
