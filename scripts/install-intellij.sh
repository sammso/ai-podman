#!/bin/bash
# IntelliJ IDEA Ultimate for Liferay/Java development, launchable to the host desktop. Ships
# a bundled JetBrains Runtime (JBR); extracted from the official tarball, sha256-verified.
# JBR/AWT needs an X server, so run the container with --gui --x11.
set -euo pipefail

IDEA_VERSION=2026.2.1
IDEA_SHA256=dac2021204c8bf3bd8d66567a1ae36a341da0050b6006c32d42006c6577eb29a
IDEA_URL="https://download.jetbrains.com/idea/idea-${IDEA_VERSION}.tar.gz"

cd /tmp
curl -fL --retry 3 -o idea.tar.gz "$IDEA_URL"
echo "${IDEA_SHA256}  idea.tar.gz" | sha256sum -c -

install -d /opt/intellij
tar -xzf idea.tar.gz -C /opt/intellij --strip-components=1   # -> /opt/intellij/{bin,jbr,...}
rm idea.tar.gz
chmod -R a+rX /opt/intellij

LAUNCHER=/opt/intellij/bin/idea
[[ -x "$LAUNCHER" ]] || LAUNCHER=/opt/intellij/bin/idea.sh
cat > /usr/local/bin/idea <<EOF
#!/bin/bash
# IntelliJ IDEA. JBR/AWT needs an X server, so start the container with --gui --x11.
exec run-detached "$LAUNCHER" "\$@"
EOF
chmod +x /usr/local/bin/idea
