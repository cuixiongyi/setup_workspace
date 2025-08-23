#!/usr/bin/env bash
# Fix JetBrains/PyCharm Remote Dev on NFS/CIFS/AUTOFS homes
# - Per-user, no sudo required
# - Idempotent; safe to run multiple times
# - Sets XDG* dirs and TMPDIR to /var/tmp/$USER/jetbrains_*
# - Makes env apply to non-interactive SSH via ~/.pam_environment (and ~/.ssh/rc)
# - Optional: purge old JetBrains caches with --purge

set -euo pipefail

PURGE=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
    --force) FORCE=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: fix_jetbrains_remote.sh [--purge] [--force]

  --purge  Remove stale JetBrains caches in $HOME and /tmp to force clean backend reinstall
  --force  Rewrite env files even if they already look correct
USAGE
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

USER_NAME="${USER:-$(id -un)}"
HOME_DIR="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}"

# Detect FS type of $HOME (fallback to /home)
FS_TYPE="$(findmnt -n -o FSTYPE --target "$HOME_DIR" 2>/dev/null || true)"
if [[ -z "$FS_TYPE" ]]; then
  # Some setups require checking parent mount of /home
  FS_TYPE="$(findmnt -n -o FSTYPE /home 2>/dev/null || true)"
fi

NEEDS_FIX=0
if [[ "$FS_TYPE" =~ ^(nfs|nfs4|cifs|smbfs|autofs)$ ]]; then
  NEEDS_FIX=1
fi

JET_BASE="/var/tmp/$USER_NAME"
XDG_CACHE="$JET_BASE/jetbrains_cache"
XDG_CONFIG="$JET_BASE/jetbrains_config"
XDG_DATA="$JET_BASE/jetbrains_data"
TMP_DIR="$JET_BASE/jetbrains_tmp"

mkdir -p "$XDG_CACHE" "$XDG_CONFIG" "$XDG_DATA" "$TMP_DIR"
chmod 700 "$XDG_CACHE" "$XDG_CONFIG" "$XDG_DATA" "$TMP_DIR"

# Helper: ensure a key=value pair exists in ~/.pam_environment with DEFAULT= form
ensure_pam_env() {
  local key="$1" val="$2"
  local file="$HOME_DIR/.pam_environment"
  touch "$file"
  if grep -qE "^\s*${key}\s+" "$file"; then
    if [[ "$FORCE" -eq 1 ]]; then
      sed -i.bak -E "s|^\s*${key}\s+.*$|${key} DEFAULT=${val}|" "$file"
    fi
  else
    printf "%s DEFAULT=%s\n" "$key" "$val" >> "$file"
  fi
}

# Helper: ensure export line exists in ~/.ssh/rc
ensure_ssh_rc_export() {
  local key="$1" val="$2"
  local file="$HOME_DIR/.ssh/rc"
  mkdir -p "$HOME_DIR/.ssh"
  touch "$file"
  if ! grep -qE "^\s*export\s+${key}=" "$file"; then
    printf "export %s=%q\n" "$key" "$val" >> "$file"
  elif [[ "$FORCE" -eq 1 ]]; then
    # replace existing
    sed -i.bak -E "s|^\s*export\s+${key}=.*$|export ${key}=${val}|g" "$file"
  fi
  chmod 700 "$file"
}

# Compute current state signature to decide idempotency
CURRENT_SIG="$(printf "%s|%s|%s|%s|%s" "$FS_TYPE" "$XDG_CACHE" "$XDG_CONFIG" "$XDG_DATA" "$TMP_DIR" | shasum | awk '{print $1}')"
STATE_DIR="$HOME_DIR/.config/jetbrains_remote_fix"
STATE_FILE="$STATE_DIR/state.sig"
mkdir -p "$STATE_DIR"

# If not on a network FS, we still allow setup (harmless), but inform user
if [[ "$NEEDS_FIX" -eq 0 ]]; then
  echo "Note: $HOME appears to be on '$FS_TYPE' (not nfs/cifs/autofs). Proceeding anyway (safe)."
fi

# Apply ~/.pam_environment (works for non-interactive SSH via pam_env)
ensure_pam_env "XDG_CACHE_HOME" "$XDG_CACHE"
ensure_pam_env "XDG_CONFIG_HOME" "$XDG_CONFIG"
ensure_pam_env "XDG_DATA_HOME"  "$XDG_DATA"
ensure_pam_env "TMPDIR"         "$TMP_DIR"

# Also set in ~/.ssh/rc for robustness (SSH-only sessions)
ensure_ssh_rc_export "XDG_CACHE_HOME" "$XDG_CACHE"
ensure_ssh_rc_export "XDG_CONFIG_HOME" "$XDG_CONFIG"
ensure_ssh_rc_export "XDG_DATA_HOME"  "$XDG_DATA"
ensure_ssh_rc_export "TMPDIR"         "$TMP_DIR"

# Quick SFTP sanity (non-fatal)
if command -v sftp >/dev/null 2>&1; then
  if sftp -b /dev/null -q "$USER_NAME@$(hostname -f 2>/dev/null || hostname)" 2>/dev/null; then
    echo "SFTP sanity: OK (loopback to this host succeeded)."
  else
    echo "SFTP sanity: could not verify via loopback (this is fine if you're configuring a different remote)."
  fi
else
  echo "SFTP not found in PATH; skipping SFTP check."
fi

# Warn if /var/tmp is mounted noexec
if mount | awk '{print $3,$6}' | grep -E "(/var/tmp| on /var/tmp )" | grep -q noexec; then
  echo "WARNING: /var/tmp is mounted with 'noexec'. JetBrains backend may fail to start there."
fi

# Optional purge of old JetBrains caches to force clean backend install
if [[ "$PURGE" -eq 1 ]]; then
  echo "Purging old JetBrains caches (safe; only caches/backends)…"
  rm -rf "$HOME_DIR/.cache/JetBrains" "$HOME_DIR/.local/share/JetBrains" \
         /tmp/JetBrains-* "$TMP_DIR"/JetBrains-* 2>/dev/null || true
fi

# Determine if anything changed since last run (very simple check)
if [[ -f "$STATE_FILE" ]]; then
  PREV_SIG="$(cat "$STATE_FILE" || true)"
else
  PREV_SIG=""
fi

if [[ "$CURRENT_SIG" == "$PREV_SIG" && "$FORCE" -eq 0 && "$PURGE" -eq 0 ]]; then
  echo "JetBrains remote env already configured. Nothing to do."
  exit 0
fi

echo "$CURRENT_SIG" > "$STATE_FILE"

cat <<EOF
✔ JetBrains Remote Dev env prepared for user '$USER_NAME'
   FS type of \$HOME: ${FS_TYPE:-unknown}
   XDG_CACHE_HOME   = $XDG_CACHE
   XDG_CONFIG_HOME  = $XDG_CONFIG
   XDG_DATA_HOME    = $XDG_DATA
   TMPDIR           = $TMP_DIR

Next steps:
  1) Start the PyCharm Remote Dev / SSH Interpreter connection again.
  2) If it still errors with "no handler is returned", try with '--purge' once to force a clean backend reinstall.

Tip:
  These settings apply on next SSH session (via pam_env and ~/.ssh/rc). If you're already logged in, just reconnect.
EOF
