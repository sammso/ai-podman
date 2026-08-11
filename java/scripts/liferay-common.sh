#!/bin/bash
# Shared helpers for liferay-up / liferay-down / liferay-status.
# Sourced, not executed — defines functions only, no side effects.

LIFERAY_HOME_DIR="${LIFERAY_HOME_DIR:-$HOME/liferay}"

# --- output ------------------------------------------------------------------
say_ok()   { printf '\xe2\x9c\x93 %s\n' "$*"; }
say_warn() { printf '! %s\n' "$*"; }
say_err()  { printf '\xe2\x9c\x97 %s\n' "$*" >&2; }
say_run()  { printf '\xe2\x86\x92 %s\n' "$*"; }

# --- environment layout ------------------------------------------------------
# Port set matches liferay-env-create: staging -> 20, live -> 21.
# HTTP <base>080, shutdown <base>005, Gogo <base>311, ES sidecar <base>201.
# The sidecar belongs in the port set for the same reason the others do: its
# default is a fixed 9201, so a second environment falling back to its own
# sidecar dies with "Failed to bind to [::1]:9201" and silently loses search.
env_base() {
    case "$1" in
        staging) printf '20' ;;
        live)    printf '21' ;;
        *) echo "env must be 'staging' or 'live' (got '$1')" >&2; return 1 ;;
    esac
}

env_dir()   { printf '%s/%s' "$LIFERAY_HOME_DIR" "$1"; }
env_port()  { printf '%s080' "$(env_base "$1")"; }
env_shutdown_port() { printf '%s005' "$(env_base "$1")"; }
env_gogo_port()     { printf '%s311' "$(env_base "$1")"; }
env_sidecar_port()  { printf '%s201' "$(env_base "$1")"; }
env_url()   { printf 'http://localhost:%s' "$(env_port "$1")"; }

# Empty output (not a non-zero exit) when the env has no tomcat dir. Callers run
# under `set -e`, so `d=$(tomcat_dir x)` must never fail the assignment: a
# non-matching glob makes `ls` exit 2, pipefail propagates it, and the caller
# dies *at the assignment* before it can print its own error. Hence `|| true`.
tomcat_dir() {
    local d; d=$(env_dir "$1")
    ls -d "$d"/tomcat* 2>/dev/null | head -1 || true
}

# --- process discovery -------------------------------------------------------
# PIDs of Tomcat JVMs for this env.
#
# Deliberately NOT `pgrep -f` on the marker: the marker string appears in the
# command line of the very shell doing the matching, so pgrep returns our own
# PID and a kill loop takes out its own shell. Exclude $$/$PPID and require the
# process to actually be a java one.
tomcat_pids() {
    local tdir marker
    tdir=$(tomcat_dir "$1") || return 0
    [[ -n "$tdir" ]] || return 0
    marker="catalina.base=$tdir"

    ps -eo pid=,args= | while read -r pid args; do
        [[ "$pid" == "$$" || "$pid" == "$PPID" ]] && continue
        [[ "$args" == *"$marker"* ]] || continue
        [[ "$args" == *java* ]] || continue
        printf '%s\n' "$pid"
    done
}

pid_uptime() { ps -o etime= -p "$1" 2>/dev/null | tr -d ' '; }

# True if anything is listening on the given localhost port.
port_in_use() {
    (exec 3<>"/dev/tcp/localhost/$1") 2>/dev/null && { exec 3<&- 3>&-; return 0; }
    return 1
}

# --- health ------------------------------------------------------------------
# HTTP status from the portal root, or 000 when nothing answers.
portal_code() {
    curl -s -o /dev/null -w '%{http_code}' -m 5 "$(env_url "$1")/" 2>/dev/null || printf '000'
}

# A booted portal answers 200 or 302 (redirect to the guest site or to license
# activation). A Tomcat whose portal context failed answers 404/503 — which is
# what makes "running" distinguishable from "running but broken".
portal_serving() {
    case "$(portal_code "$1")" in 200|302) return 0 ;; *) return 1 ;; esac
}

# Recent error lines from both the Tomcat and the portal log.
log_excerpt() {
    local env_name="$1" lines="${2:-6}" d tdir cat_out portal_log
    d=$(env_dir "$env_name")
    tdir=$(tomcat_dir "$env_name")
    cat_out="${tdir:-/nonexistent}/logs/catalina.out"
    portal_log=$(ls -t "$d"/logs/liferay.*.log 2>/dev/null | head -1 || true)

    if [[ -f "$portal_log" ]]; then
        grep -hE 'ERROR|SEVERE|FATAL|Caused by' "$portal_log" 2>/dev/null \
            | tail -n "$lines" | sed 's/^/    /'
    fi
    if [[ -f "$cat_out" ]]; then
        tail -300 "$cat_out" 2>/dev/null \
            | grep -hE 'SEVERE|ERROR|FATAL|Caused by' \
            | tail -n "$lines" | sed 's/^/    /'
    fi
}

log_paths() {
    local d tdir; d=$(env_dir "$1"); tdir=$(tomcat_dir "$1")
    [[ -n "$tdir" ]] && printf '  logs: %s/logs/catalina.out\n' "$tdir"
    printf '        %s/logs/\n' "$d"
}

# --- database ----------------------------------------------------------------
# Read the JDBC settings the env actually uses rather than assuming defaults,
# so this stays correct if the env is recreated with LIFERAY_DB_* overrides.
prop_value() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 1
    grep -E "^${key}=" "$file" | tail -1 | cut -d= -f2-
}

# Sets DB_USER / DB_PASS / DB_NAME / DB_URL for the env. Returns 1 if the env
# is not pointed at a local PostgreSQL (in which case we do not touch it).
load_db_config() {
    local env_name="$1" props
    props="$(env_dir "$env_name")/portal-ext.properties"

    DB_URL=$(prop_value "$props" 'jdbc\.default\.url') || return 1
    DB_USER=$(prop_value "$props" 'jdbc\.default\.username') || return 1
    DB_PASS=$(prop_value "$props" 'jdbc\.default\.password') || true

    [[ "$DB_URL" == jdbc:postgresql://localhost:*/* ]] || return 1
    DB_NAME="${DB_URL##*/}"
    DB_NAME="${DB_NAME%%\?*}"
    [[ -n "$DB_USER" && -n "$DB_NAME" ]]
}

pg_up()   { pg_isready -h localhost -q 2>/dev/null; }

# Role / database predicates and their provisioning counterparts. The read-only
# ones are safe everywhere; only liferay-up and liferay-env-create may call the
# db_ensure_* pair, so that a "start" command never silently creates state.
# All of these need load_db_config to have been called first.
db_role_exists() {
    [[ -n "$(psql -h localhost -d postgres -tAc \
        "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" 2>/dev/null)" ]]
}

db_exists() {
    [[ -n "$(psql -h localhost -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null)" ]]
}

# Prove the credentials Liferay will actually use, rather than inferring from
# the catalog: a role and database that exist can still fail to connect.
db_connect_ok() {
    PGPASSWORD="$DB_PASS" psql -h localhost -U "$DB_USER" -d "$DB_NAME" \
        -tAc 'SELECT 1' >/dev/null 2>&1
}

db_connect_error() {
    PGPASSWORD="$DB_PASS" psql -h localhost -U "$DB_USER" -d "$DB_NAME" \
        -tAc 'SELECT 1' 2>&1 || true
}

db_ensure_role() {
    if db_role_exists; then
        say_ok "role '$DB_USER' exists"
    else
        say_warn "role '$DB_USER' missing — creating"
        psql -h localhost -d postgres -qc \
            "CREATE ROLE \"$DB_USER\" LOGIN PASSWORD '$DB_PASS'"
    fi
}

db_ensure_database() {
    if db_exists; then
        say_ok "database '$DB_NAME' exists"
    else
        say_warn "database '$DB_NAME' missing — creating"
        createdb -h localhost -O "$DB_USER" "$DB_NAME"
        psql -h localhost -d postgres -qc \
            "GRANT ALL ON DATABASE \"$DB_NAME\" TO \"$DB_USER\"" || true
    fi
}

# --- search ------------------------------------------------------------------
# Every env runs the bundle's OWN embedded Elasticsearch sidecar; there is no
# external Elasticsearch. liferay-env-create writes an osgi .config that pins the
# sidecar to a per-env port (env_sidecar_port), but the .config only takes effect
# when its PID names the connector the bundle actually ships — otherwise Liferay
# ignores it and the sidecar falls back to the default 9201, colliding with the
# other env. These two helpers expose "what shipped" vs "what the config targets"
# so that mismatch is detectable.
#
# find (not ls+glob) so a no-match is empty output rather than a pipefail exit.

# Connector versions the bundle actually ships, e.g. "7".
es_connector_versions() {
    find "$(env_dir "$1")/osgi" -maxdepth 2 \
        -name 'com.liferay.portal.search.elasticsearch*.impl.jar' 2>/dev/null \
        | sed -n 's/.*elasticsearch\([0-9]\+\)\.impl\.jar$/\1/p' | sort -u
}

# Connector versions the env is configured for, e.g. "8".
es_config_versions() {
    find "$(env_dir "$1")/osgi/configs" -maxdepth 1 \
        -name '*ElasticsearchConfiguration.config' 2>/dev/null \
        | sed -n 's/.*elasticsearch\([0-9]\+\)\.configuration.*/\1/p' | sort -u
}

# --- boot ---------------------------------------------------------------------
# Poll until the portal serves, or the JVM dies, or the timeout expires.
# Single implementation of "is it actually up" — liferay-start calls this and
# liferay-up just propagates liferay-start's exit code.
#   0 = serving   1 = JVM exited   2 = timed out
wait_portal() {
    local env_name="$1" timeout="${2:-900}" start_ts=$SECONDS pids
    printf '  waiting for %s ' "$(env_url "$env_name")"
    while ((SECONDS - start_ts < timeout)); do
        if portal_serving "$env_name"; then
            echo
            say_ok "Liferay '$env_name' is up (HTTP $(portal_code "$env_name")) in $((SECONDS - start_ts))s"
            printf '  %s\n' "$(env_url "$env_name")"
            return 0
        fi
        # A JVM that has already exited will never serve — fail fast rather than
        # burning the full timeout.
        mapfile -t pids < <(tomcat_pids "$env_name")
        if ((${#pids[@]} == 0)); then
            echo
            say_err "Tomcat for '$env_name' exited during startup"
            return 1
        fi
        printf '.'; sleep 5
    done
    echo
    say_err "Liferay '$env_name' failed to boot after ${timeout}s (HTTP $(portal_code "$env_name"))"
    return 2
}

# The search line shared by liferay-up and liferay-status. Every env uses its own
# embedded sidecar; the only failure worth flagging is a config whose PID does not
# match the shipped connector — then the .config is inert, the sidecar defaults to
# 9201, and the two envs collide. Prints something in every case.
report_search() {
    local env_name="$1" cfg jar port
    mapfile -t cfg < <(es_config_versions "$env_name")
    mapfile -t jar < <(es_connector_versions "$env_name")
    port=$(env_sidecar_port "$env_name")

    if ((${#cfg[@]} == 0)); then
        say_warn "search  no sidecar config — Elasticsearch defaults to 9201, which collides with the other environment"
        say_warn "        recreate the env so the sidecar gets its own port ($port)"
    elif [[ " ${jar[*]} " == *" ${cfg[0]} "* ]]; then
        if port_in_use "$port"; then
            say_ok "search  embedded elasticsearch${cfg[0]} sidecar on $port"
        else
            say_warn "search  embedded elasticsearch${cfg[0]} sidecar on $port (not up yet)"
        fi
    else
        say_warn "search  config targets elasticsearch${cfg[0]} but bundle ships ${jar[*]:-none} — config inert, sidecar defaulting to 9201"
        say_warn "        recreate the env so the sidecar gets its own port ($port); 9201 collides with the other environment"
    fi
}
