# Technical documentation

Common architecture and shared tooling for the AI Development Containers. Container-specific
tools and how-to live in each kit's own README ([base](../base/README.md),
[java](../java/README.md), [dev](../dev/README.md), [android](../android/README.md)); this
document covers everything they share. Start at the [project README](../README.md).

## Image inheritance

One base image carries the AI coding CLIs, GUI apps, terminal wiring and Node LTS. Every
dev-kit image builds **on top of it**, so those tools exist everywhere and are maintained in
one place.

```
ubuntu:24.04
    └── localhost/ai-base          AI CLIs, Claude Desktop, Chrome, Meld, Lite XL, WezTerm,
            │                       rtk, agent-browser, Node 22 LTS, git, build tools, terminal
            ├── localhost/ai-java       + JDK 17/21/25, Gradle, Maven, Blade, IntelliJ,
            │                             PostgreSQL, MinIO, SQLLine, Liferay stack
            ├── localhost/ai-dev        + JDK 17/21/25 (default 21)
            ├── localhost/ai-android    + Android Studio, Android SDK + emulator, Flutter
            └── localhost/ai-node       + fnm (switchable Node), VS Code, WebStorm
```

Each `FROM localhost/ai-base:latest`; base is `FROM ubuntu:24.04`. Because the kits share a
base, `build.sh` builds **base first**:

```bash
./build.sh                # everything, base first
./build.sh java           # one kit (does NOT rebuild base)
./build.sh --no-cache     # full rebuild
```

`build.sh <kit>` never auto-rebuilds base — rebuild base yourself when its layers change, then
rebuild the kits that inherit from it.

## Run model & containment

```bash
podman/run-sandboxed.sh <kit> <project-dir> [command...]   # default command: bash
```

The project directory is the **only** host filesystem mount (at `/work`), and the container
runs as your uid (`--userns=keep-id`, `--user <uid>:<gid>`), so files created in `/work` are
yours on the host. `USER=ubuntu` is set so in-container tools whose identity must match the
image's uid-1000 passwd name agree (PostgreSQL initdb/libpq, Liferay's JDBC role).

| Agent/app sees                        | Does NOT see                     |
|---------------------------------------|----------------------------------|
| `/work` (the project dir, writable)   | host home, dotfiles, SSH keys    |
| the disposable image filesystem       | other projects                   |

Honest limits: whatever runs can still modify everything in `/work` and reach the internet —
containment protects the host, not the project contents. (`--security-opt label=disable` turns
SELinux separation off so the Wayland socket bind works; the userns + single `/work` mount stay
the containment boundary.)

| Flag | Effect |
|------|--------|
| `--gui` | Wayland socket + GPU only (no host files) — for in-container GUI apps |
| `--x11` | X11/XWayland fallback on top of `--gui` |
| `--persist-work` | Persist ALL state in `<project>/` itself (sets `HOME` to `/work`): services' data, Liferay bundles, Android AVDs, AI logins |
| `--host-network` | Reach the container's services from the host (e.g. PostgreSQL :5432, Liferay :20080/:21080) |
| `--host-dbus` | Share the host session D-Bus (portals/notifications). Off by default so GUI file dialogs browse the container fs |
| `--kvm` | Pass through `/dev/kvm` (Android emulator) |
| `--dry-run` | Print the podman command instead of running it |

Default (no persist flag) = ephemeral home, maximum containment — ideal for throwaway AI-agent
sessions. Use `--persist-work` for service/dev work that must survive the run.

```bash
podman/run-sandboxed.sh dev ~/projects/myapp                             # CLI session
podman/run-sandboxed.sh --persist-work --host-network java ~/proj/portal
```

`run-sandboxed.sh` is one-shot (`--rm`) — good for a quick command or a menu launcher.

**Hostname aliases.** A kit may map friendly names to `127.0.0.1` via podman `--add-host`
(added in `sandbox_build_args`). The **java** kit ships `staging.local`, `live.local` and
`liferay.local` (separate cookie domains for Liferay staging vs live — see
[java/README.md](../java/README.md#liferay-services-and-remote-publishing)). Override the set for
any kit with `AI_HOST_ALIASES="a.local b.local"`, or `AI_HOST_ALIASES=""` to disable. The java kit
also gets `--sysctl net.ipv4.ip_unprivileged_port_start=0` (unless `--host-network`) so its Caddy
`proxy-start` can bind port 80 as the unprivileged user.

### Persistence: `--persist-work`

Without a persist flag the container home is ephemeral — maximum containment, ideal for
throwaway AI-agent sessions. **`--persist-work`** sets `HOME=/work`, so the mounted project dir
**is** the home: all container state lands directly under `<project>/` — `~/.local/share/postgres`,
`~/liferay/…`, `~/.android/…`, `~/.claude`, `~/.bash_history.d/` — survives stop/restart, and is
yours on the host. (Best for a dedicated work directory; it will scatter dotfiles into a mounted
source repo.)

## Named sandboxes (persistent, reconnectable)

For ongoing work use a **named** sandbox that stays alive so you can reconnect more terminals
and keep state across stops:

```bash
podman/connect-sandboxed.sh myapp     # create-or-attach; asks kit/GUI/workdir on first use
podman/connect-sandboxed.sh myapp     # again from another terminal = second shell into it
podman/stop-sandboxed.sh myapp        # stop (keep); reconnect restarts it
podman/stop-sandboxed.sh --rm myapp   # stop and remove
```

First run (container doesn't exist yet) asks: **container type** (`base`/`java`/`dev`/
`android`, default `dev`), **GUI?** (default yes), and **workdir** — defaults to
`$SANDBOX_ROOT/<name>` (`~/sandboxes/<name>`; used automatically if it already exists, otherwise
you're prompted for a path). Named sandboxes always use `--persist-work`, so all state lives in
`<workdir>` itself and survives stop/restart; the sandbox **name** shows in the prompt and window
title. Run `connect-sandboxed.sh` with no name to list existing sandboxes. (After rebuilding an
image, `stop --rm <name>` then reconnect to recreate on the new image.)

Which auto-flags each kit gets on creation is defined declaratively in **`podman/sandbox.conf`**
— `<kit> = gui x11 kvm host-network host-dbus` (`gui` sets the prompt default; `x11` applies
only with GUI; `kvm` only if `/dev/kvm` exists). By default `android = gui x11 kvm` (so
`studio`/Android Studio works) and the others are `gui`. Edit that file, or a per-user
`~/.config/ai-dev/sandbox.conf` (overrides per kit), to change it. Existing sandboxes bake their
flags at creation — `sb rm <name>` then reconnect to apply changes.

**Shell integration.** Source the helper once from your `~/.bashrc` for a short `sb` command
with Tab-completion:

```bash
echo "source $PWD/podman/sandbox.bashrc" >> ~/.bashrc   # run from the repo root
```

| Command | Does |
|---------|------|
| `sb` / `sb list` | list sandboxes with status |
| `sb <name>` | connect to (or create) a sandbox |
| `sb stop <name>` | stop (keep) |
| `sb rm <name>` | stop and remove |
| `sb run <args…>` | one-shot `run-sandboxed.sh` passthrough |
| `sb export` | wizard to add a menu launcher for a GUI app in a sandbox (or `sb export <args…>` = `export-app.sh` passthrough) |

`<Tab>` completes subcommands and sandbox names. A name that clashes with a subcommand keyword
needs `sb connect <name>`.

## Terminal

Interactive shells get a git-aware prompt — `HHMMSS:<podman-env>(history#) (git-branch):cwd` —
where **podman-env** defaults to the kit name (`base`/`java`/`dev`/`android`) but is overridden
by the first line of `~/.podman_env` if present (persists per project under `--persist-work`).
The terminal window/tab **title** shows `<podman-env>:<cwd>` (e.g. `java:/work`) so you can tell
containers apart. Each shell also keeps its **own** timestamped history file under
`~/.bash_history.d/` (persisted in `<project>/` with `--persist-work`, since `HOME=/work`), with
helpers:

| Command | Does |
|---------|------|
| `hist-ls` | list stored sessions (date, command count, file) |
| `hist-grep <regex>` | search commands across all sessions |
| `hist-fzf` | fuzzy-search all history (fzf) |
| `hist-load <file>` | load an old session into the current shell |
| `hist-prune [days]` | delete sessions older than N days (default 365) |

### Tools banner

The **first** interactive shell after a container starts prints a per-kit index of the tools it
provides — base's commands plus whatever the kit adds. Run **`tools`** to reprint it any time.
The list is assembled from section files in `/etc/ai-dev/tools.d/` (base drops `10-base.txt`;
each kit appends its own, e.g. `40-java.txt`), so it always matches the image. It shows once per
container start (a marker in the `/dev/shm` tmpfs), not on reconnects or subshells; set
`AI_TOOLS_QUIET=1` to suppress the auto-banner (`tools` still works on demand).

## GUI apps mechanics

Start the container with `--gui` and bundled GUI apps display on your Wayland desktop. The apps
themselves (and their short launch commands) come from the base image — see
[base/README.md](../base/README.md#gui-apps). This section covers the plumbing.

`--gui` gives the container a writable `XDG_RUNTIME_DIR` and shares the Wayland and audio
(PipeWire/PulseAudio) sockets, so dconf/GSettings and sound work. It binds only those sockets,
never the whole runtime dir, so the host podman socket is not exposed. By **default the host
session D-Bus is NOT shared**, so GUI open/save dialogs use each app's own in-container chooser
and browse the **container** filesystem (`/work`, `/home/ubuntu`) — a harmless `Failed to
connect to the bus` line may appear. Pass `--host-dbus` to share the host session bus for
portal/notification integration; dialogs then browse the **host** filesystem instead. `--x11`
adds an X11/XWayland fallback for apps whose toolkit needs it (e.g. JetBrains JBR, Android
Studio).

Run from a container shell, the quick commands launch **in the background, detached** from the
terminal (they don't block it or spam logs — output goes to `$XDG_RUNTIME_DIR/gui-<app>.log`).
`--version`/`--help` still print, and one-shot `run-sandboxed … <app>` / menu launchers stay
attached so the container lives as long as the app.

### Recognizing container windows by colour

To tell which pod a GUI window came from, each sandbox has an identity **colour** and **app_id**,
resolved by the `ai-env-color` helper: the colour is derived from the podman-env name (distinct
per pod, stable across runs) unless you set `AI_ENV_COLOR="#3b82f6"` (or `"r,g,b"`) or put a
colour on the first line of `~/.podman_color` (persists per project with `--persist-work`).

- **Chrome** self-decorates, so its launcher passes `--set-user-color=<r,g,b>` — the browser
  **frame/title is tinted** with the pod colour on any desktop, no compositor setup needed. This
  is the reliable path.
- The Chromium/Electron launchers (`chrome`, `claude-desktop`, `code`) also pass `--class=aidev-<env>`.
  Recent Chromium/Electron use that as the **Wayland app_id**, so a compositor rule can then
  border/colour them — e.g. Hyprland `windowrulev2 = bordercolor rgb(3cb44b), class:^(aidev-.*)$`
  (Sway: `for_window [app_id="^aidev-"] …`). **Behaviour is version-dependent**, though: some
  builds derive the app_id from the `.desktop` file and ignore `--class`, so confirm the real
  app_id with your compositor (Hyprland `hyprctl clients`, Sway `swaymsg -t get_tree`) before
  relying on a rule. On KDE/GNOME the app_id at most makes windows identifiable — per-app titlebar
  colour isn't a stock rule. Toolkits that don't take a CLI class override on Wayland (JetBrains
  IDEs, Meld, Lite XL, WezTerm) keep their default app_id.

Check the resolved values inside a container with `ai-env-color`, `ai-env-color --hex`, and
`ai-env-color --appid`.

### Fedora menu launchers

`export-app.sh` generates `.desktop` entries that launch a GUI app **into a running named
sandbox** (`aidev-<name>`, created by `connect-sandboxed.sh` / `sb`) via `podman exec` — it does
**not** spin up a new container. The app entry attaches only when the sandbox is already running;
if it's stopped or absent it shows a desktop notification (it never starts or creates anything).
A companion **"Start <name>"** entry opens a terminal on `connect-sandboxed.sh <name>` to
create/resume it.

Run `sb export` (with the [shell integration](#named-sandboxes-persistent-reconnectable) sourced)
for an interactive wizard — pick the sandbox, pick the app (offered from its kit), name it — or
call `export-app.sh` directly:

```bash
podman/export-app.sh portal chrome "Chrome (portal)"   # app launcher + "Start portal"
podman/export-app.sh --no-start portal code            # app launcher only
podman/export-app.sh --remove portal chrome            # remove the app launcher
podman/export-app.sh --remove portal                   # remove the "Start portal" launcher
podman/export-app.sh --regroup                         # migrate previously-exported entries into submenus
```

Each sandbox's launchers are grouped under an **"AI Dev › `<sandbox>`"** submenu (via the XDG menu
spec: a per-sandbox category `X-AIDev-<name>`, a `.directory` under
`~/.local/share/desktop-directories/`, and a merge `.menu` under `~/.config/menus/…-merged/`;
`kbuildsycoca6` refreshes KDE's cache). `--regroup` moves launchers created before this into their
submenus.

`<app>` is the in-container launcher command (`chrome`, `claude-desktop`, `code`, `idea`,
`webstorm`, `studio`, `meld`, `lite-xl`, `wezterm`). The exec re-passes the Wayland/X11 env and
`AI_KIT=<name>` (so the [per-pod colour](#recognizing-container-windows-by-colour) resolves). The
sandbox must have been created **with GUI** — its `sandbox.conf` profile must include `gui` — for
exec'd apps to display; a sandbox made without GUI has no Wayland socket to reach.

## AI CLI auth & updates

The AI coding CLIs (`claude`, `codex`, `gemini`) come from the base image and exist in every
kit.

1. **Interactive login:** run `claude` / `codex` / `gemini` once inside the container. With
   `--persist-work` the login persists in `<project>/` (`HOME=/work`) and is reused on the next
   run against the same project; without it the login is ephemeral.
2. **API keys (headless):** pass `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY` into
   the container, e.g. `podman/run-sandboxed.sh dev ~/proj bash -c '…'` after exporting them, or
   bake them into the persisted `<project>`/agent-home `.bashrc`.

**Updates.** The CLIs are installed globally and their npm tree (`/opt/npm`) is owned by the
container user, so they **self-update in-container** (no "no write permission to npm prefix"). In
a **named** sandbox the update persists until you `sb rm` it; ephemeral one-shot runs re-check
each time. To pin a sandbox to the image's version, add `{"env":{"DISABLE_AUTOUPDATER":"1"}}` to
`~/.claude/settings.json` (persists with `--persist-work`). Rebuild the image to move the pinned
baseline for everyone.

## Repository layout

```
base/ java/ dev/ android/          Containerfiles (+ each kit's README)
scripts/                           install helpers used at image build time
podman/                            run-sandboxed.sh (one-shot), connect-sandboxed.sh +
                                   stop-sandboxed.sh (named), export-app.sh,
                                   lib-sandbox.sh (shared)
docs/                              this technical documentation
build.sh                           dependency-ordered build
```

## Maintenance notes

- SDKMAN, Android SDK and Flutter live under `/opt` (not `$HOME`) so a `--persist-work` HOME of
  `/work` never shadows them.
- After rebuilding an image, just run `run-sandboxed.sh` again — persisted state under
  `<project>/` is untouched.
