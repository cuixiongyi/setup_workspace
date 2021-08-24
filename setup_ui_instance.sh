# This file set up GUI workspace, with GUI tools.
# Should also call ./setup_instance.sh

#sublime text
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo apt-key add -
echo "deb https://download.sublimetext.com/ apt/dev/" | sudo tee /etc/apt/sources.list.d/sublime-text.list

sudo apt-get update

sudo apt-get install -y git vim htop gitk sublime-text gnome-tweak-tool
# Used for kill program when out of memory to avoid system hanging

mkdir -p ~/workspace
cd ~/workspace

# Terminator's theme
git clone https://github.com/cuixiongyi/setup_workspace /tmp/setup_workspace
cp /tmp/setup_workspace/configs/gtk.css ~/.config/gtk-3.0/gtk.css
