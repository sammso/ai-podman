#!/bin/bash
# Google Chrome stable from Google's apt repository.
# (Ubuntu's "chromium" package is a snap stub that does not work in containers.)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list

apt-get update
apt-get install -y --no-install-recommends google-chrome-stable
apt-get clean
rm -rf /var/lib/apt/lists/*
