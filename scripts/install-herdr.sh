#!/bin/bash
# herdr (herdr.dev) — background runtime that keeps coding agents (Claude Code, Codex, …)
# running persistently. Single static binary; installed system-wide (the official installer
# targets ~/.local/bin, which a --persist-work HOME of /work shadows).
set -euo pipefail

HERDR_VERSION=v0.8.2
HERDR_SHA256=976150a14d490c94b243ea2e1a7eb2dfb67f12e36b182db90936f6728e6aecf4
HERDR_URL="https://github.com/herdrdev/herdr/releases/download/${HERDR_VERSION}/herdr-linux-x86_64"

cd /tmp
curl -fL --retry 3 -o herdr "$HERDR_URL"
echo "${HERDR_SHA256}  herdr" | sha256sum -c -
install -m 0755 herdr /usr/local/bin/herdr
rm -f herdr
