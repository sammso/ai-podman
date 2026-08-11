#!/bin/bash
# Liferay bundle plumbing for the java image: the shared bundle resolver
# (/usr/local/lib/liferay-bundle.sh) and the `liferay-download` command, which fetches a
# bundle .tar.gz into ~/liferay/downloads.
#
# The environment lifecycle commands (liferay-env-create / -start / -stop / -up / -down /
# -status) are NOT generated here — they are the canonical scripts in java/scripts/, COPYed
# into /usr/local/bin by java/Containerfile (that COPY runs after this script, so it wins).
set -euo pipefail

# --- shared bundle resolver (sourced by liferay-download) ---
install -d /usr/local/lib
cat > /usr/local/lib/liferay-bundle.sh <<'EOF'
#!/bin/bash
# Liferay bundle resolver — single source of truth for product/release -> filename/URL.
DEFAULT_DXP_RELEASE=2026.q2.11
CE_RELEASE=7.4.3.132-ga132
CE_BUNDLE_URL=https://releases-cdn.liferay.com/portal/7.4.3.132-ga132/liferay-portal-tomcat-7.4.3.132-ga132-1739912568.tar.gz

# liferay_norm <product> <release> -> echoes "<product> <release>" (validated/defaulted)
liferay_norm() {
    local product="${1:-dxp}" release="${2:-}"
    case "$product" in
        dxp) release="${release:-$DEFAULT_DXP_RELEASE}" ;;
        ce)  [[ -z "$release" ]] || { echo "release override is only supported for dxp" >&2; return 2; }
             release="$CE_RELEASE" ;;
        *)   echo "product must be 'dxp' or 'ce'" >&2; return 2 ;;
    esac
    printf '%s %s' "$product" "$release"
}

# liferay_bundle_glob <product> <release> -> local tarball filename pattern
liferay_bundle_glob() {
    case "$1" in
        dxp) printf 'liferay-dxp-tomcat-%s-*.tar.gz' "$2" ;;
        ce)  printf 'liferay-portal-tomcat-%s-*.tar.gz' "$2" ;;
    esac
}

# liferay_bundle_url <product> <release> -> download URL (honors $LIFERAY_BUNDLE_URL)
liferay_bundle_url() {
    if [[ -n "${LIFERAY_BUNDLE_URL:-}" ]]; then printf '%s' "$LIFERAY_BUNDLE_URL"; return; fi
    local product="$1" release="$2" name
    case "$product" in
        dxp)
            name=$(curl -fsSL "https://releases-cdn.liferay.com/dxp/${release}/" \
                | grep -oE 'liferay-dxp-tomcat-[^"<]*\.tar\.gz' | sort -u | head -1)
            [[ -n "$name" ]] || { echo "could not find a DXP tomcat bundle for release '${release}'" >&2; return 1; }
            printf 'https://releases-cdn.liferay.com/dxp/%s/%s' "$release" "$name" ;;
        ce) printf '%s' "$CE_BUNDLE_URL" ;;
    esac
}
EOF

# --- liferay-download: fetch a bundle .tar.gz from the repository into ~/liferay/downloads ---
cat > /usr/local/bin/liferay-download <<'EOF'
#!/bin/bash
# Download a Liferay bundle into ~/liferay/downloads and print its path; pass that path to
# liferay-env-create. Usage: liferay-download [dxp|ce] [release]   (default: dxp <pinned release>)
set -euo pipefail
source /usr/local/lib/liferay-bundle.sh
NORM=$(liferay_norm "${1:-dxp}" "${2:-}") || exit 2
read -r PRODUCT RELEASE <<<"$NORM"
DL_DIR="$HOME/liferay/downloads"; mkdir -p "$DL_DIR"
existing=$(ls -t "$DL_DIR"/$(liferay_bundle_glob "$PRODUCT" "$RELEASE") 2>/dev/null | head -1 || true)
if [[ -n "$existing" ]]; then echo "already downloaded: $existing"; exit 0; fi
URL=$(liferay_bundle_url "$PRODUCT" "$RELEASE")
OUT="$DL_DIR/$(basename "$URL")"
echo "Downloading $PRODUCT $RELEASE ..."
curl -fL --progress-bar -o "$OUT.part" "$URL"
mv "$OUT.part" "$OUT"
echo "$OUT"
EOF

chmod +x /usr/local/bin/liferay-download
