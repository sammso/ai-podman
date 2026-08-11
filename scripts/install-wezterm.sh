#!/bin/bash
# WezTerm — GPU-accelerated terminal emulator, launchable to the host desktop under
# run-sandboxed --gui. Installed from the official AppImage, extracted (self-contained,
# no dep juggling): the latest stable release predates Ubuntu 24.04's t64 lib rename, so
# its .deb is unreliable here, while the 20.04-built AppImage is forward-compatible.
set -euo pipefail

WEZTERM_TAG=20240203-110809-5046fc22

curl -fsSL -o /tmp/wezterm.AppImage \
    "https://github.com/wezterm/wezterm/releases/download/${WEZTERM_TAG}/WezTerm-${WEZTERM_TAG}-Ubuntu20.04.AppImage"
chmod +x /tmp/wezterm.AppImage

cd /opt
/tmp/wezterm.AppImage --appimage-extract >/dev/null   # -> /opt/squashfs-root (no FUSE needed)
mv squashfs-root wezterm
rm /tmp/wezterm.AppImage
chmod -R a+rX /opt/wezterm

ln -sf /opt/wezterm/usr/bin/wezterm-mux-server /usr/local/bin/wezterm-mux-server

# GUI launches (no subcommand, or start/gui) run detached from the terminal; CLI
# subcommands (cli, ssh, --version, ...) stay attached so their output/exit are usable.
cat > /usr/local/bin/wezterm <<'EOF'
#!/bin/bash
case "${1:-}" in
    ""|start|gui) exec run-detached /opt/wezterm/usr/bin/wezterm "$@" ;;
    *)            exec /opt/wezterm/usr/bin/wezterm "$@" ;;
esac
EOF
cat > /usr/local/bin/wezterm-gui <<'EOF'
#!/bin/bash
exec run-detached /opt/wezterm/usr/bin/wezterm-gui "$@"
EOF
chmod +x /usr/local/bin/wezterm /usr/local/bin/wezterm-gui
