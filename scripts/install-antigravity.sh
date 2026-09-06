#!/bin/bash
# Antigravity CLI (agy) — Google's terminal-first agentic coding CLI (antigravity.google).
# Single binary; installed system-wide (the official installer targets ~/.local/bin, which a
# --persist-work HOME of /work shadows). Bump by refetching the manifest for the new version,
# url and sha512:  https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json
set -euo pipefail

AGY_VERSION=1.1.27
AGY_SHA512=793d4b9ea2c08d9a7e50bafa02cfc8c19424bd60d6e83f91408d45f9c6d4ce79a5d576fede5bef164d823abf84f81359a14b4ca665952c47b0a7cfd743bb69c0
# The path segment pairs the version with an opaque build id; bump both from the manifest.
AGY_URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/${AGY_VERSION}-5211191891591168/linux-x64/cli_linux_x64.tar.gz"

cd /tmp
curl -fL --retry 3 -o agy.tar.gz "$AGY_URL"
echo "${AGY_SHA512}  agy.tar.gz" | sha512sum -c -
tar -xzf agy.tar.gz antigravity                 # tarball holds a single binary named 'antigravity'
install -m 0755 antigravity /usr/local/bin/agy  # vendor command name is 'agy'
ln -sf agy /usr/local/bin/antigravity           # also answer to the full name
rm -f agy.tar.gz antigravity
