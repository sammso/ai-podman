# ai-node

Node.js development kit. Part of [AI Development Containers](../README.md); shared run model,
persistence and GUI plumbing live in [docs/TECHNICAL.md](../docs/TECHNICAL.md). Builds `FROM
localhost/ai-base`, so all of base's tools ([AI CLIs, GUI apps, Node LTS, …](../base/README.md))
are here too. Run **`tools`** inside the container to list its commands.

## Technical

- `FROM localhost/ai-base`; adds **fnm** (Node version manager), **Visual Studio Code** (official
  Microsoft build), and **JetBrains WebStorm**.
- **fnm** lives system-wide: the binary in `/usr/local/bin/fnm`, the version store in
  `FNM_DIR=/opt/fnm` (outside `$HOME`, so a `--persist-work` HOME of `/work` never shadows it;
  world-writable so you can `fnm install` more at runtime). Node **20** and **22** are
  preinstalled, default **22**. Every interactive shell runs `eval "$(fnm env --use-on-cd)"`, so
  the default version is active and it auto-switches on `cd` into a dir with `.node-version` /
  `.nvmrc`. Base's system Node stays for the AI CLIs.
- Both IDEs are GUI apps and need an X server (VS Code's Electron and WebStorm's JBR), so run the
  container with **`--gui --x11`** — a named `node` sandbox gets this automatically (see
  [sandbox.conf](../docs/TECHNICAL.md#named-sandboxes-persistent-reconnectable)).

## Node versions

```bash
fnm list                 # installed versions
fnm install 18           # add another (persists in /opt/fnm)
fnm use 20               # switch this shell
fnm default 22           # default for new shells
node -v ; npm -v ; npx --version
corepack enable          # pnpm / yarn shims
```

Drop a `.node-version` (or `.nvmrc`) in a project and fnm switches to it automatically when you
`cd` in.

## IDEs

```bash
# GUI + X11 (WebStorm's JBR and VS Code both need it):
podman/run-sandboxed.sh --gui --x11 --persist-work node ~/proj code
podman/run-sandboxed.sh --gui --x11 --persist-work node ~/proj webstorm
```

- **`code`** — Visual Studio Code. Launches to the host desktop under `--gui`, Wayland-native
  when a Wayland session is present; add `--no-sandbox` if the Electron sandbox refuses under
  rootless podman. Also works as a CLI (`code .`, `code --version`).
- **`webstorm`** — JetBrains WebStorm. Needs `--gui --x11`. It's a licensed IDE — free for
  non-commercial use, otherwise a trial/paid license (sign in on first launch).
