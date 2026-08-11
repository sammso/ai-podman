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
curl -fsSL -o /usr/local/bin/minio https://dl.min.io/server/minio/release/linux-amd64/minio
curl -fsSL -o /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc
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
