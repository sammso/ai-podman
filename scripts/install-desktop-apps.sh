#!/bin/bash
# GUI apps for use inside a `run-sandboxed.sh --gui` container: they display on the
# host's Wayland desktop through the shared socket. Installs Meld (diff/merge) and
# Lite XL (editor), and adds short launch commands.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

LITEXL_VERSION=2.1.8

# --- Meld (apt) + Lite XL runtime deps (SDL2) ---
apt-get update
apt-get install -y --no-install-recommends meld libsdl2-2.0-0
apt-get clean
rm -rf /var/lib/apt/lists/*

# --- Lite XL (official portable build) ---
curl -fsSL -o /tmp/lite-xl.tar.gz \
    "https://github.com/lite-xl/lite-xl/releases/download/v${LITEXL_VERSION}/lite-xl-v${LITEXL_VERSION}-linux-x86_64-portable.tar.gz"
tar -xzf /tmp/lite-xl.tar.gz -C /opt      # extracts to /opt/lite-xl/{lite-xl,data,...}
rm /tmp/lite-xl.tar.gz

# --- run-detached: launch a GUI app off the controlling terminal ---
# So GUI commands neither block the shell nor spam it with logs. Detach (new session,
# backgrounded, output to a per-app log) only when started from a terminal AND not PID 1
# - detaching the container's main process would exit the container and kill the app, so
# one-shot `run-sandboxed ... <app>` and menu launchers stay attached. --version/--help
# always run attached so they still print.
cat > /usr/local/bin/run-detached <<'EOF'
#!/bin/bash
for a in "$@"; do case "$a" in --version|-V|--help|-h) exec "$@";; esac; done
if [[ $$ -ne 1 && -t 0 ]]; then
    exec setsid -f "$@" </dev/null >"${XDG_RUNTIME_DIR:-/tmp}/gui-$(basename -- "$1").log" 2>&1
fi
exec "$@"
EOF
chmod +x /usr/local/bin/run-detached

# --- lite-xl / meld: launch detached ---
cat > /usr/local/bin/lite-xl <<'EOF'
#!/bin/bash
exec run-detached /opt/lite-xl/lite-xl "$@"
EOF
cat > /usr/local/bin/meld <<'EOF'
#!/bin/bash
exec run-detached /usr/bin/meld "$@"
EOF
chmod +x /usr/local/bin/lite-xl /usr/local/bin/meld

# --- chrome: short command, Wayland-native (verified working under --gui) ---
cat > /usr/local/bin/chrome <<'EOF'
#!/bin/bash
# Google Chrome, Wayland-native (works on the host desktop under run-sandboxed --gui).
exec run-detached google-chrome --ozone-platform=wayland "$@"
EOF
chmod +x /usr/local/bin/chrome

# --- claude-desktop: force Wayland when a Wayland session is present ---
# This Electron build ignores ELECTRON_OZONE_PLATFORM_HINT and otherwise defaults to
# the X11 backend, exiting with "Missing X server or $DISPLAY". Passing the flag
# explicitly (the proven-working invocation) fixes it. Shadows /usr/bin/claude-desktop
# (PATH order); execs the real binary by absolute path, so no recursion.
cat > /usr/local/bin/claude-desktop <<'EOF'
#!/bin/bash
args=()
[[ -n "${WAYLAND_DISPLAY:-}" ]] && args=(--ozone-platform=wayland)
exec run-detached /usr/bin/claude-desktop "${args[@]}" "$@"
EOF
chmod +x /usr/local/bin/claude-desktop

# --- gui-apps: list the GUI quick commands available in this container ---
cat > /usr/local/bin/gui-apps <<'EOF'
#!/bin/bash
cat <<'LIST'
GUI apps (start the container with run-sandboxed.sh --gui to see them on the host).
Launched in the background, detached from the terminal (logs in $XDG_RUNTIME_DIR/gui-*.log):

  chrome          Google Chrome (Wayland-native; = google-chrome --ozone-platform=wayland)
  claude-desktop  Claude Desktop (add --no-sandbox if the Electron sandbox refuses)
  meld            Meld visual diff / merge tool
  lite-xl         Lite XL editor
  wezterm         GPU-accelerated terminal (opens a shell in the container)

Example:  chrome https://localhost:20080   |   meld a.txt b.txt   |   lite-xl .   |   wezterm
LIST
EOF
chmod +x /usr/local/bin/gui-apps
