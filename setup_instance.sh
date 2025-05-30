# This file is setup for non-GUI workspace, like EC2. 
# Also should be called when setting up GUI workspace.

sudo apt-get install -y zsh git vim htop parallel nmon tmux bmon terminator
# Used for kill program when out of memory to avoid system hanging
sudo apt-get install -y earlyoom

# Build nvtop
# sudo apt install -y cmake libncurses5-dev libncursesw5-dev git
# git clone https://github.com/Syllo/nvtop.git
# mkdir -p nvtop/build && cd nvtop/build
# cmake ..
# make -j
# sudo make install


# add git log prettifier
git config --global alias.lg "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative"
git config --global alias.branchsort "for-each-ref --sort=committerdate refs/heads/ --format='%(HEAD) %(color:yellow)%(align:48)%(refname:short)%(end)%(color:reset) %(objectname:short) - %(align:16)%(authorname)%(end) (%(color:green)%(committerdate:relative)%(color:reset)) - %(contents:subject)'"


# Install tmux config (my branch)
git clone -b cxy_config https://github.com/cuixiongyi/.tmux.git /tmp/.tmux
cp /tmp/.tmux/.tmux.conf ~/.tmux.conf
cp /tmp/.tmux/.tmux.conf.local ~/.tmux.conf.local
# Add support for SSH forwarding in tmux
# https://superuser.com/questions/237822/how-can-i-get-ssh-agent-working-over-ssh-and-in-tmux-on-os-x
echo " #\!/bin/bash
if [ -S "\$SSH_AUTH_SOCK" ]; then
    ln -sf \$SSH_AUTH_SOCK ~/.ssh/ssh_auth_sock
fi" | tee ~/.ssh/rc


# install oh-my-zsh
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"


# Install fzf
git clone --depth 1 https://github.com/unixorn/fzf-zsh-plugin.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-zsh-plugin
sed -i 's/plugins=(git)/plugins=(git fzf-zsh-plugin)/g' ~/.zshrc

wget micro.mamba.pm/install.sh
zsh install.sh

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

# workspace setup script end----------
" | tee -a ~/.zshrc



# Bash setup:

git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
# put setup script into .bashrc
echo "# workspace setup script start----------
        # record command history, avoid duplicates
        export HISTCONTROL=ignoredups:erasedups  
        # When the shell exits, append to the history file instead of overwriting it
        shopt -s histappend
        HISTSIZE=999999
        SAVEHIST=999999

        # My HSTR config.
        # HSTR configuration - add this to ~/.bashrc
                alias hh=hstr                    # hh to be alias for hstr
                export HSTR_CONFIG=hicolor,prompt-bottom,keywords-matching  # get more colors, show prompt at bottom, reg based matching
                shopt -s histappend              # append new history items to .bash_history
        	# # export HISTCONTROL=ignorespace   # leading space hides commands from history
         #        export HISTFILESIZE=\${HISTSIZE}        # increase history file size (default is 500)
         #        export HISTSIZE=\${HISTFILESIZE}  # increase history size (default is 500)
         #        # ensure synchronization between Bash memory and history file
         #        export PROMPT_COMMAND=\"history -a; history -n; ${PROMPT_COMMAND}\"
         #        # if this is interactive shell, then bind hstr to Ctrl-r (for Vi mode check doc)
         #        if [[ \$- =~ .*i.* ]]; then bind '\"\C-r\": \"\C-a hstr -- \C-j\"'; fi
         #        # if this is interactive shell, then bind 'kill last command' to Ctrl-x k
         #        if [[ \$- =~ .*i.* ]]; then bind '\"\C-xk\": \"\C-a hstr -k \C-j\"'; fi
         #        #export HSTR_CONFIG=blacklist
        
        # Set the default python debugger to be pudb
        export PYTHONBREAKPOINT="pudb.set_trace"
# workspace setup script end----------
" | tee -a ~/.bashrc

# Install HSTR.
sudo add-apt-repository -y ppa:ultradvorka/ppa && sudo apt-get update && sudo apt-get install hstr && . ~/.bashrc

sudo wget https://raw.githubusercontent.com/cuixiongyi/copy-files-in-parallel/refs/heads/master/copy-files-in-parallel -O /usr/local/bin/copy-files-in-parallel
sudo chmod +x /usr/local/bin/copy-files-in-parallel
sudo wget -O /usr/local/bin/goofys  https://github.com/kahing/goofys/releases/latest/download/goofys 
sudo chmod +x /usr/local/bin/goofys
