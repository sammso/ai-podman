#!/bin/bash
# Temurin JDK 17 / 21 / 25 from the Adoptium apt repo, plus SDKMAN (system-wide in
# /opt/sdkman) with the apt JDKs registered as local candidates so `sdk use java X-tem`
# switches between them at runtime.
#
# SDKMAN must NOT live under $HOME: --persist-work repoints HOME to /work, so
# anything the image bakes into /root or /home is out of reach at runtime.
#
# Usage: install-jdks.sh [default-major]   (default-major: 17|21|25, default 21)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

DEFAULT_MAJOR="${1:-21}"

# --- Temurin JDKs via Adoptium apt repo ---
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg
echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb noble main" \
    > /etc/apt/sources.list.d/adoptium.list

apt-get update
apt-get install -y --no-install-recommends temurin-17-jdk temurin-21-jdk temurin-25-jdk
apt-get clean
rm -rf /var/lib/apt/lists/*

# --- SDKMAN, system-wide (retry: the CDN occasionally answers 503) ---
export SDKMAN_DIR=/opt/sdkman
for attempt in 1 2 3 4 5; do
    if curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash; then
        break
    fi
    [[ $attempt -eq 5 ]] && { echo "SDKMAN install failed after 5 attempts" >&2; exit 1; }
    echo "SDKMAN install failed (attempt $attempt), retrying in $((attempt * 15))s..." >&2
    rm -rf "${SDKMAN_DIR}"
    sleep $((attempt * 15))
done
# Non-interactive: auto-answer prompts (e.g. "set as default? (Y/n)")
sed -i 's/^sdkman_auto_answer=.*/sdkman_auto_answer=true/' "${SDKMAN_DIR}/etc/config"
set +u
source "${SDKMAN_DIR}/bin/sdkman-init.sh"

# Register the apt-installed JDKs as SDKMAN local candidates.
# The name must NOT collide with a remote identifier (e.g. "21-tem" IS a remote
# version — the stale 21 GA — and SDKMAN would download it instead of linking).
for major in 17 21 25; do
    sdk install java "${major}-sys" "/usr/lib/jvm/temurin-${major}-jdk-amd64"
    [[ -L "${SDKMAN_DIR}/candidates/java/${major}-sys" ]] \
        || { echo "java ${major}-sys was not registered as a local symlink" >&2; exit 1; }
done
sdk default java "${DEFAULT_MAJOR}-sys"
set -u

# Make SDKMAN available to every shell (system-wide, independent of $HOME)
cat > /etc/profile.d/sdkman.sh <<'EOF'
export SDKMAN_DIR=/opt/sdkman
[[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]] && source "${SDKMAN_DIR}/bin/sdkman-init.sh"
EOF
cat >> /etc/bash.bashrc <<'EOF'

# SDKMAN (system-wide)
export SDKMAN_DIR=/opt/sdkman
[[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]] && source "${SDKMAN_DIR}/bin/sdkman-init.sh"
EOF

# Any user may switch defaults / install more candidates
chmod -R a+rwX /opt/sdkman
