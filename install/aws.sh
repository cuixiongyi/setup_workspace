#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if [[ "${WORKSPACE_INSTALL_AWS:-1}" != "1" ]]; then
  workspace_log "AWS CLI installation disabled"
  exit 0
fi

arch="$(workspace_detect_arch)" || workspace_die "unsupported architecture for AWS CLI: $(uname -m)"
version="${WORKSPACE_AWS_VERSION:-2.36.2}"

case "$arch" in
  x86_64) aws_arch="x86_64" ;;
  aarch64) aws_arch="aarch64" ;;
  *) workspace_die "unsupported AWS CLI architecture: $arch" ;;
esac

case "$version:$arch" in
  2.36.2:x86_64)
    sha256="88045926e48315681b73ec1d4e430ae6917b0eaffc6368d34bcc07bf9fe9fcb9"
    ;;
  2.36.2:aarch64)
    sha256="7f41af8314f5a8d84742a7cf3e37e55d898355a6b605bcacb68adcf563c73064"
    ;;
  latest:*)
    workspace_die "WORKSPACE_AWS_VERSION=latest is intentionally unsupported; pin and checksum a release"
    ;;
  *)
    workspace_die "no trusted checksum is recorded for AWS CLI $version on $arch"
    ;;
esac

url="https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}-${version}.zip"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
zip_file="$tmp_dir/awscliv2.zip"

workspace_log "downloading AWS CLI v2 ($version)"
workspace_download "$url" "$zip_file"
printf '%s  %s\n' "$sha256" "$zip_file" | sha256sum -c -
unzip -q "$zip_file" -d "$tmp_dir"

if [[ -d /usr/local/aws-cli/v2 ]]; then
  workspace_log "updating AWS CLI v2"
  sudo "$tmp_dir/aws/install" --update
else
  workspace_log "installing AWS CLI v2"
  sudo "$tmp_dir/aws/install"
fi
