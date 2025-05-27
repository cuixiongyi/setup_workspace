#!/usr/bin/env bash
# This script is used to solve JetBrains/PyCharm remote connection issue 
# when the remote host's `~/` is mounted on NFS. 
# Need to set the XDG_CACHE_HOME to a local disk, not NFS.

set -euo pipefail

PROFILE_D="/etc/profile.d/jetbrains_remote_dev.sh"

#  Detect if /home (or root’s $HOME when run as root) is on a network filesystem
#    We use findmnt for a reliable lookup of the FS type.
HOME_MNT_TYPE=$(findmnt -n -o FSTYPE /home || echo "")

if [[ ! "$HOME_MNT_TYPE" =~ ^(nfs|cifs|smbfs|autofs) ]]; then
  echo "→ /home is not NFS/CIFS (found: ${HOME_MNT_TYPE:-none}); skipping JetBrains env setup."
  exit 0
fi

# Create the snippet
cat > "$PROFILE_D" << 'EOF'
# JetBrains Remote Dev: only override XDG dirs if $HOME is on NFS/CIFS
# https://github.com/cuixiongyi/setup_workspace/blob/master/fix_jetbrains_remote.sh
if findmnt -n -o FSTYPE "$HOME" | grep -Eq '^(nfs|cifs|smbfs)$'; then
  export XDG_CACHE_HOME=/tmp/jetbrains_cache
  export XDG_CONFIG_HOME=/tmp/jetbrains_config
fi
EOF

# Ensure it's world-readable
chmod 644 "$PROFILE_D"

# (Optional) Pre-create the target directories with loose permissions
mkdir -p /tmp/jetbrains_cache /tmp/jetbrains_config
chmod 1777 /tmp/jetbrains_cache /tmp/jetbrains_config

echo "✔️  Installed JetBrains env override to $PROFILE_D"
