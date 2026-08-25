#!/bin/bash
# Visual Studio Code (official Microsoft build), launchable to the host desktop under --gui.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    > /etc/apt/sources.list.d/vscode.list

apt-get update
apt-get install -y --no-install-recommends code
apt-get clean
rm -rf /var/lib/apt/lists/*

# `code` launcher: run detached, Wayland-native when a Wayland session is present (its Electron
# build otherwise defaults to X11). Shadows /usr/bin/code (PATH order) and execs the real binary
# by absolute path, so no recursion. Add --no-sandbox if the Electron sandbox refuses under
# rootless podman.
cat > /usr/local/bin/code <<'EOF'
#!/bin/bash
args=()
[[ -n "${WAYLAND_DISPLAY:-}" ]] && args=(--ozone-platform=wayland)
appid="$(ai-env-color --appid 2>/dev/null)"; [[ -n "$appid" ]] && args+=(--class="$appid")
exec run-detached /usr/bin/code "${args[@]}" "$@"
EOF
chmod +x /usr/local/bin/code
