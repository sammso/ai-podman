# ai-android

Android development kit. Part of [AI Development Containers](../README.md); shared run model,
persistence and GUI plumbing live in [docs/TECHNICAL.md](../docs/TECHNICAL.md). Builds `FROM
localhost/ai-base`, so all of base's tools ([AI CLIs, GUI apps, Node LTS, …](../base/README.md))
are here too. Run **`tools`** inside the container to list its commands.

## Technical

- `FROM localhost/ai-base`; Temurin **JDK 17** default (Android's supported build JDK; 21/25 also
  available via SDKMAN).
- **Android SDK** at `ANDROID_HOME=/opt/android-sdk` — `platform-tools` (adb), `build-tools;36`,
  `platforms;android-36` + `android-35`, `emulator`, and a `google_apis/x86_64` system image.
  **Flutter** (stable) at `/opt/flutter`. Both are on `PATH` for every shell via
  `/etc/profile.d/android.sh` (outside `$HOME`, so `--persist-work` never shadows them).
- React Native needs no image additions — Node/NPM come from base; use `npx`.

## Tools & how to use

```bash
# GUI + KVM + persistent AVDs; Android Studio's JBR needs X11:
podman/run-sandboxed.sh --gui --x11 --persist-work --kvm android ~/proj studio
```

- **Android Studio** — launch with `studio` (it reuses the image's `/opt/android-sdk`). Its
  bundled JBR uses X11, so start the container with `--gui --x11`. A **named** android sandbox
  already gets `--gui --x11 --kvm` automatically (see
  [sandbox.conf](../docs/TECHNICAL.md#named-sandboxes-persistent-reconnectable)).
- **Emulator** — needs `/dev/kvm`, passed through with `--kvm`. With `--persist-work`, AVDs
  persist under `<project>/.android` and survive the run.
- **Physical devices** — need `--host-network` or explicit USB device passthrough.
- `flutter doctor`, `adb devices`, `sdkmanager` are on the `PATH`.
