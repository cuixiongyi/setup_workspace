# Shared shell setup for bash and zsh.

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-$EDITOR}"

# Publish an agent newly inherited or started by this shell, then use the
# host-local stable path. A zsh precmd hook calls this again after commands such
# as `eval "$(ssh-agent -s)"`; changing the symlink makes the agent immediately
# available to existing tmux panes that already use the stable path.
_workspace_sync_ssh_agent() {
  _workspace_agent_helper="$HOME/.local/bin/workspace-ssh-agent"
  [ -x "$_workspace_agent_helper" ] || return 0

  if [ -z "${_workspace_agent_stable:-}" ]; then
    _workspace_agent_stable="$("$_workspace_agent_helper" path 2>/dev/null || true)"
  fi
  [ -n "$_workspace_agent_stable" ] || return 0

  _workspace_agent_source="${SSH_AUTH_SOCK:-}"
  if [ -n "$_workspace_agent_source" ] && \
     [ "$_workspace_agent_source" != "$_workspace_agent_stable" ] && \
     [ -S "$_workspace_agent_source" ]; then
    _workspace_agent_published="$("$_workspace_agent_helper" publish "$_workspace_agent_source" 2>/dev/null || true)"
    if [ -n "$_workspace_agent_published" ]; then
      _workspace_agent_stable="$_workspace_agent_published"
    fi
  fi

  if [ -S "$_workspace_agent_stable" ]; then
    export SSH_AUTH_SOCK="$_workspace_agent_stable"
  fi
  unset _workspace_agent_helper _workspace_agent_source _workspace_agent_published
}

_workspace_sync_ssh_agent

# Activate the platform-specific Miniconda prefix. Conda detects system virtual
# packages such as glibc while solving, so a shared-home cluster should not use
# one mutable prefix across different Ubuntu releases or architectures.
_workspace_os_id="ubuntu"
_workspace_os_version="unknown"
if [ -r /etc/os-release ]; then
  _workspace_os_id="$(. /etc/os-release; printf '%s' "${ID:-unknown}")"
  _workspace_os_version="$(. /etc/os-release; printf '%s' "${VERSION_ID:-unknown}")"
fi
case "$(uname -m)" in
  x86_64|amd64) _workspace_arch="x86_64" ;;
  aarch64|arm64) _workspace_arch="aarch64" ;;
  *) _workspace_arch="$(uname -m)" ;;
esac
_workspace_conda_default="$HOME/.local/opt/miniconda-${_workspace_os_id}-${_workspace_os_version}-${_workspace_arch}"
_workspace_conda_saved=""
if [ -r "$HOME/.config/setup_workspace/conda-prefix" ]; then
  IFS= read -r _workspace_conda_saved < "$HOME/.config/setup_workspace/conda-prefix" || true
fi
_workspace_conda_dir="${WORKSPACE_CONDA_DIR:-${_workspace_conda_saved:-$_workspace_conda_default}}"
if [ -r "$_workspace_conda_dir/etc/profile.d/conda.sh" ]; then
  . "$_workspace_conda_dir/etc/profile.d/conda.sh"
fi
unset _workspace_os_id _workspace_os_version _workspace_arch
unset _workspace_conda_default _workspace_conda_saved _workspace_conda_dir

rsyncxy() {
  rsync -rahP "$@"
}

slist() {
  squeue -o "%.18i %.9P %.36j %.8u %.2t %.10M %.6D %R" -u "$USER" "$@"
}

slistall() {
  squeue -o "%.18i %.9P %.36j %.8u %.2t %.10M %.6D %R" "$@"
}

slistnode() {
  sinfo -N -l "$@"
}

# Preserve the old preference when pudb is actually installed, but do not make
# Python breakpoint() fail in environments that do not contain pudb.
if command -v pudb >/dev/null 2>&1; then
  export PYTHONBREAKPOINT="${PYTHONBREAKPOINT:-pudb.set_trace}"
fi
