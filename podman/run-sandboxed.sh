#!/bin/bash
# Run an ai-* image with plain podman, sharing exactly ONE project directory with
# the host. The container sees only /work and the disposable image filesystem — the
# host home, dotfiles, SSH keys and other projects stay invisible. One-shot (--rm);
# for named, reconnectable sandboxes see connect-sandboxed.sh.
#
# Usage: run-sandboxed.sh [options] <kit> <project-dir> [command...]
set -euo pipefail

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib-sandbox.sh
source "$SELF_DIR/lib-sandbox.sh"

usage() {
    cat <<USAGE
Usage: ${0##*/} [options] <kit> <project-dir> [command...]

Run localhost/ai-<kit>:latest in a sandboxed podman container. The project
directory is the ONLY host filesystem mount (at /work). Default command: bash.

Kits: ${KITS[*]}

Options:
  --gui             Wayland display plumbing (socket + GPU only, no host files)
  --x11             X11/XWayland fallback on top of --gui (Chrome: try
                    --ozone-platform=wayland first; see comments in script)
  --persist-work    Persist ALL container state in <project-dir> itself (sets HOME
                    to /work). Liferay DB/MinIO/bundles, Android AVDs and AI logins
                    survive the run. Use for service/dev work.
  --host-network    Share the host network (reach the container's PostgreSQL :5432,
                    Liferay :20080/:21080 from the host). Off by default.
  --host-dbus       Share the host session D-Bus (portals, notifications). Off by
                    default so GUI file dialogs browse the CONTAINER fs, not the host.
  --kvm             Pass through /dev/kvm (android kit: emulator acceleration)
  --dry-run         Print the podman command instead of running it
  --help            This text

Examples:
  ${0##*/} dev ~/projects/myapp
  ${0##*/} --gui --x11 base ~/projects/site google-chrome
  ${0##*/} --persist-work --host-network java ~/projects/portal
USAGE
}

GUI=0 X11=0 PERSIST_WORK=0 HOST_NET=0 HOST_DBUS=0 KVM=0 DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gui)            GUI=1 ;;
        --x11)            GUI=1; X11=1 ;;
        --persist-work)   PERSIST_WORK=1 ;;
        --host-network)   HOST_NET=1 ;;
        --host-dbus)      HOST_DBUS=1 ;;
        --kvm)            KVM=1 ;;
        --dry-run)        DRY_RUN=1 ;;
        --help|-h)        usage; exit 0 ;;
        --*)              sb_die "unknown option: $1 (see --help)" ;;
        *)                break ;;
    esac
    shift
done

KIT="${1:-}"; [[ -n "$KIT" ]] || { usage >&2; exit 1; }
sb_is_kit "$KIT" || sb_die "unknown kit '$KIT' (expected one of: ${KITS[*]})"
IMAGE=$(sb_image "$KIT")
podman image exists "$IMAGE" || sb_die "image $IMAGE not found - build it with: ./build.sh $KIT"

[[ -n "${2:-}" ]] || sb_die "missing <project-dir> (see --help)"
PROJECT_DIR=$(realpath -e -- "$2" 2>/dev/null) || sb_die "project directory not found: $2"
[[ -d "$PROJECT_DIR" ]] || sb_die "not a directory: $PROJECT_DIR"
shift 2
CMD=("$@"); [[ ${#CMD[@]} -gt 0 ]] || CMD=(bash)

# Allocate a TTY only for interactive use; a piped/redirected stdin (scripts, CI)
# gets -i alone so TTY-detecting tools don't hang.
TTY_FLAGS=(-i)
[[ -t 0 ]] && TTY_FLAGS=(-it)

sandbox_build_args

if [[ $DRY_RUN -eq 1 ]]; then
    printf '%q ' podman run "${TTY_FLAGS[@]}" --rm "${SANDBOX_ARGS[@]}" "$IMAGE" "${CMD[@]}"
    printf '\n'
    exit 0
fi
exec podman run "${TTY_FLAGS[@]}" --rm "${SANDBOX_ARGS[@]}" "$IMAGE" "${CMD[@]}"
