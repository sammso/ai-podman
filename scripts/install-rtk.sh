#!/bin/bash
# rtk (github.com/rtk-ai/rtk) — a CLI proxy that compresses command output before an LLM
# agent reads it, cutting token use for the AI CLIs. Static musl binary, no deps. Installed
# system-wide (the official install.sh targets ~/.local/bin, which --persist-work shadows).
set -euo pipefail

RTK_VERSION=v0.45.0
TARGET=x86_64-unknown-linux-musl
ASSET="rtk-${TARGET}.tar.gz"
BASE_URL="https://github.com/rtk-ai/rtk/releases/download/${RTK_VERSION}"

cd /tmp
curl -fsSL -o "$ASSET" "${BASE_URL}/${ASSET}"
curl -fsSL -o checksums.txt "${BASE_URL}/checksums.txt"

# Refuse to install an unverified binary
grep " ${ASSET}\$" checksums.txt | sha256sum -c -

tar -xzf "$ASSET"
install -m 0755 rtk /usr/local/bin/rtk
rm -f "$ASSET" checksums.txt rtk
