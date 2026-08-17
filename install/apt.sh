#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

packages=(
  ca-certificates
  curl
  wget
  git
  zsh
  vim
  htop
  parallel
  nmon
  tmux
  bmon
  python3
  rsync
  fzf
  shellcheck
  unzip
  xz-utils
  xclip
  openssh-client
  less
  groff
  gnupg
)

install_gui=0
case "${WORKSPACE_INSTALL_GUI:-auto}" in
  1|true|yes)
    install_gui=1
    ;;
  0|false|no)
    install_gui=0
    ;;
  auto)
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" || -n "${DESKTOP_SESSION:-}" ]]; then
      install_gui=1
    fi
    ;;
  *)
    workspace_die "invalid WORKSPACE_INSTALL_GUI=${WORKSPACE_INSTALL_GUI:-}"
    ;;
esac

if [[ "$install_gui" -eq 1 ]]; then
  packages+=(terminator)
fi

workspace_log "updating apt metadata"
sudo apt-get update
workspace_log "installing base packages"
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"

case "${WORKSPACE_OOM_POLICY:-auto}" in
  none)
    workspace_log "OOM helper installation disabled"
    ;;
  earlyoom)
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y earlyoom
    if workspace_is_systemd_running; then
      sudo systemctl enable --now earlyoom.service
    fi
    ;;
  systemd-oomd)
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y systemd-oomd
    if workspace_is_systemd_running; then
      sudo systemctl enable --now systemd-oomd.service
    fi
    ;;
  auto)
    if workspace_is_systemd_running && \
       (systemctl is-active --quiet systemd-oomd.service 2>/dev/null || \
        systemctl is-enabled --quiet systemd-oomd.service 2>/dev/null); then
      workspace_log "systemd-oomd is already active/enabled; not adding earlyoom"
    else
      sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y earlyoom
      if workspace_is_systemd_running; then
        sudo systemctl enable --now earlyoom.service
      fi
    fi
    ;;
  *)
    workspace_die "invalid WORKSPACE_OOM_POLICY=${WORKSPACE_OOM_POLICY:-}"
    ;;
esac
