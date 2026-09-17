#!/bin/bash
# PostgreSQL server + MinIO (server and mc client) for the Liferay box.
#
# No systemd in the container, so both run as the invoking user with data under
# $HOME (persists under /work with --persist-work). Wrapper commands:
#   pg-start / pg-stop        data in ~/.local/share/postgres, port 5432
#   minio-start / minio-stop  data in ~/.local/share/minio, ports 9000/9001
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- PostgreSQL ---
apt-get update
apt-get install -y --no-install-recommends postgresql postgresql-contrib
apt-get clean
rm -rf /var/lib/apt/lists/*

# Drop the cluster the apt package auto-creates: it lives in the container layer
# (not persistent) and is owned by the postgres system user. Boxes use a per-user
# cluster in $HOME instead (see pg-start).
while read -r ver name _; do
    pg_dropcluster --stop "$ver" "$name" || true
done < <(pg_lsclusters -h)

cat > /usr/local/bin/pg-start <<'EOF'
#!/bin/bash
# Start a user-owned PostgreSQL with data in ~/.local/share/postgres.
# Connect with: psql -h localhost   (JDBC: jdbc:postgresql://localhost:5432/<db>)
set -euo pipefail
PG_BIN=$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)
PGDATA="${PGDATA:-$HOME/.local/share/postgres}"
if [[ ! -f "$PGDATA/PG_VERSION" ]]; then
    mkdir -p "$PGDATA"
    "$PG_BIN/initdb" -D "$PGDATA" --auth=trust --username="$USER"
fi
# /var/run/postgresql is not writable by this user; keep the socket in /tmp
exec_ok=$("$PG_BIN/pg_ctl" -D "$PGDATA" status >/dev/null 2>&1 && echo yes || echo no)
if [[ "$exec_ok" == yes ]]; then
    echo "PostgreSQL already running (data: $PGDATA)"
else
    "$PG_BIN/pg_ctl" -D "$PGDATA" -l "$PGDATA/server.log" \
        -o "-c unix_socket_directories=/tmp" start
    echo "PostgreSQL started on localhost:5432 (data: $PGDATA)"
fi
EOF

cat > /usr/local/bin/pg-stop <<'EOF'
#!/bin/bash
set -euo pipefail
PG_BIN=$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)
PGDATA="${PGDATA:-$HOME/.local/share/postgres}"
"$PG_BIN/pg_ctl" -D "$PGDATA" stop
EOF

# --- MinIO server + mc client ---
# dl.min.io (the old rolling-"latest" download CDN) was retired and now returns HTTP 410, so pull
# pinned, sha256-verified binaries from the GitHub release assets instead. Bump by refetching the
# newest *binary* release tag and its .sha256sum (skip metadata-only "Security/CVE" releases):
#   https://github.com/minio/minio/releases   and   https://github.com/minio/mc/releases
MINIO_VERSION=RELEASE.2025-09-07T16-13-09Z
MINIO_SHA256=7c5bd8512c6e966455b1d198209358b2d191c77a83ab377c4073281065fb855f
MC_VERSION=RELEASE.2025-08-13T08-35-41Z
MC_SHA256=01f866e9c5f9b87c2b09116fa5d7c06695b106242d829a8bb32990c00312e891

curl -fL --retry 3 --retry-all-errors -o /usr/local/bin/minio \
    "https://github.com/minio/minio/releases/download/${MINIO_VERSION}/minio.linux-amd64.${MINIO_VERSION}"
echo "${MINIO_SHA256}  /usr/local/bin/minio" | sha256sum -c -
curl -fL --retry 3 --retry-all-errors -o /usr/local/bin/mc \
    "https://github.com/minio/mc/releases/download/${MC_VERSION}/mc.linux-amd64.${MC_VERSION}"
echo "${MC_SHA256}  /usr/local/bin/mc" | sha256sum -c -
chmod +x /usr/local/bin/minio /usr/local/bin/mc

cat > /usr/local/bin/minio-start <<'EOF'
#!/bin/bash
# Start MinIO in the background: S3 API on :9000, web console on :9001.
# Default credentials minioadmin/minioadmin (override with MINIO_ROOT_USER/PASSWORD).
set -euo pipefail
MINIO_DATA="${MINIO_DATA:-$HOME/.local/share/minio}"
mkdir -p "$MINIO_DATA"
if pgrep -x minio >/dev/null; then
    echo "MinIO already running (data: $MINIO_DATA)"
    exit 0
fi
nohup minio server "$MINIO_DATA" --console-address :9001 \
    >> "$MINIO_DATA/server.log" 2>&1 &
echo "MinIO started: S3 http://localhost:9000, console http://localhost:9001 (data: $MINIO_DATA)"
EOF

cat > /usr/local/bin/minio-stop <<'EOF'
#!/bin/bash
pkill -x minio && echo "MinIO stopped" || echo "MinIO was not running"
EOF

chmod +x /usr/local/bin/pg-start /usr/local/bin/pg-stop \
         /usr/local/bin/minio-start /usr/local/bin/minio-stop
