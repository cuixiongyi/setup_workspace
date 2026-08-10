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
omz_ref="${WORKSPACE_OMZ_REF:-97b27bb2ec0701330b18c2d3e340b22e742b3fa8}"

if [[ ! -d "$omz_dir/.git" ]]; then
  if [[ -e "$omz_dir" ]]; then
    workspace_warn "$omz_dir exists but is not a git checkout; leaving it unchanged"
  else
    workspace_log "cloning Oh My Zsh at $omz_ref"
    git clone --filter=blob:none --no-checkout "$omz_repo" "$omz_dir"
    git -C "$omz_dir" fetch --depth 1 origin "$omz_ref"
    git -C "$omz_dir" checkout --detach FETCH_HEAD
  fi
else
  workspace_log "Oh My Zsh already installed; not changing its revision"
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
PROFILE_BODY

workspace_prepend_managed_block "$HOME/.zshrc" '# >>> setup_workspace >>>' '# <<< setup_workspace <<<' "$zsh_body"
workspace_replace_managed_block "$HOME/.bashrc" '# >>> setup_workspace >>>' '# <<< setup_workspace <<<' "$bash_body"
workspace_replace_managed_block "$HOME/.profile" '# >>> setup_workspace login >>>' '# <<< setup_workspace login <<<' "$profile_body"
workspace_replace_managed_block "$HOME/.zprofile" '# >>> setup_workspace login >>>' '# <<< setup_workspace login <<<' "$profile_body"

if [[ "${WORKSPACE_SET_DEFAULT_SHELL:-0}" == "1" ]]; then
  zsh_path="$(command -v zsh)"
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ "$current_shell" != "$zsh_path" ]]; then
    chsh -s "$zsh_path" || workspace_warn "chsh failed; set your login shell to $zsh_path manually"
  fi
fi
