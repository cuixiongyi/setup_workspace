#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/lib.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/install/lib.sh"

export WORKSPACE_ROOT="$ROOT_DIR"
export WORKSPACE_PROFILE="${WORKSPACE_PROFILE:-workstation}"
export WORKSPACE_INSTALL_SCOPE="${WORKSPACE_INSTALL_SCOPE:-all}"
export WORKSPACE_INSTALL_GUI="${WORKSPACE_INSTALL_GUI:-auto}"
export WORKSPACE_INSTALL_AWS="${WORKSPACE_INSTALL_AWS:-1}"
export WORKSPACE_INSTALL_CONDA="${WORKSPACE_INSTALL_CONDA:-1}"
export WORKSPACE_INSTALL_JETBRAINS_LOCAL="${WORKSPACE_INSTALL_JETBRAINS_LOCAL:-auto}"
export WORKSPACE_SET_DEFAULT_SHELL="${WORKSPACE_SET_DEFAULT_SHELL:-0}"
# Track the original Oh my tmux! repository. setup_workspace customizations are
# installed separately as ~/.tmux.conf.local, leaving this checkout pristine so
# it can move between pinned upstream revisions without maintaining a fork.
export WORKSPACE_TMUX_REPO="${WORKSPACE_TMUX_REPO:-https://github.com/gpakosz/.tmux.git}"
export WORKSPACE_TMUX_REF="${WORKSPACE_TMUX_REF:-58a3dcc0d718ec0fa1c0d5a2fddd640a1ad7a5b7}"
export WORKSPACE_COPY_FILES_REV="${WORKSPACE_COPY_FILES_REV:-aaa4bbabc29e1afadef98456a56b8a72a80519a2}"
export WORKSPACE_AWS_VERSION="${WORKSPACE_AWS_VERSION:-2.36.2}"
export WORKSPACE_OMZ_REPO="${WORKSPACE_OMZ_REPO:-https://github.com/ohmyzsh/ohmyzsh.git}"
export WORKSPACE_OMZ_REF="${WORKSPACE_OMZ_REF:-97b27bb2ec0701330b18c2d3e340b22e742b3fa8}"

oom_policy_explicit=0
print_config=0
if [[ -n "${WORKSPACE_OOM_POLICY+x}" ]]; then
  oom_policy_explicit=1
else
  export WORKSPACE_OOM_POLICY=auto
fi

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Profiles and phases:
  --cluster              Shared-home cluster profile. Disables GUI and OOM
                         policy changes unless explicitly overridden.
  --workstation          Standalone developer workstation profile (default).
  --system-only          Install machine-local packages/AWS CLI only.
  --user-only            Install shared-home user configuration only.

Feature options:
  --gui                  Install Terminator.
  --no-gui               Do not install Terminator.
  --jetbrains-local      Put JetBrains directories on persistent host-local disk.
  --no-jetbrains-local   Leave JetBrains directories under HOME.
  --no-aws               Skip AWS CLI installation.
  --no-conda             Skip Miniconda installation.
  --oom-policy POLICY    auto, earlyoom, systemd-oomd, or none.
  --set-default-shell    Run chsh to make zsh the login shell.
  --tmux-ref REF         Upstream tmux-config branch, tag, or commit.
  --print-config         Print resolved profile settings without installing.
  -h, --help             Show this help.

Environment overrides:
  WORKSPACE_PROFILE
  WORKSPACE_INSTALL_SCOPE
  WORKSPACE_LOCAL_ROOT
  WORKSPACE_TMUX_REPO
  WORKSPACE_TMUX_REF
  WORKSPACE_COPY_FILES_REV
  WORKSPACE_AWS_VERSION
  WORKSPACE_OMZ_REPO
  WORKSPACE_OMZ_REF
  WORKSPACE_TMUX_DIR
  WORKSPACE_CONDA_DIR
  WORKSPACE_INSTALL_GUI
  WORKSPACE_INSTALL_AWS
  WORKSPACE_INSTALL_CONDA
  WORKSPACE_INSTALL_JETBRAINS_LOCAL
  WORKSPACE_OOM_POLICY
  WORKSPACE_SET_DEFAULT_SHELL
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      export WORKSPACE_PROFILE=cluster
      shift
      ;;
    --workstation)
      export WORKSPACE_PROFILE=workstation
      shift
      ;;
    --system-only)
      [[ "$WORKSPACE_INSTALL_SCOPE" == "all" ]] ||
        workspace_die "choose only one install scope"
      export WORKSPACE_INSTALL_SCOPE=system
      shift
      ;;
    --user-only)
      [[ "$WORKSPACE_INSTALL_SCOPE" == "all" ]] ||
        workspace_die "choose only one install scope"
      export WORKSPACE_INSTALL_SCOPE=user
      shift
      ;;
    --gui)
      export WORKSPACE_INSTALL_GUI=1
      shift
      ;;
    --no-gui)
      export WORKSPACE_INSTALL_GUI=0
      shift
      ;;
    --jetbrains-local)
      export WORKSPACE_INSTALL_JETBRAINS_LOCAL=1
      shift
      ;;
    --no-jetbrains-local)
      export WORKSPACE_INSTALL_JETBRAINS_LOCAL=0
      shift
      ;;
    --no-aws)
      export WORKSPACE_INSTALL_AWS=0
      shift
      ;;
    --no-conda)
      export WORKSPACE_INSTALL_CONDA=0
      shift
      ;;
    --oom-policy)
      [[ $# -ge 2 ]] || workspace_die "--oom-policy requires a value"
      export WORKSPACE_OOM_POLICY="$2"
      oom_policy_explicit=1
      shift 2
      ;;
    --set-default-shell)
      export WORKSPACE_SET_DEFAULT_SHELL=1
      shift
      ;;
    --tmux-ref)
      [[ $# -ge 2 ]] || workspace_die "--tmux-ref requires a value"
      export WORKSPACE_TMUX_REF="$2"
      shift 2
      ;;
    --print-config)
      print_config=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      workspace_die "unknown option: $1"
      ;;
  esac
done

case "$WORKSPACE_PROFILE" in
  workstation|cluster) ;;
  *) workspace_die "invalid WORKSPACE_PROFILE=$WORKSPACE_PROFILE" ;;
esac
case "$WORKSPACE_INSTALL_SCOPE" in
  all|system|user) ;;
  *) workspace_die "invalid WORKSPACE_INSTALL_SCOPE=$WORKSPACE_INSTALL_SCOPE" ;;
esac

if [[ "$WORKSPACE_PROFILE" == "cluster" ]]; then
  [[ "$WORKSPACE_INSTALL_GUI" == "auto" ]] && export WORKSPACE_INSTALL_GUI=0
  [[ "$oom_policy_explicit" -eq 1 ]] || export WORKSPACE_OOM_POLICY=none
fi

# A shared HOME is unsafe for concurrently running JetBrains backends. Apply
# the same filesystem-based default in every profile so callers do not need to
# know whether the machine was labelled as a workstation or cluster. Explicit
# --jetbrains-local/--no-jetbrains-local choices have already changed auto to
# 1/0 and therefore remain authoritative.
if [[ "$WORKSPACE_INSTALL_JETBRAINS_LOCAL" == "auto" ]]; then
  WORKSPACE_INSTALL_JETBRAINS_LOCAL="$(
    workspace_jetbrains_local_default "$(workspace_home_filesystem_type)"
  )"
  export WORKSPACE_INSTALL_JETBRAINS_LOCAL
fi

if [[ "$print_config" -eq 1 ]]; then
  printf 'profile=%s\n' "$WORKSPACE_PROFILE"
  printf 'scope=%s\n' "$WORKSPACE_INSTALL_SCOPE"
  printf 'gui=%s\n' "$WORKSPACE_INSTALL_GUI"
  printf 'oom_policy=%s\n' "$WORKSPACE_OOM_POLICY"
  printf 'jetbrains_local=%s\n' "$WORKSPACE_INSTALL_JETBRAINS_LOCAL"
  printf 'aws_version=%s\n' "$WORKSPACE_AWS_VERSION"
  printf 'tmux_ref=%s\n' "$WORKSPACE_TMUX_REF"
  printf 'omz_ref=%s\n' "$WORKSPACE_OMZ_REF"
  printf 'copy_files_rev=%s\n' "$WORKSPACE_COPY_FILES_REV"
  exit 0
fi

[[ -r /etc/os-release ]] || workspace_die "/etc/os-release is missing"
# shellcheck disable=SC1091
source /etc/os-release

[[ "${ID:-}" == "ubuntu" ]] ||
  workspace_die "this installer targets Ubuntu only; detected ID=${ID:-unknown}"
case "${VERSION_ID:-}" in
  22.04|24.04) ;;
  *)
    workspace_die "supported Ubuntu versions are 22.04 and 24.04; detected ${VERSION_ID:-unknown}"
    ;;
esac

run_system_phase() {
  workspace_require_cmd sudo
  sudo -v

  workspace_log "running machine-local phase for Ubuntu $VERSION_ID"
  "$ROOT_DIR/install/apt.sh"
  "$ROOT_DIR/install/aws.sh"
}

run_user_phase() {
  workspace_acquire_shared_lock
  trap workspace_release_shared_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  workspace_log "running shared-home user phase"
  local steps=(
    git.sh
    miniconda.sh
    jetbrains.sh
    ssh-agent.sh
    tmux.sh
    zsh.sh
    tools.sh
  )
  local step
  for step in "${steps[@]}"; do
    workspace_log "running install/$step"
    "$ROOT_DIR/install/$step"
  done

  workspace_release_shared_lock
  trap - EXIT HUP INT TERM
}

workspace_log "profile: $WORKSPACE_PROFILE"
workspace_log "scope: $WORKSPACE_INSTALL_SCOPE"
workspace_log "tmux source: $WORKSPACE_TMUX_REPO @ $WORKSPACE_TMUX_REF"

case "$WORKSPACE_INSTALL_SCOPE" in
  all)
    run_system_phase
    run_user_phase
    ;;
  system)
    run_system_phase
    ;;
  user)
    run_user_phase
    ;;
esac

cat <<EOF

setup_workspace installation completed.

Profile: $WORKSPACE_PROFILE
Scope:   $WORKSPACE_INSTALL_SCOPE

Open a new shell, or run:
  exec zsh

SSH agent stable socket on every host:
  /tmp/setup-workspace-ssh-agent-$(id -u)/agent.sock

For cluster provisioning, run the system phase on every machine image/host and
the user phase once for the shared home.
EOF
