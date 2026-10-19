#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2030,SC2031
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "setup_workspace functional tests require Linux; skipping"
  exit 0
fi

test_root="$(mktemp -d)"
local_root="/var/tmp/setup-workspace-test-$$"
ssh_agent_test_pids=()
# Isolate tmux from the caller's server so helper tests cannot rewrite it.
export TMUX_TMPDIR="$test_root/tmux-none"
mkdir -p -- "$TMUX_TMPDIR"
cleanup() {
  if ((${#ssh_agent_test_pids[@]})); then
    kill "${ssh_agent_test_pids[@]}" 2>/dev/null || true
  fi
  rm -rf -- "$test_root" "$local_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

assert_output_contains() {
  local output="$1"
  local expected="$2"
  [[ "$output" == *"$expected"* ]] || fail "output does not contain: $expected"
}

test_profile_defaults() {
  local output
  local expected_jetbrains_local

  # shellcheck source=../install/lib.sh
  source "$ROOT_DIR/install/lib.sh"
  expected_jetbrains_local="$(
    workspace_jetbrains_local_default "$(workspace_home_filesystem_type)"
  )"

  output="$("$ROOT_DIR/install.sh" --cluster --print-config)"
  assert_output_contains "$output" "profile=cluster"
  assert_output_contains "$output" "gui=0"
  assert_output_contains "$output" "oom_policy=none"
  assert_output_contains "$output" "jetbrains_local=$expected_jetbrains_local"
  assert_output_contains "$output" "aws_version=latest"
  assert_output_contains "$output" "tmux_ref=latest"
  assert_output_contains "$output" "omz_ref=latest"
  assert_output_contains "$output" "copy_files_rev=latest"

  output="$(WORKSPACE_INSTALL_JETBRAINS_LOCAL=1 \
    "$ROOT_DIR/install.sh" --cluster --print-config)"
  assert_output_contains "$output" "jetbrains_local=1"
}

test_network_filesystem_detection() {
  # shellcheck source=../install/lib.sh
  source "$ROOT_DIR/install/lib.sh"

  local fs_type
  for fs_type in nfs nfs4 cifs smb2 ceph glusterfs gpfs lustre fuse.sshfs; do
    workspace_filesystem_is_networked "$fs_type" ||
      fail "$fs_type was not detected as a network filesystem"
    [[ "$(workspace_jetbrains_local_default "$fs_type")" == "1" ]] ||
      fail "$fs_type did not enable JetBrains localization"
  done

  if workspace_filesystem_is_networked ext2/ext3; then
    fail "local filesystem was detected as networked"
  fi
  [[ "$(workspace_jetbrains_local_default ext2/ext3)" == "0" ]] ||
    fail "local filesystem enabled JetBrains localization"
}

test_managed_files_and_backups() {
  local home="$test_root/managed-home"
  local body="$test_root/body"
  local target="$home/dotfiles/zshrc"
  local before_backups
  local after_backups
  local first_checksum
  local second_checksum

  mkdir -p -- "$home/dotfiles"
  printf 'user setting\n' > "$target"
  ln -s -- "dotfiles/zshrc" "$home/.zshrc"
  printf 'managed setting\n' > "$body"

  (
    export HOME="$home"
    # shellcheck source=../install/lib.sh
    source "$ROOT_DIR/install/lib.sh"
    workspace_replace_managed_block \
      "$HOME/.zshrc" '# start' '# end' "$body"
  )

  [[ -L "$home/.zshrc" ]] || fail "managed edit replaced a dotfile symlink"
  assert_file_contains "$target" "user setting"
  assert_file_contains "$target" "managed setting"
  before_backups="$(find "$home/dotfiles" -maxdepth 1 -name 'zshrc.pre-setup-workspace*' | wc -l)"
  first_checksum="$(sha256sum "$target")"

  (
    export HOME="$home"
    source "$ROOT_DIR/install/lib.sh"
    workspace_replace_managed_block \
      "$HOME/.zshrc" '# start' '# end' "$body"
  )

  after_backups="$(find "$home/dotfiles" -maxdepth 1 -name 'zshrc.pre-setup-workspace*' | wc -l)"
  second_checksum="$(sha256sum "$target")"
  [[ "$first_checksum" == "$second_checksum" ]] || fail "managed edit is not idempotent"
  [[ "$before_backups" == "$after_backups" ]] || fail "unchanged rerun created another backup"

  printf '# end\nuser content\n# start\n' > "$home/unbalanced"
  first_checksum="$(sha256sum "$home/unbalanced")"
  if (
    export HOME="$home"
    source "$ROOT_DIR/install/lib.sh"
    workspace_replace_managed_block \
      "$HOME/unbalanced" '# start' '# end' "$body"
  ) >/dev/null 2>&1; then
    fail "unbalanced managed markers were accepted"
  fi
  second_checksum="$(sha256sum "$home/unbalanced")"
  [[ "$first_checksum" == "$second_checksum" ]] ||
    fail "unbalanced managed file was modified"

  printf 'first user file\n' > "$home/link-target"
  (
    export HOME="$home"
    source "$ROOT_DIR/install/lib.sh"
    workspace_safe_symlink /managed/target "$HOME/link-target"
  )
  rm -f -- "$home/link-target"
  printf 'second user file\n' > "$home/link-target"
  (
    export HOME="$home"
    source "$ROOT_DIR/install/lib.sh"
    workspace_safe_symlink /managed/target "$HOME/link-target"
  )
  [[ "$(find "$home" -maxdepth 1 -name 'link-target.pre-setup-workspace*' | wc -l)" -eq 2 ]] ||
    fail "later user content did not receive a unique backup"
}

test_shared_lock() {
  local home="$test_root/lock-home"
  mkdir -p -- "$home"

  (
    export HOME="$home"
    source "$ROOT_DIR/install/lib.sh"
    workspace_acquire_shared_lock
    if HOME="$home" ROOT_DIR="$ROOT_DIR" bash -c '
      source "$ROOT_DIR/install/lib.sh"
      workspace_acquire_shared_lock
    ' >/dev/null 2>&1; then
      fail "second shared-home lock acquisition succeeded"
    fi
    workspace_release_shared_lock
  )

  [[ ! -e "$home/.local/state/setup_workspace/install.lock" ]] ||
    fail "shared-home lock was not released"

  local lock_dir="$home/.local/state/setup_workspace/install.lock"
  local dead_pid
  mkdir -p -- "$lock_dir"
  true &
  dead_pid=$!
  wait "$dead_pid" || true
  {
    printf 'host=%s\n' "$(hostname -f 2>/dev/null || hostname)"
    printf 'pid=%s\n' "$dead_pid"
    printf 'started=%s\n' "1970-01-01T00:00:00Z"
  } > "$lock_dir/owner"
  (
    export HOME="$home"
    source "$ROOT_DIR/install/lib.sh"
    workspace_acquire_shared_lock
    workspace_release_shared_lock
  ) || fail "stale same-host lock was not replaced"
  [[ ! -e "$lock_dir" ]] || fail "stale lock remained after acquire/release"

  mkdir -p -- "$lock_dir"
  {
    printf 'host=%s\n' "other-host.example"
    printf 'pid=%s\n' "$dead_pid"
    printf 'started=%s\n' "1970-01-01T00:00:00Z"
  } > "$lock_dir/owner"
  if (
    export HOME="$home"
    source "$ROOT_DIR/install/lib.sh"
    workspace_acquire_shared_lock
  ) >/dev/null 2>&1; then
    fail "foreign-host lock was stolen"
  fi
  rm -rf -- "$lock_dir"
}

write_legacy_ssh_rc() {
  local file="$1"
  cat > "$file" <<'LEGACY_RC'
#!/bin/sh

agent_dir="$HOME/.tmp/ssh-agent"
agent_host="$(hostname -f 2>/dev/null || hostname)"
stable_socket="$agent_dir/$agent_host.sock"

umask 077
mkdir -p "$agent_dir"
chmod 700 "$agent_dir" 2>/dev/null || true

# SSH_AUTH_SOCK is provided by sshd when agent forwarding is enabled.
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    ln -sfn "$SSH_AUTH_SOCK" "$stable_socket"
fi
LEGACY_RC
}

test_ssh_and_jetbrains_migration() {
  local home="$test_root/migration-home"
  local backups_before
  local backups_after
  local rc_hash_before
  local rc_output
  mkdir -p -- "$home/.ssh" "$home/.config/JetBrains" "$home/.local/share/JetBrains"
  printf 'setting\n' > "$home/.config/JetBrains/settings.xml"
  printf 'plugin\n' > "$home/.local/share/JetBrains/plugin.txt"

  cat > "$home/.profile" <<'PROFILE'
user profile
# >>> jetbrains_remote_fix >>>
export XDG_CACHE_HOME="/tmp/jetbrains_test/cache"
export TMPDIR="/tmp/jetbrains_test/tmp"
# <<< jetbrains_remote_fix <<<
PROFILE
  cat > "$home/.pam_environment" <<'PAM'
LANG DEFAULT=en_US.UTF-8
XDG_CACHE_HOME DEFAULT=/tmp/jetbrains_test/cache
PAM
  write_legacy_ssh_rc "$home/.ssh/rc"
  printf 'export XDG_CACHE_HOME=/tmp/jetbrains_test/cache\n' >> "$home/.ssh/rc"

  HOME="$home" \
  WORKSPACE_ROOT="$ROOT_DIR" \
  WORKSPACE_INSTALL_JETBRAINS_LOCAL=1 \
  WORKSPACE_LOCAL_ROOT="$local_root" \
    "$ROOT_DIR/install/jetbrains.sh"

  HOME="$home" WORKSPACE_ROOT="$ROOT_DIR" \
  WORKSPACE_SSH_AGENT_DIR="$test_root/installer-agent" \
  SSH_AUTH_SOCK= \
    "$ROOT_DIR/install/ssh-agent.sh"

  [[ -f "$home/.ssh/rc" ]] || fail "managed SSH rc was not installed"
  assert_file_contains "$home/.ssh/rc" "setup_workspace SSH agent hook"
  assert_file_contains "$home/.ssh/rc" "workspace-jetbrains-local"
  if grep -Fq 'agent_dir="$HOME/.tmp/ssh-agent"' "$home/.ssh/rc"; then
    fail "legacy SSH rc content was not replaced"
  fi
  [[ -L "$home/.cache/JetBrains" ]] || fail "JetBrains cache is not a symlink"
  [[ -L "$home/.config/JetBrains" ]] || fail "JetBrains config is not a symlink"
  [[ -L "$home/.local/share/JetBrains" ]] || fail "JetBrains share is not a symlink"
  [[ -f "$local_root/jetbrains/config/settings.xml" ]] ||
    fail "JetBrains configuration was not seeded"
  [[ -f "$local_root/jetbrains/share/plugin.txt" ]] ||
    fail "JetBrains plugins were not seeded"
  assert_file_contains "$home/.profile" "user profile"
  if grep -q 'jetbrains_remote_fix\|XDG_CACHE_HOME DEFAULT=/tmp/jetbrains' \
      "$home/.profile" "$home/.pam_environment"; then
    fail "legacy JetBrains environment configuration remains"
  fi

  backups_before="$(find "$home" -name '*.pre-setup-workspace*' | wc -l)"
  rc_hash_before="$(sha256sum "$home/.ssh/rc")"
  HOME="$home" \
  WORKSPACE_ROOT="$ROOT_DIR" \
  WORKSPACE_INSTALL_JETBRAINS_LOCAL=1 \
  WORKSPACE_LOCAL_ROOT="$local_root" \
    "$ROOT_DIR/install/jetbrains.sh"
  HOME="$home" WORKSPACE_ROOT="$ROOT_DIR" \
  WORKSPACE_SSH_AGENT_DIR="$test_root/installer-agent" \
  SSH_AUTH_SOCK= \
    "$ROOT_DIR/install/ssh-agent.sh"
  backups_after="$(find "$home" -name '*.pre-setup-workspace*' | wc -l)"
  [[ "$backups_before" == "$backups_after" ]] ||
    fail "JetBrains or SSH-agent rerun created unexpected backups"
  [[ "$(sha256sum "$home/.ssh/rc")" == "$rc_hash_before" ]] ||
    fail "SSH rc install is not idempotent"
  cmp -s -- "$home/.ssh/rc" "$ROOT_DIR/configs/ssh.rc" ||
    fail "installed SSH rc does not match the managed template"

  rm -rf -- "$local_root/jetbrains"
  rc_output="$(
    HOME="$home" \
    WORKSPACE_SSH_AGENT_DIR="$test_root/migration-agent" \
    WORKSPACE_LOCAL_ROOT="$local_root" \
    DISPLAY= \
      sh "$home/.ssh/rc"
  )"
  [[ -z "$rc_output" ]] || fail "SSH rc wrote to stdout after JetBrains wipe: $rc_output"
  [[ -d "$local_root/jetbrains/cache" && -d "$local_root/jetbrains/config" && \
     -d "$local_root/jetbrains/share" ]] ||
    fail "SSH rc did not recreate host-local JetBrains directories"

  rc_output="$(
    HOME="$home" \
    WORKSPACE_SSH_AGENT_DIR="$test_root/migration-agent" \
    WORKSPACE_LOCAL_ROOT="$local_root" \
    DISPLAY= \
      sh "$home/.ssh/rc"
  )"
  [[ -z "$rc_output" ]] || fail "SSH rc wrote to stdout on JetBrains ensure rerun: $rc_output"

  if HOME="$home" WORKSPACE_LOCAL_ROOT=/tmp/unsupported \
      "$home/.local/bin/workspace-jetbrains-local" path >/dev/null 2>&1; then
    fail "volatile JetBrains root was accepted"
  fi
}

test_ssh_agent_socket_refresh() {
  local agent_dir="$test_root/ssh-agent-helper"
  local agent_home="$test_root/agent-home"
  local source_dir="$test_root/ssh-agent-sources"
  local legacy_socket="$source_dir/legacy.sock"
  local first_socket="$source_dir/first.sock"
  local second_socket="$source_dir/second.sock"
  local started_agent_dir="$test_root/started-ssh-agent"
  local test_key="$source_dir/test-key"
  local first_pid
  local second_pid
  local started_pid
  local stable_socket="$agent_dir/agent.sock"
  local host_sock
  local rc_output
  local jb_root

  command -v ssh-agent >/dev/null 2>&1 || return 0
  mkdir -p -- "$source_dir" "$agent_home"
  unset TMUX

  first_pid="$(ssh-agent -a "$first_socket" -s | sed -n 's/^SSH_AGENT_PID=\([0-9][0-9]*\);.*/\1/p')"
  second_pid="$(ssh-agent -a "$second_socket" -s | sed -n 's/^SSH_AGENT_PID=\([0-9][0-9]*\);.*/\1/p')"
  [[ -n "$first_pid" && -n "$second_pid" ]] || fail "could not start test SSH agents"
  ssh_agent_test_pids=("$first_pid" "$second_pid")

  HOME="$agent_home" WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    "$ROOT_DIR/bin/workspace-ssh-agent" refresh "$first_socket" >/dev/null
  [[ "$(readlink -f -- "$stable_socket")" == "$first_socket" ]] ||
    fail "stable SSH socket did not resolve to the first agent"

  # Do not create a shared-home alias until an old install already has one.
  host_sock="$agent_home/.tmp/ssh-agent/$(hostname -f 2>/dev/null || hostname).sock"
  [[ ! -e "$host_sock" ]] || fail "legacy SSH alias was created on a clean home"

  mkdir -p -- "$agent_home/.tmp/ssh-agent"
  HOME="$agent_home" WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    "$ROOT_DIR/bin/workspace-ssh-agent" refresh "$first_socket" >/dev/null
  [[ "$(readlink -- "$host_sock")" == "$stable_socket" ]] ||
    fail "existing per-host SSH alias was not retargeted to the stable socket"

  # The legacy setup used a second stable link in HOME. Refreshing from that
  # alias must remain a no-op instead of replacing stable_socket with a link
  # back to the alias and creating a cycle.
  ln -s -- "$stable_socket" "$legacy_socket"
  HOME="$agent_home" WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    "$ROOT_DIR/bin/workspace-ssh-agent" refresh "$legacy_socket" >/dev/null
  [[ "$(readlink -f -- "$stable_socket")" == "$first_socket" ]] ||
    fail "legacy SSH socket alias created a cycle"

  # Recover the precise broken A -> B -> A state seen during migration.
  ln -sfn -- "$legacy_socket" "$stable_socket"
  HOME="$agent_home" WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    "$ROOT_DIR/bin/workspace-ssh-agent" refresh "$second_socket" >/dev/null
  [[ "$(readlink -f -- "$stable_socket")" == "$second_socket" ]] ||
    fail "stable SSH socket did not recover from a symlink cycle"

  mkdir -p -- "$agent_home/.local/bin"
  install -m 0755 -- "$ROOT_DIR/bin/workspace-ssh-agent" \
    "$agent_home/.local/bin/workspace-ssh-agent"
  rc_output="$(
    HOME="$agent_home" \
    WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    SSH_AUTH_SOCK="$second_socket" \
    DISPLAY= \
      sh "$ROOT_DIR/configs/ssh.rc"
  )"
  [[ -z "$rc_output" ]] || fail "SSH rc wrote to stdout: $rc_output"
  [[ "$(readlink -f -- "$stable_socket")" == "$second_socket" ]] ||
    fail "SSH rc did not publish the forwarded agent"

  # Missing JetBrains helper must not break the rc. A present helper must
  # recreate dirs without consuming the xauth cookie sshd writes to stdin.
  install -m 0755 -- "$ROOT_DIR/bin/workspace-jetbrains-local" \
    "$agent_home/.local/bin/workspace-jetbrains-local"
  mkdir -p -- "$agent_home/bin"
  cat > "$agent_home/bin/xauth" <<'XAUTH'
#!/bin/sh
cat > "$HOME/xauth-input"
XAUTH
  chmod 0755 -- "$agent_home/bin/xauth"
  jb_root="$local_root/ssh-rc-jetbrains"
  rm -rf -- "$jb_root"
  rc_output="$(
    printf 'MIT-MAGIC-COOKIE-1 deadbeef\n' |
    HOME="$agent_home" \
    PATH="$agent_home/bin:$PATH" \
    WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    WORKSPACE_LOCAL_ROOT="$jb_root" \
    SSH_AUTH_SOCK="$second_socket" \
    DISPLAY=localhost:10.0 \
      sh "$ROOT_DIR/configs/ssh.rc"
  )"
  [[ -z "$rc_output" ]] || fail "SSH rc wrote to stdout with JetBrains ensure: $rc_output"
  [[ -d "$jb_root/jetbrains/cache" ]] || fail "SSH rc did not create JetBrains cache"
  assert_file_contains "$agent_home/xauth-input" "add unix:10.0 MIT-MAGIC-COOKIE-1 deadbeef"
  rc_output="$(
    HOME="$agent_home" \
    WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    WORKSPACE_LOCAL_ROOT="$jb_root" \
    SSH_AUTH_SOCK="$second_socket" \
    DISPLAY= \
      sh "$ROOT_DIR/configs/ssh.rc"
  )"
  [[ -z "$rc_output" ]] || fail "SSH rc wrote to stdout on JetBrains rerun: $rc_output"

  if command -v ssh-keygen >/dev/null 2>&1; then
    ssh-keygen -q -t ed25519 -N '' -f "$test_key"
    HOME="$agent_home" SSH_AUTH_SOCK='' WORKSPACE_SSH_AGENT_DIR="$started_agent_dir" \
      "$ROOT_DIR/bin/workspace-ssh-agent" start "$test_key" >/dev/null
    started_pid="$(cat -- "$started_agent_dir/managed-agent.pid")"
    [[ -n "$started_pid" ]] || fail "workspace SSH-agent command did not record its agent"
    ssh_agent_test_pids+=("$started_pid")
    SSH_AUTH_SOCK="$started_agent_dir/agent.sock" ssh-add -l >/dev/null ||
      fail "workspace SSH-agent command did not add the requested key"
  fi

  if command -v zsh >/dev/null 2>&1 && [[ -f "$test_key" ]]; then
    mkdir -p -- "$test_root/zsh-agent-home/.local/bin" \
      "$test_root/zsh-agent-home/.config/setup_workspace"
    install -m 0755 -- "$ROOT_DIR/bin/workspace-ssh-agent" \
      "$test_root/zsh-agent-home/.local/bin/workspace-ssh-agent"
    install -m 0644 -- "$ROOT_DIR/configs/shell-common.sh" \
      "$test_root/zsh-agent-home/.config/setup_workspace/shell-common.sh"
    install -m 0644 -- "$ROOT_DIR/configs/workspace.zsh" \
      "$test_root/zsh-agent-home/.config/setup_workspace/workspace.zsh"

    HOME="$test_root/zsh-agent-home" \
    WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    TEST_SOURCE_SOCKET="$second_socket" \
    TEST_PRIVATE_KEY="$test_key" \
      zsh -f -c '
        source "$HOME/.config/setup_workspace/workspace.zsh"
        SSH_AUTH_SOCK="$TEST_SOURCE_SOCKET"
        workspace-agent "$TEST_PRIVATE_KEY"
        [[ "$SSH_AUTH_SOCK" == "$WORKSPACE_SSH_AGENT_DIR/agent.sock" ]]
        (( ${precmd_functions[(Ie)_workspace_sync_ssh_agent]} ))
      ' >/dev/null || fail "zsh agent utility or prompt hook did not work"
  fi

  if [[ -f "$test_key" ]]; then
    mkdir -p -- "$test_root/bash-agent-home/.local/bin" \
      "$test_root/bash-agent-home/.config/setup_workspace"
    install -m 0755 -- "$ROOT_DIR/bin/workspace-ssh-agent" \
      "$test_root/bash-agent-home/.local/bin/workspace-ssh-agent"
    install -m 0644 -- "$ROOT_DIR/configs/shell-common.sh" \
      "$test_root/bash-agent-home/.config/setup_workspace/shell-common.sh"
    install -m 0644 -- "$ROOT_DIR/configs/workspace.bash" \
      "$test_root/bash-agent-home/.config/setup_workspace/workspace.bash"

    HOME="$test_root/bash-agent-home" \
    WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    TEST_SOURCE_SOCKET="$second_socket" \
    TEST_PRIVATE_KEY="$test_key" \
      bash --noprofile --norc -c '
        . "$HOME/.config/setup_workspace/workspace.bash"
        SSH_AUTH_SOCK="$TEST_SOURCE_SOCKET"
        workspace-agent "$TEST_PRIVATE_KEY"
        [[ "$SSH_AUTH_SOCK" == "$WORKSPACE_SSH_AGENT_DIR/agent.sock" ]]
        [[ "$PROMPT_COMMAND" == *_workspace_sync_ssh_agent* ]]
      ' >/dev/null || fail "bash agent utility or prompt hook did not work"
  fi

  kill "${ssh_agent_test_pids[@]}" 2>/dev/null || true
  ssh_agent_test_pids=()
}

test_ssh_agent_install_publish_guard() {
  local home="$test_root/ssh-agent-install-home"
  local isolated="$test_root/ssh-agent-install-isolated"
  local live_sock="/tmp/setup-workspace-ssh-agent-$(id -u)/agent.sock"
  local source_sock="$test_root/ssh-agent-install-source/agent.sock"
  local before
  local after
  local pid

  mkdir -p -- "$home" "$(dirname -- "$source_sock")"
  before="$(readlink -- "$live_sock" 2>/dev/null || true)"

  HOME="$home" WORKSPACE_ROOT="$ROOT_DIR" SSH_AUTH_SOCK= \
    "$ROOT_DIR/install/ssh-agent.sh" >/dev/null

  after="$(readlink -- "$live_sock" 2>/dev/null || true)"
  [[ "$before" == "$after" ]] ||
    fail "install without SSH_AUTH_SOCK changed the host agent socket"
  [[ -x "$home/.local/bin/workspace-ssh-agent" ]] ||
    fail "ssh-agent helper was not installed"

  command -v ssh-agent >/dev/null 2>&1 || return 0
  pid="$(ssh-agent -a "$source_sock" -s | sed -n 's/^SSH_AGENT_PID=\([0-9][0-9]*\);.*/\1/p')"
  [[ -n "$pid" ]] || fail "could not start installer isolation SSH agent"
  ssh_agent_test_pids+=("$pid")

  HOME="$home" \
  WORKSPACE_ROOT="$ROOT_DIR" \
  WORKSPACE_SSH_AGENT_DIR="$isolated" \
  SSH_AUTH_SOCK="$source_sock" \
    "$ROOT_DIR/install/ssh-agent.sh" >/dev/null

  after="$(readlink -- "$live_sock" 2>/dev/null || true)"
  [[ "$before" == "$after" ]] ||
    fail "install with WORKSPACE_SSH_AGENT_DIR changed the host agent socket"
  [[ "$(readlink -f -- "$isolated/agent.sock")" == "$source_sock" ]] ||
    fail "install did not publish into WORKSPACE_SSH_AGENT_DIR"

  kill "$pid" 2>/dev/null || true
  ssh_agent_test_pids=()
}

test_custom_ssh_rc_is_preserved() {
  local home="$test_root/custom-ssh-rc-home"
  mkdir -p -- "$home/.ssh"
  printf '#!/bin/sh\n# user hook\n' > "$home/.ssh/rc"

  HOME="$home" WORKSPACE_ROOT="$ROOT_DIR" \
  WORKSPACE_SSH_AGENT_DIR="$test_root/installer-agent" \
  SSH_AUTH_SOCK= \
    "$ROOT_DIR/install/ssh-agent.sh" >/dev/null

  assert_file_contains "$home/.ssh/rc" "user hook"
  if grep -Fq "setup_workspace SSH agent hook" "$home/.ssh/rc"; then
    fail "custom SSH rc was overwritten"
  fi
}

test_shell_idempotency() {
  local home="$test_root/shell-home"
  local first
  local second

  mkdir -p -- "$home/.oh-my-zsh"
  printf 'user zsh\n' > "$home/.zshrc"
  printf 'user bash\n' > "$home/.bashrc"
  printf 'user profile\n' > "$home/.profile"

  HOME="$home" WORKSPACE_ROOT="$ROOT_DIR" "$ROOT_DIR/install/zsh.sh"
  first="$(sha256sum "$home/.zshrc" "$home/.bashrc" "$home/.profile" "$home/.zprofile")"
  HOME="$home" WORKSPACE_ROOT="$ROOT_DIR" "$ROOT_DIR/install/zsh.sh"
  second="$(sha256sum "$home/.zshrc" "$home/.bashrc" "$home/.profile" "$home/.zprofile")"
  [[ "$first" == "$second" ]] || fail "shell setup is not idempotent"
  [[ ! -e "$home/.bash_profile" ]] || fail "shell setup created .bash_profile"
}

test_bash_login_sources_workspace() {
  local home="$test_root/bash-login-home"
  local first
  local second

  mkdir -p -- "$home/.oh-my-zsh"
  printf '# user zsh\n' > "$home/.zshrc"
  printf '# user bash\n' > "$home/.bashrc"
  printf '# user profile\n' > "$home/.profile"
  printf '# user bash_profile\n' > "$home/.bash_profile"

  HOME="$home" WORKSPACE_ROOT="$ROOT_DIR" "$ROOT_DIR/install/zsh.sh"
  assert_file_contains "$home/.profile" "workspace.bash"
  assert_file_contains "$home/.bash_profile" "workspace.bash"
  assert_file_contains "$home/.bashrc" "workspace.bash"
  assert_file_contains "$home/.bash_profile" "# user bash_profile"

  HOME="$home" bash --noprofile --norc -c '
    . "$HOME/.profile"
    type workspace-agent >/dev/null
    [[ -n "${_WORKSPACE_SHELL_COMMON_LOADED:-}" ]]
  ' || fail "login profile did not load bash workspace setup"

  HOME="$home" bash --noprofile --norc -c '
    . "$HOME/.bash_profile"
    type workspace-agent >/dev/null
  ' || fail "bash_profile did not load bash workspace setup"

  HOME="$home" bash --noprofile --norc -c '
    . "$HOME/.bashrc"
    first="$PROMPT_COMMAND"
    . "$HOME/.bashrc"
    [[ "$PROMPT_COMMAND" == "$first" ]]
    [[ "$PROMPT_COMMAND" == *_workspace_sync_ssh_agent* ]]
  ' || fail "bashrc is not idempotent when sourced twice"

  first="$(sha256sum "$home/.bashrc" "$home/.profile" "$home/.bash_profile")"
  HOME="$home" WORKSPACE_ROOT="$ROOT_DIR" "$ROOT_DIR/install/zsh.sh"
  second="$(sha256sum "$home/.bashrc" "$home/.profile" "$home/.bash_profile")"
  [[ "$first" == "$second" ]] || fail "bash login setup is not idempotent"
}

test_tmux_config() {
  local socket="setup-workspace-test-$$"

  command -v tmux >/dev/null 2>&1 || return 0
  tmux -L "$socket" -f /dev/null new-session -d
  if ! tmux -L "$socket" source-file "$ROOT_DIR/configs/tmux.conf.local"; then
    tmux -L "$socket" kill-server || true
    fail "tmux local configuration did not parse"
  fi
  if ! tmux -L "$socket" show-hooks -g client-attached | grep -Fq 'workspace-tmux-agent'; then
    tmux -L "$socket" kill-server || true
    fail "tmux SSH-agent attach hook is missing"
  fi
  tmux -L "$socket" kill-server
}

test_profile_defaults
test_network_filesystem_detection
test_managed_files_and_backups
test_shared_lock
test_ssh_and_jetbrains_migration
test_custom_ssh_rc_is_preserved
test_ssh_agent_install_publish_guard
test_ssh_agent_socket_refresh
test_shell_idempotency
test_bash_login_sources_workspace
test_tmux_config

echo "setup_workspace functional tests passed"
