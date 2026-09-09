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

`make apk` and `make deploy` build `full`, preserving the existing development
and device workflow. A release build without `android/key.properties` is debug
signed and must never be distributed.

## Git flow

1. Work on `feature/*` or `fix/*` and open a pull request into `master`.
2. Require the `CI / verify` and four `CI / build-matrix` checks.
3. Use a temporary `release/X.Y` branch only when stabilization needs more than
   one commit. Merge every release fix back into `master`.
4. Create an annotated `vX.Y.Z` tag on a commit contained in `master`.
5. The Release workflow rebuilds and publishes the four APKs, the Play AAB, and
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
