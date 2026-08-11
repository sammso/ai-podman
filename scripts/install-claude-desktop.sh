#!/bin/bash
# Claude Desktop (official Linux beta) from Anthropic's apt repository.
# The host (Fedora) is not supported by the official .deb; running it in this
# Ubuntu-based image and surfacing it via podman/export-app.sh is the workaround.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

KEYRING=/usr/share/keyrings/claude-desktop-archive-keyring.asc
FINGERPRINT=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

curl -fsSLo "$KEYRING" https://downloads.claude.ai/claude-desktop/key.asc
# Fail the build loudly if the signing key is not Anthropic's
gpg --show-keys --with-colons "$KEYRING" | grep -q "$FINGERPRINT" \
    || { echo "Claude Desktop signing key fingerprint mismatch!" >&2; exit 1; }

echo "deb [arch=amd64,arm64 signed-by=$KEYRING] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
    > /etc/apt/sources.list.d/claude-desktop.list

apt-get update
apt-get install -y --no-install-recommends claude-desktop
apt-get clean
rm -rf /var/lib/apt/lists/*
