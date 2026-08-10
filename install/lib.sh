#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
export WORKSPACE_ROOT

workspace_log() {
  printf '[setup_workspace] %s\n' "$*"
}

workspace_warn() {
  printf '[setup_workspace] WARNING: %s\n' "$*" >&2
}

workspace_die() {
  printf '[setup_workspace] ERROR: %s\n' "$*" >&2
  exit 1
}

workspace_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || workspace_die "required command not found: $1"
}

workspace_unique_backup_path() {
  local path="$1"
  local candidate="${path}.pre-setup-workspace"
  local suffix=0

  if [[ ! -e "$candidate" && ! -L "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="${path}.pre-setup-workspace.$(date -u +%Y%m%dT%H%M%SZ).$$"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    suffix=$((suffix + 1))
    candidate="${path}.pre-setup-workspace.$(date -u +%Y%m%dT%H%M%SZ).$$.$suffix"
  done
  printf '%s\n' "$candidate"
}

workspace_backup_current() {
  local path="$1"
  local backup

  [[ -e "$path" || -L "$path" ]] || return 0
  backup="$(workspace_unique_backup_path "$path")"
  cp -a -- "$path" "$backup"
  workspace_log "backed up $path -> $backup"
}

workspace_move_aside() {
  local path="$1"
  local backup

  [[ -e "$path" || -L "$path" ]] || return 0
  backup="$(workspace_unique_backup_path "$path")"
  mv -T -- "$path" "$backup"
  workspace_log "moved $path -> $backup"
}

workspace_neighbor_tmp() {
  local path="$1"
  mkdir -p -- "$(dirname -- "$path")"
  mktemp "${path}.setup-workspace.XXXXXX"
}

workspace_resolve_edit_path() {
  local path="$1"

  if [[ -L "$path" ]]; then
    readlink -f -- "$path" || workspace_die "cannot resolve symlink: $path"
  else
    printf '%s\n' "$path"
  fi
}

workspace_commit_rendered_file() {
  local rendered="$1"
  local logical_path="$2"
  local path

  path="$(workspace_resolve_edit_path "$logical_path")"
  mkdir -p -- "$(dirname -- "$path")"

  if [[ -f "$path" ]] && cmp -s -- "$rendered" "$path"; then
    rm -f -- "$rendered"
    return 0
  fi

  if [[ -e "$path" || -L "$path" ]]; then
    workspace_backup_current "$path"
    chmod --reference="$path" "$rendered" 2>/dev/null || chmod 0644 -- "$rendered"
  else
    chmod 0644 -- "$rendered"
  fi

  mv -Tf -- "$rendered" "$path"
  workspace_log "updated $logical_path"
}

workspace_install_file() {
  local src="$1"
  local dst="$2"
  local mode="${3:-0644}"
  local tmp

  tmp="$(workspace_neighbor_tmp "$dst")"
  install -m "$mode" -- "$src" "$tmp"

  if [[ -f "$dst" ]] && ! [[ -L "$dst" ]] && cmp -s -- "$tmp" "$dst"; then
    rm -f -- "$tmp"
    return 0
  fi

  mv -Tf -- "$tmp" "$dst"
  workspace_log "installed $dst"
}

workspace_safe_symlink() {
  local target="$1"
  local link_path="$2"

  if [[ -L "$link_path" && "$(readlink -- "$link_path")" == "$target" ]]; then
    return 0
  fi

  mkdir -p -- "$(dirname -- "$link_path")"
  if [[ -e "$link_path" || -L "$link_path" ]]; then
    workspace_move_aside "$link_path"
  fi

  ln -s -- "$target" "$link_path"
  workspace_log "linked $link_path -> $target"
}

workspace_managed_markers_balanced() {
  local file="$1"
  local start_marker="$2"
  local end_marker="$3"

  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start {
      if (in_block) bad = 1
      in_block = 1
      starts++
      next
    }
    $0 == end {
      if (!in_block) bad = 1
      in_block = 0
      ends++
      next
    }
    END {
      if (bad || in_block || starts != ends) exit 1
    }
  ' "$file"
}

workspace_replace_managed_block() {
  local logical_file="$1"
  local start_marker="$2"
  local end_marker="$3"
  local body_file="$4"
  local file
  local input
  local tmp

  file="$(workspace_resolve_edit_path "$logical_file")"
  mkdir -p -- "$(dirname -- "$file")"
  input="$file"
  [[ -f "$input" ]] || input=/dev/null

  if ! workspace_managed_markers_balanced "$input" "$start_marker" "$end_marker"; then
    workspace_die "managed block markers are unbalanced in $logical_file"
  fi

  tmp="$(workspace_neighbor_tmp "$file")"
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { in_block = 1; next }
    $0 == end   { in_block = 0; next }
    !in_block   { lines[++n] = $0 }
    END {
      while (n > 0 && lines[n] == "") n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ' "$input" > "$tmp"

  if [[ -s "$tmp" ]]; then
    printf '\n' >> "$tmp"
  fi
  printf '%s\n' "$start_marker" >> "$tmp"
  cat -- "$body_file" >> "$tmp"
  if [[ -s "$body_file" ]] && [[ "$(tail -c 1 "$body_file" | od -An -t u1 | tr -d ' ')" != "10" ]]; then
    printf '\n' >> "$tmp"
  fi
  printf '%s\n' "$end_marker" >> "$tmp"

  workspace_commit_rendered_file "$tmp" "$logical_file"
}

workspace_remove_managed_block_if_present() {
  local logical_file="$1"
  local start_marker="$2"
  local end_marker="$3"
  local file
  local tmp

  file="$(workspace_resolve_edit_path "$logical_file")"
  [[ -f "$file" ]] || return 0

  if ! grep -Fqx -- "$start_marker" "$file" && ! grep -Fqx -- "$end_marker" "$file"; then
    return 0
  fi

  if ! workspace_managed_markers_balanced "$file" "$start_marker" "$end_marker"; then
    workspace_warn "legacy block markers are unbalanced in $logical_file; leaving it unchanged"
    return 0
  fi

  tmp="$(workspace_neighbor_tmp "$file")"
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { in_block = 1; next }
    $0 == end   { in_block = 0; next }
    !in_block   { print }
  ' "$file" > "$tmp"
  workspace_commit_rendered_file "$tmp" "$logical_file"
  workspace_log "removed legacy managed block from $logical_file"
}

workspace_prepend_managed_block() {
  local logical_file="$1"
  local start_marker="$2"
  local end_marker="$3"
  local body_file="$4"
  local file
  local input
  local tmp
  local remainder

  file="$(workspace_resolve_edit_path "$logical_file")"
  mkdir -p -- "$(dirname -- "$file")"
  input="$file"
  [[ -f "$input" ]] || input=/dev/null

  if ! workspace_managed_markers_balanced "$input" "$start_marker" "$end_marker"; then
    workspace_die "managed block markers are unbalanced in $logical_file"
  fi

  tmp="$(workspace_neighbor_tmp "$file")"
  remainder="$(workspace_neighbor_tmp "$file")"
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { in_block = 1; next }
    $0 == end   { in_block = 0; skip_blank = 1; next }
    !in_block {
      if (skip_blank && $0 == "") next
      skip_blank = 0
      print
    }
  ' "$input" > "$remainder"

  printf '%s\n' "$start_marker" > "$tmp"
  cat -- "$body_file" >> "$tmp"
  if [[ -s "$body_file" ]] && [[ "$(tail -c 1 "$body_file" | od -An -t u1 | tr -d ' ')" != "10" ]]; then
    printf '\n' >> "$tmp"
  fi
  printf '%s\n' "$end_marker" >> "$tmp"

  if [[ -s "$remainder" ]]; then
    printf '\n' >> "$tmp"
    cat -- "$remainder" >> "$tmp"
  fi
  rm -f -- "$remainder"

  workspace_commit_rendered_file "$tmp" "$logical_file"
}

workspace_detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'x86_64\n'
      ;;
    aarch64|arm64)
      printf 'aarch64\n'
      ;;
    *)
      return 1
      ;;
  esac
}

workspace_download() {
  local url="$1"
  local dst="$2"

  curl --fail --location --show-error --silent --retry 3 --retry-delay 2 \
    --output "$dst" "$url"
}

workspace_is_systemd_running() {
  [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

workspace_home_filesystem_type() {
  # statfs follows HOME to its mounted filesystem, including when HOME itself
  # is reached through an automount path.
  stat -f -c '%T' "$HOME" 2>/dev/null || printf 'unknown\n'
}

workspace_filesystem_is_networked() {
  # Keep this conservative list in sync with workspace-jetbrains-local. It
  # covers common NAS protocols plus shared/distributed filesystems frequently
  # used for cluster home directories. Unknown filesystems retain normal HOME
  # behavior rather than unexpectedly moving user state.
  case "$1" in
    nfs|nfs4|cifs|smb2|smbfs|autofs|afs|ceph|ceph-fuse|glusterfs|gpfs|lustre|panfs|9p|davfs|davfs2|fuse.sshfs|sshfs)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

workspace_jetbrains_local_default() {
  if workspace_filesystem_is_networked "$1"; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

workspace_acquire_shared_lock() {
  local state_dir="$HOME/.local/state/setup_workspace"
  local lock_dir="$state_dir/install.lock"

  mkdir -p -- "$state_dir"
  if ! mkdir -- "$lock_dir" 2>/dev/null; then
    workspace_warn "shared-home installation lock exists: $lock_dir"
    if [[ -r "$lock_dir/owner" ]]; then
      sed 's/^/[setup_workspace] lock: /' "$lock_dir/owner" >&2
    fi
    workspace_die "another user-phase install may be running; retry later or inspect the lock"
  fi

  {
    printf 'host=%s\n' "$(hostname -f 2>/dev/null || hostname)"
    printf 'pid=%s\n' "$$"
    printf 'started=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$lock_dir/owner"

  WORKSPACE_SHARED_LOCK_DIR="$lock_dir"
  export WORKSPACE_SHARED_LOCK_DIR
}

workspace_release_shared_lock() {
  local lock_dir="${WORKSPACE_SHARED_LOCK_DIR:-}"

  [[ -n "$lock_dir" ]] || return 0
  if [[ "$lock_dir" == "$HOME/.local/state/setup_workspace/install.lock" && -d "$lock_dir" ]]; then
    rm -f -- "$lock_dir/owner"
    rmdir -- "$lock_dir" 2>/dev/null || true
  fi
  unset WORKSPACE_SHARED_LOCK_DIR
}
