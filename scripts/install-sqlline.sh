#!/bin/bash
# SQLLine — a JVM/JDBC command-line SQL client — plus the PostgreSQL JDBC driver, wired to
# the image's PostgreSQL (pg-start). Fat jar + driver in /opt/sqlline; `sqlline` runs it and
# `pg-sql [db]` opens a shell on the local database.
set -euo pipefail

SQLLINE_VERSION=1.12.0
PGJDBC_VERSION=42.7.13
MC=https://repo1.maven.org/maven2

install -d /opt/sqlline
cd /opt/sqlline

# Download each jar and verify it against its Maven .sha1.
fetch() {
    local url="$1" out="$2" want
    curl -fsSL -o "$out" "$url"
    want=$(curl -fsSL "${url}.sha1") || { echo "no .sha1 for $url" >&2; exit 1; }
    echo "${want}  ${out}" | sha1sum -c -
}
fetch "${MC}/sqlline/sqlline/${SQLLINE_VERSION}/sqlline-${SQLLINE_VERSION}-jar-with-dependencies.jar" sqlline.jar
fetch "${MC}/org/postgresql/postgresql/${PGJDBC_VERSION}/postgresql-${PGJDBC_VERSION}.jar" postgresql.jar

# sqlline: both jars on the classpath; the pg driver auto-registers via ServiceLoader.
cat > /usr/local/bin/sqlline <<'EOF'
#!/bin/bash
exec java -cp "/opt/sqlline/*" sqlline.SqlLine "$@"
EOF

# pg-sql [db]: connect to the running local PostgreSQL (trust auth, superuser = $USER).
cat > /usr/local/bin/pg-sql <<'EOF'
#!/bin/bash
# Open a SQLLine shell on the local PostgreSQL. Usage: pg-sql [database]  (default: postgres)
if ! pg_isready -h localhost -q 2>/dev/null; then
    echo "PostgreSQL is not running - start it with: pg-start" >&2
    exit 1
fi
exec sqlline -u "jdbc:postgresql://localhost:5432/${1:-postgres}" -n "$USER" -p ""
EOF

chmod +x /usr/local/bin/sqlline /usr/local/bin/pg-sql
