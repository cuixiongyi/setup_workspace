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
  assert_output_contains "$output" "tmux_ref=58a3dcc0d718ec0fa1c0d5a2fddd640a1ad7a5b7"

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

  HOME="$home" WORKSPACE_ROOT="$ROOT_DIR" "$ROOT_DIR/install/ssh-agent.sh"

  [[ ! -e "$home/.ssh/rc" ]] || fail "legacy SSH rc was not retired"
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
  HOME="$home" \
  WORKSPACE_ROOT="$ROOT_DIR" \
  WORKSPACE_INSTALL_JETBRAINS_LOCAL=1 \
  WORKSPACE_LOCAL_ROOT="$local_root" \
    "$ROOT_DIR/install/jetbrains.sh"
  backups_after="$(find "$home" -name '*.pre-setup-workspace*' | wc -l)"
  [[ "$backups_before" == "$backups_after" ]] ||
    fail "JetBrains rerun created unexpected backups"

  if HOME="$home" WORKSPACE_LOCAL_ROOT=/tmp/unsupported \
      "$home/.local/bin/workspace-jetbrains-local" path >/dev/null 2>&1; then
    fail "volatile JetBrains root was accepted"
  fi
}

test_ssh_agent_socket_refresh() {
  local agent_dir="$test_root/ssh-agent-helper"
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

  command -v ssh-agent >/dev/null 2>&1 || return 0
  mkdir -p -- "$source_dir"

  first_pid="$(ssh-agent -a "$first_socket" -s | sed -n 's/^SSH_AGENT_PID=\([0-9][0-9]*\);.*/\1/p')"
  second_pid="$(ssh-agent -a "$second_socket" -s | sed -n 's/^SSH_AGENT_PID=\([0-9][0-9]*\);.*/\1/p')"
  [[ -n "$first_pid" && -n "$second_pid" ]] || fail "could not start test SSH agents"
  ssh_agent_test_pids=("$first_pid" "$second_pid")

  WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    "$ROOT_DIR/bin/workspace-ssh-agent" refresh "$first_socket" >/dev/null
  [[ "$(readlink -f -- "$stable_socket")" == "$first_socket" ]] ||
    fail "stable SSH socket did not resolve to the first agent"

  # The legacy setup used a second stable link in HOME. Refreshing from that
  # alias must remain a no-op instead of replacing stable_socket with a link
  # back to the alias and creating a cycle.
  ln -s -- "$stable_socket" "$legacy_socket"
  WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    "$ROOT_DIR/bin/workspace-ssh-agent" refresh "$legacy_socket" >/dev/null
  [[ "$(readlink -f -- "$stable_socket")" == "$first_socket" ]] ||
    fail "legacy SSH socket alias created a cycle"

  # Recover the precise broken A -> B -> A state seen during migration.
  ln -sfn -- "$legacy_socket" "$stable_socket"
  WORKSPACE_SSH_AGENT_DIR="$agent_dir" \
    "$ROOT_DIR/bin/workspace-ssh-agent" refresh "$second_socket" >/dev/null
  [[ "$(readlink -f -- "$stable_socket")" == "$second_socket" ]] ||
    fail "stable SSH socket did not recover from a symlink cycle"

  if command -v ssh-keygen >/dev/null 2>&1; then
    ssh-keygen -q -t ed25519 -N '' -f "$test_key"
    SSH_AUTH_SOCK='' WORKSPACE_SSH_AGENT_DIR="$started_agent_dir" \
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

  kill "${ssh_agent_test_pids[@]}" 2>/dev/null || true
  ssh_agent_test_pids=()
}

test_shell_idempotency() {
  local home="$test_root/shell-home"
  local first
  local second

  mkdir -p -- "$home/.oh-my-zsh/.git"
  printf 'user zsh\n' > "$home/.zshrc"
  printf 'user bash\n' > "$home/.bashrc"
  printf 'user profile\n' > "$home/.profile"

  HOME="$home" WORKSPACE_ROOT="$ROOT_DIR" "$ROOT_DIR/install/zsh.sh"
  first="$(sha256sum "$home/.zshrc" "$home/.bashrc" "$home/.profile" "$home/.zprofile")"
  HOME="$home" WORKSPACE_ROOT="$ROOT_DIR" "$ROOT_DIR/install/zsh.sh"
  second="$(sha256sum "$home/.zshrc" "$home/.bashrc" "$home/.profile" "$home/.zprofile")"
  [[ "$first" == "$second" ]] || fail "shell setup is not idempotent"
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
test_ssh_agent_socket_refresh
test_shell_idempotency
test_tmux_config

echo "setup_workspace functional tests passed"
