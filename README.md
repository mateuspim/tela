# tela

Browse [Wallhaven](https://wallhaven.cc), preview, set as your Android
wallpaper. Android-only, no backend, no accounts.

## Download and install

**[Download the latest Full APK](https://github.com/mateuspim/tela/releases/latest/download/tela-full.apk)**
· [All editions and release notes](https://github.com/mateuspim/tela/releases/latest)

Requires **Android 10 or newer** (API 29). This repository is private: sign in
with a GitHub account that has access before downloading.

1. Download `tela-full.apk` on your Android device and open it.
2. If prompted, allow your browser or file manager to install unknown apps,
   then confirm **Install** or **Update**.
3. For future updates, download the latest Full APK from the same link and
   install it over the existing app. **Do not uninstall**: uninstalling deletes
   private images, the database, and stored keys. Wait for active transfers or
   offloads to finish before updating.

Full uses `cc.pym.tela` and updates the existing Full installation when signed
with the same key. Play, Wallhaven-only, and Safe install separately and do not
share its data. If Android rejects an update, keep the installed app and check
its edition, version, and signing certificate; do not uninstall to fix it.

Each release includes `SHA256SUMS` for checking downloaded files. Edition and
signature details are in [the release guide](docs/RELEASING.md).

## Developer setup

Scope and roadmap: [`PLAN.md`](PLAN.md). Coding contract: [`CLAUDE.md`](CLAUDE.md).

## Toolchain

There is **no Flutter or Android SDK on the host**. Everything runs in a pinned
container (Flutter 3.44.6, Android SDK 36, minSdk 29), so a green build here is
a green build anywhere.

```bash
./tool/tela analyze            # must be clean before every commit
./tool/tela test               # all tests
./tool/tela dart format .      # format
./tool/tela build apk --debug
./tool/tela devices
./tool/tela --shell            # poke around inside the container
./tool/tela --build-image      # rebuild the toolchain (rarely needed)
```

The image is built automatically the first time you run any of these. Pub and
Gradle caches live in named Docker volumes, so only the first build is slow.

## Editions and releases

tela ships four compile-time editions from one source commit: Play,
Wallhaven-only, Safe multi-source, and Full. Build commands, package identities,
tagging, signing secrets, and artifact names are documented in
[`docs/RELEASING.md`](docs/RELEASING.md). Pull requests run the complete CI gate;
a `vX.Y.Z` tag builds the signed release matrix.

## Running on a device

The container shares the host network and the USB bus, so `adb` inside it sees
what the host sees.

- **Physical device:** enable USB debugging, plug it in, then
  `make deploy`.
- **Waydroid:** initialise it once on the host (needs root), then connect:

  ```bash
  sudo waydroid init          # one time
  waydroid session start
  make deploy
  ```

## The API key

SFW browsing works with no key. A [Wallhaven API
key](https://wallhaven.cc/settings/account) unlocks NSFW and your account's
browsing settings. It is stored encrypted (Android Keystore), sent only in the
`X-API-Key` header, and never logged — see the NSFW rules in `CLAUDE.md`.
