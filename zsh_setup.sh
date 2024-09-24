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
# Add support for SSH forwarding in tmux
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

# Install miniconda
if [[ "$OSTYPE" == "darwin"* ]]; then
    architecture=$(uname -m)
    if [[ "$architecture" == "arm64" ]]; then
        # Code to run on macOS M1
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh -O ~/miniconda.sh
    elif [[ "$architecture" == "x86_64" ]]; then
        # Code to run on macOS Intel
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -O ~/miniconda.sh
    else
        echo "Unknown macOS architecture" >&2
        exit 1
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Code to run on Linux
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh
else
    echo "Unsupported operating system" >&2
    exit 1
fi
zsh ~/miniconda.sh -b -p $HOME/miniconda
conda install -n base conda-libmamba-solver
conda config --set solver libmamba

"zsh" <(curl -L micro.mamba.pm/install.sh)  < /dev/null
~/.local/bin/micromamba shell init --shell zsh --root-prefix=~/micromamba

# put setup script into .zsh
python3 zshrc_setup.py


# Bash setup:
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
bash ~/.fzf/install --all
