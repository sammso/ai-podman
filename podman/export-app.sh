#!/bin/bash
# Create (or remove) application-menu launchers that run a GUI app inside a *named* sandbox
# (aidev-<name>, created by connect-sandboxed.sh) via `podman exec` — NOT a fresh container.
#
# Each sandbox's launchers are grouped under an "AI Dev" > "<name>" submenu (KDE/XDG menu spec).
#
# The app launcher attaches only when the sandbox is already RUNNING; if it is stopped or
# absent it shows a desktop notification (it never starts or creates a container). A companion
# "Start <name>" launcher opens a terminal on connect-sandboxed.sh <name> to create/resume it.
#
# Usage:
#   export-app.sh [--no-start] <sandbox-name> <app> [display-name]
#   export-app.sh --remove <sandbox-name> [<app>]        # <app> -> app launcher; none -> Start launcher
#   export-app.sh --regroup                              # migrate already-exported launchers into submenus
#   export-app.sh --exec   <sandbox-name> <app> [args...] # (internal) invoked by the app .desktop
#
# <app> is the in-container launcher command (chrome, claude-desktop, code, idea, webstorm,
# studio, meld, lite-xl, wezterm). The sandbox must have been created with GUI for exec'd apps
# to reach the host desktop.
#
# Examples:
#   export-app.sh portal chrome "Chrome (portal)"
#   export-app.sh --no-start portal code
#   export-app.sh --remove portal chrome
set -euo pipefail

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SELF="$SELF_DIR/export-app.sh"
CONNECT="$SELF_DIR/connect-sandboxed.sh"
# shellcheck source=lib-sandbox.sh
source "$SELF_DIR/lib-sandbox.sh"          # SANDBOX_PREFIX
APPS_DIR="$HOME/.local/share/applications"
DIRS_DIR="$HOME/.local/share/desktop-directories"
# KDE merges from applications-merged and (with XDG_MENU_PREFIX) <prefix>applications-merged;
# write the submenu to both candidates so it's picked up regardless of which DefaultMergeDirs uses.
MENU_DIRS=("$HOME/.config/menus/applications-merged")
[[ -n "${XDG_MENU_PREFIX:-}" ]] && MENU_DIRS+=("$HOME/.config/menus/${XDG_MENU_PREFIX}applications-merged")

die() { echo "error: $*" >&2; exit 1; }
app_desktop()   { printf '%s/aidev-%s-%s.desktop' "$APPS_DIR" "$1" "${2##*/}"; }
start_desktop() { printf '%s/aidev-%s-start.desktop' "$APPS_DIR" "$1"; }
cat_of()        { printf 'X-AIDev-%s' "${1//[^A-Za-z0-9-]/-}"; }   # per-sandbox menu category

# Rebuild the menu caches so changes show without a relogin (best-effort).
refresh_menus() {
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
    local k
    for k in kbuildsycoca6 kbuildsycoca5; do
        command -v "$k" >/dev/null 2>&1 && { "$k" >/dev/null 2>&1 || true; break; }
    done
}

# Emit the .directory (submenu title) + shared parent + the merge .menu that maps this sandbox's
# category into an "AI Dev" > "<name>" submenu. Idempotent.
write_menu() {
    local name="$1" cat d
    cat=$(cat_of "$name")
    mkdir -p "$DIRS_DIR" "${MENU_DIRS[@]}"
    printf '[Desktop Entry]\nType=Directory\nName=AI Dev\nIcon=applications-development\n' \
        > "$DIRS_DIR/aidev.directory"
    printf '[Desktop Entry]\nType=Directory\nName=%s\nIcon=applications-development\n' "$name" \
        > "$DIRS_DIR/aidev-${name}.directory"
    for d in "${MENU_DIRS[@]}"; do
        cat > "$d/aidev-${name}.menu" <<MENU_EOF
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
  <Name>Applications</Name>
  <Menu>
    <Name>AI Dev</Name>
    <Directory>aidev.directory</Directory>
    <Menu>
      <Name>AI Dev ${name}</Name>
      <Directory>aidev-${name}.directory</Directory>
      <Include><Category>${cat}</Category></Include>
    </Menu>
  </Menu>
</Menu>
MENU_EOF
    done
}

# Drop a sandbox's submenu files; also drop the shared parent once no launchers remain at all.
remove_menu() {
    local name="$1" d
    rm -f "$DIRS_DIR/aidev-${name}.directory"
    for d in "${MENU_DIRS[@]}"; do rm -f "$d/aidev-${name}.menu"; done
    ls "$APPS_DIR"/aidev-*.desktop >/dev/null 2>&1 || rm -f "$DIRS_DIR/aidev.directory"
}

# Desktop notification for the app launcher (which has no terminal); best-effort chain.
notify() {
    if   command -v notify-send >/dev/null 2>&1; then notify-send "ai-dev sandbox" "$1"
    elif command -v zenity      >/dev/null 2>&1; then zenity --warning --text="$1" 2>/dev/null
    elif command -v kdialog     >/dev/null 2>&1; then kdialog --sorry "$1" 2>/dev/null
    else echo "$1" >&2; fi
}

# --- --exec: launch <app> into the RUNNING named sandbox (invoked by the app .desktop) ---
if [[ "${1:-}" == "--exec" ]]; then
    NAME="${2:?usage: export-app.sh --exec <name> <app> [args...]}"
    APP="${3:?usage: export-app.sh --exec <name> <app> [args...]}"
    shift 3
    CN="${SANDBOX_PREFIX}${NAME}"
    if ! podman container exists "$CN" \
        || [[ "$(podman inspect -f '{{.State.Running}}' "$CN" 2>/dev/null)" != true ]]; then
        notify "Sandbox '$NAME' is not running. Start it first — 'Start $NAME' in the menu, or: sb $NAME"
        exit 1
    fi
    # Re-pass the GUI env explicitly (robust regardless of exec env inheritance) + AI_KIT so the
    # per-pod window colour/app_id resolve; XDG_RUNTIME_DIR matches the sandbox's (/run/user/<uid>).
    env_args=(-e "AI_KIT=$NAME" -e "XDG_RUNTIME_DIR=/run/user/$(id -u)")
    [[ -n "${WAYLAND_DISPLAY:-}" ]] && env_args+=(-e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY")
    [[ -n "${DISPLAY:-}" ]]        && env_args+=(-e "DISPLAY=$DISPLAY")
    exec podman exec -d "${env_args[@]}" "$CN" "$APP" "$@"
fi

# --- --regroup: migrate already-exported flat launchers into per-sandbox submenus ---
if [[ "${1:-}" == "--regroup" ]]; then
    shopt -s nullglob
    declare -A seen=()
    for f in "$APPS_DIR"/aidev-*.desktop; do
        exec_line=$(grep -m1 '^Exec=' "$f" || true)
        name=""
        if [[ "$exec_line" == *"--exec "* ]]; then
            name=${exec_line#*--exec }; name=${name%% *}
        elif [[ "$exec_line" == *"connect-sandboxed.sh "* ]]; then
            name=${exec_line#*connect-sandboxed.sh }; name=${name%% *}
        fi
        [[ -n "$name" ]] || { echo "skip (no sandbox name in Exec): $f" >&2; continue; }
        local_cat=$(cat_of "$name")
        if grep -q '^Categories=' "$f"; then
            sed -i "s|^Categories=.*|Categories=${local_cat};|" "$f"
        else
            printf 'Categories=%s;\n' "$local_cat" >> "$f"
        fi
        [[ -n "${seen[$name]:-}" ]] || { write_menu "$name"; seen[$name]=1; echo "regrouped '$name'"; }
    done
    refresh_menus
    echo "done — launchers grouped under 'AI Dev' > <sandbox>"
    exit 0
fi

# --- --remove: drop the app launcher (<app> given) or the Start launcher (name only) ---
if [[ "${1:-}" == "--remove" ]]; then
    NAME="${2:?usage: export-app.sh --remove <name> [<app>]}"
    if [[ -n "${3:-}" ]]; then TARGET=$(app_desktop "$NAME" "$3"); else TARGET=$(start_desktop "$NAME"); fi
    [[ -f "$TARGET" ]] || die "no launcher at $TARGET"
    rm -f "$TARGET"
    ls "$APPS_DIR"/aidev-"${NAME}"-*.desktop >/dev/null 2>&1 || remove_menu "$NAME"
    refresh_menus
    echo "removed $TARGET"
    exit 0
fi

# --- create mode ---
WITH_START=1
if [[ "${1:-}" == "--no-start" ]]; then WITH_START=0; shift; fi

NAME="${1:?usage: export-app.sh [--no-start] <sandbox-name> <app> [display-name]}"
APP="${2:?missing <app>}"
DISPLAY_NAME="${3:-$APP ($NAME)}"
CN="${SANDBOX_PREFIX}${NAME}"
CAT=$(cat_of "$NAME")

podman container exists "$CN" \
    || echo "note: sandbox '$NAME' ($CN) does not exist yet — create it with 'Start $NAME' or: sb $NAME" >&2

mkdir -p "$APPS_DIR"

APP_DESKTOP=$(app_desktop "$NAME" "$APP")
cat > "$APP_DESKTOP" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=$DISPLAY_NAME
Comment=Runs $APP inside the running sandbox '$NAME' (podman exec)
Exec=$SELF --exec $NAME $APP
Icon=${APP##*/}
Terminal=false
Categories=$CAT;
DESKTOP_EOF
echo "created $APP_DESKTOP"
echo "  Exec=$SELF --exec $NAME $APP"

if [[ $WITH_START -eq 1 ]]; then
    START_DESKTOP=$(start_desktop "$NAME")
    cat > "$START_DESKTOP" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=Start $NAME
Comment=Create or resume the '$NAME' sandbox and open a shell
Exec=$CONNECT $NAME
Icon=utilities-terminal
Terminal=true
Categories=$CAT;
DESKTOP_EOF
    echo "created $START_DESKTOP"
fi

write_menu "$NAME"
refresh_menus
echo "grouped under 'AI Dev' > '$NAME' in the application menu"
echo "(Icon '${APP##*/}' falls back to a generic icon if your host theme lacks it.)"
