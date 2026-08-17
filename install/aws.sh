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
version="${WORKSPACE_AWS_VERSION:-latest}"

case "$arch" in
  x86_64) aws_arch="x86_64" ;;
  aarch64) aws_arch="aarch64" ;;
  *) workspace_die "unsupported AWS CLI architecture: $arch" ;;
esac

if [[ "$version" == "latest" ]]; then
  archive="awscli-exe-linux-${aws_arch}.zip"
else
  archive="awscli-exe-linux-${aws_arch}-${version}.zip"
fi
url="https://awscli.amazonaws.com/$archive"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
zip_file="$tmp_dir/awscliv2.zip"
sig_file="$tmp_dir/awscliv2.sig"
gnupg_home="$tmp_dir/gnupg"

workspace_log "downloading AWS CLI v2 ($version)"
workspace_download "$url" "$zip_file"
workspace_download "${url}.sig" "$sig_file"

workspace_require_cmd gpg
mkdir -m 0700 -- "$gnupg_home"
gpg --batch --quiet --homedir "$gnupg_home" \
  --import "$WORKSPACE_ROOT/install/aws-cli-public-key.asc"
fingerprint="$(
  gpg --batch --homedir "$gnupg_home" --with-colons --fingerprint \
    | awk -F: '$1 == "fpr" { print $10; exit }'
)"
[[ "$fingerprint" == "FB5DB77FD5C118B80511ADA8A6310ACC4672475C" ]] ||
  workspace_die "the bundled AWS CLI signing key has an unexpected fingerprint"
gpg --batch --quiet --homedir "$gnupg_home" --verify "$sig_file" "$zip_file" ||
  workspace_die "AWS CLI signature verification failed"
unzip -q "$zip_file" -d "$tmp_dir"

if [[ -d /usr/local/aws-cli/v2 ]]; then
  workspace_log "updating AWS CLI v2"
  sudo "$tmp_dir/aws/install" --update
else
  workspace_log "installing AWS CLI v2"
  sudo "$tmp_dir/aws/install"
fi
