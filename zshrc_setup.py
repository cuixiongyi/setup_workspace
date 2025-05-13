# Python script to append setup script to .zshrc
import os

# Define the Zsh script content
zsh_script_content = """
# workspace setup script start----------
    # https://github.com/cuixiongyi/setup_workspace/edit/master/zshrc_setup.py
    # Print everything to console
    unset LESS
    setopt globdots           # Show all hidden files
    # zsh history setting
    export HISTSIZE=1000000   # the number of items for the internal history list
    export SAVEHIST=1000000   # maximum number of items for the history file
    unsetopt share_history    # Don't read history after each execution
    setopt inc_append_history # Append history right before execution, but no read history.
    setopt HIST_IGNORE_ALL_DUPS  # Keep the last unique command history.
    DISABLE_AUTO_UPDATE=true  # Disable ZSH update 
    function rsyncxy() {
        rsync -rahP $@
    }
    # Set the default python debugger to be pudb
    export PYTHONBREAKPOINT="pudb.set_trace"
    # Slurm related commands
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
#
#
"""

# Define the path to the .zshrc file
zshrc_path = os.path.expanduser("~/.zshrc")

# Open .zshrc file in append mode and write the content
with open(zshrc_path, "a") as zshrc_file:
    zshrc_file.write(zsh_script_content)

print("Zsh setup script has been successfully appended to ~/.zshrc.")
