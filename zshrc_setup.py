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
    
    # SSH agent forwarding with a stable per-machine socket.
    # HOME is shared across machines, so include the hostname in the path.
    _ssh_agent_dir="$HOME/.tmp/ssh-agent"
    _ssh_agent_host="$(hostname -f 2>/dev/null || hostname)"
    _ssh_agent_stable="${_ssh_agent_dir}/${_ssh_agent_host}.sock"
    
    umask 077
    mkdir -p "$_ssh_agent_dir"
    chmod 700 "$_ssh_agent_dir" 2>/dev/null || true
    
    # When this is a fresh SSH login, SSH_AUTH_SOCK points directly to the
    # forwarded /tmp socket. Refresh the stable per-machine symlink.
    if [[ -n "${SSH_AUTH_SOCK:-}" &&
          "$SSH_AUTH_SOCK" != "$_ssh_agent_stable" &&
          -S "$SSH_AUTH_SOCK" ]]; then
        ln -sfn "$SSH_AUTH_SOCK" "$_ssh_agent_stable"
    fi
    
    # All interactive shells, including shells in tmux panes, use the stable path.
    if [[ -S "$_ssh_agent_stable" ]]; then
        export SSH_AUTH_SOCK="$_ssh_agent_stable"
    fi
    unset _ssh_agent_dir _ssh_agent_host _ssh_agent_stable
    
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
