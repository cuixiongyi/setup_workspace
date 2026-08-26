#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

remove_legacy_env_lines() {
  local logical_file="$1"
  local kind="$2"
  local file
  local tmp

  file="$(workspace_resolve_edit_path "$logical_file")"
  [[ -f "$file" ]] || return 0

  case "$kind" in
    shell)
      if ! grep -Eq '^[[:space:]]*export[[:space:]]+(XDG_CACHE_HOME|XDG_CONFIG_HOME|XDG_DATA_HOME|TMPDIR)=/?(tmp|var/tmp)/jetbrains[_-]' "$file"; then
        return 0
      fi
      tmp="$(workspace_neighbor_tmp "$file")"
      awk '
        $0 ~ /^[[:space:]]*export[[:space:]]+(XDG_CACHE_HOME|XDG_CONFIG_HOME|XDG_DATA_HOME|TMPDIR)=\/?(tmp|var\/tmp)\/jetbrains[_-][^[:space:]]*/ { next }
        { print }
      ' "$file" > "$tmp"
      ;;
    pam)
      if ! grep -Eq '^[[:space:]]*(XDG_CACHE_HOME|XDG_CONFIG_HOME|XDG_DATA_HOME|TMPDIR)[[:space:]]+DEFAULT=/?(tmp|var/tmp)/jetbrains[_-]' "$file"; then
        return 0
      fi
      tmp="$(workspace_neighbor_tmp "$file")"
      awk '
        $0 ~ /^[[:space:]]*(XDG_CACHE_HOME|XDG_CONFIG_HOME|XDG_DATA_HOME|TMPDIR)[[:space:]]+DEFAULT=\/?(tmp|var\/tmp)\/jetbrains[_-][^[:space:]]*/ { next }
        { print }
      ' "$file" > "$tmp"
      ;;
    *)
      workspace_die "unknown legacy environment file kind: $kind"
      ;;
  esac

  workspace_commit_rendered_file "$tmp" "$logical_file"
}

# Remove only markers/lines emitted by the two previous JetBrains workarounds.
# Arbitrary SSH rc content is preserved; install/ssh-agent.sh can then recognize
# and retire the remaining legacy agent-only rc exactly.
workspace_remove_managed_block_if_present \
  "$HOME/.profile" \
  '# >>> jetbrains_remote_fix >>>' \
  '# <<< jetbrains_remote_fix <<<'
workspace_remove_managed_block_if_present \
  "$HOME/.profile" \
  '# >>> setup_workspace jetbrains-local-cache >>>' \
  '# <<< setup_workspace jetbrains-local-cache <<<'
remove_legacy_env_lines "$HOME/.pam_environment" pam
remove_legacy_env_lines "$HOME/.ssh/rc" shell
if [[ -f "$HOME/.ssh/rc" ]] && ! grep -q '[^[:space:]]' "$HOME/.ssh/rc"; then
  workspace_move_aside "$HOME/.ssh/rc"
fi

if [[ "${WORKSPACE_INSTALL_JETBRAINS_LOCAL:-0}" != "1" ]]; then
  workspace_log "persistent host-local JetBrains directories disabled"
  exit 0
fi

helper="$HOME/.local/bin/workspace-jetbrains-local"
workspace_install_file "$WORKSPACE_ROOT/bin/workspace-jetbrains-local" "$helper" 0755

# Keep the automatic path host-local and stable without requiring cluster
# mount-point conventions. Users can still select a different persistent local
# root explicitly with WORKSPACE_LOCAL_ROOT.
local_root="${WORKSPACE_LOCAL_ROOT:-/var/tmp/setup-workspace-$(id -u)}"
root_file="$(mktemp)"
printf '%s\n' "$local_root" > "$root_file"
workspace_install_file "$root_file" "$HOME/.config/setup_workspace/local-root" 0600
rm -f -- "$root_file"

local_root="$("$helper" ensure)"

seed_if_empty() {
  local source_dir="$1"
  local target_dir="$2"

  [[ -d "$source_dir" && ! -L "$source_dir" ]] || return 0
  if [[ -z "$(find "$target_dir" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    workspace_log "seeding $target_dir from $source_dir"
    cp -a -- "$source_dir/." "$target_dir/"
  fi
}

cache_link="$HOME/.cache/JetBrains"
config_link="$HOME/.config/JetBrains"
share_link="$HOME/.local/share/JetBrains"

# Preserve settings and plugins on the installation host. Cache/backend binaries
# are intentionally not copied from NAS.
seed_if_empty "$config_link" "$local_root/jetbrains/config"
seed_if_empty "$share_link" "$local_root/jetbrains/share"

workspace_safe_symlink "$local_root/jetbrains/cache" "$cache_link"
workspace_safe_symlink "$local_root/jetbrains/config" "$config_link"
workspace_safe_symlink "$local_root/jetbrains/share" "$share_link"

workspace_log "JetBrains state uses persistent host-local root $local_root"
