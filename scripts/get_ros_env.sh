#!/usr/bin/env bash
set -Eeuo pipefail

# Print environment changes made by sourcing a ROS setup script. This is useful
# for inspecting what a setup file changes without permanently changing the
# current shell.
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/setup.bash" >&2
  exit 2
fi

setup_file="$1"
[[ -r "$setup_file" ]] || { echo "Cannot read: $setup_file" >&2; exit 1; }

before="$(mktemp)"
after="$(mktemp)"
trap 'rm -f -- "$before" "$after"' EXIT

env | sort > "$before"
# shellcheck disable=SC1090
source "$setup_file"
env | sort > "$after"
comm -13 "$before" "$after"
