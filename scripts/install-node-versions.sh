#!/bin/bash
# fnm (Node version manager) system-wide, plus a couple of LTS Node versions.
#
# fnm must NOT live under $HOME: a --persist-work HOME of /work would shadow it and ephemeral
# runs would lose it. So the binary goes in /usr/local/bin and the version store in /opt/fnm
# (FNM_DIR, set in the Containerfile), world-writable so uid 1000 can `fnm install <v>` at
# runtime. The AI CLIs keep using base's system Node; fnm just prepends the selected version.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

FNM_VERSION=v1.39.0
FNM_ZIP_SHA256=7807664f39d39fc518da1c35ba0181e4b3267603c4b1dedeb4b5fc6ae440a224

apt-get update
apt-get install -y --no-install-recommends unzip
apt-get clean
rm -rf /var/lib/apt/lists/*

cd /tmp
curl -fL --retry 3 -o fnm-linux.zip \
    "https://github.com/Schniz/fnm/releases/download/${FNM_VERSION}/fnm-linux.zip"
echo "${FNM_ZIP_SHA256}  fnm-linux.zip" | sha256sum -c -
unzip -o fnm-linux.zip fnm -d /usr/local/bin
chmod +x /usr/local/bin/fnm
rm -f fnm-linux.zip

# Preinstall the active LTS line; default 22 (matches base). Versions are baked and shared
# across all runs. World-writable so the container user can add more with `fnm install`.
export FNM_DIR=/opt/fnm
install -d "$FNM_DIR"
fnm install 20
fnm install 22
fnm default 22
chmod -R a+rwX "$FNM_DIR"

# Activate fnm in every interactive shell: the default version, plus auto-switch on `cd` into a
# dir with .node-version / .nvmrc. profile.d covers login shells; appending to /etc/bash.bashrc
# covers interactive non-login shells (which do not read profile.d).
cat > /etc/profile.d/fnm.sh <<'EOF'
export FNM_DIR=/opt/fnm
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --use-on-cd --shell bash)"
fi
EOF
cat /etc/profile.d/fnm.sh >> /etc/bash.bashrc
