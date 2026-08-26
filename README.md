# setup_workspace

Idempotent Ubuntu developer-workstation and shared-home cluster bootstrap for
Ubuntu 22.04 and 24.04.

The installer separates machine-local administration from shared-home user
configuration. This matters when every machine mounts the same home directory
from NFS, CIFS, or another NAS.

## Quick start

### Standalone workstation

```bash
./scripts/check.sh
./install.sh
```

To make zsh the login shell (optional; bash is supported as-is):

```bash
./install.sh --set-default-shell
```

### Shared-home cluster

Run the machine-local phase on every node image or host that needs the tools:

```bash
./install.sh --cluster --system-only
```

Run the shared-home phase once, not concurrently on every node:

```bash
./install.sh --cluster --user-only
```

The cluster profile defaults to:

- no GUI packages;
- no change to the host's OOM policy;
- the same shared shell/tmux configuration on every node.

If `HOME` is on a network filesystem, JetBrains state automatically uses
`/var/tmp/setup-workspace-$UID` on the local host.

## Installation phases

`--system-only` changes machine-local state:

- apt packages;
- AWS CLI under `/usr/local`; and
- an OOM service only when the selected policy explicitly permits it.

`--user-only` changes shared-home state:

- Git aliases;
- the platform-specific Miniconda prefix;
- SSH-agent and tmux helpers;
- shell/tmux configuration;
- JetBrains directory links; and
- `copy-files-in-parallel`.

The user phase takes an atomic directory lock at:

```text
~/.local/state/setup_workspace/install.lock
```

Directory creation is atomic on normal NFS deployments, preventing two hosts
from mutating the same checkout, Conda prefix, or dotfiles concurrently. A lock
left by a dead process on the same host is removed automatically. A lock from
another host is never stolen; inspect the `owner` file and remove only that
lock directory before retrying.

## SSH agents and tmux

A Unix-domain socket cannot be shared through NAS. Cluster nodes and a
single workstation therefore use the same host-local stable path:

```text
/tmp/setup-workspace-ssh-agent-$UID/agent.sock
```

`/tmp` is per machine, so the pathname can be identical on every cluster node
without putting a socket on NFS. Long-lived processes keep `SSH_AUTH_SOCK`
pointed at that symlink; only the symlink target is retargeted when a new
forwarded agent arrives.

Three independent paths refresh it, so the agent works with or without tmux:

1. `~/.ssh/rc` — sshd runs this on every SSH session, including IDEs,
   `ssh host command`, and `ssh -t host tmux attach`. This is the path that
   covers non-interactive clients. The file writes nothing to stdout. It
   also recreates host-local JetBrains directories when that helper is
   installed (console logins still do this from `.profile` / `.zprofile`).
2. Interactive bash/zsh — `shell-common.sh` publishes a newly inherited
   socket and exports the stable path. Prompt hooks (`PROMPT_COMMAND` /
   `precmd`) also pick up `eval "$(ssh-agent -s)"`.
3. tmux `client-attached` — `update-environment` imports the client's
   socket, then the hook publishes it and points every session at the stable
   path. Existing panes already using that path do not need `exec zsh`.

If an older install left `~/.tmp/ssh-agent/<hostname>.sock`, refresh also
retargets that per-host alias (shared home, host-local `/tmp` target) so
already-running tools keep working until they restart onto the `/tmp` path.
The directory is never created for new installs.

Start a local agent with either standard shell form:

```zsh
workspace-agent
# optionally name one or more keys:
workspace-agent ~/.ssh/id_ed25519

# The equivalent standard commands are:
eval "$(ssh-agent -s)"
ssh-add
```

`workspace-agent` is available in bash and zsh. It reuses the current
reachable agent or starts one when needed, runs `ssh-add`, publishes the
stable socket (including to tmux on this host), and updates the current
shell. A bare `ssh-agent` command is not sufficient because it only prints
environment assignments; no program can change the environment of its
already-running parent shell.

This covers:

- a local workstation, with or without tmux;
- a shared-home cluster node, with or without tmux;
- direct SSH agent forwarding;
- reconnecting to old tmux sessions;
- multiple tmux sessions on one host;
- `ssh -t host tmux attach`, where no interactive shell runs first; and
- long-lived IDE/agent processes that inherit `SSH_AUTH_SOCK`.

If distinct client agents attach to the same host, the most recently refreshed
agent wins for that user on that host. Forwarding lasts only while the carrying
SSH connection is alive.

Agent forwarding does not automatically cross Slurm, Kubernetes, or another
scheduler boundary. A batch job needs a separately designed credential flow;
do not copy socket paths through the shared home.

Use forwarding only to trusted machines. A process that can access the forwarded
socket can request signatures while the connection is active.

Diagnostics:

```bash
workspace-ssh-agent status
printf '%s\n' "$SSH_AUTH_SOCK"
ssh-add -l
```

The user-phase installer publishes the current forwarded agent only when
`SSH_AUTH_SOCK` is a live socket. It does not create or retarget the host
stable path when no agent is present; `~/.ssh/rc` and interactive shells do
that later. Tests and other isolated runs can point the helper at a private
directory with `WORKSPACE_SSH_AGENT_DIR`.

During migration, exact legacy `~/.ssh/rc` files previously generated by this
repository are moved to a unique `.pre-setup-workspace...` backup and replaced
with the managed hook. Arbitrary user SSH hooks are left untouched; those
sessions will not refresh the agent until the rc calls
`workspace-ssh-agent publish`.

## JetBrains Remote Development

Network-mounted home directories are detected automatically. Use
`WORKSPACE_LOCAL_ROOT` to override the default local directory, or
`--jetbrains-local`/`--no-jetbrains-local` to override detection.

Shared-home symlinks under `~/.cache/JetBrains` and similar stay in NFS;
only the target directories are host-local. After a reboot those targets
under `/var/tmp` are gone until they are recreated. `~/.ssh/rc` does that
on every SSH session (Gateway, Cursor remote, `ssh host command`). Login
shells also run the same `ensure` from `workspace.profile` so a console
login without SSH still recovers. Both calls are idempotent and silent
when the helper is not installed.

Diagnostics:

```bash
workspace-jetbrains-local status
readlink ~/.cache/JetBrains
readlink ~/.config/JetBrains
readlink ~/.local/share/JetBrains
```

`--no-jetbrains-local` prevents new localization; it does not automatically
undo existing symlinks or delete local IDE data.

## Miniconda on a shared home

The default prefix includes the Ubuntu release and CPU architecture:

```text
~/.local/opt/miniconda-ubuntu-24.04-x86_64
```

This prevents cross-architecture or cross-release binary reuse. An explicit
`WORKSPACE_CONDA_DIR` is recorded so later shells activate the prefix that was
actually installed.

Machines with materially different driver/toolchain requirements should use
different explicit prefixes. Treat a shared Conda prefix as single-writer:
perform package installation or environment mutation from one host at a time.
The setup lock protects bootstrap itself, not later manual `conda` commands.

## Installer options

```text
--cluster              shared-home cluster defaults
--workstation          standalone workstation defaults
--system-only          machine-local phase only
--user-only            shared-home phase only
--gui                  install Terminator
--no-gui               skip Terminator
--jetbrains-local      localize JetBrains directories
--no-jetbrains-local   leave JetBrains directories under HOME
--no-aws               skip AWS CLI v2
--no-conda             skip Miniconda
--oom-policy POLICY    auto, earlyoom, systemd-oomd, or none
--set-default-shell    change the login shell to zsh
--tmux-ref REF         upstream tmux-config branch, tag, commit, or latest
--print-config         print resolved settings without installing
```

Environment overrides:

```text
WORKSPACE_PROFILE
WORKSPACE_INSTALL_SCOPE
WORKSPACE_LOCAL_ROOT
WORKSPACE_TMUX_REPO
WORKSPACE_TMUX_REF
WORKSPACE_TMUX_DIR
WORKSPACE_COPY_FILES_REV
WORKSPACE_AWS_VERSION
WORKSPACE_OMZ_REPO
WORKSPACE_OMZ_REF
WORKSPACE_CONDA_DIR
WORKSPACE_INSTALL_GUI
WORKSPACE_INSTALL_AWS
WORKSPACE_INSTALL_CONDA
WORKSPACE_INSTALL_JETBRAINS_LOCAL
WORKSPACE_OOM_POLICY
WORKSPACE_SET_DEFAULT_SHELL
```

The maintained installer follows the latest upstream version by default:

```text
AWS CLI       latest v2 release
Miniconda     latest Linux installer
tmux config   latest commit on the upstream default branch
Oh My Zsh     latest commit on the upstream default branch
copy-files    latest commit on the upstream default branch
```

Re-running the installer updates existing installations. AWS archives are
verified with the AWS CLI signing key; Miniconda is verified against the
SHA-256 published in Anaconda's current archive index. Set an explicit AWS
version or Git ref through the environment overrides when a reproducible,
temporarily pinned setup is needed.

## OOM policy

The workstation `auto` policy retains active/enabled `systemd-oomd`, or
installs `earlyoom` otherwise. The cluster profile uses `none`; memory policy
belongs to the node image, scheduler, and cluster administrator.

Explicit choices:

```bash
./install.sh --oom-policy earlyoom
./install.sh --oom-policy systemd-oomd
./install.sh --oom-policy none
```

`none` makes no service change; it does not disable a service already managed
by the host.

## Shell and tmux configuration

Managed configuration lives below:

```text
~/.config/setup_workspace/
```

Small marked blocks source it from `.zshrc`, `.bashrc`, `.profile`, and
`.zprofile`. If `.bash_profile` already exists, the login block is added
there too, because bash then ignores `.profile`. The login block loads
JetBrains host-local dirs for every login shell, and loads `workspace.bash`
when the shell is bash, so login bash gets PATH, conda, and the SSH agent
without relying on `.profile` sourcing `.bashrc`. `shell-common.sh` skips a
second load, so Ubuntu's default `.profile` → `.bashrc` path does not stack
conda. Existing symlinked dotfiles are edited through their resolved
targets. Changed files receive unique backups, and replacement is atomic within
the same filesystem.

The upstream tmux-config checkout lives under:

```text
~/.local/share/setup_workspace/tmux
```

`~/.tmux.conf` points to its main configuration and
`~/.tmux.conf.local` points to this repository's managed local configuration.
Local changes in the managed checkout cause installation to stop instead of
being discarded.

## Migration

See [MIGRATION.md](MIGRATION.md). The obsolete top-level README bootstrap
scripts have been removed. Specialized ROS, Docker, build, and historical
utilities that are unrelated to the workstation bootstrap remain in the
repository but are not run by `install.sh`.

## Checks

Static checks:

```bash
./scripts/check.sh
```

Linux functional tests:

```bash
./scripts/test.sh
```

The functional suite uses temporary homes and local roots. It covers clean and
repeated installs, legacy SSH migration, unique backups, shared locks,
JetBrains symlinks, network-home detection, cluster profile defaults, SSH
agent refresh with and without tmux helpers, and preservation of custom
`~/.ssh/rc` files.
