#!/bin/bash
# Build the AI development images in dependency order.
#
# Usage:
#   ./build.sh                 build everything (base first)
#   ./build.sh base|java|dev|android|node   build one target (base is NOT auto-rebuilt)
#   ./build.sh --no-cache [target]            pass --no-cache to podman build
set -euo pipefail
cd "$(dirname "$0")"

EXTRA_ARGS=()
if [[ "${1:-}" == "--no-cache" ]]; then
    EXTRA_ARGS+=(--no-cache)
    shift
fi

if [[ $# -gt 0 ]]; then
    TARGETS=("$@")
else
    TARGETS=(base java dev android node)
fi

build_one() {
    local kit="$1"
    echo "==> Building localhost/ai-${kit}:latest"
    podman build "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" \
        -t "localhost/ai-${kit}:latest" \
        -f "${kit}/Containerfile" \
        .
}

for kit in "${TARGETS[@]}"; do
    case "$kit" in
        base|java|dev|android|node) build_one "$kit" ;;
        *) echo "Unknown target: $kit (expected base|java|dev|android|node)" >&2; exit 1 ;;
    esac
done

echo "==> Done"
podman images --filter reference='localhost/ai-*'
