# setup_workspace
```
# Install cli
sudo apt-get update
sudo apt-get install -y zsh git vim htop parallel nmon tmux bmon terminator curl
# Used for kill program when out of memory to avoid system hanging
sudo apt-get install -y earlyoom


Dev machine setup
wget https://raw.githubusercontent.com/cuixiongyi/setup_workspace/master/zsh_setup.sh -O zsh_setup.sh
wget https://raw.githubusercontent.com/cuixiongyi/setup_workspace/master/zshrc_setup.py -O zshrc_setup.py
chmod u+x zsh_setup.sh
./zsh_setup.sh


# Set zsh as default shell
chsh -s $(which zsh)

# Fix JetBrains remote dev issue when ~/ is mounted on NFS
wget https://raw.githubusercontent.com/cuixiongyi/setup_workspace/refs/heads/master/fix_jetbrains_remote.sh -O fix_jetbrains_remote.sh
sudo bash fix_jetbrains_remote.sh
```
