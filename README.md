# AI Development Containers

AI-assisted development environments run with plain **rootless Podman**. Each session runs an
`ai-*` image sharing exactly **one** project directory with the host — the host home, dotfiles,
SSH keys and other projects stay invisible.

One base image carries the AI coding CLIs (Claude Code, Codex, Pi, Antigravity), Claude Desktop,
the ChatGPT/Codex desktop app, Google Chrome, Node 22 LTS and CLI essentials. Three dev-kit images
build on it:

| Image | Adds |
|-------|------|
| [`localhost/ai-base`](base/README.md) | Claude/Codex/Pi/Antigravity (`agy`) CLIs, Claude Desktop, ChatGPT/Codex desktop, Chrome, Meld, Lite XL, WezTerm, rtk, agent-browser, Node 22 LTS, git, build tools |
| [`localhost/ai-java`](java/README.md) | IntelliJ IDEA Ultimate, JDK 17/21/25, Gradle, Maven, PostgreSQL, MinIO, SQLLine — plus a full Liferay stack |
| [`localhost/ai-dev`](dev/README.md) | Temurin JDK 17/21/25 (default 21); Node/NPM LTS from base |
| [`localhost/ai-android`](android/README.md) | Android Studio, JDK 17 default, Android SDK + emulator, Flutter, React Native-ready |
| [`localhost/ai-node`](node/README.md) | Node.js: fnm (switchable Node 20/22), Visual Studio Code, JetBrains WebStorm |

How the images inherit from one another, the run/containment model, persistence, named
sandboxes, GUI plumbing and AI-CLI auth are all in **[docs/TECHNICAL.md](docs/TECHNICAL.md)**.

## Requirements

- **Rootless Podman** on a **Linux** host (developed on Fedora).
- A **Wayland** session to display the in-container GUI apps (Chrome, Claude Desktop, IntelliJ,
  Android Studio, …); `--x11` provides an XWayland fallback.
- **`/dev/kvm`** for the Android emulator (pass through with `--kvm`).
- Disk per image, roughly: base ~4.4 GB · dev ~5.4 GB · java ~10.6 GB · android ~17.6 GB. Two
  Liferay environments side by side need ~5–6 GB free RAM.

## Build

```bash
./build.sh                # everything, base first
./build.sh java           # one target (does not rebuild base)
./build.sh --no-cache     # full rebuild
```

Base builds first because every kit inherits from it — see
[docs/TECHNICAL.md#image-inheritance](docs/TECHNICAL.md#image-inheritance).

## Getting started

```bash
# one-shot session (ephemeral home, maximum containment)
podman/run-sandboxed.sh dev ~/projects/myapp

# named, reconnectable sandbox that keeps its state
podman/connect-sandboxed.sh myapp        # create-or-attach (asks kit/GUI/workdir first time)
```

The project directory is the only host mount (at `/work`) and the container runs as your uid, so
files created there are yours on the host. Add `--persist-work` to keep services/logins/state,
`--gui` to show GUI apps, `--host-network` to reach container services from the host. Full flag
reference and the `sb` shell helper are in [docs/TECHNICAL.md](docs/TECHNICAL.md#run-model--containment).

## Documentation

- **[docs/TECHNICAL.md](docs/TECHNICAL.md)** — architecture, inheritance, run model, sandboxes,
  GUI plumbing, terminal, AI-CLI auth, maintenance.
- **[base/README.md](base/README.md)** — AI CLIs, rtk, agent-browser, the GUI apps.
- **[java/README.md](java/README.md)** — JDK/Gradle/Maven/Blade, IntelliJ, PostgreSQL/MinIO/
  SQLLine, and the full Liferay stack.
- **[dev/README.md](dev/README.md)** — the general JDK + Node dev kit.
- **[android/README.md](android/README.md)** — Android Studio, SDK/emulator, Flutter.

Licensed under the terms in [LICENCE](LICENCE).
