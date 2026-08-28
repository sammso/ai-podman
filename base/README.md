# ai-base

The base AI development image. Part of [AI Development Containers](../README.md); shared run
model, GUI plumbing and AI-CLI auth live in [docs/TECHNICAL.md](../docs/TECHNICAL.md). Every dev
kit ([java](../java/README.md), [dev](../dev/README.md), [android](../android/README.md)) builds
`FROM localhost/ai-base`, so everything here exists in all of them.

## Technical

- `FROM ubuntu:24.04`; runs as the invoking user (uid 1000 = `ubuntu`) via plain rootless
  podman — no `USER`/`ENTRYPOINT` baked in.
- npm globals install into a **user-owned prefix `/opt/npm`** (on `PATH`), so the AI CLIs
  self-update as the container user without root. See
  [AI CLI updates](../docs/TECHNICAL.md#ai-cli-auth--updates).
- The git-aware prompt and per-shell history are wired into every interactive shell at build
  time — see [Terminal](../docs/TECHNICAL.md#terminal).

## Tools

The first shell in a container prints an index of these commands; run **`tools`** to reprint it
(see [Tools banner](../docs/TECHNICAL.md#tools-banner)).

### AI coding CLIs

`claude` (Claude Code), `codex`, and `gemini` are installed globally. Sign in or pass API keys
per [AI CLI auth](../docs/TECHNICAL.md#ai-cli-auth--updates).

### rtk

`rtk` is a CLI proxy that compresses command output ~60–90 % before an AI CLI reads it (fewer
tokens). The binary is installed; enable its hook per tool with `rtk init -g` (Claude Code) or
`rtk init -g --gemini` — config lands in `~/.config/rtk` and persists per project under
`--persist-work`.

### agent-browser

`agent-browser` is a browser-automation CLI for AI agents (`agent-browser open <url>`,
`snapshot`, `click`, `mcp` for an MCP server). It drives the bundled Google Chrome
(`AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/google-chrome`) — no extra browser download. Headless by
default; run the container with `--gui` for a visible window.

### herdr

`herdr` ([herdr.dev](https://herdr.dev)) is a background runtime that keeps coding agents (Claude
Code, Codex, …) running continuously — persistent sessions, status tracking, and multi-agent
coordination across workspaces. The single binary is installed system-wide; run `herdr` to start
the server / manage agents.

### Node & CLI essentials

Node 22 LTS + npm, git, and common build tools come from base and are available in every kit
(the dev kit's `npx react-native` / `create-expo-app` rely on them).

## GUI apps

Start the container with `--gui` (add `--x11` for X11-only toolkits) and these display on your
Wayland desktop. From a container shell the short launch commands are on the `PATH` — run
`gui-apps` to list them. They launch **detached** in the background; the plumbing (Wayland,
D-Bus, menu launchers) is documented in
[GUI apps mechanics](../docs/TECHNICAL.md#gui-apps-mechanics).

To tell pods apart, `chrome`'s frame is tinted with a per-pod colour (the reliable path), and the
Chromium/Electron launchers also try a per-pod `aidev-<env>` app_id for compositor rules
(version-dependent — see the note). Configure the colour with `AI_ENV_COLOR` / `~/.podman_color`
(see [Recognizing container windows](../docs/TECHNICAL.md#recognizing-container-windows-by-colour);
`ai-env-color` shows the resolved value).

| Command | App |
|---------|-----|
| `chrome` | Google Chrome, Wayland-native (`google-chrome --ozone-platform=wayland`) |
| `claude-desktop` | Claude Desktop (add `--no-sandbox` if the Electron sandbox refuses) |
| `meld` | Meld visual diff / merge tool |
| `lite-xl` | Lite XL editor |
| `wezterm` | GPU terminal (opens a shell inside the container) |

```bash
podman/run-sandboxed.sh --gui --persist-work base ~/projects/site
# then, inside the container:
chrome http://localhost:20080      # or: meld a.txt b.txt   |   lite-xl .   |   claude-desktop

# or launch a single app directly:
podman/run-sandboxed.sh --gui base ~/projects/site chrome
```

- **Chrome:** prefer pure Wayland (`--ozone-platform=wayland`); the `--x11` fallback works too
  but allows input snooping between X clients. Chrome may need `--no-sandbox` under rootless
  podman (the container is the sandbox).
- **Claude Desktop** (official Linux beta — Ubuntu-only, hence in-container on a Fedora host):
  sign in with your claude.ai account. Use `--persist-work` so its `~/.config/Claude` login
  survives. The `claude-desktop` command forces `--ozone-platform=wayland` when a Wayland
  session is present (its Electron build otherwise defaults to X11 and exits with "Missing X
  server or $DISPLAY"); add `--no-sandbox` only if the Electron sandbox refuses. Linux-beta
  limits: no Computer Use or dictation; the Quick Entry global hotkey may not work from inside a
  container. Residual `Gtk-Message: Failed to load module …` lines are harmless (KDE-only GTK
  modules absent in the image).
