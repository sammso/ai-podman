# ai-dev

General-purpose dev kit. Part of [AI Development Containers](../README.md); shared run model,
persistence and GUI plumbing live in [docs/TECHNICAL.md](../docs/TECHNICAL.md). Builds `FROM
localhost/ai-base`, so all of base's tools ([AI CLIs, GUI apps, Node LTS, …](../base/README.md))
are here too. Run **`tools`** inside the container to list its commands.

## Technical

- `FROM localhost/ai-base`; adds Temurin **JDK 17/21/25** via SDKMAN (default **21**).
- Node/NPM LTS, git and build tools are inherited from base — nothing extra needed for
  JavaScript/React Native work.

## Tools

```bash
sdk use java 25          # switch JDK for this shell
sdk default java 17      # persist the default

npx react-native init MyApp     # React Native — no image additions needed
npx create-expo-app my-app      # Expo
```

Run it like any kit:

```bash
podman/run-sandboxed.sh dev ~/projects/myapp            # one-shot
podman/connect-sandboxed.sh myapp                       # named sandbox (kit: dev)
```
