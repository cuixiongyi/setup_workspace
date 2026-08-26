# setup_workspace zsh configuration.

[[ -r "$HOME/.config/setup_workspace/shell-common.sh" ]] && \
  source "$HOME/.config/setup_workspace/shell-common.sh"

# Detect an agent started in this shell as soon as the prompt returns. Since
# every pane uses the same stable socket, no other pane needs to restart zsh.
# `workspace-agent` is defined in shell-common.sh for both bash and zsh.
if (( $+functions[_workspace_sync_ssh_agent] )); then
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _workspace_sync_ssh_agent
fi

unset LESS

# Preserve the existing dot-glob behavior from the old setup.
setopt GLOBDOTS

# Large history suitable for a shared home directory. Do not use SHARE_HISTORY:
# multiple hosts append without trying to merge every command live across
# shells. HIST_FCNTL_LOCK is deliberately NOT set: it takes a real network
# lock (NLM) on the NFS-mounted $HISTFILE on every start/exit/write, and when
# the lock manager hiccups that lock call hangs the shell (Ctrl-C often
# needed twice to break it). This trades away NFS append-safety across hosts
# (rare risk of a garbled/interleaved history line on truly simultaneous
# multi-host writes) for shells that reliably start/exit.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=500000
SAVEHIST=500000
unsetopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_SAVE_BY_COPY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_EXPIRE_DUPS_FIRST
# Ignore/Don't append any command with a leading space
setopt HIST_IGNORE_SPACE

# Keep routine/noise commands out of history entirely, so the periodic
# trim-rewrite (HIST_SAVE_BY_COPY, copies the whole file across NFS) has
# less to copy and Ctrl-R stays useful. Adjust the list to taste. Prefix
# any one-off command with a leading space to skip it ad hoc
# (HIST_IGNORE_SPACE, set above).
HISTORY_IGNORE="(ls|ll|la|l|cd -|pwd|clear|exit|history|bg|fg|jobs)"

# Oh My Zsh. This file owns the OMZ setup so the installer does not need to
# mutate arbitrary lines in .zshrc.
export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_THEME="${ZSH_THEME:-robbyrussell}"
plugins=(git)
(( $+commands[fzf] )) && plugins+=(fzf)
(( $+commands[aws] )) && plugins+=(aws)
zstyle ':omz:update' mode disabled
