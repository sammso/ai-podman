#!/bin/bash
# ChatGPT desktop app (official OpenAI Linux preview) — bundles Chat, Work and Codex.
# Fedora (the host) isn't a supported target; running it in this Ubuntu image and surfacing it
# via podman/export-app.sh is the workaround, same as Claude Desktop. Pinned + sha256-verified
# (the /latest/ URL is a moving target). Bump by refetching the repo's Packages index for the
# new version, pool path and SHA256:
#   https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-amd64/Packages
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

CHATGPT_VERSION=26.901.51231
CHATGPT_SHA256=62580188d87c3d3a9369dab7c73b42a8a32518d4df8a2d5bae6466ddeac5c05e
CHATGPT_URL="https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${CHATGPT_VERSION}_amd64.deb"

cd /tmp
curl -fL --retry 3 -o chatgpt.deb "$CHATGPT_URL"
echo "${CHATGPT_SHA256}  chatgpt.deb" | sha256sum -c -
apt-get update
apt-get install -y --no-install-recommends ./chatgpt.deb   # resolves the GTK/Electron deps
apt-get clean
rm -f chatgpt.deb
rm -rf /var/lib/apt/lists/*
