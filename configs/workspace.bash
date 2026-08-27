# setup_workspace bash configuration. Sourced from .bashrc and, for login
# bash, from .profile / .bash_profile. shell-common.sh is idempotent.
[ -r "$HOME/.config/setup_workspace/shell-common.sh" ] && \
  . "$HOME/.config/setup_workspace/shell-common.sh"
