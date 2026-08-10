#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if [[ "${WORKSPACE_INSTALL_CONDA:-1}" != "1" ]]; then
  workspace_log "Miniconda installation disabled"
  exit 0
fi

arch="$(workspace_detect_arch)" || workspace_die "unsupported architecture: $(uname -m)"
version="py312_26.5.3-2"
case "$arch" in
  x86_64)
    sha256="37606f9f03ced8ef60f4ffc76b21dda01728eac8a632dcab316c891cea4fe2f5"
    ;;
  aarch64)
    sha256="822923b30d789477964ef5589f86de5a72ac4c584bad3b9f72d97190e13d776f"
    ;;
  *)
    workspace_die "unsupported Miniconda architecture: $arch"
    ;;
esac

# Use one shared prefix per Ubuntu release/architecture. This avoids solving an
# environment on Ubuntu 24.04 and then reusing the same binaries on Ubuntu 22.04
# (or across x86_64/aarch64) when HOME is shared across a cluster.
# shellcheck disable=SC1091
source /etc/os-release
platform_id="ubuntu-${VERSION_ID}-${arch}"
conda_dir="${WORKSPACE_CONDA_DIR:-$HOME/.local/opt/miniconda-${platform_id}}"
conda_bin="$conda_dir/bin/conda"

if [[ ! -x "$conda_bin" ]]; then
  if [[ -e "$conda_dir" ]]; then
    workspace_die "$conda_dir exists but does not contain a working conda; move it aside or set WORKSPACE_CONDA_DIR"
  fi

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf -- "$tmp_dir"' EXIT
  installer="$tmp_dir/miniconda.sh"
  url="https://repo.anaconda.com/miniconda/Miniconda3-${version}-Linux-${arch}.sh"

  workspace_log "downloading Miniconda $version for $arch"
  workspace_download "$url" "$installer"
  printf '%s  %s\n' "$sha256" "$installer" | sha256sum -c -
  bash "$installer" -b -p "$conda_dir"
  workspace_log "installed Miniconda in $conda_dir"
else
  workspace_log "Miniconda already present in $conda_dir"
fi

# Do not use `conda init`; shell integration is sourced from the managed shell
# config so .bashrc/.zshrc stay deterministic.
"$conda_bin" config --set prefix_data_interoperability true

# Persist an install-time override so later shells activate the prefix that was
# actually installed. A one-shot WORKSPACE_CONDA_DIR would otherwise be lost.
prefix_file="$(mktemp)"
printf '%s\n' "$conda_dir" > "$prefix_file"
workspace_install_file "$prefix_file" "$HOME/.config/setup_workspace/conda-prefix" 0600
rm -f -- "$prefix_file"
