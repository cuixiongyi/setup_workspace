# Install oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh --unattended)"

# Install zfz
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install


# put setup script into .bashrc
echo "# xiongyi workspace setup script start----------
    # Print everything to console
    unset LESS

    # zsh history setting
    export HISTSIZE=1000000   # the number of items for the internal history list
    export SAVEHIST=1000000   # maximum number of items for the history file
    unsetopt share_history    # Don't read history after each execution
    setopt inc_append_history # Append history right before execution, but no read history.
    setopt HIST_IGNORE_ALL_DUPS  # Keep the last unique command history.
# xiongyi workspace setup script end----------
" | tee -a ~/.zshrc
