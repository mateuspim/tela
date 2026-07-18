# tela handoff

Updated: 2026-07-17

## START HERE — the UI/UX pass is code-complete (both threads); only the owner's device pass remains

The owner asked for a UI/UX pass — "make it more beautiful" **and** fix some
core-loop interactions. **Both threads are now built.** The interaction half (B)
was five slices, `f662ba4` → `163c414`; the beauty half (A) is A1/A2/A3, ending
at **A3 (`2e7034c`)** — the skeleton wall and tile edge (see *The beauty thread*
below). The suite is **670 tests** green, `analyze` and `dart format` clean,
every new behaviour mutation-checked (revert the fix, watch the new test fail
with the real symptom, restore). **None of the visual work has been on the
device yet — that pass is the one thing owed** (see the end of this section).

The pass was **planned first, then sliced**, at the owner's request, with the
two open threads split: **A = beauty** (expressive chrome — a branded accent, a
real logo mark, editorial headers, a glass app bar; *not started*), **B =
interactions** (built below).

| slice | commit | what the user can now do |
|---|---|---|
| B1 | `f662ba4` | Follow a tag/uploader and **keep the filters you were browsing** — sketchy stays sketchy across a tag→wallpaper→tag chain |
| B2a | `eea8021` | **Tap a dominant colour** → a listing of more wallpapers in it, under the same filters |
| B2b | `01a517e` | Open a wallpaper's **source**, and a **View on Wallhaven** action, in the device browser |
| B3 | `fd03c58` | **Swipe or step between wallpapers on the detail page**, not only in fullscreen |
| B4 | `163c414` | A **Library tab** hubbing favorites + download history + private, so the two tiers aren't buried in Settings |

### The decisions inside these worth not re-litigating

- **B1's root cause was one layer down from where it looked.** Following a link
  reseeded filters from the *global* Browse query (`linkedQueryProvider`'s
  `build()` read `browseQueryProvider`), so a listing you had narrowed to sketchy
  lost it the moment you drilled through a wallpaper. The detail screen carried
  **no query context at all**. The fix threads the active `SearchQuery` as an
  *origin seed* grid → detail → follow (`WallpaperDetailArgs`, `LinkedListingArgs`)
  and makes `LinkedListingScreen` seed-authoritative on local state — which
  **retired `linkedQueryProvider`/`LinkedQueryController`**, a global holder that
  only ever served that one transient screen. Safe against the `id:` exclusivity
  rule: the link's `id:N` stays the sole `q` term; inherited purity/ratios/colour
  ride as separate params and never pollute `q`.
- **B2a generalised the link, it didn't special-case colour.** `WallpaperLink`
  went from a `term` getter to `narrow(query)`, so a link can be a `q` operator
  (tag, uploader) **or** a param (colour, via `ColorLink` → `withColor`) without
  the screen branching. Colour therefore flows through the *same* follow path as
  tags, inheriting B1's seed for free — the detail screen needed no change.
- **B2b is a real port, per the CLAUDE.md rule.** `ExternalLink`
  (over `url_launcher`) + a domain `ExternalLinkFailure` that carries only a
  category, so a tapped address never reaches logs/UI. The Wallhaven page URL is
  centralised on `Wallpaper.pageUrl` (reused by `ShareWallpaper`). A free-text
  source that isn't an `http(s)` URL stays plain, copyable text. **Needed a
  manifest change**: an `https` `<queries>` intent so `launchUrl` resolves a
  browser under Android 11+ package visibility.
- **B3 reuses the session, not a second paging model.** The detail preview is a
  `PageView` over the *same* `GallerySessionController` the fullscreen viewer
  pages. Pager↔session sync is one guarded loop (swipe → `select`; an outside
  move — a chevron, or the fullscreen viewer paging the shared session while
  Detail sits behind it — moves the session first and the pager jumps to catch
  up). **Only the selected page carries the Hero**, so the neighbours the pager
  pre-builds can't collide with a grid tile's tag ("multiple heroes").
- **B4 was additive, and Private stayed discreet on purpose.** History/Private
  were reachable only through Settings, where their placement is *deliberately*
  contextual (history by the download routing, private by the app-lock — the old
  `_PrivateLibraryTile` docstring argued for it). So the Library tab **adds** a
  faster path without taking the Settings ones away; the entry row is one shared
  `LibraryDestinationTile` used by both, and Private is a plain locked row, never
  a thumbnailed shortcut. `FavoritesScreen` was extracted to `FavoritesGrid` and
  retired; the favorites shell branch is now `/library`.

### Owed on the device (only the owner can), for this pass

1. **B2b's browser hand-off** — `launchUrl` is a real platform round trip, like
   the wallpaper-apply ones; it can't be unit-tested. Tap *View on Wallhaven* and
   a source link on the tablet.
2. **B5 — "the history gallery is finnicky."** The owner reported this but it was
   never pinned to a symptom; it needs eyes on the device to diagnose before it
   can be fixed. **Not started.**
3. A general look at B1–B4 on real hardware: the colour drilldown, the detail
   swipe/chevrons, and the new Library nav.

### The beauty thread (A) — A1, A2 and A3 are built; only an owner's device pass remains

**A3 landed (`2e7034c`).** Two pieces, both owner-eye-owed on the SM-X730 like
the rest of the beauty work:

- **`WallpaperGridSkeleton`** (`core/ui/wallpaper_grid_skeleton.dart`) replaces
  the lone centred spinner on every shelf — Browse's first page, Favorites,
  Download History, Private Library — with a masonry of placeholder tiles under
  a slow shimmer, in the *exact* grid rhythm (columns, 12dp gutters, safe-area
  inset, 16dp corners) the real wall lands in, so nothing jumps when images
  arrive. **Do not give it a scroll view of its own:** the pager hosts a
  first-page indicator in `SliverFillRemaining(hasScrollBody: false)`, which
  content-sizes its child, and a nested `ScrollView` there throws "does not
  support returning intrinsic dimensions". It lays tiles out as clipped columns
  and honours reduced motion (sweep dropped, tiles static, no controller left
  repeating). Pinned by `test/core/ui/wallpaper_grid_skeleton_test.dart`.
- **`wallpaperTileEdge`** (`core/ui/wallpaper_grid_columns.dart`) — one shared
  hairline (`outlineVariant @ .22`) drawn *over* every thumbnail as a
  `foregroundDecoration`, inside the tile's clip, so a near-white/near-black
  wallpaper does not melt into the surface. Shared by the browse tile and the
  private tile so they cannot drift.

The knobs owed a device look: the shimmer tone (`surfaceContainerHigh` glint on
`surfaceContainerHighest`), the 1200ms sweep, and the `.22` edge alpha.

*(Historical, from before A3 — the direction and the earlier slices:)*

Agreed direction: **expressive chrome, but keep Material You** — borrow the
device palette for surfaces, add a fixed tela accent (the `0xFF7772E5` seed
family) for brand moments, harmonised alongside Monet so identity survives on
every device. The slices, updated as they land:

| slice | piece | state |
|---|---|---|
| A1 | brand accent — *pick any accent, or follow the wallpaper* | ✅ `e6967cb` |
| A1 | a real `tela` wordmark + a display face (Bricolage Grotesque) | ✅ `21f75bc` |
| A1 | **stronger selected states** | ✅ (this session) |
| A2 | editorial shelf headers / plaques | ✅ `21f75bc` |
| A2 | **an opaque gradient app bar** (`GradientAppBar`) | ✅ (this session) |
| A3 | **a shimmering skeleton wall + a hairline tile edge** | ✅ `2e7034c` |

**A2's app bar: frosted glass was built, rejected on device, and replaced with
an opaque gradient band — do not rebuild the frosted one.** First cut was frosted
glass (`GlassAppBar` + `extendBodyBehindAppBar`, grid scrolling *under* a
translucent blurred bar). On the SM-X730 it read as broken: the bar is
see-through, so the wall of thumbnails showed *through* the search bar and bled
into the status-bar strip above it — busy, fighting "photos lead, chrome stays
quiet." Owner's words: "the wallpapers still show up behind the search bar."
Reverted (`8855eda` + inset-fix `400f6f3`, both undone).

The replacement is **`GradientAppBar`** (`core/ui/gradient_app_bar.dart`): a plain
`AppBar` on an **opaque** vertical wash — a brand-warmed `surfaceContainerHighest`
top settling to `surface`, with a hairline bottom edge. No
`extendBodyBehindAppBar`, so the grid stops cleanly beneath it and nothing shows
through; grid padding is untouched. Applied to **Browse, Library, LinkedListing,
Download History, Private Library**. Pinned by `gradient_app_bar_test.dart`, whose
load-bearing test asserts **every gradient stop is opaque** (drop one below 1 and
the wall leaks — the exact bug that killed the frosted bar). The tint strength is
one knob, `_accentWash` (`.10`); verified on device. Settings/Detail/crop keep a
plain `AppBar` — they adopt `GradientAppBar` trivially if consistency is wanted.
(Aside kept from the frosted work: `extendBodyBehindAppBar: true` makes Scaffold
fold the bar height into the body's `MediaQuery.padding.top` itself — adding your
own inset double-counts it.)

**A1's stronger selected states, decided.** All selection — bottom nav, rail,
Browse sorting tabs — rode Material's default `secondaryContainer`, so even under
a fixed accent the brand barely read in "you are here." Moved every selected
indicator to **`primaryContainer`** (the theme docstring already named "the
selected tab, the nav indicator" as accent moments) and added a **selected-label
weight bump** (w600 vs w500), so selection survives for anyone who can't split the
two container tones by hue. It is a single theme-level change in `theme.dart` —
three named helpers (`_navigationBarTheme`, `_navigationRailTheme`,
`_tabBarTheme`) that also retire the over-long inline `_themeFrom`. Pinned in
`test/app/theme_test.dart` (5 new tests, incl. the identity claim: under a fixed
accent the nav indicator resolves to *that accent's* `primaryContainer`),
mutation-checked. Filter-sheet `FilterChip`s and the `SegmentedButton` were left
on the default tone deliberately — they live in a transient modal, rarely beside
the nav; unify them in a follow-up if the split ever shows. **Not yet on the
device** — like all the beauty work, it wants an owner's eye on real hardware.

## Wave 4 — crop done; auto-rotate, collections, and Omarchy sync still open

*(Was the START HERE before the UI/UX pass above; still the live description of
Wave 4's product work.)*

Wave 3 is closed. **Wave 4's crop item is done, both halves.** The
system-editor half shipped first (`266a0d7`) and ran on the SM-X730: Detail's
*Adjust & set* hands a safe wallpaper to Android's own crop-and-set editor —
Samsung's "Wallpaper and style" picker on the right image, with Lock/Home
previews and reposition. **tela's own crop editor is now built too (`6a67ac3`)**,
for the two paths the OEM editor cannot serve. The suite is **614 tests** green
(from 598), `analyze` and `format` clean, and both `build apk --debug` and
`--release` succeed. There is also a new one-command deploy — `make deploy` — see
**The install rule**.

### The device taught us the AOSP path is dead on One UI — read this before touching it

The first build shipped only `getCropAndSetWallpaperIntent` and it **threw
`IllegalArgumentException` on the SM-X730** ("Couldn't open the wallpaper
editor"). That method is not a generic lookup: it pins the intent to the default
*launcher* package, then to a configured cropper package, and One UI ships
neither as a `CROP_AND_SET_WALLPAPER` handler — so it throws rather than
returns. It is simply dead on One UI, and likely other OEM skins.

The working path, verified on hardware, is a fallback: **`ACTION_ATTACH_DATA`
(`image/*`) wrapped in a chooser**. That is the "Use image as…" mechanism Gallery
fires; on the SM-X730 it resolves to `com.samsung.android.app.dressroom/
.presentation.SetAsWallPaperActivity` — the same crop/Home-Lock/widgets editor —
which read our FileProvider file cleanly (no `SecurityException`, no decode
error; the read grant forwards through the resolver). `SystemWallpaperEditing`
now tries the AOSP intent first (a cleaner one-tap cropper where it works, e.g.
stock Android) and falls back to the chooser. **Do not** try to target the OEM
component directly to skip the chooser: launching `SetAsWallPaperActivity` by
explicit component bounced straight back to the launcher on the tablet, and
picking "the wallpaper app" out of the handler list needs a per-brand heuristic
that already broke once here (`SET_WALLPAPER` without a type does not match
Samsung's editor). The chooser is the OEM-agnostic path and the owner accepted
its one cost: WhatsApp/Contacts appear beside "Wallpaper and style" in the list.

### The slice, and the decision inside it worth not re-litigating

The idea came from the owner: on a Samsung, setting a wallpaper from the gallery
opens a system app that resizes and shows the widgets, so hand off to *that*
rather than building a cropper. It is the right call and it is nearly free here —
the hand-off needs a `content://` URI typed `image/*`, and `WallpaperSharing`
already had every piece: the FileProvider, the authority, the one-shot read
grant, the download-to-cache.

**But it is SFW-only, and that is not a new rule.** The pixels reach a separate
app that keeps its own wallpaper history — the ungated index the private tier
exists to prevent — which is the same shape as the image share the domain already
refuses for explicit content. So `mayExportBitmap` is now the single home for
"explicit pixels never leave the app", and **`shareOptionsFor` asks it too**, so
the two cannot drift apart. A test pins exactly that agreement across every
purity. Enforced twice, the way every NSFW rule here is: `AdjustWallpaper` throws,
and the button is withheld.

Three things that are deliberate, not oversights:

- **Success says nothing.** The editor owns the crop, the Home/Lock/Both choice
  and the apply, and hands back no result. A "wallpaper set" snackbar would be a
  lie — the user may still be framing it, or may have backed out. Only failures
  speak, and "this device has no wallpaper editor" is its own message because it
  is not a thing to retry.
- **`resolveActivity` is not used to detect a missing editor.** From API 30
  package visibility can hide a handler from our own query even when the device
  has one — a null there would refuse a picker that exists. The chooser fallback
  sidesteps this: the system resolver enumerates handlers out of our process, so
  no `<queries>` entry is needed. A missing editor surfaces as
  `ActivityNotFoundException`, caught at the launch.
- **A separate cache folder** (`adjusted/`, added to `file_paths.xml`). Both
  hand-off folders wipe on the way in, so sharing one would make a share and an
  adjust delete each other's file. `ImageHandoffCache` now owns that wipe for
  both — it is a privacy rule, and it earns one home.

### tela's own crop editor — built (`6a67ac3`); on-device apply still owner-owed

The other half of the crop item, and the fulfilment of what this section used to
say was owed. It decodes only the framed sub-rect
(`BitmapRegionDecoder.decodeRegion` → `setBitmap(bitmap, null, …)`) inside tela's
own process, so the pixels never leave the app — as safe for NSFW as
`ApplyWallpaper` already is, and deterministic where `setStream`'s
`visibleCropHint` is only a *hint* OEMs may reinterpret. Decoding just the region
also dodges `PLAN.md` §15's 6K OOM. The native class is `WallpaperCropApplying`;
`MainActivity` reaches it through `applyCroppedWallpaper` on the wallpaper channel.

**Routing, decided:** SFW keeps the OEM editor, falling back to tela's cropper
only where no editor resolves; NSFW's Adjust *is* the cropper, unconditionally.
The button shows for every purity now — `AdjustWallpaper` still refuses to route
explicit pixels to the OEM editor, but the cropper is a separate use case
(`ApplyCroppedWallpaper`) with **no purity gate**, because it never exports.
Enforced the usual two ways: the domain use case, and the detail-screen routing.

**One bug found and fixed in the same commit** (owner, on device): the preview
flashed to black on every pinch. It sized the decoded widget to `image × scale`,
so each zoom frame re-decoded at a new resolution and drew the black placeholder.
It now decodes **once** at cover scale and zooms via a paint-time `Transform`;
pinned by a regression test asserting the layer's layout size stays constant
while its on-screen rect grows, mutation-checked. Trade-off left in on purpose:
the preview softens at high zoom (a cover-scale decode upscaled), but the
*applied* wallpaper is full-res via the native region decode, so output is
unaffected. If that softening ever bothers someone, raise the decode base scale
in `crop_wallpaper_screen.dart`'s `_imageLayer` — the maths already divides it out.

The crop geometry is a pure `crop_geometry.dart` (cover scale, offset clamp,
source-rect mapping), unit-pinned and mutation-checked without a widget.

**Still owner-owed on device:** the native `BitmapRegionDecoder` → `setBitmap`
round trip. It changes the real wallpaper, so it is theirs to run — exactly like
the existing `applyWallpaper` round trip, and nothing here can unit-test it.
`make deploy` puts a release build on the tablet safely.

### The rest of Wave 4

Unbuilt, in `PLAN.md`'s own order: daily auto-rotate (WorkManager), collections
browser, and **Omarchy sync** — export favorites to an Aether-consumable format,
which is the one that closes the desktop↔mobile loop this app exists inside.

**Omarchy sync's unknown is already eliminated, so do not re-research it.**
Aether keeps `~/.config/aether/favorites.json`: a top-level JSON array whose
Wallhaven entries are `{id, path, thumbs:{small}, resolution, file_size}`, where
`path` is the full-res Wallhaven URL and the presence of `id` is what marks an
entry Wallhaven rather than local (`internal/favorites/service.go` in
`bjarneo/aether`). tela's `Wallpaper` covers every field exactly — `id`,
`fullImageUrl`, `thumbSmallUrl`, `resolution`, `fileSizeBytes` — and
`FavoritesRepository` stores the whole `Wallpaper`, so the export needs no
network. Two decisions remain open: the **transport** (write into the
`filesOutsideGallery` tier `PLAN.md` already calls the USB/MTP desktop-sync path,
versus pushing through the share sheet) and **NSFW** — whether explicit favorites'
URLs belong in a plaintext desktop config. Note a link is not an export under
`mayExportBitmap`, so that rule does not decide it for you.

### Still owed on hardware, and only the owner can

1. ~~The *Adjust & set* hand-off.~~ **Done, verified on the SM-X730 (2026-07-17):**
   tapped on a safe wallpaper, the chooser opened, "Wallpaper and style" launched
   Samsung's editor on the right image with the Lock/Home previews, and it read
   the FileProvider file with no grant or decode error. NSFW button absent,
   confirmed. The one thing still unseen by choice: pressing "Next" through to an
   actual apply (that would change the owner's wallpaper) — but the editor owns
   that step and hears nothing back either way.
2. The wallpaper-apply round trip — now **two** native paths, `applyWallpaper`
   and the crop editor's `applyCroppedWallpaper` (`BitmapRegionDecoder` →
   `setBitmap`). Both change the owner's wallpaper, so both are theirs to run.
3. The real biometric prompt (adb cannot pass `FLAG_SECURE`).
4. The cache figure after a real browse.
5. **The keystore**, whenever shipping matters. The only part of item 7 left.

Items 2–5 are unchanged in spirit and none of them block the above.

### Housekeeping — done

**Both worktrees are removed** (2026-07-16), along with the now-empty
`.worktrees/`. Each was verified spent before it went: no uncommitted changes, no
untracked files, no stashes, and zero commits not already on `master`. No
toolchain container had leaked, so there was nothing to `docker rm -f` this time
— that remains the thing to check first if phantom apk-missing errors ever
reappear.

The two **branch pointers survive** — `image-viewer-ux` (`ea9a7f9`) and
`ui-ux-polish` (`2d2a153`) — fully merged, costing nothing, and kept as history
rather than deleted on someone else's behalf. `git branch -d` takes them whenever
they stop being useful; it refuses if they are ever somehow unmerged, so it is
the safe way to ask.

## SOLVED — Wave 3's exit: the filters are proven on the wire (`7510500`)

**tela sends what it thinks it sends, and Wallhaven honours it.** Proven end to
end on 2026-07-16, and the exit criterion `PLAN.md` §12 set for Wave 3 is met.

**The old handoff's framing was wrong in a way worth naming, so the next agent
does not redo the work.** It said both halves were open. Wallhaven's half had in
fact been done on 2026-07-14 and written down where it belonged — in the
docstrings of `ratio_choice.dart` and `resolution_filter.dart`, dated, with the
numbers. The handoff simply did not know. **Read those two files before probing
the API; the comment convention is doing its job and the evidence is in them.**
Re-run live on 2026-07-16, every claim still holds:

| probe | real server says |
|---|---|
| `ratios=9x20` | all ratio 0.45 — arbitrary `WxH` is honoured |
| `ratios=9x19` / `9x21` | honoured — 268 / 80 total, all 0.47 / 0.43 |
| `ratios=bogus` | **identical listing to no filter** (same ids) — the trap |
| `ratios=portrait` | 0.49→0.85, not a synonym for any exact ratio |
| `atleast=1920x1080` | nothing below the floor |
| `atleast` **+** `resolutions` | identical to `atleast` alone — `resolutions` dropped |
| `resolutions=2560x1440` alone | exact, one distinct size |

**The real gap was narrower than described, and one layer lower.**
`SearchQuery.toQueryParameters()` returns a param *map* and
`search_query_test.dart` covers that map well. What nothing could see was **Dio
encoding that map into a URI**: `FakeWallhavenApi` records a `SearchQuery`, so it
sits *above* the encoding, and so do the map tests. `test/data/dio_wallhaven_api_test.dart`
(12 tests) closes it over `FakeWallhavenTransport`, a fake at Dio's
`HttpClientAdapter` — below serialization — capturing the literal URI. Both
claims unique to that file are mutation-checked (break the base URL → 2 fail;
union separator `,`→`|` → 2 fail).

**The one thing that nearly bit**: Dart's `Uri.encodeQueryComponent` escapes
commas, so tela's `ratios=16x9,9x16` leaves the device as `ratios=16x9%2C9x16`.
Wallhaven decodes it — both forms answer identically (total 10619) — so it is
**not** a bug, but nothing in the codebase knew that, and a server that stopped
decoding it would cost the union filter with no error. Pinned by test now.

**How the loop was actually closed**, and the trick is reusable: have the test
print the URI tela emits, then `curl` *those exact bytes*. The test proves
emission, the curl proves the server honours it; neither alone is the claim.

```
phone  1080x2400 → …&atleast=1080x2400&ratios=9x16&page=1  → 2575 results, all 0.56, none below screen
tablet 1600x2560 → …&atleast=1600x2560&ratios=9x16&page=1  → 2035 results, all 0.56
q+union → q=sunset+%2B%22city+lights%22&ratios=16x9%2C9x16 → identical to the hand-written form
```

So the filter badge showing **1** on a fresh launch (the *Automatic* resolution
folding the screen in) is now understood rather than merely observed: that is
`atleast=<screen>` reaching the real server, and it works.

### Two product observations, neither a bug — judgement calls, not defects

- **Exotic ratios are honoured but thinly stocked**: 9x20 has 339 wallpapers,
  9x19 has 268, 9x21 just **80**. `ExactRatio.ofScreen` is correct, but on an
  unusual phone it can hand the user a near-empty grid. **A sparse grid and a
  broken filter look alike** — worth remembering on the device pass.
- **The default `ratios: [ExactRatio(9, 16)]` is not the shape of a modern
  phone.** A 1080x2400 screen is 9x20, so the default browse returns 9x16 images
  that will always be cropped. This looks deliberate — 9x16 is by far the
  best-stocked portrait shape — and was left alone, but nobody stated it.

## SOLVED — the Drift test seam (`3a09f67`)

`telaDatabaseProvider` **has no default any more**. It used to open the real
database, which every Drift-backed port hangs off — settings, favorites,
download history, blocklist — so any test mounting a widget that reached one got
the real thing. Mounting a `WallpaperGrid` was enough, since its `build` listens
to the blocklist.

**The failure never named a database**, which is why it cost two harnesses.
`TelaDatabase.open()` resolves through path_provider, which answers no plugin
under `flutter test`, *lazily* — so the provider constructed fine and the error
landed elsewhere as an `AsyncError` in `blockedTagsProvider`, which the grid's
own change-gate correctly ignores as "no value yet". The symptom was an empty
grid and a `RangeError` from tapping a tile that was never built. Verified by
deleting the override from `gallery_session_launch_test` and watching exactly
that.

Unbound now throws by name at the read, naming both ways out. `main.dart`
applies the production binding with `overrideWith(openTelaDatabase)` — still
lazy, so boot is unchanged. No existing test needed touching; all 557 were
already overriding their ports properly. Pinned by
`test/app/tela_database_binding_test.dart` (4 tests), mutation-checked.

**The other fix was considered and rejected**, so do not re-litigate it: folding
blocked names into `SearchQuery` at the provider would have let the grid drop
the blocklist entirely, but `blockedTagNames` is documented as *"not something a
screen sets"* — the use case fills it in right before the request leaves,
precisely so no feature can forget. Trading that production invariant for
convenient tests is a bad trade.

## SOLVED — the release cold-launch hang

**Fixed**, in `wallpaper_grid.dart`'s `_retry()`. Four for four clean cold
launches on the SM-X730 in release, untouched, grid fully loaded — where it used
to spin forever. The suite was **557 tests** green at this fix; it is **561**
now that the database seam is pinned too.

The lead in the old handoff pointed at the right two lines and the wrong
mechanism, so the *shape* is worth keeping:

**`PagingController.refresh()` does not re-fetch.** It sets `operation = null`
and `value = value.reset()`, and that is all. The re-fetch is a *side effect*:
`PagedLayoutBuilder.didUpdateWidget` fires one only when it sees `oldWidget.state
!= widget.state`. `PagingState` compares **by value** (deep equality on
`PagingStateBase`), and `reset()` returns a state equal to the pristine one. So
when the layout has only ever been built with the pristine state — which is the
case until the opening fetch's `isLoading: true` has actually *drawn a frame* —
`refresh()` is invisible: no diff, no re-fetch. Meanwhile it has already cleared
the guard that would have let the opening fetch's own result land, so that gets
discarded as stale on arrival. **Nobody is left to ask.** Permanent spinner.

A sorting tab "fixed" it because `TabBarView`'s children are keyed by sorting: a
tab tap *mounts a new grid*, whose fresh controller fetches from `initState`. It
was never repairing the broken one.

**What rewrites the query inside that one-frame window** — and this is the part
the old lead got wrong. It is *not* mainly `browseDefaultsProvider`: on the wiped
tablet the defaults resolve to tela's own, the query is unchanged, and Riverpod
does not even notify. The trigger that fires on **every** cold launch is
`screenResolution(context)`: Android delivers real display metrics after the
first frame, `BrowseScreen` folds them into every query via
`forScreen(...)` → `AtLeastResolution`, and the query is rewritten under the
opening fetch. No account, no key, no saved filters needed — which is exactly why
a wiped device still hung, and why a fixed test viewport never saw it. Defaults
resolving is a second, rarer trigger through the same hole.

Release vs. debug was real but incidental: AOT lands the rewrite inside the
window, JIT draws a frame first and recovers.

The fix is that `_retry()` asks for the page itself rather than hoping something
notices. It cannot double-fetch — the guard `refresh()` clears is the same one
that makes the layout's own scheduled call a no-op. A second, latent bug is fixed
beside it: `_fetchPage` wrote `_lastPage` even for a fetch the controller had
already abandoned, and a stale `hasMore: false` there ends the *new* listing at
page one, forever. Both halves are mutation-checked independently.

Pinned by `test/features/browse_opening_fetch_test.dart` (4 tests), at both
altitudes — the grid's own `didUpdateWidget` path, and the real `BrowseScreen`
under both triggers. All four fail on the unfixed code with the device's exact
symptom: **zero tiles**.

### If you ever measure this on the device again

Two ways the measurement lies, one of which cost this session several rounds:

- **A black screenshot usually means the tablet is locked, not that the app is
  stuck.** `screencap` on a dozing or keyguarded device returns ~19KB of black,
  which looks exactly like the hang. Check `dumpsys power | grep mWakefulness`
  and `dumpsys window | grep isKeyguardShowing` *before* believing a dark frame.
  A loaded grid is ~2.1MB. Wake with `input keyevent KEYCODE_WAKEUP` and dismiss
  with a swipe.
- **The stddev trick lies about error states**: an error view is also dark and
  also scores low. Look at the image.

```bash
./tool/tela build apk --release          # NOT --split-per-abi; see the install rule
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am force-stop cc.pym.tela && adb shell am start -n cc.pym.tela/.MainActivity
# do not touch the screen; screenshot after 25s+
adb exec-out screencap -p > /tmp/f.png
```

### What it was not — each ruled out with evidence, do not re-litigate

Kept because these eliminations are what the builds were spent on, and they all
still hold:

- **Not R8.** `isMinifyEnabled = false` *and* `isShrinkResources = false`:
  still stuck.
- **Not the data.** Stuck against a freshly wiped database. (And now understood:
  the trigger never needed any data.)
- **Not `a1e057d` / `75b7fbb` / `54b2aa7`.** Those are in the debug build too.
- **Not the INTERNET permission**, **not the rate limiter**, **not a crash**,
  **not an error state**.

## The install rule — read this before touching the device

**Since `0cdf0a1`, `make deploy` (or `./tool/tela deploy [host:port]`) does the
right thing by construction:** it builds the *universal* release APK
(versionCode 1) and installs it with `adb install -r`, which can only update in
place — never a downgrade, never an uninstall. Prefer it. The rest of this
section is *why* that command is shaped the way it is, and it still governs any
hand-rolled install.

**A `--split-per-abi` release APK bumps the versionCode. Installing one arms a
trap that wipes the device's data on the next debug build.**

| artifact | versionCode |
|---|---|
| `app-arm64-v8a-release.apk` | **2001** |
| `app-release.apk` (universal) | 1 |
| `app-debug.apk` | 1 |

Install the split APK (2001), then run any debug build (1), and Android refuses
the downgrade — so `flutter run` **uninstalls the app to get out of it**, taking
the Drift database and the Keystore-backed API key with it. That is precisely the
failure `tool/tela`'s header describes; note it names the *signature*, which sent
this session chasing a signature check that passed while the versionCode was the
real trigger. **Check both.**

This already cost the tablet its data once, on 2026-07-16: 32 private wallpapers
and the stored API key, gone. The old handoff line that said "Install
`app-arm64-v8a-release.apk`" is what armed it, and is now deleted.

- **Use `flutter build apk --release`** (universal, versionCode 1) for anything
  going on the device. It exercises R8 identically — R8 is a buildType setting,
  not a split setting — and it can never downgrade.
- **Use `adb install -r`**, not `flutter install` and not `flutter run`, when an
  in-place update is what you want. `-r` cannot uninstall; its worst case is a
  harmless error. Only `--split-per-abi` when *measuring per-ABI size*, and then
  do not leave it on the device.

## What the device did confirm (item 7's R8 question, largely answered)

Verified statically against the R8'd APK, and at runtime:

- All four method-channel handlers survive R8 with their names intact:
  `Downloads`, `ImageStorage`, `WallpaperSharing`, `MainActivity`. So does every
  channel-name string (`cc.pym.tela/images`, `/screen`, `/share`, `/wallpaper`).
  The `-keep class cc.pym.tela.**` rule does its job.
- The release build launches clean: no `FATAL`, no `ClassNotFound`, no
  `MissingPluginException`.
- It reaches **real Wallhaven** and renders the grid — on cold launch now, and at
  the time only once a tab tap shook the hang loose. Either way R8 breaks neither
  the network path nor the image pipeline.

**Still owed on the device**: the wallpaper-apply round trip (proving the handler
*answers*, not just that it exists — that changes the owner's wallpaper, so it is
theirs to run), the real biometric prompt (adb cannot pass `FLAG_SECURE`), and the
cache figure after a real browse.

## Device state as of this handoff

- Installed: `app-release.apk` — universal, **R8 on**, debug-signed, versionCode 1,
  **carrying the cold-launch fix and the database binding** (`3a09f67`), built
  and installed 2026-07-16 20:03 with `adb install -r`; both versionCodes read
  as 1 *from the APKs themselves* first, so no downgrade and no wipe.
- **Data: preserved** across that install, but it is the post-wipe data — fresh
  database, no API key, no blocklist, no saved filters.
- It **cold-launches to a loaded grid**, untouched, on this build too, with a
  clean logcat (no `UnimplementedError`, no `ProviderException`, zero Flutter
  error lines). That is not just a smoke test: the grid cannot render without
  the blocklist, which reaches `telaDatabaseProvider` → `openTelaDatabase`, so a
  loaded grid *is* the end-to-end proof that `main.dart`'s new override works on
  hardware.

### Read the versionCode, do not infer it

There is no `aapt` on the host or in the toolchain image, which is how "install
the split APK" survived long enough to wipe the tablet. Parse it out of the
artifact instead — `tool/` has no home for this yet, so it lived in the
scratchpad, and the 40 lines are worth rewriting over trusting a build flag:

| artifact | versionCode (read, 2026-07-16) |
|---|---|
| `app-release.apk` (universal) | **1** ← the only one to install |
| `app-debug.apk` | 1 |
| `app-armeabi-v7a-release.apk` | 1001 |
| `app-arm64-v8a-release.apk` | **2001** ← the trap |
| `app-x86_64-release.apk` | 4001 |

Those confirm the rule rather than restate it: Flutter's split scheme is
`1000 × abiIndex + base`, and the reading reproduced the 2001 this file already
documented, which is what makes the 1 trustworthy. **The stale split APKs from
17:47 are still in `build/app/outputs/flutter-apk/`.** Do not install them.
- The tablet (SM-X730, `192.168.50.191:5555`) is on a **VPN** (`tun0`, NordVPN).
  It resolves and pings `wallhaven.cc` at ~118ms. The VPN is *not* the hang — a
  tab tap loads instantly over the same tunnel — but it does add real latency, and
  it is a live variable in anything measured from that device.
- No keystore (`android/key.properties` absent), so release falls back to the
  debug key with a warning. Fine for testing, still owed before shipping.

## PRIOR — the code debts are closed

All seven device findings are **fixed and committed on `master`**, and the three
carried debts that could be settled at a desk now are. The suite was **553 tests**
green at that point (from 514); **557** once the hang was pinned, and **561**
with the database seam (`3a09f67`);
`./tool/tela analyze` clean, `dart format .` clean, `gen-l10n`
run (five new strings), and `build apk --debug` and `build apk --release
--split-per-abi` both succeed. **Work in `master`**, or short-lived branches off
it. The `.worktrees/image-viewer-ux` worktree is spent.

```
5e661d7  fix: let the viewer's close button actually close
4128780  fix: charge the app-lock once per session, not once per screen
8155ba4  fix: keep every app-private download out of Download History
626a9bb  feat: let a tag or uploader listing be filtered, on its own terms
1becb61  feat: give the viewer a button that hides its chrome
ea5e94f  fix: cap the image cache, which had reached ~2GB on a tablet
d29b4b4  build: shrink the release APK, and stop silently debug-signing it
70b5638  docs: record the fix list as done, and what the device still owes
a1e057d  fix: re-fetch the grid when the blocklist changes, not when it loads
75b7fbb  docs: settle Next/Previous while zoomed as correct, and pin it there
```

Each commit body carries its own *why*, including where the fix list was wrong.
Read those before re-litigating a decision.

**Every fix was mutation-checked**: the fix was reverted and the new test watched
to fail with the real symptom, then restored. That mattered most for item 1,
which had been known since slice 6 and was never once pinned. **Hold the next
work to the same bar** — a test that passes before and after is not a test.

### The next work, in order

The cold-launch hang that used to sit here is **fixed** — see the top of this
file. What is left:

1. **The device verifications below**, which need the owner's own hands.
2. **The keystore**, whenever shipping matters. The only part of item 7 left.

The third item that used to sit here — `WallpaperGrid` mounting silently opening
a Drift database — is **closed** in `3a09f67`; see the top of this file. It was
fixed at `telaDatabaseProvider` rather than with the shared test helper this
line used to ask for: a helper would have made the trap convenient to avoid,
while an unbound provider that throws by name makes it impossible to fall into,
for all four Drift ports at once.

### The three carried debts, settled 2026-07-16

1. **`_reapplyBlocklist` fired on any `hasValue`** — a real bug, now fixed in
   `a1e057d`. A `FutureProvider`'s first resolution is a value where there was
   none, so the grid re-fetched page 1 the moment the blocklist loaded, against
   the blocklist its opening fetch had already read. Cost a redundant request or
   nothing depending on who won the race. Gated on the blocklist's effect on a
   search actually changing — by tag *name*, since names are what reach the query.
   **The bar earned its keep here**: the first version of the regression test
   passed against the unfixed code, because the pump helper pumps 300ms and the
   fake's delay was 50ms, so the baseline was captured *after* the re-fetch it
   was meant to catch. It looked like a passing test and measured nothing. If you
   shorten that delay, it silently stops testing.
2. **Next/Previous while zoomed was correct**, and is now documented and pinned
   at the viewer (`75b7fbb`). Slice 3: "explicit Previous/Next still selects and
   resets zoom." Both halves already held — the chrome passes the callbacks
   straight through, and each *session* resets zoom on selected-index change. No
   behavior changed. The viewer test that only covered the key path was titled
   "horizontal input pans…", which is a fair part of why this read as broken; a
   button is horizontal input too. It now says keys, and the button has its own
   test beside it.
3. **The ~575 test count was phantom.** Reconciled, not estimated: **575 = 487 +
   88**, the branch's final total plus the branch's *own* 88 new tests, added to
   a total that already contained them. It was never achievable. The merge lost
   nothing, and the arithmetic is exact — merge-base 392 static test
   declarations, master added 27, the branch added 88, keep-both predicts 507,
   and `babce71` has exactly 507. The runtime numbers agree independently:
   514 − 487 = 27, master's delta to the digit. There are also no "merge notes":
   `575` appears nowhere in any branch's history except the two handoff commits
   that cite them. **Do not carry this again.**

### What the fix list turned out to be

Seven, plus four things the list did not know:

1. **Close button** — `maybePop()` → `pop()` in both sessions. **Also dead for
   the same reason: History's "remove from history"** (`_confirmForget`), whose
   test only asserted the row was forgotten, never that the viewer left. Both
   pinned now. The forget path deliberately keeps `maybePop()`: it routes *into*
   `_exitFullscreen` (restoring system UI), which is the intended direction.
2. **Double app-lock** — `privateUnlockSessionProvider` holds the *satisfied*
   state for one foreground session; both screens still gate. `FLAG_SECURE`
   untouched. The revoke listens for lifecycle in the **provider**, not the
   mixin: the unlock outlives both screens, and a revoke that only fires while
   the grid is mounted is not a revoke. `inactive` deliberately does not revoke —
   the biometric prompt itself raises it.
3. **appPrivate in History** — gated on destination at both layers plus the read
   side, and **the migration decision was made: purge** (schema v5). The read
   filter alone was not enough: `backup_rules.xml` says in as many words that the
   Drift database backs up, so an unpurged row keeps a private file's location in
   the user's cloud backup — the exact exposure the tier exists to prevent. Note
   the v3 migration fixture *was* the bug (a `sfw` + `appPrivate` row) and the
   old test asserted it was listed.
4. **Linked-listing filter** — `BrowseFilterButton` extracted and shared.
   Decision made: **per-listing override** (`linkedQueryProvider`, autoDispose,
   seeded from Browse). **The handoff's second decision dissolved**: it conflated
   `Sorting` (the tabs) with `SortOrder` (the sheet's asc/desc). Only `Sorting` is
   forced, so Order works fine here; Top-range is meaningless exactly as it is on
   Browse's own non-Top tabs, which `filter_sheet.dart:292` already settled by
   showing it with a hint.
5. **Hide-chrome button** — added, icon-only. Forced the top row to adopt the
   navigation row's `compact` breakpoint (it overflowed at 300dp), so
   `_navigationButton` became the shared `_tonalControl`.
6. **Image cache** — split into `thumbnailImageCache` (600 objects, 30d) and
   `fullImageCache` (10 objects, 3d), both project-owned, with a `Clear cache`
   Settings tile behind a new `FetchedImageCache` port. **Correction to the fix
   direction: a byte-capped `CacheManager` does not exist.** `Config` caps
   *objects* only — which is precisely why one bucket could reach 2GB — so the
   split is what makes a count mean a budget. No WorkManager needed.
7. **APK size** — R8 + `shrinkResources` + `--split-per-abi`. **arm64-v8a is now
   22.4 MiB**, from a 62 MiB fat APK. Both levers are real and were measured:
   without R8 the split arm64 APK is 35.4MB, with it 23.5MB. (Do not reason
   about R8 from the *shrunk* APK's 1.5MB `classes.dex` — that is the output.
   The unminified dex is ~13MB of AndroidX, Kotlin stdlib and plugins.) Release signing now
   reads a gitignored `android/key.properties`; **absent, it still falls back to
   the debug key and now warns at configure time.** Creating that keystore is the
   owner's, and is the only part of item 7 left.

### The device pass (2026-07-16, second run)

**The owner ran it: everything worked.** No regressions reported across the
fixed flows. Two things came out of it anyway, and the second is the important
one.

**The "173MB" is the debug APK — the same wrong artifact as the 201MB.** The
installed package reports `flags=[ DEBUGGABLE … ]` and its `/data/app` directory
is 165MB. R8 does not touch a debug build, so that number could not have moved
and never will. **`app-arm64-v8a-release.apk` is 22.4 MiB.** Measure that one, or
item 7 stays untested. (**Measure** it — do not *install* it. Its versionCode is
2001 and installing it wipes the device on the next debug build; see "The install
rule" at the top. R8 can be exercised from the universal APK instead.) What the
device actually holds:

| | |
|---|---|
| `/data/app/…` (the APK) | **165MB** — debug; ~22 MiB in release |
| `files/wallpapers` | **235MB** — 32 private wallpapers. The user's own data. |
| `app_flutter/flutter_assets` | **94MB** — debug-only; absent from release |
| `cache/` | **empty** — the image cache had already been cleared |
| `app_flutter/tela.sqlite` | 45KB |

So the app is not big. Its APK was measured in the one form that is, and the
rest is 32 wallpapers someone chose to keep.

**The find: the old cache bucket was orphaned, and it was mine.** Splitting the
buckets left `libCachedImageData` — the ~2GB one — referenced by nothing.
`flutter_cache_manager` evicts a bucket only while that bucket is in use, so an
abandoned one never shrinks: an upgrading device would have kept every byte
forever while the new "Clear cache" tile reported **0 B** beside it. The tablet
still had `files/libCachedImageData.db`, 2.5MB of rows, hours after the split.
Fixed: `purgeLegacyCache()` on the port, deleting the files **and** the sqflite
index beside them (the two live in different directories — deleting the folder
alone leaves rows pointing at nothing), run unawaited from `main()` so nobody has
to go looking, and counted in `sizeInBytes()` until it is gone. Six tests,
including the upgrade case.

The tablet's cache being empty is why this did not show up as a number: it was
luck, not correctness.

### What is owed

The device pass confirmed the *behaviour*. What it did not confirm is anything
that only a **release** build or a **real prompt** can show:

- **Item 2 wants a real biometric prompt.** The lifecycle revoke is pinned
  against Flutter's own state machine, but whether Android delivers `paused`
  *before* `local_auth` returns — the ordering the grant relies on — is a device
  fact, not a test fact. If an OEM delivers it late, the unlock would be revoked
  immediately after being granted and the toll would be charged twice again,
  which is the old bug wearing a new hat.
- **Item 7 wants R8 exercised.** The method channels are reached by channel name,
  never by a Kotlin reference, so R8 cannot see they are used;
  `proguard-rules.pro` keeps `cc.pym.tela.**` for exactly that reason. A stripped
  handler presents as a plugin that silently stops answering — no wallpaper
  applied, no private listing, no share. **Install the release APK, not the debug
  one**, or this is untested.
- **Item 6 wants a real browse.** The tablet's cache was already empty, so the
  buckets have never been seen filling and evicting against real Wallhaven
  traffic. Browse a while, then read the Settings tile's figure.
- ~~**The viewer's Next button did not advance on the tablet**~~ — **likely
  closed.** It was suspected to be adb tap coordinates missing the button at
  2560×1600 rather than a bug, and the 2026-07-16 device pass reported the viewer
  working. The button is pinned by tests at both the viewer and Detail (see debt
  2 above), including while zoomed — so a real failure here would be the tap, not
  the code. Confirm with one real finger and delete this line.

**Item 7's R8 half is largely answered** — see "What the device did confirm" at
the top. What is left there is the wallpaper-apply round trip.

For how to get a build onto the device without wiping it, see **The install
rule** at the top of this file. The instruction that used to sit here — install
`app-arm64-v8a-release.apk` — is what wiped the tablet, and is gone.

## PRIOR CHECKPOINT — slice 7 is merged, and the tablet found seven things

**Superseded: every item below is fixed. Kept for the root-causes, which are
still the best description of what was wrong.**

`image-viewer-ux` is merged into `master` as **`babce71`** and the device pass is
done. The worktree has nothing left to give; **work in `master` from here**, or
in short-lived branches off it. What follows is the fix list the SM-X730
produced, each item root-caused to a file and a line. **This is now the work.**

Every fix below gets a regression test — the project rule, and in the case of the
first item, the *reason* it is still a bug: it has been known since slice 6 and
was never once pinned by a test.

### The merge itself (done)

Five conflicts, all additive, all resolved "keep both": `routes.dart` and
`router.dart` (blocked-tags vs. download-viewer routes, now siblings),
`wallpaper_grid.dart` (imports only), and two test files. `dart format .`,
`./tool/tela analyze`, `./tool/tela gen-l10n` and `./tool/tela build apk --debug`
are all clean; the suite is **514 tests** green.

The merge surfaced exactly one regression, in the two tests the merge notes
predicted — and it is worth reading as a **design smell rather than a test bug**.
Master's `_reapplyBlocklist` and the branch's Hero tags live in different methods
of `wallpaper_grid.dart`, so git auto-merged them happily; but the merged
`build()` now calls `ref.listen(blockedTagsProvider, …)`
(`wallpaper_grid.dart:110`), which gives *the grid* a hard dependency on the real
Drift-backed `tagBlocklistRepositoryProvider` → `telaDatabaseProvider` →
`TelaDatabase.open()`. The branch's two minimal-`ProviderScope` harnesses predate
that dependency, so they reached real Drift and collided with live paging. Fixed
test-only, by giving both the `FakeTagBlocklistRepository` that master's own
`browse_screen_test` already wires. **The seam is still sharp**: any future
harness that mounts `WallpaperGrid` will silently open a database unless it
remembers this. Worth a shared test helper, or a hard look at whether the grid
should know about the blocklist at all.

### 1. The close button never closes (P1 — and we have known since slice 6)

**Symptom, on the tablet:** the viewer's Close button does nothing; Android Back
is the only way out.

**Root cause, confirmed.** `_exitFullscreen()`
(`immersive_gallery_viewer.dart:163`) sets `_allowPop = true` inside `setState`
and then *synchronously* awaits `widget.onClose()`. Both the private and the
History sessions implement `onClose` as `Navigator.of(context).maybePop()`
(`private_immersive_session.dart:124`, `download_immersive_session.dart:111`).
`maybePop` **consults the route's `PopScope`**, which still reports
`canPop: false` — the `setState` rebuild has not run yet. So the `PopScope` fires
`onPopInvokedWithResult(didPop: false)` (`immersive_gallery_viewer.dart:335`),
which calls `_exitFullscreen()` again, which hits the `_isExiting` guard and
returns. **Nothing pops.** Android Back works because by then the rebuild landed
and `canPop` is true.

This also explains why Detail's viewer closes fine:
`wallpaper_detail_screen.dart:407` uses `Navigator.pop()`, not `maybePop()`, and
`pop()` bypasses `PopScope` entirely. The private viewer's delete-to-empty exit
sidesteps it the same way, deliberately — and slice 6 wrote that down (see its
note below), while slice 7 concluded it "did not surface and needed no fix." It
surfaced.

**Fix direction:** use `Navigator.pop()` in both sessions. `_exitFullscreen` *is*
what the `PopScope` defers to; consulting the `PopScope` from inside it is the
cycle. Do not "fix" this by awaiting a frame before `onClose` — that leaves the
re-entrant call in place and makes the exit depend on frame timing.

**Regression test:** pump each session, tap `Key('immersive-viewer-close')`,
assert the route is gone. Both sessions — the bug is inherited, so testing one
proves nothing about the other.

### 2. The private library asks for the lock twice (P1)

**Symptom:** authenticate to open the private grid, then authenticate *again* to
open a fullscreen image.

**Root cause:** this is currently **by design**, and the design is wrong.
`PrivateSecureAccess._unlocked` (`private_secure_access.dart:29`) is per-`State`,
and both the grid and the viewer mix the mixin in and call `beginPrivateAccess()`
from `initState`. The mixin's own docstring argues for it: "Neither leans on the
other… the gate is defence in depth rather than a one-time toll paid at the grid."

**Keep the reason, drop the toll.** The docstring's real argument is
*deep-linkability* — "a route can be reached more ways than one — gating a button
would leave the content one deep link away from being shown ungated." That
argument is about where the **gate** lives, not about how often the user pays. So
keep the gate on both screens; hoist only the *satisfied* state into a
session-scoped provider, invalidated when the app backgrounds. A viewer opened
over an unlocked grid inherits the unlock; a viewer reached cold still prompts.

The `FLAG_SECURE` half is reference-counted and correct — **do not touch it**.

**Regression tests:** viewer opened after a grid unlock does not prompt; viewer
opened cold *does* prompt; the unlock does not survive backgrounding.

### 3. A private download is indexed in History (P1 — privacy-shaped)

**Symptom:** download a *safe* or *sketchy* wallpaper straight to the private
library and it shows up in Download History.

**Root cause:** both layers gate on **purity**, never on **destination**.
`DownloadWallpaper._remember` (`download_wallpaper.dart`) reads
`if (wallpaper.isNsfw) return;`, and `DriftDownloadHistory.record`
(`drift_download_history.dart:53`) repeats exactly that check. So an SFW
wallpaper sent to `appPrivate` — by config or by the long-press per-download
override — earns a history row.

**The invariant needs restating, not patching.** Today it reads "explicit
wallpapers are never recorded here" (`download_history.dart`, port docstring).
It should read: **nothing in `appPrivate` is ever recorded here, whatever its
purity** — the private library *is* that tier's index, and a history row is
precisely the ungated, backed-up thumbnail index the tier exists to prevent.
Keep the purity rule as well; both, at both layers, the way every other NSFW rule
here is enforced twice.

Touches the port docstring, `_remember`, `DriftDownloadHistory.record`, and the
read side — `downloads()` should drop `appPrivate` rows too, which also cleans up
the bad rows already on the user's device for free. A one-time purge migration is
optional; decide it explicitly.

**Regression tests:** sfw → `appPrivate` writes no row; sketchy → `appPrivate`
writes no row; sfw → `sharedGallery` still writes one.

### 4. No filter on a tag or uploader listing (P2 — feature)

**Symptom:** follow a tag or an uploader and the filter button is gone; no way to
see only General or only People for that tag, or to set purity or colour.

**Root cause:** `LinkedListingScreen` builds an `AppBar` with no `actions`
(`linked_listing_screen.dart:32`). `BrowseScreen` has `_filterButton(…)` in its
`actions` (`browse_screen.dart:75`) and it is **private to that file**.

**The good news:** nothing else is missing. The filter sheet already offers
categories, purity, tags, ratio, resolution, colour, order and top range
(`filter_sheet.dart:123-159`), and `LinkedListingScreen` *already inherits*
`browseQueryProvider` (line 27-30), so those filters already apply here — only the
control is absent. Extract `_filterButton` into a shared widget and add it.

**Two decisions to make first**, both real:

- The sheet writes the **global** `browseQueryProvider`, so filtering from a tag
  listing also re-filters the Browse tabs behind it. That matches the screen's
  own docstring ("their filters still apply here, as they do on wallhaven.cc") —
  but say yes to it on purpose, or build a per-listing override.
- `LinkedListingScreen` forces `sorting: Sorting.dateAdded` (line 29), so the
  sheet's Order and Top-range groups would sit there doing nothing. Either drop
  the force, or hide those groups on a linked listing. A filter that visibly does
  nothing is the exact trap the `ratios=bogus` finding warned about.

### 5. A button to hide the viewer chrome (P2 — feature)

Today the only way to hide the controls is tapping the image
(`immersive_gallery_viewer.dart:229-243`). Add an explicit control to
`ImmersiveGalleryControls`.

Two notes. The l10n already exists — `galleryShowControls` / `galleryHideControls`
are in the ARB and are currently used as the canvas's semantics label — so this
needs no `gen-l10n`, only a tooltip. And **the button hides the thing the button
is in**: tap-to-show must keep working, or the controls become unreachable.

### 6. The image cache reaches ~2GB (P2)

**Root cause:** no `CacheManager` is configured anywhere in the app — grep finds
zero `CacheManager`, `stalePeriod`, or `maxNrOfCacheObjects`. So every
`CachedNetworkImage` falls to `DefaultCacheManager`: **200 objects, 30-day stale
period, capped by object count rather than bytes.**

The killer is what shares that one bucket. `wallpaper_gallery_session.dart:53`
caches `wallpaper.fullImageUrl` — full-resolution Wallhaven originals, routinely
5–20MB and up to 8K — alongside tiny thumbnails, against a cap that cannot tell
them apart. 200 × ~10MB ≈ 2GB. That is the number on the device.

**Fix direction:** project-owned cache managers, one bucket per role — thumbnails
(many, small, long-lived) and full images (few, huge, tight byte budget). Note
that per the CLAUDE.md ports rule this is already a violation: `cached_network_image`'s
cache is a third-party dependency reaching straight into features, with no
project-owned interface and no adapter.

**On the requested worker:** a byte-capped `CacheManager` self-evicts, so an
Android WorkManager (a new dependency, a new port, a new native seam) is probably
unnecessary. Recommend the cheaper shape first — cap, evict on resume, and a
"Clear cache (1.9GB)" tile in Settings showing the real figure — and only reach
for a worker if that proves insufficient.

Do not confuse this with the decode budget: `cacheWidth`/`ResizeImage` are
already applied correctly across the gallery sources, and they bound **memory**.
The 2GB is **disk**.

### 7. The 201MB app is a debug build (P3 — measurement correction)

Measured on this machine: `app-debug.apk` is **192MB**; `app-release.apk` is
**62MB**. The 201MB on the tablet is the *debug* APK installed for the device
pass — debug carries the JIT VM, both ABIs, and no tree-shaking. So "we are
building stuff we don't need" is not what is happening; the wrong artifact was
being measured.

**But 62MB is still ~3× a normal Flutter release**, and that part is real:
`android/app/build.gradle.kts` has no `minifyEnabled`, no `shrinkResources`, and
no ABI splits — its `buildTypes` block sets a signing config and nothing else.
Enable R8 and resource shrinking and build `--split-per-abi` (or an AAB, which
Play splits for you); expect ~20–25MB per ABI. The release build is also **still
debug-signed** — a TODO in that same block, worth folding into this fix.

### Carried debts (not from the device)

**Moved to the current checkpoint, which is where the open work belongs.** The
one detail worth keeping here: the Next button "did not advance" on the *first*
tablet run (stayed "1 of 48", appeared to toggle chrome instead) while a swipe
reached "2 of 48" — the evidence for it being adb tap coordinates at 2560×1600
rather than a bug.

### What the tablet did confirm

All with clean logcat — no Flutter exceptions, no RenderFlex overflow, no FATAL,
no "multiple heroes": app launch (Impeller/Vulkan, 2560×1600, Monet core palette
detected); the landscape browse grid with adaptive rail and aspect-correct
masonry; tile→Detail Hero landing on the exact tapped wallpaper; Detail's
two-pane; the immersive viewer full-bleed; **public paging into real Wallhaven**
("1 of 48" → "2 of 48", Previous correctly enabling); Settings' two-pane
including the three-tier storage copy.

**The private path's `FLAG_SECURE` is genuinely engaged.** Opening the private
library raised Samsung's `BiometricPromptRoot … (secure)`, which adb cannot pass.
`screencap` at that point returned fully black (35,940 bytes) and a later BACK
recovered to a normal 280,229-byte frame — proving the black was the secure
window and not a crash. **No private screenshot was captured, and capture is not
possible.**

### Still owed on the device

Unchanged from the slice-7 list, and still owed because the app-lock cannot be
passed over adb: the native `BitmapFactory` bounds decode returning a real private
file's dimensions; `FLAG_SECURE` surviving the grid↔viewer round trip and the
inherited close-button path (item 1 above blocks this one outright); and History's
native `materializeImage`/`releasePreview` decoding a real `content:`/SAF preview.

These need the owner's own eyes and cannot be automated: the Hero flight reading
well against real thumbnails on all four shelves (flying the decoded thumbnail,
not a blank box); no "multiple heroes" on a repeated wallpaper under `random`
sort; reduce motion collapsing to an instant cut; landscape safe-area clearing
the gesture bar with no double gap; grid and scroll restoration on return.

One more, specific to the merge: block a tag from Detail with a Browse grid open
and confirm the in-place re-filter survives the tiles shifting under it. Note the
failure mode — `shelf_hero_tag.dart` documents that a shifted tile **simply does
not fly** rather than flying to the wrong image, so watch for a *silently missing*
flight, not for an exception.

## PRIOR CHECKPOINT — image viewer UX slice 7 complete (merged as `babce71`)

The staged implementation continues on branch `image-viewer-ux` in the existing
`.worktrees/image-viewer-ux` worktree. **Continue there; do not create another
worktree and do not work in `master`.** Slice 7 was the **last implementation
slice**: what remains is step 6, the full automated + real-device matrix. The
broader product contract below stays authoritative.

Slice 7 is the consistency-and-motion pass that ties every gallery together —
no new surfaces, no new zoom or viewer implementation, and the domain, storage,
and privacy model untouched (delivery-order step 5):

- **One shelf geometry.** `wallpaper_grid_columns.dart` now owns the whole
  rhythm: `wallpaperGridSpacing` (12), `wallpaperTileRadius` (16), the existing
  responsive `wallpaperGridColumns` (2 on a phone → 6 on a tablet, never
  comically narrow), and a new `wallpaperGridPadding` that adds the un-consumed
  `MediaQuery.padding` to the 12dp inset on the sides and bottom — so a
  landscape notch or a full-screen gesture bar never clips the last row, while a
  bottom nav bar or rail that already reserved the space reads back as zero and
  is not double-counted. The top is left to each shelf's app bar. Browse (paged)
  and Favorites, History, and Private (all `MasonryGridView`) now draw from this
  one source, so they read as the same system. No important action hides behind
  a long press only: History's "remove from history" is in the viewer overflow
  and Private's delete is a viewer button; the long press is a shortcut, not the
  sole path.
- **Tile-to-viewer Hero.** A restrained shared-element flight now carries a
  tile's already-decoded thumbnail into the viewer it opens: `GalleryViewport`
  gained an optional `heroTag` that wraps *only* the contained image frame (not
  the zoom viewport or the calm backdrop), with a `flightShuttleBuilder` that
  flies the grid tile's thumbnail in both directions so the flight is never a
  blank box while the viewer's own image still decodes. `ImmersiveGalleryViewer`
  and `ProgressiveWallpaperPreview` forward the tag; `WallpaperTile` and the
  private tile wrap their thumbnails in the matching `Hero`.
- **Tags scoped so nothing collides**, in `core/ui/shelf_hero_tag.dart`:
  `shelfHeroTag(identity, id, position)`. The identity separates shelves — go
  _router keeps Browse and Favorites both mounted in the shell's `IndexedStack`,
  so one id kept-and-browsed would otherwise share a tag — and the position
  separates repeats *within* one shelf, because Wallhaven's `random` sort can
  return the same wallpaper on two pages and the grid renders both. (That second
  case is exactly what the full suite caught mid-slice: an id-only tag threw
  "multiple heroes share the same tag" on a real paged grid.) The viewer passes
  its own `selectedIndex` as the position, so the tag matches back to the exact
  tile — and simply does not fly, rather than flying to the wrong image, if a
  deduplicated append has since shifted it.
- **Reduce-motion-aware transitions.** `core/ui/gallery_route_transitions.dart`
  holds `galleryTransitionDuration` (220ms, or `Duration.zero` when
  `MediaQuery.disableAnimations` is set) and a `fadeGalleryPage` go_router page.
  Detail, the linked listing, and the History and Private viewers all push
  through it, so their fade — and the Hero flight it paces — collapses to an
  instant cut under reduce motion. Detail's own fullscreen `PageRouteBuilder`
  now reuses the same duration helper. Returning from any viewer still restores
  the grid and its scroll position (the viewers are pushed over the shelf).
- **Decode budget audited, not changed.** Every tile already caps its decode:
  `WallpaperTile` decodes `thumbOriginalUrl` (never the full 6K image) at
  `~200·dpr`, and the private tile decodes its file at the same cap; the viewer
  clamps as before, and `GallerySessionController` still prefetches only the
  immediate neighbour. A test pins the tile to the thumbnail URL and a bounded
  `memCacheWidth`.

The close-button `PopScope`/`_allowPop` interaction flagged by slice 6 was left
alone: the fade transition wraps the *route*, not the viewer's own exit path, so
it did not surface and needed no fix. No l10n strings were added (the pass adds
no user-facing copy), so `gen-l10n` was not run.

Slice 7 verification (all green; full suite now 487 tests):

```bash
./tool/tela dart format <touched Dart files>   # touched files only, not the tree
./tool/tela analyze
./tool/tela test test/core/shelf_hero_tag_test.dart \
  test/core/gallery_route_transitions_test.dart \
  test/features/gallery_shelf_polish_test.dart \
  test/features/gallery_paging_bridge_test.dart \
  test/features/gallery_session_launch_test.dart
./tool/tela test
```

New/covered tests: shared grid geometry at 390x844, 844x390, and a 1280x800
expanded surface (column counts 2/4/6, a 12dp inset that grows by the system
safe area, and a full shelf packing without a RenderFlex overflow at each);
reduce motion collapsing the transition duration to zero and a Hero navigation
settling in a single frame; the same id on two shelves rendering two distinct
Hero tags and flying without a collision; one id repeated at two positions on a
shelf staying distinct (the real paged-grid regression); scroll restoration on
return from a viewer; and the tile decode budget. Named fakes reused:
`FakeFavoritesRepository`, `FakeWallhavenApi`.

One note for the next agent: the Hero flight, the reduce-motion cut, and the
safe-area padding have not run on a device — they are proven in the widget
tests, but a tablet pass (step 6) should confirm the flight reads well against
real thumbnails and that the last grid row clears the gesture bar in landscape.
This joins the device confirmations already owed from slices 5 and 6 (below).

### PRIOR SLICE — slice 6 (secure private viewer)

Slice 6 gives the private/NSFW library the same first-class fullscreen viewing
as Browse and History, the image dimensions its tiles never had, and a
Set-from-private flow (delivery-order step 4):

- **Dimensions.** The native listing (`ImageStorage.listPrivate`) now runs a
  bounds-only decode (`BitmapFactory.Options.inJustDecodeBounds`) per file and
  returns pixel `width`/`height`; a corrupt file reads back as `-1`.
  `MethodChannelImageStore` maps those to `PrivateImage.width/height` as `int?`
  (null for absent or non-positive), and `PrivateImage.aspectRatio` is null when
  either is unknown. The grid is now `MasonryGridView` with each tile shaped to
  its `aspectRatio`, falling back to a square for a corrupt file; the viewer uses
  the same ratio, or a square canvas for an unknown one.
- **Secure viewer.** `features/private_library/private_immersive_session.dart`
  wraps the shared `ImmersiveGalleryViewer` over one local
  `GallerySessionController<PrivateImage>` (complete list, **no** `requestMore`).
  It holds `FLAG_SECURE` and satisfies the app-lock **independently** of the
  grid via a new `PrivateSecureAccess` mixin (`private_secure_access.dart`) that
  both the grid and the viewer mix in — so neither leans on the other, and the
  gate is per-entry (not per-swipe). The `ScreenGuard` adapter is now
  **reference-counted**: the grid and viewer both acquire, and the window clears
  only after the last release, so the viewer popping never strips protection
  from the grid still behind it. `FakeScreenGuard` folds the same balance.
- **Source.** `PrivateGallerySource` resolves the plain `file:` location through
  the existing `LocalPreviewCache` (non-temporary — the user's own file is never
  released) with **no** network fallback; an unreadable or corrupt file renders a
  safe broken-image state. No path is ever placed in shared cache or logged.
- **Set + delete.** A pure-Dart `ApplyPrivateImage` use case
  (`applyPrivateImageProvider`) sends the private URI through `WallpaperApplier`
  — the viewer's primary action, Home/Lock/Both behind it. There is **no** share
  action, by design. Delete is explicit and confirmed;
  `GallerySessionController.removeSelected()` advances to the next image (the one
  that slid into the index), then the previous at the end, and returns false when
  empty so the viewer pops to the grid's empty state. The secure window stays up
  through grid, viewer, target sheet, and delete confirmation.
- Position/semantics announcements never carry a file name or path (the position
  is the `galleryPosition` "x of y"; the image label is the path-free
  `privateLibraryImageLabel`). No new l10n strings were needed — Set, delete, and
  the target sheet all reuse existing keys, so `gen-l10n` was not run.

Slice 6 verification (all green; full suite now 470 tests):

```bash
./tool/tela dart format <touched Dart files>
./tool/tela analyze
./tool/tela test test/domain/models/private_image_test.dart \
  test/data/method_channel_image_store_test.dart \
  test/data/method_channel_screen_guard_test.dart \
  test/domain/use_cases/apply_private_image_test.dart \
  test/core/gallery_session_controller_test.dart \
  test/features/private_immersive_session_test.dart
./tool/tela test
```

New/covered tests: dimension mapping including a corrupt file (native `-1` →
null dims, safe state); reference-counted screen guard (only the window's edges
cross the channel); `ApplyPrivateImage` reaches the applier with the private URI
and never falls back; `removeSelected` next/previous/empty; app-lock pass/fail
gating the viewer and not re-running on swipe; `FLAG_SECURE` acquired before
content and held across viewer → target sheet → delete confirmation, released on
dispose; no share action; Set → target → applier; delete next-then-previous-then
-empty; the position announcement carrying no path; corrupt file safe state.
Named fakes: `FakeWallpaperApplier`, `FakeScreenGuard`, `FakeAppLock`,
`FakeLocalPreviewCache`, `FakeImageStore`.

One note for the next agent: the native `BitmapFactory` bounds decode has not
run on a device — the Dart mapping is proven through the channel fake, and the
`file:`-scheme `LocalPreviewCache` path is exercised (private files take no
native round-trip), but a device pass should confirm a real private file decodes
its bounds and that `FLAG_SECURE` survives the grid↔viewer round trip. Also note
the shared viewer's close **button** relies on `ImmersiveGalleryViewer`'s
`PopScope`/`_allowPop`, which does not pop on the first synchronous `maybePop`;
the private viewer's own delete-to-empty exit uses an unconditional
`Navigator.pop()` to sidestep that, but the button-close path is inherited from
History and unverified on hardware.

### PRIOR SLICE — slice 5 (History viewer)

Slice 5 gives Download History the same first-class fullscreen viewing as
Browse and moves target selection behind a Set action (delivery-order step 3):

- A History tile now opens the shared immersive surface at that exact record,
  over the whole history (newest first) as one local `GallerySessionController`
  snapshot. `features/downloads/download_immersive_session.dart` is the new
  feature wrapper around `ImmersiveGalleryViewer` (no new zoom impl); it passes
  **no** `requestMore`, so `canRequestMore` is false and it never pages — the
  same complete-local-snapshot isolation Favorites holds.
- Local-first, so the viewer works offline. A new `LocalPreviewCache` port
  (`domain/ports/local_preview_cache.dart`) + `LocalPreview` model materialise a
  download's location — `file:`, MediaStore `content:`, or a SAF document URI —
  into a decodable file. `DownloadGallerySource` shows that file first and falls
  back to `ProgressiveWallpaperPreview`'s network source on a null result or a
  decode error, releasing any throwaway copy when the selection moves or the
  widget disposes. The adapter `MethodChannelLocalPreviewCache` resolves a
  `file:` path directly in Dart and copies a `content:`/SAF one through native
  `materializeImage`/`releasePreview` on `cc.pym.tela/images`; the Kotlin side
  copies into a `cacheDir/previews` folder and confines every release to it. No
  URI or path is ever logged.
- The viewer's primary action is **Set wallpaper** → target sheet →
  `ApplyDownload`, so the missing-file → Wallhaven fallback stays intact. An
  overflow action carries "Remove from history" with the exact pinned wording,
  and the grid's long-press still forgets. Set, the missing badge, and forget
  all follow the item currently shown, never the tile that opened the viewer.
- `ImmersiveGalleryViewer` gained three generic slots — `primaryAction`,
  `actions`, `statusOverlay` — so feature actions stay *outside* the shared
  surface. History puts Set in `primaryAction`, its overflow in `actions`
  (both fade with the transient chrome), and the persistent "not on this
  device" badge in `statusOverlay`. The missing badge is derived from
  `missingDownloadsProvider`, agreeing with the grid.
- Aspect ratio and masonry geometry use the record's real `Wallpaper.resolution`.
  Previous/Next, swipe, and arrow keys move through the history order; returning
  restores the grid and its scroll position (the viewer is pushed over the
  history route).

Slice 5 verification (all green; full suite now 446 tests):

```bash
./tool/tela gen-l10n   # three new strings: gallery-more-actions, viewer-missing, forget-menu
./tool/tela dart format <touched Dart files>
./tool/tela analyze
./tool/tela test test/data/method_channel_local_preview_cache_test.dart \
  test/features/download_immersive_session_test.dart \
  test/features/download_history_screen_test.dart
./tool/tela test
```

New/covered tests: adapter resolves all three URI schemes and releases only
temporary copies; viewer shows local-first, falls back to Wallhaven with the
badge when the file is gone, Set → target → `ApplyDownload`, overflow forget
keeps the pinned "the file stays" sentence, Set/forget follow the shown item
across Next, temporary previews are released; the screen opens the viewer at the
tapped record (not index zero) and restores the grid + scroll on return.
`FakeLocalPreviewCache` is the named fake modelling the three schemes.

One note for the next agent: the private-library viewer is step 4 and was
deliberately **not** touched here. The native `materializeImage`/`releasePreview`
Kotlin was written but has not run on a device — the Dart side is proven through
the fake; a device pass should confirm a `content:`/SAF preview actually decodes.

### PRIOR SLICE — slice 4 (public viewer paging)

Slice 4 connects the public viewer to Wallhaven pagination:

- `GallerySessionController` now owns a one-in-flight-at-a-time request-more
  guard, appends deduplicated by an optional `itemKey`, updates position and
  enables Next the instant items arrive, prefetches only the immediate new
  neighbour, records a failed request (`hasRequestFailed`) rather than throwing,
  and auto-asks for more when the selection nears the loaded end (including a
  shelf opened on its last tile, deferred one microtask so wiring completes). It
  still imports no Riverpod, paging package, or transport.
- `features/browse/gallery_paging_bridge.dart` is the small adapter: it drives
  the grid's *own* `PagingController.fetchNextPage` and appends the new tail to
  the open session. Going through the grid's fetch path is what preserves the
  live query and the `random` shuffle seed; `fetchNextPage` returns void, so the
  bridge observes completion through the controller's loading flag. A failed
  page rethrows the paging error so the session marks it for retry.
- `WallpaperGrid` builds a `GalleryPagingBridge` and hands each session a
  `requestMore` closure bound to that session, plus an `itemKey` of the
  wallpaper id. Favorites (a plain `MasonryGridView`, no `WallpaperGrid`) passes
  no `requestMore`, so `canRequestMore` is false and it never pages — the
  complete-local-snapshot invariant holds structurally, not by convention.
- `WallpaperImmersiveSession` now resets zoom only when the *selected index*
  changes, so an appended page rebuilds Next/position without flinging the
  current image back to fitted scale.
- The non-blocking retry path is `session.requestMore()` itself: it leaves the
  selected image, loaded boundary, chrome, and fullscreen untouched, clears the
  in-flight guard on completion, and the near-end auto-trigger retries as the
  user keeps navigating. No new viewer chrome was added for it.

Slice 4 verification (all green; full suite now 434 tests):

```bash
./tool/tela dart format <touched Dart files>
./tool/tela analyze
./tool/tela test test/core/gallery_session_controller_test.dart \
  test/features/gallery_paging_bridge_test.dart \
  test/features/gallery_session_launch_test.dart
./tool/tela test
```

New/covered tests: near-end triggering (on select and on a last-tile mount),
one in-flight request at a time, append ordering + id dedup, query/seed
preservation through the grid's fetch path, failure-then-retry, Favorites
isolation (`canRequestMore` false, never pages), position + Next after append,
and the existing selected-item/scroll-restoration-across-viewer-exit coverage.

One test-shape note for the next agent: a widget test that taps a tile and
expects only page 1 loaded is unreliable — `PagedMasonryGridView` eagerly
fetches page 2 to fill the viewport. Test the bridge's append/dedup directly
against a hand-driven `PagingController` (see
`gallery_paging_bridge_test.dart`), and assert seed/query preservation via the
page-2 request the grid records.

### PRIOR SLICES

Slices 1 and 2 established the honest shared viewport and reusable immersive
surface. Slice 3 adds already-loaded public gallery sessions:

- `core/ui/gallery_session_controller.dart` owns stable shelf identity,
  ordered loaded items, selected index, boundaries, immediate-neighbour
  prefetch, append, and an optional request-more callback without importing
  Riverpod, `PagingController`, or Wallhaven transport.
- Browse, Favorites, and linked listings create a session from the exact shelf
  snapshot and tapped index. Query-backed and linked shelves have distinct,
  deterministic identities; Favorites uses `favorites`. Returning keeps the
  existing route and scroll state.
- Immersive chrome now has visible 48dp Previous/Next controls with true
  boundary-disabled states and a live accessible “x of y” position. Horizontal
  swipe and keyboard/D-pad arrows share selection behavior.
- Raw pointer observation detects fitted swipes without competing with
  `InteractiveViewer`. While zoomed, touch input pans and horizontal keys pan
  by a bounded step; explicit Previous/Next still selects and resets zoom.
- Detail, metadata loading, favorite/share/download/Set actions, and the normal
  preview all follow the session selection. Closing fullscreen leaves Detail
  on that selected wallpaper.
- Immediate loaded neighbours warm their aspect-correct preview and full image.
  No next page is requested in this slice.

Slice 3 verification:

```bash
./tool/tela dart format <touched Dart files>
./tool/tela analyze
./tool/tela test test/core/gallery_session_controller_test.dart \
  test/core/gallery_zoom_controller_test.dart \
  test/core/immersive_gallery_viewer_test.dart \
  test/core/gallery_viewport_test.dart \
  test/features/gallery_session_launch_test.dart \
  test/features/wallpaper_detail_screen_test.dart
./tool/tela test
```

All pass; the full suite now has 426 tests.

### ~~NEXT SLICE ONLY~~ — the device matrix (step 6) — **DONE 2026-07-16**

**This pass has been run; its results are the fix list at the top of this file.**
Kept for the record. Steps 1–5 were done at slice 7; step 6 was the full
automated + real-device matrix on the SM-X730, and it produced seven findings —
including the close-button bug that slice 6 predicted below and slice 7 waved
through.

Before installing, run the pre-handoff gate from the "Acceptance matrix" below:
`./tool/tela gen-l10n`, `dart format .`, `./tool/tela analyze`, `./tool/tela
test`, `./tool/tela build apk --debug`.

Device confirmations still owed, carried forward and now joined by slice 7's:

- **Slice 7:** the tile→viewer **Hero flight** reads well against real
  thumbnails; the **reduce-motion** cut is genuinely instant on device; the
  safe-area **grid padding** clears the gesture bar on the last row in landscape.
  All three are proven only in widget tests.
- **Slice 6 (Private):** the native `BitmapFactory` **bounds decode** returns a
  real private file's pixel dimensions, and `FLAG_SECURE` survives the
  grid↔viewer round trip (and the viewer's inherited close-button path — the
  delete-to-empty exit is proven, the button-close is not). Do **not** claim the
  private screenshot path was captured — `FLAG_SECURE` must make that impossible.
- **Slice 5 (History):** the native `materializeImage`/`releasePreview` copy
  decodes an actual `content:`/SAF preview.

Inspect logcat for Flutter exceptions/overflows; confirm system chrome and
`FLAG_SECURE` restore correctly on every exit.

## START HERE — immersive image viewing and the next UI/UX pass

This is the next agent's task. Start from clean `master`; its implementation
baseline is `2d2a153`, which already contains sharing and the adaptive
gallery-first shell. **Do not work in the master worktree.** Create a dedicated
worktree before editing:

```bash
git worktree add .worktrees/image-viewer-ux -b image-viewer-ux master
```

The objective is to make every gallery image enjoyable at its real aspect ratio
in portrait and landscape, then give Download History and the private/NSFW
library the same first-class fullscreen viewing experience as Browse. This is
an image-viewing and gallery-polish slice, not a rewrite of tela's domain,
storage, or privacy model.

### What the real tablet exposed

The current UI was exercised on a Samsung SM-X730 at 1600x2560, Android 16, in
both landscape and portrait. Browse, filters, adaptive navigation, detail,
sharing, and fullscreen all worked without a crash or RenderFlex overflow. The
remaining problems are visual and interaction problems that widget tests did
not reveal:

1. `ProgressiveWallpaperPreview` paints `thumbLargeUrl` beneath
   `fullImageUrl`. Those files do not always have the same crop. On the tablet,
   a portrait source was correctly contained in the centre while a different,
   wider thumbnail crop remained visible down both sides. The same mismatch was
   visible in portrait, landscape, and the so-called fullscreen view. A loading
   preview must never show two contradictory compositions of the same image.
2. Fullscreen is not actually immersive. Android's status/navigation areas stay
   visible, chrome is always present, there is no tap-to-toggle chrome, and the
   zoom experience has no obvious double-tap/reset path.
3. Download History skips viewing entirely: tapping a tile immediately opens
   the target sheet to set it again.
4. The private/NSFW library has no tap action at all. Its images can be deleted
   by long press, but cannot be inspected fullscreen or set again from the
   library.
5. Private tiles are square and `BoxFit.cover` because `PrivateImage` does not
   carry dimensions. This crops every non-square file in the one gallery where
   recognising an image before acting on it matters most.

### Product result

The finished experience should feel like an image viewer first and an app
second:

- A tap from any image shelf leads to a large, honest preview; no source pixels
  are cropped by default.
- Portrait images use the available height, landscape images use the available
  width, and orientation changes recompute the fit without losing the selected
  image.
- The canvas is calm and intentional (black is acceptable). Never use a second,
  differently cropped version as accidental side fill. If a backdrop is kept,
  it must be an explicit treatment of the same source and must not compete with
  the contained image.
- Fullscreen goes edge-to-edge, hides system/app chrome, restores it on exit,
  and supports pinch/pan, double-tap zoom/reset, tap-to-toggle controls, an
  obvious close/back control, and screen-reader equivalents for every gesture.
- Gallery viewers can move to the previous/next item without returning to the
  grid. This must not be gesture-only: provide visible Previous and Next
  controls, swipe navigation, keyboard/D-pad arrows where available, and an
  accessible position such as “5 of 24”. Disable the relevant arrow at a true
  boundary. Horizontal paging must not steal a gesture while the current image
  is zoomed.
- Returning from a viewer restores the same gallery and scroll position.
- Animations are short and spatially coherent, and become instant when
  `disableAnimations` is true. A restrained Hero transition is welcome, but
  duplicate IDs across shelves must not create duplicate Hero tags.

### One shared viewer, three kinds of image

Build one reusable viewer/viewport in `core/ui` and keep feature actions outside
it. Do not create separate zoom implementations for Detail, History, and the
private library.

The shared viewport must accept an honest aspect ratio, an accessible label,
and an image source without knowing whether the surrounding screen will share,
delete, download, or set it. It should handle loading, decode failure, zoom,
chrome visibility, orientation changes, and reduced motion. Keep files below
500 lines and split controls, viewport, and gallery paging if needed.

Every shelf must open a **gallery session**, not a disconnected single-image
route. The session carries the ordered images, selected index, gallery identity,
and an optional way to request more results. Browse and linked listings should
append the next API page as the viewer approaches the end; Favorites, History,
and Private use their complete local lists. At minimum, every already-loaded
image must be reachable back and forth without returning to the grid. Do not
couple the reusable viewer to `PagingController`; expose a small project-owned
session/controller seam instead.

Navigation behaviour is load-bearing:

- tapping a tile opens that exact item, not index zero;
- Next/Previous, horizontal swipe, and arrow-key/D-pad input all update the same
  selected index and semantics announcement;
- zoom resets to fitted scale when the selected image changes, while an
  orientation change keeps the selected image and recomputes its fit;
- swiping left/right pans a zoomed image first; page navigation becomes active
  again only at fitted scale (or through the explicit Previous/Next controls);
- prefetch only the immediate neighbour in each direction;
- exiting fullscreen leaves Detail on the newly selected wallpaper, and Back
  to the shelf restores the grid near that tile;
- deleting the current private item selects the next item, then the previous at
  the end, and closes to the empty state when none remain.

Source behaviour differs:

- **Browse/Favorites/linked listings:** keep the existing detail route and its
  metadata/actions, but refactor its preview and fullscreen mode onto the shared
  viewport. Use an aspect-ratio-preserving thumbnail for progressive loading —
  `thumbOriginalUrl` is already used by `WallpaperTile` for this reason — or
  constrain both layers to exactly the source aspect ratio. Fade only between
  geometrically identical images.
- **Download History:** show the saved local file first so the viewer works
  offline. `DownloadRecord.location` can be `file:`, MediaStore `content:`, or a
  SAF document URI; do not assume `FileImage` can read all three. If Flutter
  needs a materialised cache file, put that platform work behind a
  project-owned port/adapter and clean temporary previews. Never log a URI or
  path. If the file is missing, clearly show that the network source is being
  used and preserve the existing re-download/apply fallback.
- **Private/NSFW library:** treat every `PrivateImage` as sensitive even if the
  original purity is unavailable. The fullscreen route must independently hold
  `FLAG_SECURE`; do not rely only on the grid remaining mounted behind it. It
  must also respect the app-lock gate, never expose a path in logs/semantics,
  never offer image or link sharing, and never place a preview in shared cache
  or MediaStore.

The current `DownloadWallpaper._remember` already excludes explicit downloads
from ungated Download History; keep that invariant and add a regression test if
the viewer changes listing code.

### Screen-specific interaction contracts

**Wallpaper Detail**

- Preserve favorite, share, download, metadata, uploader/tag navigation, and
  the fixed **Set wallpaper** action.
- Compact portrait remains preview-first; expanded landscape remains a useful
  preview/information split. Rebalance the preview pane if necessary, but do not
  make metadata compete with the image.
- Entering fullscreen must use the exact image and current progressive state,
  not visibly restart from a mismatched placeholder.
- Browse, Favorites, and linked-listing launches must give fullscreen access to
  their gallery session. Moving to another wallpaper updates the Detail image,
  metadata, favorite/share/download actions, and Set action to that wallpaper;
  no action may remain bound to the item that originally opened the route.

**Download History**

- Tap opens the fullscreen/local viewer instead of immediately choosing a
  target.
- Previous/Next moves through the history order (newest first), and the Set,
  missing-file, and forget actions always follow the image currently shown.
- The viewer's primary action is **Set wallpaper**; only then show Home / Lock /
  Both and reuse `ApplyDownload` so missing-file fallback stays intact.
- Keep “missing locally” obvious in both grid and viewer.
- Keep “remove from history” distinct from deleting the downloaded file. Move
  it into a discoverable viewer overflow/action as well as retaining any useful
  long-press shortcut.
- Use the record's real `Wallpaper.resolution` for masonry/preview geometry.

**Private/NSFW library**

- Tap opens a secure fullscreen gallery at that image; swiping visits the other
  private images without dropping `FLAG_SECURE` or re-running authentication.
  Visible Previous/Next buttons must work with TalkBack and physical
  keyboard/D-pad input; sensitive item names or paths must not appear in the
  position announcement.
- Add a primary **Set wallpaper** flow backed by a small pure-Dart use case that
  sends the private file URI through the existing `WallpaperApplier` port.
- Delete is explicit, confirmed, and returns to the nearest remaining image or
  the empty state. Sharing is absent by design.
- Extend the native private-file listing to return pixel width/height using a
  bounds-only decode, then add those dimensions to `PrivateImage`. Use them for
  aspect-ratio tiles instead of square crops. Corrupt/unreadable files still
  render a safe broken-image state and must not crash the gallery.
- The secure window must remain active through grid, viewer, target sheet, and
  deletion confirmation, and release only after leaving the private flow.

### Gallery and screen polish

Apply the same image-first quality bar to Browse, Favorites, History, and the
private library:

- consistent 12dp grid rhythm and 16dp corners;
- responsive column counts without comically narrow tiles;
- edge padding that respects safe areas and navigation mode;
- useful headers/empty/error/loading states that do not dominate the gallery;
- no important action available only through an undiscoverable long press;
- 48dp targets, dynamic type without clipping, meaningful semantics, visible
  focus, and adequate contrast over images;
- prefetch only immediate viewer neighbours and cap decode sizes to the display;
  do not decode a whole gallery of 6K originals or keep unbounded image bytes.

Do not add decorative controls merely to fill tablet space. The image remains
the interface and **Set wallpaper** remains the one primary action.

### Suggested delivery order

1. Write regression tests for the mismatched progressive layers and extract the
   shared aspect-ratio-correct viewport.
2. Make Detail fullscreen truly immersive and verify portrait/landscape,
   reduced motion, back, zoom, and chrome restoration.
3. Add the local History viewer and move target selection behind its Set action.
4. Add private image dimensions plus the secure private viewer and apply use
   case.
5. Add gallery paging/transitions and finish consistent shelf polish.
6. Run the full automated and real-device matrix before merging.

### Acceptance matrix

Automated coverage must include:

- 390x844 compact portrait, 844x390 compact landscape, and at least one
  >=840dp expanded landscape surface;
- portrait, landscape, square, and extreme-aspect images using contain geometry
  with no contradictory placeholder visible after the source loads;
- pinch/double-tap/reset and app/system chrome restoration (factor controller
  logic into testable code where raw gestures would be brittle);
- History tap -> viewer -> Set -> target, missing-file state, local-first source,
  forget confirmation, and back/scroll restoration;
- gallery sessions open at the tapped index; Previous/Next buttons, swipe, and
  arrow keys stay in sync; boundary controls disable correctly; approaching a
  Browse/linked-listing boundary requests the next page once; actions and
  metadata follow the selected item rather than the initially tapped item;
- private lock pass/fail, `FLAG_SECURE` acquired before content and retained for
  every child surface, no share action, set flow, delete flow, corrupt file, and
  dimension mapping;
- screen-reader labels, 48dp targets, large text, and reduced motion;
- existing share policy: explicit wallpapers remain link-only on Detail and
  private files have no share action at all.

Before handoff/merge, run:

```bash
./tool/tela gen-l10n
dart format .
./tool/tela analyze
./tool/tela test
./tool/tela build apk --debug
```

Then install the exact commit on the SM-X730 and repeat Browse, Detail,
History, and private-library flows in portrait and landscape. Inspect logcat for
Flutter exceptions/overflows, confirm system chrome and `FLAG_SECURE` restore
correctly, and do not claim the private screenshot path was visually captured —
`FLAG_SECURE` must make that impossible.

## Sharing a wallpaper, and the one thing that never leaves (Wave 4, first slice)

The newest work, and the one to read first. **Wave 4 has begun, and its first
slice is the share sheet** — a wallpaper's detail screen can now hand it to
another app. It is built, tested, and **verified on the tablet** (2026-07-15,
Samsung SM-X730, Android 16): the chooser opens, a link lands in the receiving
app as `https://wallhaven.cc/w/{id}`, and the image path fetches the full file
and hands it off through a `FileProvider` grant.

**The load-bearing decision is that a wallpaper shares two different things, and
they obey different rules.** A *link* is the public Wallhaven page and may be
shared for any purity — it reveals nothing tela is holding. The *image file* is
the actual bitmap leaving the device, so it is refused for explicit wallpapers,
exactly the way `StorageSettings.choicesFor` refuses the gallery tier. The rule
lives in `shareOptionsFor(purity)` and is enforced twice: the menu never shows
the Image tile for an explicit wallpaper, and `ShareWallpaper.image` throws if
called anyway. A widget test pins the tile's absence, and the tablet confirmed
it — an explicit wallpaper's share menu is link-only. This is the same
fail-toward-safe posture as every other NSFW rule here: the private library's
`FLAG_SECURE`, the never-index storage adapter, the corrupt purity that reads as
`nsfw`.

The seam is the usual one: a `WallpaperSharer` port, a `ShareWallpaper` use case,
and a `MethodChannelWallpaperSharer` on a new `cc.pym.tela/share` channel. Kotlin
`WallpaperSharing` fires `ACTION_SEND` — plain text for a link, and for an image
a `FileProvider` content URI with a one-shot read grant, out of a cache folder
emptied before each share so only the wallpaper being shared right now is ever
exposed. The applier's HTTP download moved to a shared `Downloads.kt` so the two
paths do not carry two copies of it; the apply path is otherwise untouched and
still passes its tests. The manifest grew a `FileProvider` and a `file_paths.xml`
scoped to that one cache subfolder — the only storage-shaped addition, and it
grants nothing beyond a single handed-out URI.

**What the device could not settle** is the same shape as everywhere else: the
happy path is deliberately silent (the share code logs no URLs or paths, per the
logging rule), so what was watched for was a crash — a `FileProvider`
misconfiguration throws "Failed to find configured root" — and none came. The
`filesOutsideGallery`-style edge cases do not apply; a share always fetches fresh
from Wallhaven rather than reading a stored file.

## The two filters, and what the real server actually said (Wave 3, slices 1–2)

**Historical, and still the record of what the live API says** — re-confirmed
probe by probe on 2026-07-16 (see "SOLVED — Wave 3's exit"), so it is evidence
rather than a memory. **Wave 3's last two slices are built, and they are the
first thing in tela that was designed against the live Wallhaven API rather than
against its docs** — the docs 403 from here, so the vocabulary was
settled by `curl`ing the real `/search` and reading back what came out. That is
worth knowing because *four* of the design decisions below exist only because the
server was asked, and every one of them contradicts what a reasonable person would
have assumed.

**Read this first, because it is the finding the whole ratio slice turns on:
Wallhaven's `ratios` takes an arbitrary `WxH`, not a fixed vocabulary.**
`ratios=9x20` comes back with 24 wallpapers, every one of them at ratio 0.45;
`9x19` likewise at 0.47. So a modern phone can ask for *exactly its own shape* —
which appears in no wallpaper site's dropdown — and the fallback rule this slice
was expected to need (what do you offer a 9x20 phone?) simply evaporated.

The other three, each of which changed the code:

- **An unreadable `ratios` value is silently ignored**, and answered with an
  *unfiltered* grid. `ratios=bogus` returns the same mixed listing as no filter at
  all. So a corrupt literal must be caught in `RatioChoice.tryParse`, or it reads
  on screen as a filter that quietly does nothing.
- **`resolutions` fails the opposite way: `resolutions=bogus` returns *zero*
  results.** It is an exact match, so an unpopular size is not a narrower listing,
  it is an *empty* one. `720x1280` has **no wallpapers at all** on the real server.
  That is why `offerableResolutions` offers only sizes Wallhaven actually has, why
  the portrait ladder starts at 1080p, and why the Exactly mode says out loud that
  few wallpapers match a phone-shaped size. Wallhaven is largely a *desktop*
  wallpaper site; Exactly is really for the desktop-sync tier, and Automatic stays
  the default.
- **`atleast` and `resolutions` conflict.** Sent together, Wallhaven honours
  `atleast` and silently ignores `resolutions`. `ResolutionFilter` is therefore a
  **sealed** type — Automatic / AtLeast / Exactly — so the combination that loses
  is not expressible. That is a proof rather than a check, and it is the reason the
  resolution filter is a *mode* rather than two independent fields.

**`SearchQuery.atLeast`'s `copyWith`-cannot-clear trap is retired**, as PLAN
promised: the field is now a non-nullable `ResolutionFilter`, so there is no
cleared state to be unable to express. The same hole is still open for `seed`.

**Neither slice has run on hardware** — see "Owed on the device". The distinction
matters and cuts the *opposite* way from the sorting slice: there, a fake could
prove tela *built* `sorting=views` but not that Wallhaven *honoured* it. Here
Wallhaven's half is the half that is proven, by real requests; what has never
happened is **tela itself sending a `ratios=9x20` or a `resolutions=` to the real
server**. Only `FakeWallhavenApi` has seen those params.

## Every sorting is reachable (Wave 3, slice 3)

Slice 3, and now one wave behind. **Three of Wallhaven's seven
sortings could not be reached at all** — `relevance`, `views` and `favorites`
have been in the `Sorting` enum since Wave 1, and nothing could select them,
because the tab *was* the sorting and there were four tabs. The bar is now
scrollable and carries Most viewed and Most favorited; **Relevance appears only
while a search term is set** and is selected on submit.

`offerableSortings(hasTerm:)` is the rule, and it sits beside `offerablePurities`
because it is the same shape of rule: an option Wallhaven cannot honour is not
offered. Relevance ranks results *against* `q`, so with no term there is nothing
to rank and the tab would quietly be a listing of something else.

**The load-bearing part is that the selection is held by *sorting*, not by tab
index.** Relevance appearing renumbers every tab behind it, so an index-based
controller would move someone from Top to Hot the moment they cleared a search.
`BrowseScreen` is stateful now for exactly this: it owns a `TabController` whose
length changes under it, and `_selected` is what carries across the rebuild.

**It has run on hardware against real Wallhaven** (2026-07-14, Samsung SM-X730):
Most viewed and Most favorited come back as real, *distinct* grids — proof the
params are honoured and not merely well-formed, which is all a fake could ever
show. Searching from Most viewed moved the user to Relevance and returned
genuinely sunset-ranked results, and clearing the search from Top left them on
Top rather than Hot. No Flutter errors in logcat.

**Still owed on a phone:** at 2560px the tablet fits all seven tabs without
scrolling, so the *scrolling* of the scrollable bar has never actually been
exercised. It joins the palette and the launch grid on the phone list.

## Tags and the uploader lead somewhere (Wave 3, slice 4)

The newest slice, and the one to read first. **A wallpaper is now a place you can
navigate *from*.** Its tags and its uploader were printed on the detail screen
from Wave 1 onward and led nowhere; a tag chip now opens that tag's listing and
the uploader opens theirs. This is the fourth of Wave 3's four slices, taken
first because it is the only one that is entirely self-contained.

`WallpaperLink` is the model — a sealed `TagLink` / `UploaderLink` that carries
only *what was followed*, never a query — and `LinkedListingScreen` is what shows
it. The link supplies the term (`id:{tagId}`, `@username`) and the sorting;
everything else is inherited from the listing the user is already browsing, so
their filters still apply and the grid is still fitted to the device's screen.

**It has run on hardware against real Wallhaven, and the exactness is proven, not
assumed**: following the *Wamiqa Gabbi* tag returned exactly **one** wallpaper —
the one it was followed from — which is what `id:{n}` is supposed to do and what
a fuzzy `+name` would not have done. The device also found the one thing wrong
with it (a link sitting below its own label), which is fixed.

**There is still no tag filter you can type into**, and this slice is the first
thing in tela that builds a Wallhaven operator *for* the user. See "What the
search box already does" below — the answer surprises people.

## The device pass: what a phone found that no test could

**Wave 2 finally ran on hardware,
and it was worth every minute** — the device found four bugs, one of them a
security hole, and not one of them was findable in a test suite that was green
the whole time.

- **The private library's lock opened itself.** Fumble the fingerprint five
  times and the gate let anyone in, with no prompt. Fixed by making it fail
  closed, and by teaching `AppLock` to tell a locked-out sensor apart from a
  device that has no credentials — see the decisions below.
- **Turning the lock *off* was ungated**, which made the gate decorative: the
  switch that removes it sat one tap away on an open Settings screen. It now
  raises the same prompt the library does.
- **Downloads did not appear until the app was relaunched** — both the download
  history and the private library. The files and the rows were always there; the
  listings were caching an empty world from app start.
- **A history row outlived its file** with no way to say so, and no way to
  remove it. Both built: a badge, and a long-press.

Everything in that list is fixed, tested, and re-verified on the tablet.
**Wave 2's exit criterion is met**, with the exceptions in "Owed on the device".

## Browse defaults: a switch, not a heuristic

**Where browse takes its opening
filters from is now the user's choice**, in Settings: the Wallhaven account, or a
snapshot saved from this device's filter sheet ("Save as default", next to
Reset). It replaces the invisible rule that used to answer the question — the
account's defaults were adopted only while the current query still equalled the
old ones, which worked but could not be seen, predicted, or overruled.

`BrowseDefaults` is the model (categories, toplist range, ratios, order, colour),
`BrowseDefaultsSource` the choice, `ResolveBrowseDefaults` the use case that picks
between them, and `browseDefaultsProvider` (in `app/`, beside the account one, for
the same "two features meet here" reason) the thing browse reads. `AccountSettings`
no longer applies itself to a query; it converts to a `BrowseDefaults` like any
other source. Storage is four new KV rows plus the source — no migration, as every
setting since v1.

**Purity is still not a field, in either source.** Not the account's — that was the
device bug of this morning — and not a snapshot you save, which would do the
identical thing with the user's own fingerprints on it. It is structurally absent
from `BrowseDefaults`, not merely unread.

**It has run on hardware, and the device found the bug in it** (see "Owed on the
device" for what that leaves). Everything else about it is verified: the toggle
persists, switching sources moves the live grid, and the snapshot survives a
restart.

## Current milestone

**Wave 4 has started, with the share sheet built and verified on hardware**
(`share_wallpaper.dart`, `wallpaper_sharing.dart`, and the detail-screen button;
see the top of this file). It is the first of Wave 4's opt-in extras — the rest
(crop/reposition, daily auto-rotate, collections, Omarchy sync) are still open.

**Wave 3 is complete and its exit criterion is met** (`7510500`). Its four slices
are: the tag/uploader links (`984b546`), every sorting reachable (`eb2af8a`), the
ratio filter (`7f41d13`) and the resolution filter (`1c90b86`). The first two ran
on the tablet.

The two filters are proven, though **not by a hand-driven pass over the filter
sheet on the tablet** — be precise about what was shown, because it is a
different and in one way stronger claim. tela's emission is pinned by test at the
wire (`dio_wallhaven_api_test.dart`, below Dio's serialization), Wallhaven's
behaviour by `curl`, and the two are joined by curling the exact URIs the test
captures. The tablet contributes the end-to-end half without anyone touching it:
it **cold-launches to a loaded grid**, and that query *is*
`atleast=<screen>&ratios=9x16` — so the resolution path reaching the real server
and answering with images is observed on hardware every launch. What no one has
done is drive the sheet by hand and watch a *chosen* filter narrow the grid; that
is a UI check, not a contract one, and the contract is what was open.

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

**Wave 2 is complete, and verified on hardware.** Favorites are `0cf2781`,
Material You is `c056369`, the private library is `a2e5da7` + `5f747a8`, the
download history is `50485bd`, the colour filter with the shared status states is
`f0c1e10`, and the account `/settings` sync is `9dd0d6a`; see "Wave 2" below. The
device pass of 2026-07-14 ran it on a real tablet and found four bugs, all fixed —
read the top of this file first. What the tablet could not settle is in "Owed on
the device", and none of it blocks Wave 3.

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

Verifying is now `GET /settings`, so the same request also brings back the
account's own browse defaults: its categories and its toplist range. Browse opens
on them, "Reset filters" returns to them, and a filter the user set by hand is
never overwritten by them. Forgetting the key forgets them too. The account's
**purity is deliberately not among them** — browse always opens on safe, and
sketchy and explicit stay per-session choices in the filter sheet.

Browse is finally a search, not four fixed listings. The app bar holds a search
field, and a filter sheet behind it edits categories, purity, shape (portrait /
landscape / any), sort order, and the toplist range. All of it is one
`SearchQuery` in `browseQueryProvider`, shared by the four tabs; the tab layers
its `Sorting` on top and the screen layers `atLeast`, because neither is a filter
the user chose. **The Explicit purity chip appears only once a key is stored** —
that is the step that was missing for NSFW to be reachable at all, and it is why
the key slice came first.

## Wave 2

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

**Colour filter + shared status states** (`f0c1e10`). The filter sheet now carries
Wallhaven's 29-swatch palette, and every grid in the app draws its empty and
failed states through one `WallpaperStatusView` instead of four hand-rolled
centred `Text`s. Browse, favorites, the download history, and the private
library now say "nothing here" the same way, and a failure picks its icon from
what actually failed — the offline cloud for a dead network, not a generic
error triangle.

**Account `/settings` sync** (`9dd0d6a`, plus `70f6227`, `76471d3` and `e7db95f`
from the device pass). Saving an API key now pulls the Wallhaven account's own
browse defaults — **categories and toplist range, and deliberately not purity** —
and browse opens on them. The same request is what *verifies* the key, so the
sync is free: it replaced an NSFW-purity search that cost the same one of the
45 req/min and learned nothing but "valid". A filter the user set by hand is
never overwritten, and forgetting the key drops the defaults with it. This was
Wave 2's last slice.

**It has run on hardware, and the device found both of the things that were
wrong with it.** Neither was findable in a test, and both are fixed and
re-verified on the phone:

- **A key that predates the sync never synced** (`70f6227`). The phone's database
  held a working API key and no `account.*` rows at all: `SaveApiKey` syncs, so a
  key saved by *this* build always has defaults, but a key saved by an earlier one
  had nothing that would ever ask again. The feature would have silently done
  nothing for every existing user until they re-pasted a key that already worked.
  `LoadAccountDefaults` now backfills once when it finds a stored key with no
  stored defaults.
- **Syncing the account's purity opened the front page on explicit** (`76471d3`,
  then `e7db95f`). An account with NSFW enabled turned tela's launch screen into a
  masonry grid of explicit thumbnails, behind no gate. Purity is now not synced at
  all — see the decision below. This one only shows up on an account that actually
  has NSFW enabled, which is why no fixture would ever have caught it.

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
- **The API key is verified on save**, so a typo is caught in the dialog rather
  than three screens later as a mystery empty grid. It first did that with an
  NSFW-purity search — the cheapest request Wallhaven *must* 401 for a bad key,
  chosen so the key slice would not drag Wave 2's `GET /settings` in a wave
  early. **`GET /settings` is now that request** (see the sync decisions below):
  same single cost out of the 45 req/min, but it answers with the account's
  defaults instead of a page of explicit imagery tela immediately throws away.
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
- **The app-lock gate now fails closed, and this was a real fail-open.** Found on
  hardware, 2026-07-14: fumble the fingerprint a few times and the private
  library would **open to anyone, with no prompt at all**. The gate asked
  `AppLock.isAvailable()` first and stepped aside when it said no — an escape
  hatch meant for "this device has no biometric and no screen lock, so it can
  never answer a prompt, and enforcing the lock would trap the owner outside
  their own files". But `local_auth`'s `isDeviceSupported()` is
  `isDeviceSecure() || canAuthenticateWithBiometrics()`, and it reports a
  **temporarily locked-out sensor** exactly the same way it reports *no
  credentials at all*. On a device whose only credential is a fingerprint (this
  tablet: three prints enrolled, no PIN — which is also why the PIN fallback
  never appeared, since `allowCredentials` is literally `isDeviceSecure()`), five
  bad reads flipped `isAvailable()` to false and the door swung open. Every other
  rule in this codebase fails safe — a corrupt lock setting reads as locked, a
  corrupt purity reads as `nsfw` — and this one failed open.
  `PrivateLibraryScreen._unlock` no longer consults `isAvailable()`: if the lock
  is on, a passing prompt is the only way in.
- **The escape hatch moved to the Settings switch, and it had to.** With the gate
  failing closed, a device that has genuinely lost its credentials would leave
  the owner's app-private files unreachable for good — they live nowhere else and
  no other app can see them. `AppLockSwitch` therefore disables itself only in
  the *on* direction: an unavailable lock that is already **on** stays turn-off-
  able (with a subtitle saying why), while turning one *on* stays refused,
  because a lock nothing can satisfy protects nothing. The two changes are one
  design and must not be separated — failing closed without a reachable "off" is
  a trap, and an "off" without failing closed is what shipped.
- **Turning the app-lock *off* is now gated too, and the switch was the real
  hole.** A gate on the library is worth nothing when the switch that removes it
  sits one ungated tap away on an open Settings screen. Switching *off* now
  raises the same prompt the library does; switching *on* asks for nothing, since
  there is nothing to prove yet and demanding a fingerprint to *add* protection
  only teaches people not to bother.
- **`AppLock.authenticate` returns an `AppLockOutcome`, not a bool, and that is
  the load-bearing part of both fixes.** A bool cannot tell "the sensor is locked
  out for 30 seconds" apart from "this device has no credentials at all" — both
  are `false` — and the whole family of bugs here lives in that gap. `passed`,
  `refused`, `lockedOut`, `unavailable`. Only `passed` opens the library. Only
  `passed` *or* `unavailable` may switch the lock off, and the exclusion of
  `lockedOut` is the point: if a lockout opened the switch, then failing the
  fingerprint five times would *be* the way past the lock — the original bug,
  moved rather than fixed. `unavailable` is the escape hatch and is honoured in
  exactly one place (the switch, off-ward), because app-private files live
  nowhere else and a device that can never answer a prompt must not strand its
  owner outside them for good.
- **`AppLock.isAvailable()` is now only ever a reason to *withhold* the setting,
  never a reason to open anything.** It is `isDeviceSupported()`, it flips false
  during a lockout, and any code that reads it as "this device cannot ask" is one
  step from reintroducing the fail-open. The port's docstring says so.
- **Remaining limit:** the gated-off switch raises the prompt, so someone past
  the *device's* lock screen still cannot remove tela's lock without a
  fingerprint — but a device with no credentials at all (`unavailable`) can still
  have the lock switched off by anyone holding it. That is the deliberate cost of
  not stranding the owner, and on such a device the biometric gate could never
  have been enforced anyway.
- **Both "on-device" listings are invalidated when a download lands** — and this
  was the "my download vanished" bug of 2026-07-14. `recentDownloadsProvider` and
  `privateImagesProvider` are plain (non-autoDispose) futures: each resolves once
  per process and then caches. Nothing dropped them after a download, so the file
  was written and the row inserted while the download history and the private
  library went on rendering the world as it looked when they were *first opened*.
  It presented as "the download didn't save"; a relaunch made it appear, which is
  what proved it a stale read rather than a lost write. The detail screen now
  invalidates both after a successful download. It drops both rather than picking
  by purity, because which one is stale is the wallpaper's business, not the
  caller's.
- **The two listings moved to `lib/app/library_listings.dart`.** A download is
  *written* from one feature (detail) and *read* in two others (downloads,
  private_library), and features may not import each other (CLAUDE.md) — the same
  reason `accountDefaultsProvider` lives in `app/`. They meet at the composition
  root instead.
- **A history row can be removed, and it never deletes the file.** The history is
  an index, not a folder: the file lives in the gallery or under the user's own
  SAF tree, where Photos and every file manager can already delete it, and tela
  reaching out from behind a tile that merely *looks* like a file is how someone
  loses a wallpaper they meant to keep. This was left unbuilt for exactly that
  reason, and the answer turned out to be **wording, not code** — the
  confirmation says in plain words that the wallpaper stays where it was
  downloaded, and the button says "Remove", never "Delete". A widget test pins
  that sentence, so it cannot quietly be reworded into a lie.
- **A history row whose file is gone is badged, and that is honesty rather than
  decoration.** The history calls itself "wallpapers already on this device", and
  for a row whose file was deleted from Photos that is simply false: the tile
  still works, but it silently costs a full re-download and needs a network the
  other rows do not. Those are two different actions and the grid was drawing
  them identically. Now the tile dims, takes a cloud-download badge, and — since
  a badge that exists only visually is not information — changes its semantics
  label too.
- **`ImageStore.canRead` opens the file rather than asking whether it exists.** A
  MediaStore row can outlive its file and a SAF grant can be revoked while the
  document is still listed, so the only honest test of "can tela read this" is to
  read it. Every failure answers false rather than throwing: a wallpaper the user
  deleted from Photos is an ordinary state of the world, not an error.
- **The badge is derived from the listing, not folded into it**, and a failed
  probe reads as *gone* rather than *fine*. Two deliberate asymmetries: a file
  check that hangs must never keep the download history off the screen (the grid
  renders from `recentDownloadsProvider`; the badges arrive when they arrive), and
  a probe that fails should over-warn rather than under-warn — the worst an
  incorrect badge does is promise a re-download that turns out to be unnecessary.
- **Apply is not download, and the device made someone ask.** Setting a wallpaper
  from a history row whose file is gone re-fetches from Wallhaven into a *cache
  temp file*, streams it to `WallpaperManager`, and deletes it in a `finally`
  (`MainActivity.kt`). It does **not** re-create the gallery file, which reads as
  "where did my download go?" until you know that setting a wallpaper was never a
  download. Confirmed on the device: nothing is left behind.
- **Put a build on the device with `./tool/tela run`, never `./tool/tela
  install`.** `flutter install` uninstalls the existing app before installing —
  unconditionally, by design, not because of anything wrong — and that takes the
  Drift database and the Keystore-backed API key with it. This is *not* the
  signing-mismatch problem the `~/.android` volume fixes; it happens with a
  perfectly matching signature, and the log line ("Uninstalling old version…") is
  the only warning you get. It cost this device its accumulated database on
  2026-07-14, along with the one hardware check that needed it (see "Owed").
  `tool/tela`'s header says so now.
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
- **The account seeds the defaults; it does not overrule a live choice.** This
  was the open "what wins" question, and the answer is neither extreme. Pulling
  the account's filters on top of one the user just set by hand would silently
  undo their choice; writing them to disk and *only* to disk would mean saving a
  key appears to do nothing until the next launch. So a sync replaces the current
  query **only while it still equals the old defaults** — and "still equals" is a
  real comparison, not a guess, because `SearchQuery` already has value equality
  (which it grew for the grid's reload check, `f0c1e10`). The search term is not
  a filter: searching for "sunset" is not an opinion about categories, so an
  adopted default keeps the term.
- **Only two of the account's five settings are synced.** `resolutions` and
  `aspect_ratios` are set by desktop users at a desktop: a synced `16x9` would
  fill a phone grid with landscape wallpapers, and tela already derives `atLeast`
  from the screen it is actually running on — strictly better information than
  the account has. `purity` is refused for the reason above. What is left is
  categories and toplist range: the two that mean the same thing on a phone as on
  the web, and that carry no risk when they are wrong.
- **The account's purity is never synced. Browse always opens on safe.** This is
  the most important decision in the slice, and the device is what forced it: an
  account with NSFW enabled made tela's launch screen a masonry grid of explicit
  thumbnails, behind no gate. That is exactly what "the account seeds the defaults"
  means, and it is the one place tela ran against its own grain — every other NSFW
  rule here fails toward safe (downloads route explicit to app-private, the private
  library is behind `FLAG_SECURE` and an app-lock, a corrupt purity reads as `nsfw`
  rather than `sfw`). A phone is the device you unlock on a train. Sketchy and
  explicit are now things you turn on for a session in the filter sheet, where the
  Explicit chip still appears as long as a key is stored.
- **Purity is dropped from the model, not merely ignored** — the mapper does not
  read Wallhaven's `purity` list, `AccountSettings` has no purity field, and the
  repository *deletes* the `account.purity` row an older build wrote. A stored
  value nothing reads is a value that misleads whoever next opens the database,
  and a model that carries one is a model where somebody eventually applies it.
  (The first attempt, `76471d3`, kept the field and narrowed it at the seam. That
  is one refactor away from the bug coming back.)
- **Forgetting the key drops the account defaults with it.** They belong to an
  account this device can no longer reach. This used to be half of a two-door guard
  against an explicit default outliving its key; not syncing purity at all closed
  that hole outright, so the load path no longer strips anything by hand.
- The account defaults are **read back through the port on every load, never
  cached from what the sync returned** — which is what gives the backfill somewhere
  to live.
- **The browse defaults are a switch the user sets, not a rule tela infers.** The
  old heuristic ("the account seeds, it does not override") was correct and
  invisible: nobody could see which source had won, or say they wanted the other.
  A radio in Settings answers the question out loud, and the heuristic survives
  only where it is still needed — a *changed source* is a deliberate act and
  resets the listing outright, while defaults arriving late from the source
  already in force (the backfill, a manual refresh) still refuse to overwrite a
  filter set by hand. Those are different events and they deserve different
  answers; `ActiveBrowseDefaults` carries the source precisely so browse can tell
  them apart.
- **A saved snapshot carries no purity either, and that is the same rule, not a
  new one.** Every argument against syncing the account's purity — a phone is the
  device you unlock on a train, a masonry grid of explicit thumbnails behind no
  gate — applies unchanged to a default the user saved themselves. So `Sketchy`
  survives "Save as default" *for the session* and is absent from the snapshot;
  the next launch opens safe. Only `clearFilters` (Reset) returns purity to safe
  within a session.
- **Adopted defaults are applied onto the live query, never a fresh one.** They
  speak for five fields and must leave the rest exactly as they were — the term,
  the tab's sorting, and the purity. The first cut applied them to a fresh
  `SearchQuery`, which meant saving your filters while Sketchy was on knocked the
  grid back to Safe underneath you. A default that silently un-does a choice you
  made one tap ago is worse than no default.
- **Each Settings row summarises its own source, never the one in force.** Found
  on hardware (2026-07-14): the account's row rendered whichever defaults were
  *active*, so with the device selected it read the device's filters back at you —
  on a device whose snapshot said "Last 24 hours" and whose account says "Last
  month". That line is what you consult *before* switching, so a wrong one is
  worse than none. No fixture caught it because every test had the two sources
  agreeing or only one populated; it needs a real device where they disagree.
  `deviceDefaultsProvider` exists to give the device row its own answer.
- **Switching the source keeps the snapshot it switched away from.** Choosing the
  account is not a request to delete the filters you saved, and a user toggling
  between them must not pay for it twice.
- `SearchQuery.withColor` earns its keep again: a snapshot saved with *no* colour
  has to be able to clear one, and `copyWith` reads a null colour as "leave it
  alone". Without it an adopted default would be unable to turn the swatch off,
  and the Drift adapter would have to be careful too — which is why saving a
  colourless snapshot **deletes** `device.color` rather than upserting it.
- **A stored key with no stored defaults backfills, once.** The sync runs inside
  `SaveApiKey`, so it only ever fires on a *save*; every user upgrading with a key
  already in place would have been handed a feature that does nothing until they
  happened to re-paste a working key. A successful backfill writes the rows it
  exists to look for, so every later load costs nothing. A failure writes nothing
  and answers null — browse opens on tela's own defaults and the next launch may
  try again, because being offline says nothing about an account, exactly as it
  says nothing about a key. It never spends a request without a key: Wallhaven
  would only 401.
- `accountDefaultsProvider` lives in `app/`, not in a feature. Settings *writes*
  it (a save syncs, a forget clears) and browse *reads* it, and features may not
  import each other (CLAUDE.md). They meet at the composition root instead.
- **There is no periodic refresh.** The sync runs once per saved key, from inside
  `SaveApiKey`. An account's defaults change about as often as its password, and
  a poll would spend the 45 req/min budget on a question nobody asked.
- Stored as Wallhaven's own wire literals (`"110"`, `"1M"`), not enum names: they
  are the values' canonical form, they survive a renamed enum constant, and they
  read the same in a `sqlite3` shell as they do in a request. Three KV rows, so
  no migration — the settings table has taken every new setting this way since v1.
  An unreadable row costs the *whole* account (`tryParse` is all-or-nothing):
  half an account's defaults is not a state worth having, and "no account" is
  already a state tela handles — it is where browse starts.
- `Purity`/`Category` grew `tryFromApiName` beside the throwing `fromApiName`,
  and the throwing one is now written in terms of it. A wallpaper with an
  unreadable purity is a bug worth throwing on; an *account* naming a bucket
  Wallhaven added last week and tela does not know yet should cost that bucket
  and not the sync. Same for `TopRange.tryFromApiValue` and
  `CategoryFilter.tryFromApiBits`. An empty list from Wallhaven means "never
  narrowed it" and falls back to tela's default, because the literal translation
  — the `"000"` mask — is a 400. (`PurityFilter` has no `tryFromApiBits`: no
  purity is ever read back from Wallhaven or from disk, so the parse would be
  dead code, and dead code is where a purity gets applied by accident.)

- **A tag chip searches `id:{tagId}`, never `+{name}`.** Wallhaven's `id:` is the
  *exact*-tag operator; `+name` is a fuzzy text match that would quietly return
  wallpapers carrying a **different** tag whose name merely reads the same. The
  device settled that this is not theoretical: the *Wamiqa Gabbi* tag comes back
  with exactly one wallpaper, and a fuzzy match could not have.
- **A `WallpaperLink` is not a query, and that separation is what keeps the
  features apart.** It names only what was followed; the screen showing it is what
  layers on the filters and the resolution. So the *detail* screen never has to
  know what browse's live query is — it pushes a route with a link in it — and
  `features/detail` still imports nothing from `features/browse` (CLAUDE.md).
- **`LinkedListingScreen` lives in `features/browse/`, and it belongs there.** It
  *is* a listing: it reuses `WallpaperGrid` and reads `browseQueryProvider`, and a
  new feature holding it would have had to import both sideways. Detail reaches it
  by route **name** only, so the dependency runs feature → router → feature, which
  is the same shape as every other screen in the app.
- **A followed listing inherits the filters you are browsing under.** Only the
  term and the sorting are the link's. Categories, purity, colour and shape carry
  over — which is what wallhaven.cc itself does when you click a tag, and it is
  also the only reading that does not silently *widen* a filter someone set. The
  cost is real and known: there is no filter sheet on the pushed screen, so a
  listing emptied by an inherited colour filter can only be widened by going back.
  Wave 3's remaining slices are where that sheet grows; this is the moment to
  reconsider if it bites.
- **Purity inherits too, and that is not a hole in the NSFW rules.** The rule is
  that browse *opens* on safe — a phone is the device you unlock on a train — and
  a relaunch or Reset still returns to it. A listing followed mid-session from a
  wallpaper you are already looking at is inside that session, so switching it
  back to safe underneath the user would be the same bug as an adopted default
  doing it (see the `_adopt` decision above).
- **The uploader's screen says "Uploads by this user", and never implies a
  profile.** Wallhaven's API has **no user endpoint** — their uploads, their
  avatar, and their group are all it can ever know — so a screen headed with a
  username and nothing else would be promising something that does not exist. The
  subtitle is load-bearing wording, like the history's "the wallpaper file stays".
- **The uploader is a `TextButton` and the tags are `ActionChip`s, not tapped
  `Text`.** Both carry button semantics and a real touch target; a link only a
  sighted user with a steady thumb can find is not a link. The button's target is
  taller than a line of text, which is what made the uploader sit visibly *below*
  its own label on the device — so the linked metadata row centres where the plain
  rows top-align.
- **`screenResolution` moved to `core/ui`.** Browse and every listing pushed from
  it must answer "how big is this screen" identically, and it was about to become
  a second copy of the same six lines.

- **The selected tab is held by *sorting*, never by index — and that is the whole
  design of the slice.** Relevance appears and vanishes with the search term,
  which renumbers every tab behind it, so a `TabController` that kept its index
  across the change would move a user from Top to Hot the instant they cleared a
  search. `_selected` is a `Sorting`, `_recordSelection` writes it on every tap
  and swipe, and the controller is rebuilt *only* when the tab list itself
  changes — rebuilding every frame would restart the indicator mid-swipe, and
  keeping a stale one when Relevance arrives throws (a `TabController` shorter
  than its `TabBar`). A test pins it: mutating `_recordSelection` to a no-op
  fails "clearing the search keeps the listing you were on" with Top → Latest.
- **Selecting Relevance on submit has two code paths, and only one of them is the
  rebuild.** A *first* search grows the tab list, so the controller is recreated
  and simply opens on Relevance. *Refining* a search that is already running does
  not change the list at all — nothing rebuilds the controller, and the tab has to
  be moved by hand with `animateTo`. Deleting that one line still passes the
  first-search test and fails only the refine one, which is why both exist.
- **`offerableSortings(hasTerm:)` sits beside `offerablePurities`, and is the same
  rule.** An option Wallhaven cannot honour is not offered: NSFW without a key
  401s, and `relevance` with no `q` has nothing to rank against, so it answers
  with an arbitrary listing. A tab that silently means something else is worse
  than a tab that is not there.
- **Each grid is keyed by its `Sorting`.** Relevance appearing shifts every grid
  one place right in the `TabBarView`, and an unkeyed child would inherit the
  paging state of the listing that used to sit in that slot.
- The tab bar is `isScrollable` with `TabAlignment.start`. Seven sortings do not
  fit across a phone, and fixed tabs would shrink to fit and cut their own labels
  off. **The tablet cannot prove this**: at 2560px all seven fit without
  scrolling, so the scrolling itself is still owed on a phone.
- **"Most viewed" and "Most favorited", not "Views" and "Favorites".** The app
  already has a favorites shelf in the same app bar, and a tab reading "Favorites"
  next to it would promise the user's own saved wallpapers rather than
  Wallhaven's most-favorited. These are wire sortings, not the local library.

- **The ratio chips are a union; the colour swatches are a radio. Both match the
  API, and the difference is not a style choice.** Wallhaven's `ratios` genuinely
  unions (`ratios=16x9,9x16` returns both, checked), where its `colors` matches one
  palette bucket at a time. A control that lies about which of those it is produces
  a filter the user cannot predict.
- **The last ratio chip *may* be turned off, unlike the last category or purity.**
  An empty `ratios` is a legitimate request — it is how you ask Wallhaven for every
  shape, and the param is simply omitted — where an empty category mask is a `000`
  that throws. So `toggledChoice`'s refuse-to-empty rule deliberately does not
  apply here, and "Any shape" leads the row for the same reason "Any color" leads
  the palette: a row of chips with nothing selected must not read as "nothing
  chosen yet" when it means "everything".
- **`ExactRatio.ofScreen` takes the *standard spelling* of the shape it reduces
  to.** A 2560x1600 tablet reduces to `8x5`, which Wallhaven honours exactly as it
  honours `16x10` — both answer with ratio 1.6, so this is not the server rejecting
  anything. It is that `offerableRatios` would otherwise offer **both**: two chips,
  one filter, where selecting one leaves the other looking unselected. `==`
  distinguishes them (they are different strings on the wire) and `isSameShapeAs`
  does not, which is the whole reason both exist.
- **`ShapeRatio` is an enum implementing the sealed `RatioChoice`.** Not
  decoration: it makes a `switch` over a ratio exhaustive over *both* keywords, so
  a third one Wallhaven adds later is a compile error at every label rather than a
  chip with a raw wire word (`portrait`) rendered on it. The first cut was a class,
  and it needed a dead fallback branch that did exactly that.
- **`AutomaticResolution` carries no size, and `SearchQuery.forScreen` is what
  answers it.** The domain has no idea how big the screen is — that is precisely
  why `atLeast` used to be imposed by the *widget* — so "Automatic" travels as an
  intention and is turned into a real `atleast` at the one point a `BuildContext`
  can answer the question. It resolves the *default* and never overrules a choice:
  a user who asked for 4K must not have their phone's screen substituted for it. A
  mutation test pins that (deleting the guard fails four tests, two of them widget
  tests).
- **Switching resolution mode seeds with the screen.** Both picked modes need a
  size before they mean anything, and the screen is what Automatic was already
  asking for — so switching mode changes what the user *can* edit without changing
  the listing under them.
- **An unreadable resolution row costs the filter; an unreadable *ratio* costs only
  that ratio.** Deliberately different fail-softs. A ratio list drops the bad entry
  and keeps the rest, like `WallpaperColor.readAll`. A resolution list is
  *exact*: silently dropping one entry leaves a filter asking for a **different**
  set of wallpapers, not a smaller one — so `exact:1920x1080,bogus` reads as no
  filter at all, and browse falls back to Automatic, which is somewhere it is
  always happy to be.
- **Wallhaven's `21x9` is a *family*, not an exact ratio**, and the resolution
  buckets are labelled with Wallhaven's names rather than the mathematically
  reduced ones. Neither `2560x1080` (which is 64x27) nor `3440x1440` (43x18)
  reduces to 21x9, and `ratios=21x9` returns both — along with 2.33, 2.37 *and*
  2.39. So the heading over a bucket is the label that actually **finds** the sizes
  filed under it, which is the only property that matters. A test asserts every
  offered size sits within 3% of its own bucket's heading; a size in the wrong
  bucket would be a chip that filters out the thing sitting next to it.
- **Every dimension placeholder in the ARB is a `String`, never an `int`.** An
  `int` placeholder is rendered through `NumberFormat`, which groups thousands — so
  a 1080x2400 phone read back on screen as **`1,080×2,400`**. A pixel count is a
  label, not a quantity. A widget test caught it, and only because the *ratio*
  labels (9, 20) are all under 1000 and happily hid the bug.
- **`Resolution.tryParse` now sits beside the throwing `Resolution.parse`**, the
  same pairing as `Purity.tryFromApiName` / `fromApiName`. A wallpaper whose size
  tela cannot read is a bug worth throwing on; a *stored filter* that has gone bad
  should cost the filter, not the screen it sits on. (It also removes an
  `avoid_catching_errors` lint the first cut earned by catching `ArgumentError`.)
- **The custom W×H is a dialog, not two fields in the sheet.** A half-typed
  `1920x` is not a resolution, and a filter that re-queried on every keystroke would
  spend the 45 req/min budget on prefixes — the same reason search runs on submit.
  It refuses anything that will not parse, because Wallhaven answers an unparseable
  `resolutions` with an *empty grid* rather than an error: a typo would read as "no
  wallpapers are this size", which is a lie, and an unfixable-looking one.
- **The resolution filter *is* in `BrowseDefaults`, where `atLeast` deliberately
  was not.** The old field came from the screen and was choosable by nobody, so
  there was nothing to save. Now that it is a filter the user sets, a snapshot has
  to carry it — and a saved `AutomaticResolution` still means "fit the screen", so
  a snapshot stays portable between devices. One new `device.resolution` KV row; an
  absent one reads as Automatic, so a device that upgrades browses exactly as it
  did yesterday. No migration, as every setting since v1.

## Verification

- `./tool/tela dart format .`: clean
- `./tool/tela analyze`: clean
- `./tool/tela test`: 356 tests pass

- **Wallhaven's own behaviour is verified by real requests**, not by fixtures and
  not from the docs (which 403 from here). Every claim the two filter slices rest
  on was `curl`ed against the live `/search` on 2026-07-14 and checked by reading
  back the `ratio` and `dimension_x/y` of what came out — not merely the result
  *count*, which proves nothing here, since `ratios=bogus` returns a full page of
  24 like everything else. The findings are at the top of this file.
- The ratio model: both dialects encode, the list unions, "any shape" encodes as
  *no param* rather than an empty one, every offered shape round-trips, a value
  that names nothing reads back as null (the load-bearing one — Wallhaven ignores
  such a value and answers unfiltered), one corrupt ratio costs that ratio and not
  the list, `ofScreen` reduces and then takes the standard spelling of its own
  shape, and `offerableRatios` never offers the device twice
- The resolution model: each mode's params, **never `atleast` and `resolutions`
  together** (a proof, not a check — the type is sealed), an exact filter with no
  sizes refused, each mode round-tripping through storage as its wire literal, a
  row that names nothing reading as null, one unreadable size costing the *whole*
  exact filter, and `forScreen` answering Automatic while leaving a chosen filter
  exactly as it is
- `offerableResolutions`: leads with the shape of the screen and offers the screen
  itself, does not offer it twice when it is standard, **offers no size Wallhaven
  has no wallpapers at** (720x1280 and 1280x720 are absent by name), and every
  offered size really does sit under the heading that finds it
- The browse screen, end to end against a fake: the device's own 9×20 shape is
  offered on a phone viewport, picking a second shape asks for **both** (a
  radio-style toggle fails this — confirmed by mutating `_toggleRatio`), a keyword
  shape sits beside the exact ones, "Any shape" sends no `ratios` at all, the
  resolution filter opens on Automatic and says which screen it is fitting,
  "Exactly" sends `resolutions` and **no** `atleast` with it, and "At least"
  re-queries with the size that was picked
- Both load-bearing resolution rules were **confirmed to fail against deliberately
  mutated code** before the tests were kept: dropping `forScreen`'s guard (so it
  overrules a chosen filter) fails four tests, two of them widget tests; and
  letting an unreadable stored row decay to anything but Automatic fails the
  snapshot test
- The Drift adapter: each resolution filter round-trips, the wire literal is on
  disk (`device.resolution` = `auto`), and **a snapshot saved before the filter
  existed reads as Automatic** — which is the upgrade path every device takes
- **The app-lock, end to end, on hardware** (2026-07-14, Samsung SM-X730): the
  gate raises a real BiometricPrompt (`BiometricService/PreAuthInfo: Package:
  cc.pym.tela` in logcat), a dismissed prompt lists nothing, and the fail-open is
  gone. `FLAG_SECURE` is machine-verified in both directions: `adb exec-out
  screencap` of the private library returns a **black frame** (20 KB against a
  normal 205 KB) and SurfaceFlinger tags every tela layer `secure`, while after
  leaving, screencap is normal again and **zero** secure layers remain
- The app-lock rules: the gate opens on `passed` and on nothing else (including
  `unavailable`), the switch refuses to disable on `lockedOut` — the load-bearing
  one — and allows it on `unavailable`, turning the lock *on* asks for nothing,
  and the switch is withheld entirely when nothing could satisfy it
- The stale-listing regression is pinned by a test that **reads the listing
  before the download**, which is what poisoned the cache; it was confirmed to
  fail against the old code before the fix was restored
- Remove-from-history: the Drift adapter (forgets one row and leaves the others,
  and forgetting a missing row is not an error) and the screen (the dialog, its
  load-bearing "the wallpaper file stays" sentence, cancel keeping the row, and
  confirm dropping only the one long-pressed while the grid refreshes without a
  relaunch)
- The missing-file badge: the native adapter (the call reaches Kotlin, an
  unopenable file reads as gone, and a native error costs the badge rather than
  the screen) and the screen (the badge and its *distinct semantics label* appear
  only for the row whose file is gone, and no badge appears when every file is
  there)
- **Verified on the tablet:** downloads now appear in the history and the private
  library without a relaunch; removing a row works and leaves the file alone; a
  "set again" whose file was deleted from Photos quietly re-fetches from Wallhaven
  and applies, leaving nothing behind (cache holds only `libCachedImageData`)
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
- Account sync: the mapper against a captured `/settings` fixture (plus an
  unknown bucket costing that bucket, an empty list falling back to tela's
  default, an unreadable range costing the range, and — the load-bearing one —
  an account listing every purity still yielding a query at `100`),
  `AccountSettings` (the two fields it applies and the eight it leaves alone,
  including a purity the user chose for this session; `tryParse` round-trip and
  each corrupt shape; member-wise equality), `SyncAccountDefaults` (persists,
  costs exactly one request, stores nothing on a rejected key),
  `LoadAccountDefaults`, the Drift adapter (round trip, the wire literals on
  disk, **never writing a purity row and deleting the one an older build left**,
  re-sync upserting, forget removing every row and touching no other setting, a
  corrupt or half-written account reading as none), `SaveApiKey` (verifies with
  `/settings` and *not* an NSFW search, keeps the defaults it answered with,
  stores nothing on rejection while leaving the previous key's defaults intact),
  `ForgetApiKey` (drops the defaults with the key), and the browse controller
  (opens on the account's, adopts on sync, keeps the search term, and never
  overrides a hand-set filter — while "Reset" now returns to the account's
  defaults rather than tela's)
- `test/features/account_sync_test.dart` is the whole path in one place, which no
  other test can see: saving a key in settings moves the browse query, forgetting
  it moves it back, and a hand-set filter survives both
- The backfill: syncs a key that predates the sync, costs nothing once the
  defaults are there, never spends a request without a key, and answers null
  (rather than throwing, or deleting the key) when the account cannot be reached
  or the key is rejected
- **The account sync is verified on hardware** (2026-07-14, Samsung, debug build,
  installed as an update over the previous one):
  - the backfill fired on first launch and wrote the account's real settings —
    and the `account.purity=111` it wrote *at the time* is what proved the live
    `GET /settings` had genuinely parsed, since tela's own fallback would have
    been `100`. It also proved the bug: that account browses explicit, and so did
    the front page.
  - after `e7db95f`, the same device browses **safe** on launch while still
    opening on the account's categories and Last month
  - the settings table's other rows, the favorites, and the download history all
    survived every upgrade; permissions still `INTERNET`, `SET_WALLPAPER`,
    `USE_BIOMETRIC`, `USE_FINGERPRINT`; no errors in logcat
  - **the device still carries a stale `account.purity` row**, which is inert
    (nothing reads it) and clears itself the next time the key is saved or
    removed. If you ever see one in a database, that is what it is.

- **The app-lock and `FLAG_SECURE` are verified on hardware** (2026-07-14, Samsung
  SM-X730, debug build, on a database created fresh by that day's uninstall):
  - opening the private library with the lock on raises a real BiometricPrompt —
    logcat shows `BiometricService/PreAuthInfo: Package: cc.pym.tela` and the
    Samsung fingerprint UI. `MainActivity` being a `FlutterFragmentActivity` is
    what makes that work, and this is the first time it has been proven.
  - `FLAG_SECURE` is genuinely held: `adb exec-out screencap` of the private
    library returns a **black frame** (20 KB against a normal 205 KB), and
    SurfaceFlinger tags every `cc.pym.tela` layer `secure`.
  - and it is genuinely *released*: after leaving, screencap is normal again and
    **zero** secure layers remain. A leaked flag would have disabled screenshots
    app-wide, which is the failure this check exists for.
  - a dismissed prompt does not list anything.
  - and the device found the **fail-open** described above, which is fixed: the
    gate no longer consults `isAvailable()`, and a locked-out sensor now leaves
    the library shut instead of opening it.
  - **Still owed:** re-confirming the fix by hand — fail the fingerprint ~5 times
    until Android locks the sensor out, then reopen the library and check it
    stays **locked** (before the fix it opened straight up). Also the `_locked()`
    Retry screen: dismissing with the system Back key pops the whole route rather
    than landing there, so use the prompt's own Cancel to reach it.
  - **The device-PIN fallback cannot be tested on this tablet at all**: it has no
    PIN, pattern, or password, and `local_auth` only offers the credential
    fallback when `isDeviceSecure()` is true. Set a screen lock on the device (or
    use one that has one) to exercise it.
- Browse defaults: the model (capture from a query, apply back, the purity and
  the term never captured, a colour cleared that `copyWith` could not, an empty
  ratio list surviving as "any shape", every corrupt shape, element-wise
  equality), the Drift adapter (round trip, the wire literals on disk, **never a
  `device.purity` row**, upsert-not-append, the colour row *deleted* rather than
  left behind, an absent source reading as the account, a corrupt one too),
  `ResolveBrowseDefaults` (each source, either source falling back to tela's own
  when it has nothing stored, and — pinned across both — a query that still opens
  on `100`), the browse controller (opens on the device's snapshot, a source
  switch overruling a hand-set filter while a *sync* still may not, a
  session-chosen purity surviving an adopted snapshot, saving switching the source),
  and the screens: Settings renders both sources, withholds the account without a
  key, persists a pick, refreshes from Wallhaven, keeps its defaults when the
  refresh fails, and **summarises each source on its own terms** — plus the filter
  sheet saving a snapshot that browses immediately and carries no purity
- **The browse-defaults switch is verified on hardware** (2026-07-14, Samsung
  SM-X730 / Android 16, debug build, installed as an update):
  - the upgrade wrote **no** `browse.defaults.source` row, and an absent one reads
    as the account — a device that upgrades browses exactly as it did yesterday
  - saving a snapshot, switching sources, and switching back all persist, and the
    live grid follows: the filter sheet moved from the snapshot's Any / Last 24
    hours to the account's Portrait / Last month on the switch alone
  - the device found the summary bug above, which is now fixed and re-verified:
    the two rows render "Last month · Portrait" and "Last 24 hours · Any"
  - switching away from the device keeps its snapshot on disk

- Following a link: the model (`id:{n}` and `@user`, and each link equal only to
  another link to the same thing), the listing screen (a tag searches its id, an
  uploader searches their name, the screen says which kind it is, newest first,
  fitted to the screen it opened on, and — the load-bearing one — the browsing
  filters carrying over into it), and the whole path through the **real router**
  in `test/features/follow_wallpaper_links_test.dart`: a tag chip and the uploader
  each open their listing, Back returns to the wallpaper, and the browse query is
  still termless underneath
- **Following a link is verified on hardware** (2026-07-14, Samsung SM-X730,
  debug build, installed as an update with `adb install -r` so the database and
  the key survived):
  - the *Wamiqa Gabbi* tag returns **exactly one** wallpaper — the one it was
    followed from. That is the proof `id:{tagId}` reaches Wallhaven *and* matches
    exactly; a fuzzy `+name` would have returned a pile of loosely related
    actresses, and no fixture could tell the two apart
  - `@ranvijay` returns that uploader's uploads and stops, so the uploader
    operator is bounded and real
  - Back walks listing → wallpaper → browse with the tabs, the scroll position and
    the search field untouched — the listing really is pushed, not applied
  - no Flutter errors in logcat
  - and the device found the misaligned uploader link, which is fixed and
    re-confirmed on it

- Every sorting reachable: `offerableSortings` (relevance withheld without a term
  and leading with one, and — the one that would have caught the whole gap —
  every member of `Sorting` being offered by *something*, since a sorting nothing
  offers is a listing nobody can reach), and the browse screen, which asserts on
  the **selected tab's own label** rather than an index, because the index is
  exactly what the screen must not rely on: Most viewed and Most favorited each
  re-query with their sorting, relevance is absent until a term is set, a submit
  lands on it, *refining* a search returns to it, and clearing a search from Top
  leaves you on Top (rather than Hot) and from Relevance falls back to Latest.
  Both regressions were confirmed to fail against a deliberately mutated screen
  before the tests were kept
- **Every sorting reachable is verified on hardware** (2026-07-14, Samsung
  SM-X730, debug build, installed as an update):
  - Most viewed and Most favorited return real and *distinct* grids from
    Wallhaven. That is the part no fake could ever show: `FakeWallhavenApi`
    proves tela **builds** `sorting=views`, not that Wallhaven **honours** it,
    and neither param had ever been sent to the real server
  - searching "sunset" from the Most viewed tab moved the user to Relevance and
    came back genuinely sunset-ranked — so `sorting=relevance` is live too
  - clearing the search from Top left them on **Top**, not Hot: the tab list
    shrank by one under a selection held by sorting rather than by index
  - all seven tabs fit the tablet's 2560px bar, so the *scrolling* of the
    scrollable bar is still owed on a phone. No Flutter errors in logcat

The Random tab's deep paging is the one Wave 1 behaviour never exercised on
hardware — see below.

## Start of next session

### 1. Put Wave 3's two filters on a phone — *the contract half is now closed*

**Superseded in part, 2026-07-16 (`7510500`).** Items 1 and 2 below asked whether
the params *reach Wallhaven*, and that is answered — by a wire-level test plus
`curl` of the exact URIs it emits, without a device. See "SOLVED — Wave 3's
exit". **Wave 3's exit criterion is met and it is no longer the next work.**

Items 3 and 4 are untouched and still want a real phone: they are **UI** claims,
which no amount of wire proof can reach. They ride along with the rest of the
phone list rather than justifying a trip of their own.

1. ~~**A `ratios=9x20` request, sent by tela and answered by Wallhaven.**~~
   **Proven** — pinned below Dio's serialization and curled live. Still worth a
   glance if the sheet is open anyway: tap the "· your screen" chip and confirm
   the grid comes back full rather than empty. Note that on an unusual phone an
   *honest* near-empty grid is possible (9x21 has only 80 wallpapers on the whole
   site) — a sparse grid and a broken filter look alike.
2. ~~**The Exactly mode against the real server.**~~ **Proven** — `resolutions`
   travels, and never beside `atleast`. The device-side question that remains is
   only how it *reads*: 1080x2400 had ~66 wallpapers on 2026-07-14, so expect
   short-but-not-empty, and that is the filter working, not failing.
3. **The sheet's height, one-handed.** The ratio group added ~15 chips and the
   resolution group a mode switch plus several ladders, on top of a palette that
   was already 29 swatches. **The filter sheet is now by far the tallest thing in
   the app**, and nobody has scrolled it on a real phone. The pinned apply bar is
   what makes it survivable, and that claim is under much more strain than when it
   was written.
4. **The custom W×H dialog**, which has never been typed into on a device.

**This is one trip with the rest of the phone list** — the palette, the launch
grid, and the seven-tab scrolling bar all need an actual phone too.

PLAN's old Wave 3 (crop/reposition, daily auto-rotate, collections, share sheet,
Omarchy sync) is now **Wave 4**.

### What the search box already does, and does not tell anyone

Asked and answered on 2026-07-14, and worth writing down because the answer is
not what the screen suggests. **There is no tag filter you can type into.** The
filter sheet is chips and dropdowns end to end — categories, purity, ratio,
colour, order, toplist range — and has no text input at all.

But the search field passes its string to Wallhaven's `q` **completely
untouched**, so every operator Wallhaven has already works if you happen to know
it and type it by hand: `+tag`, `-tag`, `id:123`, `@username`, `like:{id}`,
`type:png`. Nothing in the app says so, and nothing builds one for you — **except
the new tag chips, which are the first thing in tela that constructs an operator
(`id:{tagId}`) on the user's behalf.** So a proper `+tag` / `-tag` filter is a
feature tela can already *express* and does not *offer*; the machinery is now
there for whoever wants to build the UI. It is not one of Wave 3's four slices.

Three things were deliberately left out rather than forgotten:

- **`/settings` is synced, but nothing pushes back.** tela never writes the
  account's settings, and Wallhaven's API has no endpoint for it anyway (confirmed
  again this session) — so a filter changed in tela stays in tela, and "Save as
  default" saves it *here*. That is the honest direction of the arrow, and worth
  saying out loud before someone reads "sync" as two-way.
- ~~The history has **no way to remove an entry**.~~ **Built, 2026-07-14.**
  Long-press a history tile → "Remove from history?". `DownloadHistory.forget`
  drops the row and **does not touch the file** — the history is an index, not a
  folder, and the file lives in the gallery or under the user's own SAF tree,
  where Photos and every file manager can already delete it. The danger this
  entry named is real and is answered in the *wording*, not the code: a history
  tile looks exactly like a file, so the confirmation says in plain words that
  the wallpaper stays where it was downloaded, and the button is "Remove", never
  "Delete". A widget test pins that sentence.
- **Only `color` got a `withColor`, and `atLeast` no longer needs one.** The
  `copyWith`-cannot-clear hole was called out here for `atLeast` and `seed`; the
  resolution slice (`1c90b86`) retired it for the first by making the field a
  **non-nullable** `ResolutionFilter` — there is no cleared state left to be unable
  to express, which is a better answer than a second escape-hatch method. `seed`
  still has the hole and is still never cleared. Whoever needs to clear it first
  will find the trap, and should consider doing what the resolution filter did
  rather than what the colour filter did.

### 2. Owed on the device

**Most of Wave 2 is now verified on hardware** (see Verification) — the app-lock,
`FLAG_SECURE`, the private library against real files, downloads in all the
listings, remove-from-history, and "set again" including the re-fetch fallback.
What follows is what the tablet could *not* settle.

**Neither Wave 3 filter has run on hardware.** The ratio and resolution filters
(`7f41d13`, `1c90b86`) are the newest and largest gap: tela has never *sent* a
`ratios=9x20` or a `resolutions=` to the real server, only to a fake. Wallhaven's
side of both contracts is proven by real requests (see the top of this file), which
is the opposite of the usual gap and worth being precise about. The full check list
is in "Start of next session".

**The device is a Samsung SM-X730 — a tablet, not a phone.** Everything on this
list works there, but four claims it cannot settle: whether the 29-swatch palette
is usable one-handed, **whether the now much taller filter sheet is** (the ratio
and resolution groups roughly doubled it), how the launch grid reads on a small
screen, and whether the seven-tab sorting bar scrolls sanely — at 2560px every tab
fits at once, so the scrolling that the bar exists for has never actually happened.
All four are still owed on an actual phone. **It also has no screen lock**, which is
why the PIN fallback is untestable on it — and, not coincidentally, why the app-lock
fail-open bit there first.

**One gap the hardware could not close**, and it is not tela's fault: this
account's browse settings (`categories=111`, `toplist_range=1M`) happen to be
*identical to tela's own defaults*, so "the account's defaults were adopted" and
"tela fell back to its own" render the same screen. The `/settings` response was
confirmed by hand with `curl` and the database matches it field for field, so the
sync is verified as faithful — but **browse visibly adopting an account default
that differs from tela's has still never been seen.** To close it: change the
account's Browsing settings on wallhaven.cc (and press *Save Changes* — the form
does not autosave), then hit **Refresh from Wallhaven** in Settings and watch the
summary and the filter sheet move. Note the old canary is gone: `account.purity`
used to prove a live parse, since tela's fallback (`100`) differed from what the
account said — with purity no longer synced, a failed parse and an all-defaults
account are indistinguishable from the rows alone.

Everything else in Wave 2 has still never run on hardware. In rough order of what
would actually bite:

- ~~**The app-lock, end to end.**~~ **Done, and it found the fail-open** (see
  Verification, and the decisions above). `MainActivity` being a
  `FlutterFragmentActivity` is proven by a real prompt.
- ~~**`FLAG_SECURE`.**~~ **Done**, and machine-verified in both directions — held
  in the library, released on the way out. Only the *app-switcher card* was never
  eyeballed; the screencap evidence makes it a formality.
- ~~**The private library against real files.**~~ **Done.** Explicit downloads
  landed in `filesDir/wallpapers`, listed, deleted cleanly, and never appeared in
  Photos. (They did not list *until a relaunch* at first — that was the stale
  listing, now fixed.)
- ~~**"Set again", from the gallery tier, including after the file is gone.**~~
  **Done.** A `content://` MediaStore read applies, and a file deleted from Photos
  quietly re-fetches from Wallhaven and applies, leaving no temp file behind.
  **Still owed: the SAF (`filesOutsideGallery`) tier**, which has never been used
  on this device at all — no SAF tree has ever been granted. A MediaStore URI and
  a SAF document URI fail differently when they fail, and only the first has been
  seen.
- **The device-PIN fallback, on a device that has a PIN.** This tablet has three
  fingerprints enrolled and **no screen lock**, and `local_auth` only offers the
  credential fallback when `isDeviceSecure()` is true — so the PIN path cannot be
  exercised here at all. It is also *why* the fail-open bit: the sensor was the
  device's only credential, so a lockout left nothing to ask with. Set a screen
  lock (or use another device) to close this.
- **The missing-file badge, on hardware.** Built and unit-tested, but the device's
  history is empty now, so the badge has never been seen on a real row. Download
  to Gallery, delete the file from Photos, reopen the history: the tile must dim
  and take a cloud-download badge.
- ~~**The v2→v3 migration on the real database.**~~ **Written off, and it cannot
  come back on this device.** A `./tool/tela install` on 2026-07-14 uninstalled
  the app and took the accumulated database and the API key with it (see the
  decision above), so the device is now **v3-native**: it created a fresh v3
  database on first launch and migrated nothing. The hand-built v1→v2→v3 tests
  still pass, so the migration path is covered — what is given up is the
  on-hardware confirmation against a database that had really been accumulating,
  and there is no way to re-earn it short of rebuilding a v2 state by hand. A
  device that upgrades from a shipped v2 build has therefore still never been
  seen. **Re-paste the API key before anything else on this list.**
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
