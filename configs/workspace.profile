# setup_workspace login-shell configuration.

# Recreate/validate the persistent host-local JetBrains directories on each
# login. The shared-home symlinks use this same absolute path on every host.
if [ -x "$HOME/.local/bin/workspace-jetbrains-local" ]; then
  "$HOME/.local/bin/workspace-jetbrains-local" ensure >/dev/null 2>&1 || {
    printf '%s\n' "setup_workspace: JetBrains local directory setup failed; run workspace-jetbrains-local status" >&2
  }
fi

