#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

rev="${WORKSPACE_COPY_FILES_REV:-latest}"
if [[ "$rev" == "latest" ]]; then
  rev="HEAD"
fi
url="https://raw.githubusercontent.com/cuixiongyi/copy-files-in-parallel/${rev}/copy-files-in-parallel"
dst="$HOME/.local/bin/copy-files-in-parallel"
tmp="$(mktemp)"
trap 'rm -f -- "$tmp"' EXIT

workspace_log "installing copy-files-in-parallel from $rev"
workspace_download "$url" "$tmp"
workspace_install_file "$tmp" "$dst" 0755
