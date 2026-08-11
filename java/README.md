# ai-java

Java / Liferay development kit. Part of [AI Development Containers](../README.md); shared run
model, persistence and GUI plumbing live in [docs/TECHNICAL.md](../docs/TECHNICAL.md). Builds
`FROM localhost/ai-base`, so all of base's tools ([AI CLIs, GUI apps, …](../base/README.md)) are
here too. Run **`tools`** inside the container to list its commands.

## Technical

- `FROM localhost/ai-base`; adds Temurin **JDK 17/21/25** via SDKMAN (`/opt/sdkman`, default 21),
  Gradle and Maven, and the **Blade CLI** (a system-wide `/opt/blade/blade.jar` + `blade`
  wrapper). SDKMAN's JDKs register as `17/21/25-sys` (the apt-installed Temurin builds).
- **IntelliJ IDEA Ultimate** under `/opt`; **PostgreSQL** and **MinIO** run as the container
  user with data under `$HOME`; **SQLLine** (JDBC client) + the Postgres JDBC driver.
- The **Liferay command set** (`liferay-common.sh`, `liferay-env-create`, `liferay-start`,
  `liferay-stop`, `liferay-up`, `liferay-down`, `liferay-status`) is baked into `/usr/local/bin`
  by `java/Containerfile`. The build helper `scripts/install-liferay-envs.sh` only generates
  `liferay-download` + the shared bundle resolver (`/usr/local/lib/liferay-bundle.sh`); the
  Containerfile COPYs the canonical scripts over the top. Their internals (design, exit codes,
  port sets) are documented in **[scripts/README.md](scripts/README.md)**.
- **Search is Liferay's own embedded Elasticsearch sidecar** — each environment boots its own on
  a per-env port (staging 20201, live 21201). There is no standalone Elasticsearch service.

## JDK selection

```bash
sdk use java 25-sys        # switch JDK for this shell
sdk default java 17-sys    # persist the default
```

## IntelliJ IDEA Ultimate

Launch with `idea` (open the project on `/work`). It needs a JetBrains subscription (30-day
trial otherwise); add the Liferay plugin from the IDE Marketplace. Its JBR uses X11, so a
**named** java sandbox (`connect-sandboxed.sh`) already gets `--gui --x11` automatically; for
one-shot use run `run-sandboxed.sh --gui --x11 --persist-work java ~/proj idea`.

## Databases: PostgreSQL, MinIO, SQLLine

```bash
podman/run-sandboxed.sh --persist-work --host-network java ~/projects/portal
# inside the container:
pg-start        # PostgreSQL  :5432   data in /work/.local/share/postgres
minio-start     # MinIO S3 :9000 / console :9001 (minioadmin/minioadmin)
pg-sql lportal  # SQLLine (JDBC) shell on the local DB
```

- `pg-sql [db]` opens a **SQLLine** JDBC shell on the running PostgreSQL (`\q`/`!quit` to exit);
  raw form: `sqlline -u jdbc:postgresql://localhost:5432/<db> -n ubuntu`.
- With `--persist-work` everything lives under `<project>/` and survives the run; `--host-network`
  makes the services reachable from the host at `localhost:<port>`.

## Liferay: services and remote publishing

Liferay connects as DB user **`liferay`** / password **`admin`** (each `lportal_<env>` DB is
owned by that role). Override with `LIFERAY_DB_USER` / `LIFERAY_DB_PASSWORD` before
`liferay-env-create`. Local PostgreSQL is trust-auth, so the password isn't enforced for
localhost connections; connect as this user with
`sqlline -u jdbc:postgresql://localhost:5432/<db> -n liferay -p admin`.

### Remote publishing (staging → live)

Two Liferay environments run side by side on distinct port sets:

| Env     | HTTP  | Shutdown | SSL redirect | Gogo shell | ES sidecar | Database          |
|---------|-------|----------|--------------|------------|------------|-------------------|
| staging | 20080 | 20005    | 20443        | 20311      | 20201      | `lportal_staging` |
| live    | 21080 | 21005    | 21443        | 21311      | 21201      | `lportal_live`    |

```bash
BUNDLE=$(liferay-download dxp)          # fetch the bundle .tar.gz, prints its path (once)
liferay-env-create "$BUNDLE"            # install staging (default env) FROM that tarball
liferay-env-create "$BUNDLE" live       # install live from the same tarball
liferay-up staging                      # http://localhost:20080  (test@liferay.com / test)
liferay-up live                         # http://localhost:21080
liferay-status                          # health of both envs + PostgreSQL
liferay-down staging                    # stop (reliably; force-kills a stuck JVM)
```

**Lifecycle commands.** `liferay-up <env>` is the recommended start — it brings up PostgreSQL if
needed, creates/repairs the DB role & database, and waits until the portal actually serves HTTP
(add `--restart` to recycle a wedged instance, `--timeout N` to change the boot wait). Search
needs no separate step — Liferay boots its embedded Elasticsearch sidecar itself. `liferay-down
<env>` stops it reliably; `liferay-status [env]` is a read-only health report. These wrap the
low-level `liferay-start`/`liferay-stop` (which just call Tomcat's start/shutdown), and
`pg-start` still works standalone.

**Download vs install.** `liferay-download [dxp|ce] [release]` is the only step that hits the
repository — it caches the bundle in `~/liferay/downloads` and prints the tarball path.
`liferay-env-create <path-to-bundle.tar.gz> [staging|live]` then **installs from that explicit
path** (it never downloads and never guesses a directory). The env name is optional and defaults
to **staging** — pass `live` for the second environment. Give it any tarball — a
`liferay-download` result, or your own custom/offline build from anywhere on the filesystem.

**Product is detected, not selected** — `liferay-env-create` reads the product (DXP vs CE) and
release straight off the unpacked bundle (`.liferay-version`, with the filename as a fallback),
so there is no product/release argument. `liferay-download [dxp|ce] [release]` still chooses what
to *fetch*:

- Default download is **DXP** (EE) at a pinned quarterly release (`2026.q2.11`; bump
  `DEFAULT_DXP_RELEASE` in `scripts/install-liferay-envs.sh` to move). A release override is the
  third argument, e.g. `liferay-download dxp 2026.q1.5`.
- `liferay-download ce` fetches Portal CE 7.4 GA132.
- `LIFERAY_BUNDLE_URL` overrides the download URL.
- Both environments must be the **same product+release** for remote publishing — env-create
  warns if they differ (tracked in `<project>/liferay/<env>/.product`).

**DXP activation key (EE subscription):** download the key XML from
[support.liferay.com](https://support.liferay.com) (Account → Activation Keys) into
`<project>/liferay/licenses/` once — env-create copies every XML there into the new env's
`deploy/` folder automatically (also hot-deployable into `<project>/liferay/<env>/deploy/` while
running).

Bundles live under `<project>/liferay/<env>` and survive the run. Both environments share
`<project>/liferay/tunnel-secret` (`tunneling.servlet.shared.secret`), so remote publishing works
out of the box: in staging, enable staging for the site under **Publishing → Staging → Remote
Live** with host `localhost`, port `21080`, and the live site's ID. Note: two Liferays need
~5–6 GB free RAM.

---

For the design and internals of the `liferay-*` scripts (authority split, exit codes, port sets,
the embedded-sidecar configuration), see **[scripts/README.md](scripts/README.md)**.
