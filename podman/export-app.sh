#!/bin/bash
# Create (or remove) a Fedora application-menu launcher for a GUI app that runs
# inside an ai-* image via run-sandboxed.sh --gui.
#
# Usage:
#   export-app.sh [run-sandboxed flags...] <kit> <project-dir> <app> [display-name]
#   export-app.sh --remove <kit> <app>
#
# Examples:
#   export-app.sh --persist-work base ~/projects/site google-chrome "Chrome (base)"
#   export-app.sh --persist-work base ~/projects/site claude-desktop "Claude Desktop"
#   export-app.sh --remove base google-chrome
set -euo pipefail

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RUNNER="$SELF_DIR/run-sandboxed.sh"
APPS_DIR="$HOME/.local/share/applications"
KITS=(base java dev android)

die() { echo "error: $*" >&2; exit 1; }
is_kit() { case " ${KITS[*]} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# --- removal mode ---
if [[ "${1:-}" == "--remove" ]]; then
    KIT="${2:?usage: export-app.sh --remove <kit> <app>}"
    APP="${3:?usage: export-app.sh --remove <kit> <app>}"
    DESKTOP="$APPS_DIR/aidev-${KIT}-${APP##*/}.desktop"
    [[ -f "$DESKTOP" ]] || die "no launcher at $DESKTOP"
    rm -f "$DESKTOP"
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
    echo "removed $DESKTOP"
    exit 0
fi

# --- create mode: collect pass-through run-sandboxed flags, then positionals ---
FLAGS=(--gui)
while [[ $# -gt 0 && "$1" == --* ]]; do
    FLAGS+=("$1"); shift
done

KIT="${1:?usage: export-app.sh [flags] <kit> <project-dir> <app> [display-name]}"
is_kit "$KIT" || die "unknown kit '$KIT' (expected one of: ${KITS[*]})"
PROJECT_DIR=$(realpath -e -- "${2:?missing <project-dir>}" 2>/dev/null) \
    || die "project directory not found: ${2:-}"
APP="${3:?missing <app>}"
NAME="${4:-$APP ($KIT)}"

podman image exists "localhost/ai-${KIT}:latest" \
    || die "image localhost/ai-${KIT}:latest not found - build it with: ./build.sh $KIT"

mkdir -p "$APPS_DIR"
DESKTOP="$APPS_DIR/aidev-${KIT}-${APP##*/}.desktop"

# Exec must be an absolute, self-contained command line for the desktop launcher.
EXEC="$RUNNER"
for f in "${FLAGS[@]}"; do EXEC+=" $f"; done
EXEC+=" $KIT $PROJECT_DIR $APP"

cat > "$DESKTOP" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=$NAME
Comment=Runs in localhost/ai-${KIT}:latest (run-sandboxed --gui)
Exec=$EXEC
Icon=${APP##*/}
Terminal=false
Categories=Development;
DESKTOP_EOF

update-desktop-database "$APPS_DIR" 2>/dev/null || true
echo "created $DESKTOP"
echo "  Exec=$EXEC"
echo "(Icon '${APP##*/}' falls back to a generic icon if your host theme lacks it.)"
