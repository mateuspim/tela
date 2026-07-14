# tela handoff

Updated: 2026-07-14

## Current milestone

Wave 0 is complete at `209101c`. Wave 1 landed slice by slice: the apply core
loop is `bcba151`, detail metadata is `36ec9f9`, three-tier downloads are
`28fa0b1` + `568e1ef`, and persisted per-purity storage settings are `1d8e4de`.
API-key entry and search + filters are both in the working tree, uncommitted.

**Wave 1 is now feature-complete in code, and unverified on hardware.** Nothing
in it has run on a physical device yet — see "Start of next session".

The app now supports the thin product loop:

1. Tap a real Wallhaven tile.
2. Preview the full-resolution image with pinch zoom.
3. Tap **Set wallpaper** and choose Home, Lock, or Both.

The detail screen now starts with the large Wallhaven thumbnail and fades the
full source over it. In parallel, it loads `GET /w/{id}` and renders complete
metadata: resolution, file size/type, category, purity, ratio, colours, tags,
uploader, source, views, and favorites. The apply action remains available
while this request is pending or fails.

The action passes through `ApplyWallpaper` → `WallpaperApplier` → tela's native
Android method channel. Kotlin downloads to app-private cache and calls
`android.app.WallpaperManager`; Both uses sequential home/lock writes separated
by 500 ms for restrictive OEM compatibility.

The detail app bar now also has Download: tap routes to the purity default,
while long-press offers a one-download Gallery / Files, not gallery / Private
library override. `DownloadWallpaper` passes `ImageStore` the ID, source,
purity, and selected `StorageTier`. Its project-owned Android adapter applies
the actual storage policy: SFW/sketchy Gallery downloads are MediaStore images
in `Pictures/tela`; app-private files live below tela's internal files dir; and
the middle tier asks once for a persistent local Storage Access Framework tree,
then writes to `tela/.nomedia` below it. The adapter rejects NSFW before a
MediaStore write can happen.

Download destinations are now a persisted setting rather than a constant.
`StorageSettings` holds one tier for safe/sketchy content and one for explicit
content; `DownloadWallpaper` reads it through the new `SettingsRepository` port
whenever a download arrives without an explicit tier, so the long-press override
is the only thing that can deviate from it. A settings screen off the browse app
bar edits both, writing each change straight through — there is no save button to
lose. Drift is now wired (its first table is the settings key/value store), which
is also the database Wave 2's favorites will land in.

A Wallhaven API key can now be entered, replaced, and removed, from a new account
section at the top of Settings. `SaveApiKey` trims the pasted key, stores it, and
then verifies it; `ForgetApiKey` drops it. The UI holds only *whether* a key
exists, never the key — a saved key cannot be read back out of the app.

Browse is finally a search, not four fixed listings. The app bar holds a search
field, and a filter sheet behind it edits categories, purity, shape (portrait /
landscape / any), sort order, and the toplist range. All of it is one
`SearchQuery` in `browseQueryProvider`, shared by the four tabs; the tab layers
its `Sorting` on top and the screen layers `atLeast`, because neither is a filter
the user chose. **The Explicit purity chip appears only once a key is stored** —
that is the step that was missing for NSFW to be reachable at all, and it is why
the key slice came first.

## Decisions made

- `flutter_wallpaper_plus 1.1.1` was evaluated first, as originally locked in
  `PLAN.md`, but its Android Gradle script does not compile with tela's pinned
  AGP 9 toolchain. The failing dependency was removed rather than weakening the
  hermetic build or patching pub-cache state.
- `WallpaperApplier` remains the domain-owned seam. Its current adapter is a
  small project-owned method channel, so a package can still replace it without
  touching features or use cases.
- Native failures map to `WallpaperApplyFailure`; source URLs and platform
  messages never enter the safe domain error.
- The preview decode is capped at twice the physical screen width. Wallpaper
  apply streams the cached source through Android rather than decoding a 6K
  bitmap in Dart.
- The packaged manifest has no storage or media-read permissions.
- `WallpaperDetails` is deliberately separate from the browse `Wallpaper`.
  Its detail fields are non-nullable, so paged grids stay small and detail UI
  cannot turn every field into a null-state branch.
- The NSFW non-indexing rule is now enforced in three places on purpose, each
  closing a different door: `StorageSettings` refuses to *hold* an NSFW→Gallery
  routing (so it cannot be saved), `StorageSettings.choicesFor` is what both the
  settings screen and the one-download override sheet build their options from
  (so it cannot be picked), and the Android adapter still rejects the write (so
  a hand-edited database cannot smuggle it past either).
- Settings persist as key/value rows (`storage.tier.sfw`, `storage.tier.nsfw`)
  rather than a column per setting: a new setting should be a new row, not a
  schema migration. An unreadable, unknown, or forbidden stored value falls back
  to the default instead of throwing — a download must always have somewhere safe
  to go.
- The toolchain image now installs `libsqlite3-dev`. `flutter test` runs Drift on
  the host VM, where `sqlite3_flutter_libs` (which ships the library on Android)
  does not apply, and `dart:ffi` opens the unversioned `libsqlite3.so` that only
  the dev package's symlink provides. Re-run `./tool/tela --build-image` if the
  Drift tests fail to load the library.
- **The API key is verified on save, with an NSFW-purity search** — the open
  question from last session, now closed. That request is the cheapest one
  Wallhaven *must* 401 for a bad key, so it proves the key without adding Wave 2's
  `GET /settings` account endpoint to `WallhavenApi` a wave early. It costs one of
  the 45 req/min, and it means a typo is caught in the dialog rather than three
  screens later as a mystery empty grid.
- `SaveApiKey` writes the key *before* probing, because the key reaches the
  request through `SecretStore` (via `ApiKeyInterceptor`) — there is no way to
  send a key that isn't stored yet. A test with a store-reading fake API pins the
  ordering: probing first would 401 every valid key.
- A rejected key restores the *previous* key rather than leaving the store empty.
  Editing a working key and mistyping it should not cost the user the working key.
- A key that cannot be verified because the device is offline or rate-limited is
  **kept**, and the outcome (`ApiKeySaveOutcome.savedUnverified`) says so in a
  snackbar. Only an actual rejection discards it; being offline says nothing about
  whether a key is good, and forcing a re-paste later would be punishment for it.
- `SearchQuery` now has value equality, and that is load-bearing rather than
  tidiness: the browse grid reloads when its query changes, and every rebuild
  hands it a freshly constructed query. Without element-wise `==` over its sets
  and lists, identical filters would look like a new listing and re-fetch on
  every frame. `WallpaperGrid.didUpdateWidget` is what turns a changed query into
  a reload — a cached page against the old query is a filter that appears ignored.
- The filter sheet edits a **draft** and applies it in one write, unlike the
  settings screen, which deliberately has no save button. The difference is what
  a write costs: a settings write is a local SQLite upsert, while an applied
  filter is a Wallhaven request out of 45/min. Five toggles must not cost five
  listings. Search runs on submit for the same reason — search-as-you-type would
  spend the budget on prefixes of an unfinished word.
- Purity and category are now rendered through `categoryLabel` / `purityLabel` in
  `core/ui`, not `enum.name`. The detail screen had been showing Wallhaven's wire
  values (`sfw`, `general`) straight to the user, which is both untranslatable and
  not language.
- `RatioChoice`, not `Orientation`: Flutter already has an `Orientation` enum, and
  every file with the filter sheet in it imports Material.
- **`~/.android` is now a named volume, and this was a real bug, not tidiness.**
  The toolchain container is `--rm`, so Gradle minted a fresh `debug.keystore`
  on *every* run. A differently signed APK cannot update an installed one
  (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`), and `flutter run` resolves that by
  uninstalling first — so every `./tool/tela run` was silently a clean install,
  wiping the Keystore-backed API key and the Drift database. It presented as
  "the key doesn't save". Nothing was wrong with the key code. If a signing
  fingerprint ever changes again, look here first.
- The API key is excluded from Android Auto Backup and device transfer
  (`res/xml/backup_rules.xml`, `res/xml/data_extraction_rules.xml`). The blob is
  encrypted with a Keystore key that no backup carries, so restoring it would
  hand the app a secret it cannot decrypt — corrupt, rather than merely absent.
  Absent is a state tela already handles: it asks for a key. Everything else
  (the database, the download destinations) still backs up.
- The non-gallery tier must use a user-selected SAF directory. An automatic
  raw shared-storage path is not available to a scoped-storage app targeting
  Android 11+ without broader access, and a MediaStore row would violate the
  NSFW non-indexing invariant. Only the local external-storage documents
  provider is accepted, preserving file-manager / USB-MTP reachability.

## Verification

- `./tool/tela dart format .`: clean
- `./tool/tela analyze`: clean
- `./tool/tela test`: 96 tests pass
- Three-tap browse → detail → Both widget flow: covered
- Domain use case and all native target/error mappings: covered
- `/w/{id}` is covered by a detail JSON fixture, mapper boundary tests, and a
  detail widget metadata test
- `./tool/tela build apk --debug`: passes
- `./tool/tela build apk --release`: passes
- Release merged manifest re-inspected after adding Drift: still only `INTERNET`
  and `SET_WALLPAPER`; no `READ_EXTERNAL_STORAGE` or `READ_MEDIA_*`
- Download routing has domain/use-case, method-channel, and detail-widget
  coverage; `./tool/tela build apk --debug` compiles the Android storage code
- Storage settings covered at every layer: the domain model (defaults, sketchy
  routing with sfw, both rejections of an indexed NSFW tier), the Drift adapter
  (round-trip, upsert-not-append, unknown value, forbidden value), the use case
  (settings default vs. override), and the settings screen (renders the saved
  tier, persists on tap, withholds the gallery from NSFW)
- `sqlite3_flutter_libs` compiles under the pinned AGP 9 toolchain, which is what
  `flutter_wallpaper_plus` failed to do — both APKs build
- API-key entry is covered at both layers: the use cases (trim, nsfw probe,
  store-before-probe, blank input, rejection with and without a previous key,
  offline and rate-limited both keeping the key) and the settings screen (presence
  without the key itself, save, rejection, removal). One widget test asserts the
  stored key never appears anywhere on screen
- Search + filters: `SearchQuery` equality (same members, any order, and each
  field's change detected), the browse controller (defaults, trimmed term, term
  surviving both an apply and a reset, the last chip refusing to turn off, NSFW
  withheld without a key, ratio round-trip), and the browse screen end to end —
  the Explicit chip is absent with no key, present with one, and applying it
  re-queries at purity `101` rather than leaving the old page up

The Android 16 tablet was initially visible to Flutter, but its ADB USB
transport disappeared before install, and it has not come back (`./tool/tela
devices` lists only Linux). Physical Home/Lock/Both application and the
three-tier download walkthrough remain smoke-test pending.

## Start of next session

### 1. Smoke-test on the device (blocked two sessions running)

**Uninstall tela from the device once before the next run.** The copy installed
there is signed with a debug key that no longer exists, so the first run after
the `~/.android` fix still hits a signature mismatch and still wipes data. After
that one uninstall, installs are stable and app data survives — which is what
makes any persistence test below meaningful. Every "did it persist?" result
recorded before this fix is worthless: the app was being reinstalled clean each
time.

Reconnect the Android 16 device and install the debug APK. Smoke-test Home,
Lock, and Both with one portrait and one large landscape wallpaper; then test
all three download tiers. For Gallery, confirm it appears in Photos. For Files,
pick a local shared-storage directory when Android's picker opens, then confirm
the resulting `tela/.nomedia` directory is visible through USB/MTP but absent
from Photos. For Private library, confirm no gallery entry is created. Then
change a destination in Settings, kill the app, reopen it, and confirm the choice
survived — the Drift path has only ever run against an in-memory database, never
a real file on a device. Record any OEM behavior here.

Now also worth a pass on the device: save a **real** Wallhaven key in Settings and
confirm it comes back verified. The whole save path has only ever run against fake
stores — never against the Android Keystore, and never against Wallhaven itself,
so the NSFW probe has not once made a real request. Then kill the app, reopen it,
and confirm Settings still says the key is saved.

Search and filters need the same pass: run an explicit listing end to end for the
first time (Filters → Explicit → Show wallpapers), and confirm the NSFW rules hold
where it counts — download an explicit wallpaper and check it is **not** in Photos
under any tier. Also scroll deep into the Random tab: the shuffle seed carries
through `SearchWallpapers.nextPageAfter`, which is covered by unit tests but has
never paged a real Wallhaven response, and a lost seed shows up only as repeated
images several pages in.

### 2. Then: Wave 2

Wave 1 is code-complete, so once the device pass is clean there is no Wave 1 work
left to schedule. Wave 2 is favorites (the Drift database is already open and its
settings table is the first of them), Material You dynamic colour, and the account
endpoints — `GET /settings` among them, which is the one Wave 2 pulls in that
would *also* give the API key a first-class validity check, if the NSFW probe ever
proves too blunt.
