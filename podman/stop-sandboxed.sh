#!/bin/bash
# Stop a named sandbox (created by connect-sandboxed.sh). The container is kept so it can
# be restarted by reconnecting; pass --rm to remove it entirely.
#
# Usage: stop-sandboxed.sh [--rm] [<name>]
set -euo pipefail

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib-sandbox.sh
source "$SELF_DIR/lib-sandbox.sh"

RM=0 NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rm)      RM=1 ;;
        --help|-h) sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --*)       sb_die "unknown option: $1" ;;
        *)         NAME="$1" ;;
    esac
    shift
done

if [[ -z "$NAME" ]]; then
    echo "Running sandboxes:"
    podman ps --filter "name=^${SANDBOX_PREFIX}" --format '{{.Names}}' | sed "s/^${SANDBOX_PREFIX}/  /" || true
    read -rp "Sandbox name: " NAME || true
    [[ -n "$NAME" ]] || sb_die "no name given"
fi

CN="${SANDBOX_PREFIX}${NAME}"
podman container exists "$CN" || sb_die "no sandbox '$NAME'"

# Stop in-container services (e.g. pg-stop) first for a clean shutdown.
podman stop "$CN" >/dev/null && echo "stopped $NAME"
if [[ $RM -eq 1 ]]; then
    podman rm "$CN" >/dev/null && echo "removed $NAME (workdir data under <workdir> is kept)"
fi
