# Releasing tela

Every edition is built from the same commit. Editions are product flavors, not
long-lived source branches.

| Flavor | Application id | Sources | Credentials / explicit content |
|---|---|---|---|
| `play` | `cc.pym.tela.play` | Wallhaven | unavailable |
| `wallhaven` | `cc.pym.tela.wallhaven` | Wallhaven | available |
| `safe` | `cc.pym.tela.safe` | Wallhaven + `konachan.net` | unavailable |
| `full` | `cc.pym.tela` | Wallhaven + Konachan | available |

`full` keeps the historical application id so it can update the owner's
existing installation. The other identities intentionally have isolated
databases, secure storage, and private files.

## Local builds

Always supply matching Gradle flavor and Dart edition values:

```bash
./tool/tela build apk --release \
  --flavor safe \
  --dart-define=TELA_EDITION=safe
```

`make apk` and `make deploy` build `full` by default; `make deploy
EDITION=safe` builds and installs another edition. A release build without
`android/key.properties` **fails**. Set `TELA_ALLOW_DEBUG_SIGNING=1` only for an
APK that will never be installed over a release (CI's PR build, a size check).

## The release key on a new machine

Every build that will reach a device is signed with the one release key, whose
certificate is pinned in `tool/release-certificate.sha256`. The key lives in
the owner's Vaultwarden as a Login item named `tela release signing`: hidden
fields `storePassword`, `keyAlias`, `keyPassword`, and the keystore attached as
`tela-release.jks`.

```bash
mise use -g npm:@bitwarden/cli@2026.8.0  # 2026.9.0 cannot log in to Vaultwarden 1.37.3 (vaultwarden#7750)
bw config server <your-vaultwarden-url>
bw login
make signing-setup
```

`signing-setup` writes the two gitignored files and deletes them again unless
the keystore's certificate matches the pin. `deploy` then compares the
certificate of the app already on the device with the one it built and refuses
a mismatch rather than install it — never uninstall to get past that.

The Play artifact is checked after compilation with `tool/audit-play-apk`. The
gate verifies its application id and the absence of Konachan endpoints or the
Wallhaven secure-storage key in AOT code. Treat a failure as a product-boundary
regression, not as an ignorable string warning.

## Git flow

1. Work on `feature/*` or `fix/*` and open a pull request into `master`.
2. Require the `CI / verify` and four `CI / build-matrix` checks.
3. Use a temporary `release/X.Y` branch only when stabilization needs more than
   one commit. Merge every release fix back into `master`.
4. Bump `version: X.Y.Z+N` in `pubspec.yaml` in the release PR. `N` must be
   greater than every previous release versionCode (and any installed local
   build). Local deployment and CI both use this value; do not use run counters
   or split-per-ABI codes. Add `docs/releases/vX.Y.Z.md` with release notes.
5. Create an annotated `vX.Y.Z` tag on a commit contained in `master`.
6. The Release workflow rebuilds and publishes the four APKs, the Play AAB, and
   `SHA256SUMS` from that exact commit.

## Repository configuration

Protect `master`: pull requests required, branch up to date, no force pushes,
and all CI jobs required. Protect tags matching `v*` from deletion or update.

Create the `github-release` environment with these secrets:

- `TELA_KEYSTORE_BASE64`
- `TELA_STORE_PASSWORD`
- `TELA_KEY_ALIAS`
- `TELA_KEY_PASSWORD`

The keystore must be the certificate already used for `cc.pym.tela`; replacing
it makes the Full APK unable to update existing installations. Encode it with
`base64 -w0 android/tela-release.jks` and keep the original offline too.

Play publishing is deliberately a separate promotion step. Upload the generated
`tela-play-vX.Y.Z.aab` to Internal testing first, complete the content-rating and
data-safety declarations, and promote only after a hardware pass. A Git tag does
not publish directly to production.

## Downloads and verification

The stable Full download is
https://github.com/mateuspim/tela/releases/latest/download/tela-full.apk .
Each release also retains `tela-{edition}-vX.Y.Z.apk` and
`tela-play-vX.Y.Z.aab`. The stable Full asset is a byte-identical copy of the
versioned APK, and both are included in `SHA256SUMS`.

Download all assets with `gh release download vX.Y.Z --repo mateuspim/tela`,
then run `sha256sum -c SHA256SUMS` in that download directory. Check an APK
with Android SDK `apksigner verify --verbose --print-certs tela-full.apk`.
The expected SHA-256 certificate fingerprint is:

```text
33b859cc2dce878345bd6c04e9b53e02808e7c6cd03de3ebc38ac2cfff40cb64
```

The workflow rejects APKs signed with a different certificate. This is the
existing Full signing key, not a debug certificate. Keep it backed up offline.
Use `apkanalyzer manifest application-id`, `version-name`, `version-code`, and
`min-sdk` to inspect a downloaded APK. Matching identity and certificate prove
signing compatibility; an actual device update still requires a hardware test.

Manual dispatch validates the supplied version against `pubspec.yaml` and
builds artifacts without publishing. Published tags must belong to `master`.
For each new release, update the source version first so later `make deploy`
builds cannot accidentally downgrade a released installation.
