#!/bin/bash
# agent-browser (github.com/vercel-labs/agent-browser) — browser-automation CLI for AI
# agents. Installed as an npm global; it drives the base image's Google Chrome via
# AGENT_BROWSER_EXECUTABLE_PATH (set in the Containerfile), so no separate Chrome-for-
# Testing download is needed.
set -euo pipefail

npm install -g agent-browser
npm cache clean --force
