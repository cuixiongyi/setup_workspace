#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export WORKSPACE_ROOT="$ROOT_DIR"
export WORKSPACE_INSTALL_JETBRAINS_LOCAL=1

usage() {
  cat <<'USAGE'
Usage: ./scripts/fix_jetbrains_remote.sh [--local-root ABSOLUTE_PATH]

Compatibility entry point for configuring persistent host-local JetBrains
Remote Development directories. Prefer:

  ./install.sh --cluster --user-only
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-root)
      [[ $# -ge 2 ]] || { echo "--local-root requires a value" >&2; exit 2; }
      export WORKSPACE_LOCAL_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
done

exec "$ROOT_DIR/install/jetbrains.sh"

