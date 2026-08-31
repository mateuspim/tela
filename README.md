# tela

Browse [Wallhaven](https://wallhaven.cc), preview, set as your Android
wallpaper. Android-only, no backend, no accounts.

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
  `./tool/tela run`.
- **Waydroid:** initialise it once on the host (needs root), then connect:

  ```bash
  sudo waydroid init          # one time
  waydroid session start
  ./tool/tela run
  ```

## The API key

SFW browsing works with no key. A [Wallhaven API
key](https://wallhaven.cc/settings/account) unlocks NSFW and your account's
browsing settings. It is stored encrypted (Android Keystore), sent only in the
`X-API-Key` header, and never logged — see the NSFW rules in `CLAUDE.md`.
