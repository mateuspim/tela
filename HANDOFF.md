# tela handoff

Updated: 2026-07-14

## Current milestone

Wave 0 is complete at `209101c`. Wave 1 landed slice by slice: the apply core
loop is `bcba151`, detail metadata is `36ec9f9`, three-tier downloads are
`28fa0b1` + `568e1ef`, persisted per-purity storage settings are `1d8e4de`,
API-key entry is `be7c7d2`, and search + filters are `a3baacd`.

**Wave 1 is complete and smoke-tested on the device.** Apply (home/lock/both),
all three download tiers, a real API key against real Wallhaven, and the
explicit listing all pass on hardware. One item was not exercised: **deep paging
of the Random tab**, so the shuffle seed carried by
`SearchWallpapers.nextPageAfter` has still never survived a real multi-page
Wallhaven response. It is unit-tested; a lost seed would show up only as
repeated images several pages in.

**Wave 2 is now in progress.** Favorites are `0cf2781`, Material You is
`c056369`, the private library is `a2e5da7` + `5f747a8`, the download history is
`50485bd`, and the colour filter with the shared status states is `HEAD`; see
"Wave 2 so far" below. **One slice remains: account `/settings` sync.**

The app supports the thin product loop:

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

## Wave 2 so far

**Favorites** (`0cf2781`). Tap the heart on the detail screen to keep a
wallpaper; the browse app bar opens the shelf. `FavoritesRepository` is a
pure-domain port with a Drift adapter, and `ToggleFavorite` returns the state it
landed in so the heart renders from the answer rather than re-reading the store.

**Material You** (`c056369`). `DynamicColorBuilder` feeds the device palette to
`TelaTheme`, which harmonizes it. The seed stays a live path, not a placeholder.

**Private library** (`a2e5da7`, and its app-lock in `5f747a8`). The `appPrivate`
tier had been written to since Wave 1 with no way to read it back, so explicit
downloads were write-only — uninstalling was the only way to get a file out. It
is now listable and deletable, behind `FLAG_SECURE` and an optional biometric/PIN
gate. Reached from Settings, not the browse app bar.

**Download history + set again** (`50485bd`). Every non-explicit download is now
recorded in Drift (schema v3), and the history opens from Settings. Tapping a
tile goes straight to the Home/Lock/Both sheet and applies the wallpaper **from
the file the download already left on the device** — no second fetch, and it
works with no network. `WallpaperApplier` therefore takes a `Uri` source rather
than a URL, and Kotlin reads a local `file://` or `content://` through the
`ContentResolver` when the scheme is not http(s).

**Colour filter + shared status states** (`HEAD`). The filter sheet now carries
Wallhaven's 29-swatch palette, and every grid in the app draws its empty and
failed states through one `WallpaperStatusView` instead of four hand-rolled
centred `Text`s. Browse, favorites, the download history, and the private
library now say "nothing here" the same way, and a failure picks its icon from
what actually failed — the offline cloud for a dead network, not a generic
error triangle.

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
- **Favorites store the whole wallpaper row, not just its Wallhaven id.** An
  id-only table would need the network to render the favorites grid, and
  offline-readable favorites are the entire reason the feature exists (it is
  PLAN's Wave 2 exit criterion). Every field apply and download need is in the
  row, so a favorite can still be set as a wallpaper in airplane mode.
- **An unrecognised stored purity reads back as `nsfw`, not `sfw`** — the
  deliberate opposite of every other fallback in the codebase, which all fail
  toward the safe default. Purity is what routes a download and gates MediaStore
  indexing, so a corrupt row misread as safe is the one mistake that could index
  an explicit image. Misread as explicit it is merely over-protected.
- Favorites are **local**, and are not Wallhaven's account favorites. Syncing
  those is a different feature and belongs with the `/settings` account slice.
- The v1→v2 migration **adds** a table rather than recreating the database, and
  a test builds a v1 database by hand with raw `sqlite3` to prove the settings
  survive it (drift can only ever create the *current* schema, so nothing else
  exercises the upgrade path a real phone takes). The device carries real
  download destinations; "the app forgot my settings" is the exact failure
  `91cb7b0` spent a session chasing, and it must not come back as a migration
  bug.
- `flutter_staggered_grid_view` became a **direct** dependency. The favorites
  grid is unpaged, so it cannot use `infinite_scroll_pagination`'s
  `PagedMasonryGridView`, and importing a transitive dependency is both a lint
  error and a version-resolution trap.
- A Material You palette whose brightness disagrees with the one requested is
  **refused**, not adapted: a light scheme rendered in dark mode is how you get
  white-on-white text. Quiet-but-wrong beats unreadable. The seed is not dead
  code — Monet is Android 12+ and tela's minSdk is 29.
- `dynamic_color` compiles under the pinned AGP 9 toolchain, which is precisely
  what `flutter_wallpaper_plus` could not do. Both APKs still build.
- **Only the app-private tier is listable, and that asymmetry is the design.**
  The other two tiers land where the system gallery or a file manager already
  shows the result; app-private files are visible to nothing but tela. `ImageStore`
  therefore grew `privateImages()` and `deletePrivateImage()` and *not* a general
  "list any tier" method.
- The app-lock gate lives **inside** `PrivateLibraryScreen`, not on the Settings
  tile that opens it. A route can be reached more than one way, and gating the
  button would leave a deep link to `/private` walking straight past it.
- **The lock deliberately declines to lock anyone out, in two places.** A device
  with no biometric *and* no screen lock cannot answer a prompt, so the gate
  steps aside and the switch hides itself — a setting that cannot be satisfied
  would trap the owner outside their own files. And `biometricOnly` stays false,
  so a fingerprint that stops reading is never the only key.
- A corrupt *lock* setting reads as **locked**, unlike the storage-tier fallbacks
  that read as the safe default. "I can't tell whether this was locked" has only
  one safe reading. (Absent still means unlocked: the lock is opt-in.)
- `FLAG_SECURE` is taken in `initState` and released in `dispose`, and the
  `ScreenGuard` is held in a field because **Riverpod forbids `ref.read` in
  `dispose`** — there is no second chance to release it. Left on, it would
  silently block screenshots of the whole app.
- The native delete matches the id against `VALID_ID` *before* building any path.
  The id arrives over a method channel, and `../../databases/tela` is how a
  listing feature turns into an arbitrary-file delete.
- Private-library tiles are **square, not masonry**. Masonry packs by aspect
  ratio; a file on disk has no known ratio until it is decoded, and a browse tile
  only gets its shape from Wallhaven's metadata, which these do not have. (A
  zero-height tile is also dropped from the semantics tree, which is how the
  first version failed its own accessibility test.)
- **`MainActivity` is now a `FlutterFragmentActivity`.** `local_auth`'s
  BiometricPrompt needs a `FragmentManager`, and a plain `FlutterActivity` fails
  at *prompt* time rather than at build time — the app-lock would have compiled
  and simply not worked.
- The manifest now carries `USE_BIOMETRIC` (declared) and `USE_FINGERPRINT`
  (**merged in by `local_auth_android`**, not by us — worth knowing before the
  next permission audit reads it as a regression). Both are normal, install-time
  permissions. There is still **no storage or media permission**.
- **"Set again" reads the file, and that is why the applier port changed.** The
  handoff had predicted a pure-Dart slice, but re-fetching six megabytes tela
  already wrote is not "setting it again" — it is downloading it again, and it
  needs a network the user may not have. `WallpaperApplier.apply` now takes a
  `Uri` source, and the Kotlin branches on its scheme: http(s) downloads,
  anything else goes through the `ContentResolver`, which covers all three tiers
  (a MediaStore image tela inserted, a document under the user's SAF tree, and an
  app-private file) with **no new permission** — an app can always read what it
  created, and the SAF grant is already persisted.
- A local file that cannot be read maps to the same `WallpaperApplyProblem.source`
  a failed download does, and `ApplyDownload` retries against Wallhaven when it
  sees it. A gallery download can be deleted from Photos and a document one from
  a file manager, neither of which tela hears about; the history row still knows
  the source URL, so a deleted file costs a re-fetch rather than the feature.
  Only *that* problem is retried — a wallpaper Android itself rejected would fail
  the same way the second time, at the price of a pointless download.
- **Explicit downloads are never recorded in the history, in any tier.** This is
  the one place the history deliberately forgets something. Those files already
  have a home — the private library, which lists the real files behind
  `FLAG_SECURE` and the app-lock. A history row is the opposite of that: a
  browsable index of thumbnails and URLs on an ungated screen, inside a database
  that Android's Auto Backup carries off the device (the API key is excluded from
  backup; the database is not). Refused in `DownloadWallpaper` *and* in the Drift
  adapter, and `downloads()` additionally withholds any row whose purity no longer
  reads as safe — which is exactly what a corrupt row does, since `storedPurity`
  fails closed to `nsfw`.
- The downloads table is keyed by wallpaper id, not by download event: the
  history is "what is on this device", so downloading the same wallpaper twice
  updates one row instead of stacking duplicates.
- The wallpaper columns are now a **Drift table mixin** (`WallpaperColumns`), and
  the fail-safe parses a **shared `stored_wallpaper_fields.dart`**. Favorites and
  downloads store the same eleven fields for the same reason (render offline,
  apply offline), and the purity fail-closed rule is the load-bearing part of
  both — a second copy of it is a second chance to get it wrong. The generated
  favorites schema is byte-identical to what v2 shipped.
- The Home/Lock/Both sheet moved to `core/ui/wallpaper_target_sheet.dart`. Two
  screens can now apply a wallpaper, and "Set wallpaper on" must read the same on
  both.
- The settings widget test now pumps a **tall viewport**. Settings is a
  `ListView`, and the new history tile pushed the explicit-purity picker below a
  phone-sized test fold, where it is never built — which failed as "the setting
  disappeared" rather than "scroll down".
- **The colour filter is one colour, not a set**, unlike categories and purity.
  Wallhaven's `colors` param matches a single palette entry; a comma-separated
  list is not a union, it is a request that matches nothing. So the swatches are
  a radio, and picking a second colour replaces the first.
- **The palette is a fixed list of 29, not a free hex field.** Wallhaven matches
  against its own buckets, so an arbitrary `#123456` returns zero results —
  which would read as a broken filter rather than an unsupported one. Wallhaven
  quantizes every wallpaper's own colours down to the same 29, so a colour seen
  on a detail screen is always one the filter can search for.
- **`SearchQuery.withColor` exists because `copyWith` structurally cannot clear
  a nullable field.** `copyWith` fills an omitted argument from `this`, so it
  reads `color: null` as "leave it alone" and not as "no colour" — the two are
  indistinguishable at the call site. Without a separate method the colour
  filter would have been *unremovable*. The same hole is still open for
  `atLeast` and `seed`; neither is ever cleared today, so neither has been given
  the same treatment yet. It is a trap for whoever needs to clear one first.
- **`WallpaperColor` has a throwing constructor *and* a fail-soft `readAll`**,
  and the split is on purpose. The filter path passes palette constants, where a
  bad value is a programmer error and should throw. The display path passes
  whatever Wallhaven put in a wallpaper's JSON, where one unreadable swatch must
  cost that swatch and not the detail screen it sits on. The detail screen's old
  `int.parse('FF${hex.substring(1)}')` would have thrown on a malformed colour
  and taken the whole metadata panel with it; routing it through `readAll`
  fixed that on the way past.
- **The filter sheet's actions are now pinned below a scrolling list**, not the
  last row of it. The palette is tall enough that "Show wallpapers" fell off the
  bottom of the sheet — an apply button you have to go looking for is one that
  doesn't get pressed. A widget test holds the button on screen so the next
  filter group cannot quietly push it off again.
- `wallpaper_failure_text.dart` **moved from `features/browse` to `core/ui`**.
  Three features now report the same Wallhaven failures, and `core` may not
  import a feature. The icon-per-failure switch lives next to it in
  `WallpaperStatusView`; both are exhaustive over the sealed failure type, so a
  new failure is a compile error rather than a blank screen with a generic
  triangle.
- The status view's *empty* states take an explicit icon from each screen rather
  than deriving one, because "empty" means something different on each: browse
  found nothing, favorites has never been used, the history is genuinely empty
  by design for explicit downloads. Only the *failure* states derive their icon,
  because there the failure itself is the fact worth reading.

## Verification

- `./tool/tela dart format .`: clean
- `./tool/tela analyze`: clean
- `./tool/tela test`: 187 tests pass
- Three-tap browse → detail → Both widget flow: covered
- Domain use case and all native target/error mappings: covered
- `/w/{id}` is covered by a detail JSON fixture, mapper boundary tests, and a
  detail widget metadata test
- `./tool/tela build apk --debug`: passes
- `./tool/tela build apk --release`: passes
- Release merged manifest re-inspected after the private library: `INTERNET`,
  `SET_WALLPAPER`, `USE_BIOMETRIC`, `USE_FINGERPRINT`. Still no
  `READ_EXTERNAL_STORAGE` and no `READ_MEDIA_*`
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

- Favorites are covered at every layer: the use case (saves an unsaved
  wallpaper, forgets a saved one without re-saving it, round-trips to the state
  it started in, leaves other favorites alone), the Drift adapter (every field
  of the round trip, newest-first ordering, upsert-not-append, forget as a
  no-op, an NSFW favorite surviving as NSFW, and both fail-safe parses), and the
  screens (empty state, a tile per favorite in order, the heart filling and
  emptying, and the grid rendering with no API bound at all)
- The v1→v2 migration is tested against a hand-built v1 database: the settings
  survive and the favorites table appears
- Private library: the method-channel adapter (listing mapped to domain images,
  an empty tier listing nothing rather than failing, a mangled row skipped rather
  than emptying the library, listing and delete failures mapped to safe failures),
  and the screen — `FLAG_SECURE` held while it is open and released when it is
  left, the empty state, a tile per image, and a long-press deleting only after
  it is confirmed
- The app-lock gate: nothing is listed until the prompt passes, a failed prompt
  leaves only a retry, a dismissed prompt can be retried, no prompt is raised when
  the lock is off, and the gate steps aside on a device that cannot ask. The Drift
  adapter covers the opt-in default, the round trip, and the corrupt-reads-locked
  rule
- Material You: the device palette is used, a missing one falls back to the
  seed, a wrong-brightness one is refused, and the chrome stays untinted
- Download history: the use case (records where the file actually landed, refuses
  every explicit download in every tier while still storing the file), the Drift
  adapter (full round trip, newest first, re-download upserts rather than stacks,
  an explicit record refused, and a row whose purity reads corrupt withheld from
  the listing), `ApplyDownload` (applies the local file, falls back to Wallhaven
  only when that file is unreadable, and does *not* re-download after a rejected
  apply), and the screen — empty state, a tile per download newest-first, and a
  tap applying the stored URI rather than the Wallhaven URL, with no API bound
- The v2→v3 migration is tested against a hand-built v2 database: the favorite
  survives, the settings survive, and the downloads table appears. v1→v3 lands
  both new tables at once, which is the jump a device that skipped v2 takes
- `./tool/tela build apk --debug` and `--release`: pass, and the release merged
  manifest still shows only `INTERNET`, `SET_WALLPAPER`, `USE_BIOMETRIC`,
  `USE_FINGERPRINT` — reading back a download needs no permission
- Colour filter: the domain model (both Wallhaven dialects, case normalization,
  four rejected shapes, the ArgumentError naming the value *and* `#rrggbb`, RGB
  without alpha, `readAll` dropping one bad colour instead of the list, and the
  palette being 29 unique encodable colours that contain the fixture's own),
  `SearchQuery` (no `colors` param when unfiltered, a bare hex when filtered,
  equality, and `withColor` clearing what `copyWith` cannot while leaving every
  other field alone), and the browse screen end to end — a swatch re-queries with
  `colors`, tapping it again clears it, "Any color" clears it, and the apply
  button stays on screen under the palette
- The shared status view: icon and message render, no button when there is no
  action, the action fires, each failure gets its own icon and sentence, and
  neither a raw non-Wallhaven error nor a developer-facing failure message ever
  reaches the screen

The Random tab's deep paging is the one Wave 1 behaviour never exercised on
hardware — see below.

## Start of next session

### 1. Wave 2, last slice

**Account `/settings` sync** is all that is left of Wave 2. `GET /settings` on
`WallhavenApi`, pulling the account's default purity/categories/resolutions. This
is also the endpoint that would give the API key a first-class validity check, if
the NSFW probe used by `SaveApiKey` ever proves too blunt.

The open design question is **when it syncs, and what wins**. tela already has
browse defaults and a persisted `SearchQuery`; pulling the account's defaults on
top of a filter the user set by hand would silently undo their choice. Landing
this as "fetch once when a key is saved, and only seed the *defaults*" is
probably right, but it is a decision, not an implementation detail.

Two things were deliberately left out rather than forgotten:

- The history has **no way to remove an entry**. "Remove from history" and
  "delete the file" are two different actions, and offering the first next to a
  tile that looks like a file is how someone deletes the wrong thing. Worth
  designing, not worth guessing at.
- **Only `color` got a `withColor`.** `SearchQuery.atLeast` and `seed` have the
  same `copyWith`-cannot-clear hole; neither is ever cleared today, so neither
  was given an escape hatch it does not need yet. Whoever needs to clear one
  first will find the trap — see the decision above.

### 2. Owed on the device

Nothing in Wave 2 has run on hardware yet. In rough order of what would actually
bite:

- **The app-lock, end to end.** It has only ever met `FakeAppLock`. Turn it on in
  Settings, leave the private library, come back, and confirm the prompt appears
  and the PIN fallback works. `MainActivity` became a `FlutterFragmentActivity`
  for this; it compiles, but the *prompt* is the thing a plain `FlutterActivity`
  would have broken, and only a device shows that.
- **`FLAG_SECURE`.** Open the private library and check the app switcher shows a
  blank card, and that a screenshot is refused. Then leave it and confirm
  screenshots work again everywhere else — a leaked flag would disable them app-wide.
- **The private library against real files.** It has never listed a real
  `filesDir/wallpapers`. Download an explicit wallpaper, confirm it appears there,
  delete it, and confirm it is gone and still absent from Photos.
- **"Set again", from each tier that can hold a file.** The applier has only ever
  met a fake `Uri`. Download one wallpaper to Gallery and one to Files-not-gallery,
  open the history, and set each again — the `content://` read is the new code
  path, and a MediaStore URI and a SAF document URI fail differently when they
  fail. Then delete one of the files from Photos and set it again anyway: it must
  quietly re-fetch from Wallhaven rather than fail.
- **The v2→v3 migration on the real database.** The test builds a v2 database by
  hand, but the device holds the actual one. Confirm the download destinations,
  the API key, and the existing favorites survive the first launch of this build.
- **Favorites persistence.** Favorite a wallpaper, kill the app, reopen it, and
  confirm it is still there and still renders in airplane mode.
- **Material You.** Change the system wallpaper/accent and confirm tela's chrome
  follows.
- **The colour filter against real Wallhaven.** It has only ever met
  `FakeWallhavenApi`, so the `colors=0066cc` param has never been answered by the
  real server. Pick a swatch, confirm the grid actually comes back blue, and
  confirm an unpopular colour returns the empty state rather than an error. Also
  check the palette is usable one-handed on a real phone — 29 swatches is a lot
  of sheet, and the pinned apply button is the thing that makes it survivable.
- **Random-tab deep paging** — still owed from Wave 1. The shuffle seed carries
  through `SearchWallpapers.nextPageAfter`, unit-tested but never against a real
  multi-page Wallhaven response; a lost seed shows up only as repeated images
  several pages in.
