#!/bin/bash
# Shared helpers for the sandbox runners (run-sandboxed.sh = one-shot, connect-sandboxed.sh
# = named/persistent, stop-sandboxed.sh). Source after `set -euo pipefail`.

KITS=(base java dev android node)
SANDBOX_PREFIX=aidev-
_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

sb_die() { echo "error: $*" >&2; exit 1; }
sb_is_kit() { case " ${KITS[*]} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
sb_image() { printf 'localhost/ai-%s:latest' "$1"; }

# Per-kit flag profiles: which auto-flags (gui x11 kvm host-network host-dbus) a kit gets in
# connect-sandboxed.sh. Read from podman/sandbox.conf, then overridden per kit by an optional
# user file ($SANDBOX_CONF or ~/.config/ai-dev/sandbox.conf).
declare -gA SANDBOX_KIT_PROFILE=()
sandbox_load_profiles() {
    SANDBOX_KIT_PROFILE=()
    local f line kit flags
    for f in "$_LIB_DIR/sandbox.conf" "${SANDBOX_CONF:-$HOME/.config/ai-dev/sandbox.conf}"; do
        [[ -r "$f" ]] || continue
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"                        # strip comments
            [[ "$line" == *=* ]] || continue
            kit="${line%%=*}"; flags="${line#*=}"
            read -r kit <<<"$kit"                     # trim
            flags="$(printf '%s' "$flags" | xargs)"   # collapse/trim
            [[ -n "$kit" ]] && SANDBOX_KIT_PROFILE["$kit"]="$flags"
        done < "$f"
    done
    return 0
}

# True if <kit> has <flag> in its profile (unlisted kit defaults to "gui").
sandbox_kit_flag() {
    local prof="${SANDBOX_KIT_PROFILE[$1]:-gui}"
    [[ " $prof " == *" $2 "* ]]
}

# List existing sandboxes as "<name>\t<status>" (prefix stripped).
sandbox_list() {
    podman ps -a --filter "name=^${SANDBOX_PREFIX}" \
        --format '{{.Names}}	{{.Status}}' 2>/dev/null | sed "s/^${SANDBOX_PREFIX}//"
}

# Populate the global SANDBOX_ARGS array with everything BETWEEN `podman run <mode>` and the
# image (mounts, env, --gui plumbing, persistence, network, devices). Inputs are globals:
#   KIT PROJECT_DIR GUI X11 PERSIST_WORK HOST_NET HOST_DBUS KVM DRY_RUN
#   optional AI_KIT_NAME (prompt/title name; defaults to KIT).
#   optional AI_HOST_ALIASES (override the per-kit /etc/hosts aliases; "" disables).
sandbox_build_args() {
    local uid gid container_user=ubuntu home_target="" host_aliases _h
    local -a _aliases
    uid=$(id -u); gid=$(id -g)
    local env_name="${AI_KIT_NAME:-$KIT}"

    # HOME inside the container: --persist-work sets it to /work (the mounted project dir itself)
    # so all state (services, AVDs, ~/.claude, ~/liferay) persists in the project; otherwise HOME
    # is the image default (ephemeral).
    if [[ $PERSIST_WORK -eq 1 ]]; then
        home_target=/work
    fi

    # label=disable: SELinux separation off (the Wayland socket bind fails under strict
    # :Z-only labeling); userns + single /work mount stay the containment boundary.
    # USER: podman doesn't set it, but wrappers need it to equal the container passwd name
    # (initdb superuser, libpq default role, liferay JDBC user must all agree).
    SANDBOX_ARGS=(
        --userns=keep-id
        --user "${uid}:${gid}"
        -e "USER=$container_user"
        -e "AI_KIT=$env_name"
        --security-opt label=disable
        --shm-size=1g
        -v "$PROJECT_DIR:/work:Z"
        -w /work
    )
    [[ $PERSIST_WORK -eq 1 ]] && SANDBOX_ARGS+=(-e "HOME=$home_target")

    if [[ $GUI -eq 1 ]]; then
        [[ -n "${WAYLAND_DISPLAY:-}" ]] \
            || sb_die "--gui needs \$WAYLAND_DISPLAY set (are you in a Wayland session?)"
        local rundir="/run/user/${uid}" wl
        wl="$rundir/$WAYLAND_DISPLAY"
        [[ -S "$wl" ]] || sb_die "--gui: Wayland socket not found at $wl"
        SANDBOX_ARGS+=(
            # Writable XDG_RUNTIME_DIR (mode=1777, sticky like /tmp) so dconf/GSettings work;
            # the socket binds land inside this tmpfs (podman mounts it first).
            --tmpfs "$rundir:rw,mode=1777"
            -e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
            -e "XDG_RUNTIME_DIR=$rundir"
            -v "$wl:$wl"
            --device /dev/dri
            # Electron apps default to X11 Ozone and exit; force Wayland.
            -e "ELECTRON_OZONE_PLATFORM_HINT=auto"
            # Drop inherited KDE GTK-module list (host-only modules missing in the image).
            -e "GTK_MODULES="
        )
        # Host session D-Bus OFF by default so GUI file dialogs browse the CONTAINER fs
        # (native chooser) not the host portal. --host-dbus opts into host integration.
        # Bind ONLY the bus socket, never the runtime dir (holds the podman socket = escape).
        if [[ $HOST_DBUS -eq 1 && -S "$rundir/bus" ]]; then
            SANDBOX_ARGS+=(-v "$rundir/bus:$rundir/bus" -e "DBUS_SESSION_BUS_ADDRESS=unix:path=$rundir/bus")
        fi
        # Audio (low-risk): PipeWire / PulseAudio-compat sockets if present.
        [[ -S "$rundir/pipewire-0" ]] && SANDBOX_ARGS+=(-v "$rundir/pipewire-0:$rundir/pipewire-0")
        [[ -S "$rundir/pulse/native" ]] && SANDBOX_ARGS+=(-v "$rundir/pulse/native:$rundir/pulse/native")
    fi

    if [[ $X11 -eq 1 ]]; then
        SANDBOX_ARGS+=(-e "DISPLAY=${DISPLAY:-:0}" -v /tmp/.X11-unix:/tmp/.X11-unix)
    fi

    # Hostname aliases -> 127.0.0.1. Podman regenerates /etc/hosts and the container is
    # unprivileged, so --add-host (applied at creation) is the only way to add them. The java kit
    # ships staging.local/live.local/liferay.local so Liferay staging and live get separate cookie
    # domains (reach them by port, e.g. staging.local:20080). Override with
    # AI_HOST_ALIASES="a.local b.local", or AI_HOST_ALIASES="" to disable.
    if [[ -n "${AI_HOST_ALIASES+x}" ]]; then
        host_aliases="$AI_HOST_ALIASES"
    else
        case "$KIT" in
            java) host_aliases="staging.local live.local liferay.local" ;;
            *)    host_aliases="" ;;
        esac
    fi
    read -ra _aliases <<<"$host_aliases"
    for _h in "${_aliases[@]}"; do SANDBOX_ARGS+=(--add-host "$_h:127.0.0.1"); done

    [[ $HOST_NET -eq 1 ]] && SANDBOX_ARGS+=(--network host)
    [[ $KVM -eq 1 ]] && SANDBOX_ARGS+=(--device /dev/kvm)
    return 0
}
