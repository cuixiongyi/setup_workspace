#!/bin/bash

# add git log prettifier
git config --global alias.lg "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative"
git config --global alias.branchsort "for-each-ref --sort=committerdate refs/heads/ --format='%(HEAD) %(color:yellow)%(align:48)%(refname:short)%(end)%(color:reset) %(objectname:short) - %(align:16)%(authorname)%(end) (%(color:green)%(committerdate:relative)%(color:reset)) - %(contents:subject)'"
git config --global rerere.enabled true
git config --add oh-my-zsh.hide-info 1


# Install tmux config
git clone -b cxy_config https://github.com/cuixiongyi/.tmux.git /tmp/.tmux
cp /tmp/.tmux/.tmux.conf ~/.tmux.conf
cp /tmp/.tmux/.tmux.conf.local ~/.tmux.conf.local
# Add support for SSH forwarding in tmux
# https://superuser.com/questions/237822/how-can-i-get-ssh-agent-working-over-ssh-and-in-tmux-on-os-x
echo " #\!/bin/bash
if [ -S "\$SSH_AUTH_SOCK" ]; then
    ln -sf \$SSH_AUTH_SOCK ~/.ssh/ssh_auth_sock
fi" | tee ~/.ssh/rc

# Avoid zsh prompts
touch ~/.zshrc
# install oh-my-zsh
#zsh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended


# Install oh-my-zsh plugin
# fzf: command history search
# aws: aws command auto-complete
# dirhistory: directory back/forward  https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/dirhistory
sed -i 's/plugins=(git)/plugins=(fzf aws)/g' ~/.zshrc
# Install fzf
#git clone --depth 1 https://github.com/unixorn/fzf-zsh-plugin.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-zsh-plugin


"zsh" <(curl -L micro.mamba.pm/install.sh)  < /dev/null
~/.local/bin/micromamba shell init --shell zsh --root-prefix=~/micromamba

# put setup script into .zsh
echo "# workspace setup script start----------
        # Print everything to console
        unset LESS
        # zsh history setting
        export HISTSIZE=1000000   # the number of items for the internal history list
        export SAVEHIST=1000000   # maximum number of items for the history file
        unsetopt share_history    # Don't read history after each execution
        setopt inc_append_history # Append history right before execution, but no read history.
        setopt HIST_IGNORE_ALL_DUPS  # Keep the last unique command history.
        function rsyncxy() {
            rsync -rahP \$@
        }
        # Set the default python debugger to be pudb
        export PYTHONBREAKPOINT="pudb.set_trace"

        slist() {
            squeue --user=${USER} -o "%.18i %.9P %.45j %.8u %.2t %.10M %.6D %.15R %.6C %.15b"
        }
        slistall() {
            squeue -o "%.18i %.9P %.45j %.8u %.2t %.10M %.6D %.15R %.6C %.15b"
        }
        slistnode() {
            scontrol show node
        }
        

# workspace setup script end----------
" | tee -a ~/.zshrc



# Bash setup:
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install --all
