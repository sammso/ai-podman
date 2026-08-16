#!/bin/bash
# JetBrains WebStorm, launchable to the host desktop. Ships a bundled JetBrains Runtime (JBR);
# extracted from the official tarball, sha256-verified. JBR/AWT needs an X server, so run the
# container with --gui --x11.
set -euo pipefail

WS_VERSION=2026.2.1
WS_SHA256=bb0e2e345473bfa7c6645f20761a91a6fc7170598f944998e7d948d045d52b23
WS_URL="https://download.jetbrains.com/webstorm/WebStorm-${WS_VERSION}.tar.gz"

cd /tmp
curl -fL --retry 3 -o webstorm.tar.gz "$WS_URL"
echo "${WS_SHA256}  webstorm.tar.gz" | sha256sum -c -

install -d /opt/webstorm
tar -xzf webstorm.tar.gz -C /opt/webstorm --strip-components=1   # -> /opt/webstorm/{bin,jbr,...}
rm webstorm.tar.gz
chmod -R a+rX /opt/webstorm

LAUNCHER=/opt/webstorm/bin/webstorm
[[ -x "$LAUNCHER" ]] || LAUNCHER=/opt/webstorm/bin/webstorm.sh
cat > /usr/local/bin/webstorm <<EOF
#!/bin/bash
# JetBrains WebStorm. JBR/AWT needs an X server, so start the container with --gui --x11.
exec run-detached "$LAUNCHER" "\$@"
EOF
chmod +x /usr/local/bin/webstorm
