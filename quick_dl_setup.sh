#sublime text
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo apt-key add -
echo "deb https://download.sublimetext.com/ apt/dev/" | sudo tee /etc/apt/sources.list.d/sublime-text.list

sudo apt-get update

sudo apt-get install -y git vim htop 
# Used for kill program when out of memory to avoid system hanging
sudo apt-get install -y earlyoom

# UI
sudo apt-get install -y gitk sublime-text gnome-tweak-tool

# add git log prettifier
git config --global alias.lg "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative"
git config --global alias.branchsort "for-each-ref --sort=committerdate refs/heads/ --format='%(HEAD) %(color:yellow)%(align:48)%(refname:short)%(end)%(color:reset) %(objectname:short) - %(align:16)%(authorname)%(end) (%(color:green)%(committerdate:relative)%(color:reset)) - %(contents:subject)'"

sudo apt-get install -y python3-pip python3-venv python3-yapf 
sudo pip3 install black

mkdir -p ~/workspace
cd ~/workspace
python3 -m venv dl_env 

# Switching to HSTR
# git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
# ~/.fzf/install --key-bindings --completion --update-rc

# Install tmux config (my branch)
git clone -b cxy_config https://github.com/cuixiongyi/.tmux.git /tmp/.tmux
cp /tmp/.tmux/.tmux.conf ~/.tmux.conf
cp /tmp/.tmux/.tmux.conf.local ~/.tmux.conf.local

git clone https://github.com/cuixiongyi/setup_workspace /tmp/setup_workspace
cp /tmp/setup_workspace/configs/gtk.css ~/.config/gtk-3.0/gtk.css

# put setup script into .bashrc
echo "# xiongyi workspace setup script start----------
        # record command history, avoid duplicates
        export HISTCONTROL=ignoredups:erasedups  
        # When the shell exits, append to the history file instead of overwriting it
        shopt -s histappend
        HISTSIZE=999999
        SAVEHIST=999999

        # After each command, append to the history file and reread it
        export PROMPT_COMMAND=\"\${PROMPT_COMMAND:+\$PROMPT_COMMAND$'\\n'}history -a; history -c; history -r\"
        function activate_dl_env 
        {
                source ~/workspace/dl_env/bin/activate
        }
        # My HSTR config.
        # HSTR configuration - add this to ~/.bashrc
                alias hh=hstr                    # hh to be alias for hstr
                export HSTR_CONFIG=hicolor,prompt-bottom,keywords-matching  # get more colors, show prompt at bottom, reg based matching
                shopt -s histappend              # append new history items to .bash_history
        	# export HISTCONTROL=ignorespace   # leading space hides commands from history
                export HISTFILESIZE=\${HISTSIZE}        # increase history file size (default is 500)
                export HISTSIZE=\${HISTFILESIZE}  # increase history size (default is 500)
                # ensure synchronization between Bash memory and history file
                export PROMPT_COMMAND=\"history -a; history -n; ${PROMPT_COMMAND}\"
                # if this is interactive shell, then bind hstr to Ctrl-r (for Vi mode check doc)
                if [[ $- =~ .*i.* ]]; then bind '\"\C-r\": \"\C-a hstr -- \C-j\"'; fi
                # if this is interactive shell, then bind 'kill last command' to Ctrl-x k
                if [[ $- =~ .*i.* ]]; then bind '\"\C-xk\": \"\C-a hstr -k \C-j\"'; fi
                #export HSTR_CONFIG=blacklist
# xiongyi workspace setup script end----------
" | tee -a ~/.bashrc

# Install HSTR.
sudo add-apt-repository ppa:ultradvorka/ppa && sudo apt-get update && sudo apt-get install hstr && . ~/.bashrc

# install libraries in venv
source ~/workspace/dl_env/bin/activate
pip3 install torch torchvision numpy scipy matplotlib ipython jupyter pandas tensorboardX pyyaml pycocotools pyrealsense2 pytransform3d cython pycocotools
