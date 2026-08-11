# Liferay toolchain

The canonical `liferay-*` environment scripts. `java/Containerfile` COPYs this whole
set — `liferay-common.sh` plus `liferay-env-create` / `-start` / `-stop` / `-up` /
`-down` / `-status` — into `/usr/local/bin`. That COPY runs *after*
`scripts/install-liferay-envs.sh`, so these are what actually run; the generator now
only produces `liferay-download` and the bundle resolver
(`/usr/local/lib/liferay-bundle.sh`).

The set is copied **complete**, never partially: each script resolves its siblings
with `$(dirname "$(readlink -f "$0")")`, so a partial copy would pair one version of
`liferay-up` with a different `liferay-down`. `liferay-download` and
`/usr/local/lib/liferay-bundle.sh` come from the generator and resolve normally
alongside them.

## What was wrong

`liferay-start live` printed `Tomcat started.` and exited 0 while the portal died
on `FATAL: role "liferay" does not exist`. Four independent defects:

- **`liferay-env-create` skipped DB provisioning silently.** It created the role
  and database only `if pg_isready`, otherwise printed a NOTE and still exited 0
  with "Environment ready. Start it with: liferay-start". PostgreSQL was down at
  creation time, so the env could never boot.
- **`liferay-start` verified nothing.** `startup.sh` forks and returns 0 as long
  as the JVM launches, so every portal-level failure was invisible. Its
  `pg_isready` check confirmed the *server* was up, never the role or database.
- **No already-running guard.** Re-running it launched a second JVM onto held
  ports; it died with BindException but lingered, and `liferay-stop` could not
  reap it (`shutdown.sh` only reaches the instance owning the shutdown port).
- **Elasticsearch config chosen from the product string, not the bundle.**
  `dxp ⇒ elasticsearch8` wrote an elasticsearch8 config onto a 2025.q1.24-lts
  bundle that ships only the elasticsearch7 connector. It matched nothing and was
  ignored. Compounding it, `.product` recorded the *requested* release rather
  than the installed one, because `LIFERAY_BUNDLE_TARBALL` bypasses release
  resolution.

## Design

`liferay-start` and `liferay-up` split by **authority**, not thoroughness:

|                                   | `liferay-start` | `liferay-up` |
|-----------------------------------|:---------------:|:------------:|
| already-running guard             | yes             | yes          |
| DB role/database/credential check | yes             | yes          |
| DB role/database **create**       | no              | yes          |
| start PostgreSQL                   | no              | yes          |
| kill and restart JVMs             | no              | `--restart`  |
| verify the portal actually serves | yes             | delegates    |

Checks have no consequences and are what stop `Tomcat started.` from being a lie.
Repairs are what a "start" primitive has no business doing silently. There is no
duplicated-logic hazard: `liferay-up` returns, or calls `liferay-down`, before it
ever reaches `liferay-start`, so every repeated check already passes by then.

`liferay-start` exit codes: **0** serving · **1** usage / env missing ·
**2** preflight refused, *nothing was started* · **3** started but never served.

## Port sets

`staging` → base 20, `live` → base 21.

| service            | port         | staging | live  |
|--------------------|--------------|---------|-------|
| HTTP               | `<base>080`  | 20080   | 21080 |
| Tomcat shutdown    | `<base>005`  | 20005   | 21005 |
| AJP (commented)    | `<base>009`  | 20009   | 21009 |
| Gogo shell         | `<base>311`  | 20311   | 21311 |
| Elasticsearch sidecar | `<base>201` | 20201 | 21201 |

The sidecar is in the port set because its default is a fixed 9201: without this
the second environment's sidecar dies on `Failed to bind to [::1]:9201` and that
env silently has no search.

## Search — embedded sidecar only

There is no external Elasticsearch. Every environment runs the bundle's **own embedded
Elasticsearch sidecar**, pinned to a per-env port so staging and live never collide.
`liferay-env-create` writes one config per env:

```
osgi/configs/…elasticsearch<N>.configuration.ElasticsearchConfiguration.config
    productionModeEnabled=B"false"
    sidecarHttpPort=I"<20201|21201>"
    indexNamePrefix="liferay-<env>-"
```

`<N>` is read from the connector jar the bundle actually ships (CE 7.4 → `elasticsearch7`,
DXP quarterlies → `elasticsearch8`), not from the product string — the `.config` is honoured
only when its PID names the shipped connector. If it doesn't (or there is no config), Liferay
ignores it and the sidecar falls back to its **default 9201**, which the two envs then fight
over; `report_search` flags exactly that case. `es_connector_versions` /
`es_config_versions` expose "what shipped" vs "what the config targets" so the mismatch is
detectable.

## Changes

- `liferay-common.sh` — added `env_sidecar_port`, `env_gogo_port`,
  `db_role_exists`/`db_exists`/`db_connect_ok`/`db_ensure_role`/`db_ensure_database`,
  `es_connector_versions`/`es_config_versions`, `wait_portal`, `report_search`. Most are
  hoists of logic that was duplicated between `liferay-up` and `liferay-status`. (The earlier
  external-Elasticsearch helpers — `es_up`, `es_server_major`, `es_wait_ready`,
  `es_config_file`, `es_mode`, `env_uses_external_es` — were **removed** when the kit went
  embedded-sidecar only.)
- `liferay-start` — rewritten (see above); `--no-wait` and `--timeout` added.
- `liferay-up` — uses the shared helpers; `--restart` now restarts a *healthy*
  portal too (it used to be a no-op exactly when you needed it, to pick up a
  config change); default `--timeout` 300 → 900; delegates the launch entirely.
- `liferay-status` — uses the shared helpers; always reports a search line
  (an empty config list previously printed nothing at all).
- `liferay-stop` — guards on `tomcat_pids`; its "not found" message was
  unreachable dead code (see below).
- `liferay-env-create` — **signature is now `liferay-env-create <bundle.tar.gz>
  [staging|live]`**: the bundle is a required, explicit filesystem path and comes
  first; the env name is optional and defaults to `staging` (pass `live` for the
  second environment). No `~/liferay/downloads` glob, no `[dxp|ce] [release]` args,
  no `LIFERAY_BUNDLE_TARBALL`. Product (DXP vs CE) and release are auto-detected from
  the unpacked bundle — `.liferay-version` first (grep for DXP / Community), the
  tarball filename as the fallback. Also: starts PostgreSQL and fails hard rather
  than printing a NOTE; proves the credentials it provisions; writes the embedded-sidecar
  ES config using the PID of the connector the bundle actually ships, pinned to the env's
  own port; records `.product` from `.liferay-version`; compares against the other env
  *after* unpacking so it sees real tags; `trap`-cleans a failed unpack; maps AJP 8009 into
  the port set; `portal-ext.properties` is 600 (it holds the DB password).

### The `set -euo pipefail` glob bug

`TOMCAT_DIR=$(ls -d "$ENV_DIR"/tomcat* | head -1)` appeared in `liferay-start`,
`liferay-stop` and `liferay-env-create`. A non-matching glob makes `ls` exit 2,
`pipefail` fails the pipeline, and `set -e` kills the script *at the assignment* —
so `liferay-stop staging` died silently with status 2 and its own "not found"
message on the next line was unreachable. `tomcat_dir` now ends in `|| true` and
returns empty, and callers guard explicitly. `log_excerpt`/`log_paths` had the
same shape, which broke them exactly when a diagnostic was most needed.
