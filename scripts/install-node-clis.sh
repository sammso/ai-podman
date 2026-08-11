#!/bin/bash
# Node 22 LTS (NodeSource) + AI coding CLIs: Claude Code, Codex, Gemini.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

NODE_MAJOR=22

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list

apt-get update
apt-get install -y --no-install-recommends nodejs
apt-get clean
rm -rf /var/lib/apt/lists/*

npm install -g \
    @anthropic-ai/claude-code \
    @openai/codex \
    @google/gemini-cli

npm cache clean --force
