#!/bin/bash
# Caddy reverse proxy for the Liferay staging/live environments, on port 80 by hostname:
#   http://staging.local , http://liferay.local  -> localhost:20080 (staging)
#   http://live.local                            -> localhost:21080 (live)
#
# Commands: proxy-start / proxy-stop. Binding :80 as the unprivileged container user needs the
# container's own network namespace + the unprivileged-port sysctl (run-sandboxed adds the sysctl
# for the java kit when NOT --host-network). Browse from the in-container browser/IDE, whose
# /etc/hosts has the .local aliases (added via --add-host).
set -euo pipefail

CADDY_VERSION=2.11.4
CADDY_SHA512=8220d1f013b6f27510247b2360c9e0ca9f018feebd82515f07635318b34ff9777ccc8fd0b6e6f2486ce3a33fe389fbb7db12d05baa474f4587509fb4f5ebf1c9

cd /tmp
curl -fL --retry 3 -o caddy.tar.gz \
    "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz"
echo "${CADDY_SHA512}  caddy.tar.gz" | sha512sum -c -
tar -xzf caddy.tar.gz caddy
install -m 0755 caddy /usr/local/bin/caddy
rm -f caddy.tar.gz caddy

# Static routing config. Caddy passes the client Host header upstream by default (keeping the
# per-env cookie domains) and adds X-Forwarded-*; auto_https off keeps it plain HTTP on :80.
install -d /etc/ai-dev/liferay
cat > /etc/ai-dev/liferay/Caddyfile <<'EOF'
{
    admin off
    auto_https off
}
http://staging.local, http://liferay.local {
    reverse_proxy 127.0.0.1:20080 {
        header_up X-Forwarded-Port 80
    }
}
http://live.local {
    reverse_proxy 127.0.0.1:21080 {
        header_up X-Forwarded-Port 80
    }
}
EOF

cat > /usr/local/bin/proxy-start <<'EOF'
#!/bin/bash
# Start the Liferay reverse proxy (Caddy) on :80.
#   http://staging.local , http://liferay.local  -> localhost:20080 (staging)
#   http://live.local                            -> localhost:21080 (live)
# Binding :80 needs the container's own network — run the java sandbox WITHOUT --host-network
# (the default) and browse from the in-container browser/IDE.
set -euo pipefail
CADDYFILE=/etc/ai-dev/liferay/Caddyfile
LOG="$HOME/.local/share/liferay-proxy.log"
mkdir -p "$(dirname "$LOG")"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

if pgrep -u "$(id -u)" -x caddy >/dev/null 2>&1; then
    echo "proxy already running on :80"
    exit 0
fi

setsid -f caddy run --config "$CADDYFILE" --adapter caddyfile </dev/null >"$LOG" 2>&1
sleep 1
if pgrep -u "$(id -u)" -x caddy >/dev/null 2>&1; then
    echo "Liferay proxy on :80  ->  staging.local/liferay.local :20080 · live.local :21080"
else
    echo "proxy failed to start (see $LOG)" >&2
    echo "  :80 needs the container's own network — run java WITHOUT --host-network." >&2
    tail -n 3 "$LOG" 2>/dev/null | sed 's/^/    /' >&2 || true
    exit 1
fi
EOF

cat > /usr/local/bin/proxy-stop <<'EOF'
#!/bin/bash
set -euo pipefail
if pkill -u "$(id -u)" -x caddy; then
    echo "proxy stopped"
else
    echo "proxy not running"
fi
EOF

chmod +x /usr/local/bin/proxy-start /usr/local/bin/proxy-stop
