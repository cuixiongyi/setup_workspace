# Migration from the README-driven bootstrap

The modular installer replaces the old top-level `zsh_setup.sh`,
`zshrc_setup.py`, `setup_instance.sh`, `setup_ui_instance.sh`,
`quick_dl_setup.sh`, `fix_jetbrains_remote.sh`, and `get_ros_env.sh`
workflow. The maintained ROS environment inspection helper is now
`scripts/get_ros_env.sh`.

## Recommended migration

On a standalone workstation:

```bash
./install.sh
```

For a shared-home cluster, run the phases separately:

```bash
# Every host or machine image:
./install.sh --cluster --system-only

# Once for the shared home:
WORKSPACE_LOCAL_ROOT="/local/$USER/setup-workspace" \
  ./install.sh --cluster --user-only
```

Do not launch the user phase concurrently from multiple nodes.

## Backups

The installer never recursively deletes a destination it did not create.
Unexpected files, directories, and symlinks are moved to a unique sibling such
as:

```text
.zshrc.pre-setup-workspace
.zshrc.pre-setup-workspace.20260810T201500Z.12345
```

Managed dotfile updates are rendered beside the destination and renamed into
place. If a dotfile is a symlink, its resolved target is updated rather than
replacing the symlink.

## SSH agent

Two exact variants of the old generated `~/.ssh/rc` are recognized, including
the blank lines emitted by the current legacy script. A recognized file is
moved aside. Arbitrary user `~/.ssh/rc` files are preserved with a warning.

Old setup-managed XDG/TMPDIR exports are removed before the SSH migration check,
so an old combined JetBrains/agent hook can also be recognized.

The replacement still uses a host-local stable socket under `/tmp`. A
recognized legacy `~/.ssh/rc` is replaced with a managed hook that refreshes
that socket (no NFS Unix socket), recreates host-local JetBrains directories
when that helper is installed, and restores xauth. Arbitrary user `~/.ssh/rc`
files stay untouched. Tmux attach remains a second refresh path, not the only
one. Re-running the installer replaces a previously managed rc in place when
the content changed, and is a no-op when it is already current.

## JetBrains

The old workaround globally set XDG variables and `TMPDIR`, sometimes through
all of `.pam_environment`, `.profile`, and `.ssh/rc`. The migration:

- removes only the old marked profile blocks;
- removes only setup-generated JetBrains XDG/TMPDIR lines;
- leaves arbitrary environment and SSH hook content untouched;
- redirects only JetBrains directories; and
- rejects volatile `/tmp` and network-backed local roots.

Review any old `.pre-setup-workspace...` backup after confirming Gateway works.
Nothing is deleted automatically.

## Zsh and Bash

All legacy blocks delimited by:

```text
# workspace setup script start----------
# workspace setup script end----------
```

are removed from `.zshrc`. New source blocks point to files below
`~/.config/setup_workspace`.

The installer does not run `conda init`. It records the selected prefix and
sources that installation's `conda.sh` from the managed common shell file.

## tmux

User-owned behavior is in `configs/tmux.conf.local`. The managed upstream tmux
checkout is pinned by default. If the checkout contains local modifications,
installation stops rather than using `git reset --hard`.
