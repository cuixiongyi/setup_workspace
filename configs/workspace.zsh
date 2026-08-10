# setup_workspace zsh configuration.

[[ -r "$HOME/.config/setup_workspace/shell-common.sh" ]] && \
  source "$HOME/.config/setup_workspace/shell-common.sh"

unset LESS

# Preserve the existing dot-glob behavior from the old setup.
setopt GLOBDOTS

# Large history suitable for a shared home directory. Do not use SHARE_HISTORY:
# multiple hosts can append safely using file locking without trying to merge
# every command live across shells.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=1200000
SAVEHIST=1000000
unsetopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_FCNTL_LOCK
setopt HIST_SAVE_BY_COPY
setopt HIST_IGNORE_ALL_DUPS

# Oh My Zsh. This file owns the OMZ setup so the installer does not need to
# mutate arbitrary lines in .zshrc.
export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_THEME="${ZSH_THEME:-robbyrussell}"
plugins=(git)
(( $+commands[fzf] )) && plugins+=(fzf)
(( $+commands[aws] )) && plugins+=(aws)
zstyle ':omz:update' mode disabled

