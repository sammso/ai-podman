#!/bin/bash
# Android Studio (the IDE) for the android kit, launchable to the host desktop. Ships a
# bundled JetBrains Runtime (JBR) and reuses the image's /opt/android-sdk. Extracted from
# the official tarball (self-contained), sha256-verified.
set -euo pipefail

AS_VERSION=2026.1.3.7
AS_TARBALL=android-studio-quail3-linux.tar.gz
AS_SHA256=36832122557ab73ca68dfd9bd989ddac40103ac003ca10e04c949a1f61578a67
AS_URL="https://redirector.gvt1.com/edgedl/android/studio/ide-zips/${AS_VERSION}/${AS_TARBALL}"

cd /tmp
curl -fL --retry 3 -o studio.tar.gz "$AS_URL"
echo "${AS_SHA256}  studio.tar.gz" | sha256sum -c -

tar -xzf studio.tar.gz -C /opt      # -> /opt/android-studio/
rm studio.tar.gz
chmod -R a+rX /opt/android-studio

# Launcher: prefer the current bin/studio, fall back to bin/studio.sh. Routed through
# run-detached (from ai-base) so it launches off the terminal, like the other GUI apps.
LAUNCHER=/opt/android-studio/bin/studio
[[ -x "$LAUNCHER" ]] || LAUNCHER=/opt/android-studio/bin/studio.sh
cat > /usr/local/bin/studio <<EOF
#!/bin/bash
# Android Studio. JBR/AWT needs an X server, so start the container with --gui --x11.
exec run-detached "$LAUNCHER" "\$@"
EOF
chmod +x /usr/local/bin/studio
