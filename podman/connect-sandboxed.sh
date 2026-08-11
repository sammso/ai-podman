#!/bin/bash
# Connect to a named, persistent sandbox — or create it (asking a few questions) if it
# doesn't exist yet. Unlike run-sandboxed.sh (one-shot --rm), the container stays alive
# so you can reconnect more terminals and its state persists across stops.
#
# Usage: connect-sandboxed.sh [<name>]
#   Workdirs default under $SANDBOX_ROOT (default ~/sandboxes). Named sandboxes always
#   use --persist-work (state in <workdir> itself, which is HOME).
set -euo pipefail

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib-sandbox.sh
source "$SELF_DIR/lib-sandbox.sh"

SANDBOX_ROOT="${SANDBOX_ROOT:-$HOME/sandboxes}"

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && {
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

# TTY for the exec (interactive when run from a terminal; -i alone for scripts).
TEXEC=(-i); [[ -t 0 ]] && TEXEC=(-it)

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
    echo "Known sandboxes:"
    sandbox_list | sed 's/^/  /' || true
    read -rp "Sandbox name: " NAME || true
    [[ -n "$NAME" ]] || sb_die "no name given"
fi
CN="${SANDBOX_PREFIX}${NAME}"

# Already exists -> start if stopped, then attach (no questions).
if podman container exists "$CN"; then
    [[ "$(podman inspect -f '{{.State.Running}}' "$CN")" == true ]] || podman start "$CN" >/dev/null
    exec podman exec "${TEXEC[@]}" "$CN" bash
fi

# Create: ask kit / gui / workdir.
read -rp "Container type [${KITS[*]}] (default dev): " KIT || true
KIT="${KIT:-dev}"
sb_is_kit "$KIT" || sb_die "unknown kit '$KIT' (expected one of: ${KITS[*]})"
IMAGE=$(sb_image "$KIT")
podman image exists "$IMAGE" || sb_die "image $IMAGE not found - build it with: ./build.sh $KIT"

sandbox_load_profiles
if sandbox_kit_flag "$KIT" gui; then _def=Y; else _def=n; fi
read -rp "GUI? [Y/n] (default $_def) " _g || true
case "${_g:-$_def}" in [Nn]*) GUI=0 ;; *) GUI=1 ;; esac

CAND="$SANDBOX_ROOT/$NAME"
if [[ -d "$CAND" ]]; then
    WORK="$CAND"
else
    read -rp "Workdir [$CAND]: " WORK || true
    WORK="${WORK:-$CAND}"
fi
mkdir -p "$WORK"
PROJECT_DIR=$(realpath -e -- "$WORK") || sb_die "cannot resolve workdir: $WORK"

# Named sandboxes always persist. Auto-flags come from the kit's profile in sandbox.conf:
# x11 only applies with GUI, kvm only if /dev/kvm exists. Prompt/title show the sandbox name.
PERSIST_WORK=1 DRY_RUN=0
X11=0;       if [[ $GUI -eq 1 ]] && sandbox_kit_flag "$KIT" x11; then X11=1; fi
KVM=0;       if sandbox_kit_flag "$KIT" kvm && [[ -e /dev/kvm ]]; then KVM=1; fi
HOST_NET=0;  if sandbox_kit_flag "$KIT" host-network; then HOST_NET=1; fi
HOST_DBUS=0; if sandbox_kit_flag "$KIT" host-dbus; then HOST_DBUS=1; fi
AI_KIT_NAME="$NAME"

sandbox_build_args
podman run -d --name "$CN" --stop-timeout 2 "${SANDBOX_ARGS[@]}" "$IMAGE" sleep infinity >/dev/null
echo "created sandbox '$NAME' (kit=$KIT gui=$GUI x11=$X11 kvm=$KVM hostnet=$HOST_NET, workdir=$PROJECT_DIR)"
exec podman exec "${TEXEC[@]}" "$CN" bash
