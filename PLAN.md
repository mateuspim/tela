# tela — PLAN.md

> A nice, beautiful, dead-simple **Android** app to browse Wallhaven, preview a wallpaper, and set it as your background in a couple of taps. The wallpaper-browsing half of Aether, reborn on the phone.

**Status:** locked. Decisions in §4 are settled; this drives the scaffold.

---

## 1. Context & inspiration

On desktop (Omarchy), [Aether](https://github.com/bjarneo/aether) is a GTK4/Go theming app that does a lot — color extraction, palette generation, template theming, image editing — and includes a **Wallhaven browser** to search and download wallpapers.

`tela` keeps *only that browsing loop* and moves it to the phone:

**find a wallpaper → preview it → set it as the Android background.**

No color extraction, no theming engine, no image editor. Those stay on the desktop. The phone job is: "I saw a nice wall — let me try it on my screen right now."

---

## 2. Scope

**In scope (the reason it exists)**
- Browse Wallhaven: latest / toplist / hot / random.
- Search by query + core filters (categories, purity, sorting, order).
- Wallpaper detail: full-res preview (pinch-zoom) + metadata (resolution, tags, colors, source).
- **Set as wallpaper** → home / lock / both.
- Download, with three-tier storage routing (§8).
- API-key support → NSFW + personal Wallhaven browsing settings.
- Favorites (local).

**Out of scope**
- Color extraction / theme generation (Aether's job, stays on desktop).
- Image editing / filters.
- Animated / video wallpapers.
- Any backend, account system, or cloud of our own.
- **iOS.** There is no public API to set a wallpaper on iOS; an iOS build could only save-to-Photos, a fundamentally weaker experience. Android-only is the honest choice.

---

## 3. Product name

`tela` (pt: "screen / canvas") — your wall is painted on the *tela*. Keeps the Portuguese/Latin-rooted convention alongside `luma` / `volta` / `focal` / `pauta`. Package/app id e.g. `cc.pym.tela`.

---

## 4. Decisions locked

| Area | Decision | Rationale |
|---|---|---|
| Framework | **Flutter** (Dart) | You already ship Flutter → more polish iterations; UX ceiling gaps are mitigable (see §5.1) |
| Platform | Android only | wallpaper-setting is the core feature; iOS can't do it |
| NSFW / API key | **In the MVP** (Wave 1) | you want it from the start |
| Download storage | **Three tiers, configurable per purity**, with per-download override (§8) | fits your desktop-sync workflow + privacy |
| Desktop sync | Wave 4 | **built as a LocalSend beam**, not an Aether config export — see §12 |
| Language | English UI, **i18n-ready day 1** | more locales later = translation file, not refactor |

## 5. Stack

### 5.1 Framework — why Flutter (UX summary)

Flutter wins **velocity** (you know it → more real polish passes), **motion** (hero transitions, pinch-zoom nearly free), and **custom look**. Kotlin/Compose would win two surfaces: native `WallpaperManager` control and Material-You-from-your-wallpaper theming. Both gaps are mitigable — `dynamic_color` reads the system Monet palette on Android 12+, and the wallpaper apply sits behind our own interface with a platform-channel fallback for stubborn OEMs. For a solo app you want beautiful *and* enjoyable to build, realized polish beats theoretical ceiling.

### 5.2 Libraries

| Concern | Choice | Notes |
|---|---|---|
| UI | Flutter + Material 3 | `dynamic_color` for Monet (Wave 2) |
| State / DI | **Riverpod** | constructor/provider injection, matches our DI rule |
| Routing | **go_router** | typed routes |
| Networking | **Dio** | behind our `WallhavenApi` port |
| Images | **cached_network_image** | always `cacheWidth`/`ResizeImage` on decode |
| Pagination | **infinite_scroll_pagination** | infinite grid |
| Local DB | **Drift** | typed SQL; fits your SQLite comfort (cesta/pauta) |
| Secrets | **flutter_secure_storage** | API key at rest |
| Set wallpaper | **Native Android method channel** | direct `WallpaperManager`, behind our `WallpaperApplier` port |

### 5.3 Platform targets
- `minSdk 29` (Android 10). Chosen over 26 so scoped storage is *always* available: below API 29 both `sharedGallery` and `filesOutsideGallery` need `WRITE_EXTERNAL_STORAGE` and a runtime grant, which would mean a second legacy write path inside the one adapter that enforces the NSFW non-indexing rule. One path, no permission prompt, ~90% device reach.
- `targetSdk` latest (35/36).
- Permissions: `INTERNET`, `SET_WALLPAPER` (normal, auto-granted). Scoped MediaStore covers every supported API → **no storage permission at all**.

---

## 6. Architecture

Feature-first, Clean layering, ports/adapters. `domain/` is pure Dart with **zero Flutter/plugin imports** (fully unit-testable). Mirrors `CLAUDE.md`.

```
lib/
├── main.dart
├── app/                  # App widget, router, theme, Riverpod root
├── core/
│   ├── network/          # Dio client, api-key + rate-limit interceptors, error mapping
│   ├── storage/          # three-tier storage adapters (§8)
│   ├── i18n/             # generated l10n
│   └── ui/               # design system: colors, type, spacing, shared widgets
├── domain/               # models, repository interfaces (ports), use cases — pure Dart
├── data/                 # DTOs, mappers, repo impls, Drift, plugin adapters
└── features/
    ├── browse/  search/  detail/  favorites/  settings/
```

**Ports (interfaces owned by us):** `WallhavenApi`, `WallpaperApplier`, `ImageStore`, `SecretStore`, `FavoritesRepository`, `SettingsRepository`. Third-party packages live only in their adapter; swapping one touches one file.

**Use cases:** `SearchWallpapers`, `GetWallpaperDetail`, `DownloadWallpaper`, `ApplyWallpaper`, `ToggleFavorite`, `SaveApiKey`, `GetSettings`.

---

## 7. Wallhaven API integration

Base `https://wallhaven.cc/api/v1` · **45 req/min** (429 on exceed) · SFW needs no key.

### 7.1 Endpoints

| Purpose | Endpoint | Notes |
|---|---|---|
| Search / listings | `GET /search` | workhorse; all filters are query params; 24/page |
| Wallpaper detail | `GET /w/{id}` | full metadata, `path` (full-res), `thumbs`; NSFW needs key |
| Tag info | `GET /tag/{id}` | tag chips (optional) |
| User settings | `GET /settings?apikey=` | Wave 2 — pull user default purity/categories/resolutions |
| Collections | `GET /collections?apikey=`, `/collections/{user}/{id}` | Wave 3 |

### 7.2 Search params we expose

| Param | Values | UI |
|---|---|---|
| `q` | text; `+tag` `-tag` `id:123` `like:{id}` `@user` `type:png` | search bar |
| `categories` | 3-bit e.g. `111` (general/anime/people) | toggles |
| `purity` | `100`/`110`/`111` (sfw/sketchy/nsfw); **nsfw needs key** | toggles (nsfw hidden until key set) |
| `sorting` | `date_added`,`relevance`,`random`,`views`,`favorites`,`toplist`,`hot` | tabs + sort |
| `order` | `desc`,`asc` | sort menu |
| `topRange` | `1d…1y` (only when `sorting=toplist`) | shown for toplist |
| `atleast` | e.g. `1080x1920` | **auto-default to device screen** |
| `ratios` | e.g. `9x16` | default portrait |
| `colors` | hex from fixed palette | Wave 2 |
| `page`, `seed` | pagination; keep `seed` across pages for `random` | handled by paging |

### 7.3 Response fields we map
List/detail wallpaper: `id`, `url`, `resolution`, `dimension_x/y`, `ratio`, `file_size`, `file_type`, `colors[]`, `purity`, `category`, `path`, `thumbs.{small,large,original}`. Detail adds `tags[]`, `uploader`, `source`, `views`, `favorites`. Meta: `current_page`, `last_page`, `per_page`, `total`, `seed`.

### 7.4 Networking rules
- API key travels **only** in `X-API-Key` header (Dio interceptor), never query string, **never logged**.
- Rate safety: throttle + exponential backoff on 429. Coil-style disk caching of thumbs keeps browsing off the JSON budget.
- Error mapping: 401 → "invalid API key"; 429 → auto-retry w/ backoff; network → offline banner.
- DTOs never escape `data/` — map to domain at the boundary.
- Wallhaven ToS: images remain their owners' property; show `source` when present; downloads are personal-use.

---

## 8. Storage — three tiers (first-class feature)

Download destination is **configurable per purity** (SFW and NSFW set independently), with a **per-download override** (long-press the download button).

| Tier | Location | In Photos / cloud? | Reachable by | Survives uninstall |
|---|---|---|---|---|
| `sharedGallery` | MediaStore `Pictures/tela` | yes | system gallery, other apps | yes |
| `filesOutsideGallery` | `.nomedia` dir on shared storage | no | file manager / USB / MTP | yes |
| `appPrivate` | app-internal storage | no | only tela | no |

The middle tier is the **desktop-sync path**: pull walls onto Omarchy over USB/MTP without touching your camera roll or cloud backup.

**Defaults:** SFW → `sharedGallery`, NSFW → `appPrivate`.

**NSFW hard rules (enforced in the storage adapter, not the UI):**
- NSFW files are **never** MediaStore-indexed, in any tier.
- The in-app private-library screen sets `FLAG_SECURE` (no app-switcher thumbnails / screenshots).
- Optional app-lock (biometric/PIN) gates the private library.

> There is no public API to write into Google Photos' own "Locked Folder," so "private" means *tela's* library — which is the right call anyway (full control, nothing leaks).

---

## 9. Local data model

**Drift tables**
- `favorites(id, thumb_url, full_url, resolution, ratio, purity, saved_at)` — render the grid + reopen detail offline without a refetch.
- `downloads(id, wallpaper_id, tier, uri, purity, target, applied_at)` — history + "set again."

**Secure storage:** `apiKey`.

**Settings (Drift KV table, behind `SettingsRepository`):** `sfwStorageTier`, `nsfwStorageTier`, `defaultTarget` (home/lock/both), `defaultPurity`, `autoResolutionFilter`, `appLockEnabled`, `theme`. Not `shared_preferences` — Drift is the locked local store.

No personal data leaves the device; no server. The only secret is the API key — encrypted at rest, never logged. One line in the README covers it.

---

## 10. Core UX flow

1. **Browse** — tabs (Latest · Top · Hot · Random). Justified/staggered grid of `thumbs.small`, infinite scroll. Portrait-first: default `ratios=9x16` + `atleast=<device>` so results already fit the phone.
2. **Search** — top bar → query + filter sheet (categories, purity, sort).
3. **Detail** — tap thumb → hero transition to full preview (`thumbs.large` → `path`), pinch-zoom. Metadata row (resolution, size, tag chips, color swatches). Primary action: **Set wallpaper**.
4. **Set** — sheet: Home / Lock / Both → apply via `WallpaperApplier`. Snackbar confirms.
5. **Download** — routes by purity config; long-press overrides the tier for one image.
6. **Favorites / Settings** — local favorites tab; settings for API key, storage tiers, default target, app-lock, theme.

"Test it there" = steps 3→4 in **≤3 taps** from any grid.

---

## 11. Setting the wallpaper (the crux)

`data/wallpaper/` implements `WallpaperApplier`:
- Download full-res `path` into app-private cache and stream it to Android's
  wallpaper service, keeping the bitmap out of Dart's heap.
- Apply home / lock / both through a Kotlin method channel calling
  `WallpaperManager` directly, behind the domain interface.
- Write home and lock sequentially for `both`, which is more reliable on
  restrictive OEMs than a combined flag.
- Known Android reality: on some restrictive ROMs the apply can briefly recreate the host activity (a flicker) — mitigate with the plugin's sequential home/lock write; document per-device quirks with issue refs.

---

## 12. Roadmap (waves, with exit criteria)

**Wave 0 — Skeleton**
Scaffold, Riverpod root, theme/design system, go_router, Dio + `WallhavenApi` port, browse grid (latest SFW) with infinite scroll.
*Exit:* real Wallhaven thumbs render and scroll smoothly in an infinite grid.

**Wave 1 — Core loop (MVP)** ← the whole point
Detail screen (preview + pinch-zoom + metadata), **apply wallpaper** (home/lock/both), download with **three-tier storage + per-purity config + override**, search + filters (categories, purity, sorting), **API-key support** (secure storage) unlocking NSFW, device-resolution default filter, l10n scaffolding. Storage adapter enforces the NSFW non-indexing rule from day one.
*Exit:* find a wall → preview → set as background in ≤3 taps; entering a key unlocks NSFW; downloads route per config.

**Wave 2 — Personal & polish**
Favorites (Drift), download history + "set again," **private-library screen with `FLAG_SECURE` + app-lock**, `/settings` sync from your Wallhaven account, color/resolution/ratio filters, error/empty/offline states, hero-transition polish, Material You (`dynamic_color`).
*Exit:* app feels like *yours* — favorites persist, your settings apply, private library is locked, offline browsing of cached favorites works.

**Wave 3 — Search & discovery** — *complete; all four slices built and proven against the real server*
The filters Wave 2 named but did not finish, plus the two ways *into* a listing that tela prints on screen and does not let you follow.

- ~~**Resolution filter.**~~ **Built** (`1c90b86`). `atleast` was imposed by the browse screen from the device screen and could not be changed. It is now *Automatic* (the screen you are holding — still the default), *At least*, or *Exactly* (the `resolutions` param, which tela never sent), over buckets grouped by ratio plus a custom W×H. The three modes are a **sealed type**, because Wallhaven's two size params conflict: sent together, `atleast` wins and `resolutions` is silently ignored. Retired `SearchQuery.atLeast`'s `copyWith`-cannot-clear trap on the way past.
- ~~**Ratio filter, expanded.**~~ **Built** (`7f41d13`). `RatioChoice`'s portrait / landscape / any is now a multi-select over Wallhaven's real vocabulary — its `portrait` / `landscape` keywords and its exact ratios — with the device's own reduced ratio offered first. Ratios are a **union** in the API, unlike `colors`, so chips rather than a radio. **Wallhaven accepts an arbitrary `WxH`**, not a fixed vocabulary, so a modern phone can ask for its own 9x20 shape.
- ~~**Every sorting reachable.**~~ **Built and verified on hardware** (`eb2af8a`).
- ~~**Tags and the uploader become links.**~~ **Built and verified on hardware** (`984b546`).

*Exit:* the filter sheet answers everything wallhaven.cc's own filter bar does, and a wallpaper is a place you can navigate *from* — its tags and its uploader lead somewhere. **Met** (`7510500`, 2026-07-16). Both halves of the contract are proven: Wallhaven's side by `curl` (the evidence lives in `ratio_choice.dart` and `resolution_filter.dart`'s docstrings, dated, with the totals), and **tela's side on the wire** — `dio_wallhaven_api_test.dart` fakes Dio's `HttpClientAdapter`, *below* query serialization, and asserts on the literal URI. That seam is the one `FakeWallhavenApi` structurally cannot see: it records a `SearchQuery`, so it sits above the encoding. The two were joined by curling the exact URIs the test captures — a phone's cold-launch URI answers with 2575 wallpapers, all at ratio 0.56, none below the screen.

**Wave 4 — Nice-to-haves** — *share sheet built and verified on hardware*
~~Crop/reposition editor before apply~~ **built, both halves** (see below), ~~daily auto-rotate (WorkManager)~~ **built** (`962ff8d`), ~~collections browser~~ **built** (`ac2909d`), ~~share sheet~~ **built**, ~~Omarchy sync~~ **superseded and built as the beam** (`a4574cd`).

- ~~**Collections browser.**~~ **Built** (`ac2909d`, 2026-08-26). Wallhaven's
  collections API was probed live first, and it constrains the feature: the
  contents endpoint honours **only `purity`** — `categories`, `atleast`,
  `ratios`, `sorting` and `order` are accepted and silently ignored (measured
  against a 447-wallpaper collection; Wallhaven's own reference says the same).
  So a collection listing gets a purity-only control, never the filter sheet.
  A collection's `count` and a page's `total` are also different numbers — one
  reporting 82 answers 0 under the default purity — so the screen says what it
  is withholding rather than rendering an empty grid under a promise of 82.
  The username is a stored setting because neither `/settings` nor the
  authenticated `/collections` returns one, while the contents route is
  addressed by it.
- ~~**Daily auto-rotate.**~~ **Built** (`962ff8d`, 2026-08-26). WorkManager, and
  the work is **entirely native with no Dart alive**: a rotation lists a
  directory, picks a file and calls `WallpaperManager`, none of which needs an
  engine started every fifteen minutes. Candidates are already-downloaded files
  rather than a live search, so the schedule spends no rate ceiling and needs no
  network at whatever hour it fires. The private library is its own source,
  never folded into an "everything" option — a rotation puts its pick where
  anyone glancing at the phone sees it.
- **Omarchy sync is superseded, and the reason is dated.** The plan was to
  export favorites to Aether's `~/.config/aether/favorites.json` and carry it
  over USB. **Omarchy 4.0 "Quattro" shipped 2026-08-14** and rewrote the whole
  desktop shell in Quickshell/QML, with a documented plugin contract and its own
  theme and wallpaper switchers — so a config file written for Aether now aims
  at a target Omarchy has partly absorbed. That export also only ever moved
  *links*: the desktop re-downloads every image, explicit ones included.
- ~~**Omarchy sync.**~~ **Replaced by the beam** (`a4574cd`, 2026-08-26): tela
  sends the actual files over **LocalSend v2.2**. The protocol needs only one
  party to run an HTTP server and that party is the receiver, so tela is a
  sender only — no listening socket — and the whole thing is Dio plus `dart:io`
  with **no new packages**. The one native piece is the Wi-Fi multicast lock,
  without which Android drops the very packets discovery listens for and the
  chooser is silently, permanently empty.
- **The beam is the one deliberate exception to "explicit pixels never leave
  the app", and it did not touch the old rule.** `mayExportBitmap` still refuses
  to hand explicit pixels to another app *on this device*, because that app
  keeps its own wallpaper history — the ungated index the private tier exists to
  prevent. A beam has no such index, so `mayBeamBitmap` sits **beside** it,
  gated on a setting that is false on a fresh install (owner's call,
  2026-08-26). Enforced twice, as every NSFW rule here is: the use case refuses
  before a byte leaves, and the private library withholds the action entirely.
  A mixed batch is refused whole rather than sent minus the explicit files.
- **The desktop half is deliberately out of scope for this repo.** A `tela`
  plugin for Omarchy's Quickshell — presenting what landed, setting it — is a
  real thing to build, but this project is the Android app and Quattro's plugins
  live in `~/.config/omarchy/plugins/`. It wants its own repo.
- **Crop/reposition, the SFW half: built and verified on the SM-X730** (2026-07-17).
  Detail's *Adjust & set* hands the image to Android's own crop-and-set editor —
  on the tablet, Samsung's "Wallpaper and style" picker, opened on the right
  image with the Lock/Home previews and reposition. That editor owns the crop,
  the Home/Lock/Both choice **and** the apply, so tela hears no result back and
  says nothing on success; only failures speak. It is an *optional* branch beside
  the direct apply, which is untouched — Wave 1's "≤3 taps" is a promise about
  that button and this must not tax it.
- **The hand-off is two intents, because the AOSP one is dead on One UI.**
  `WallpaperManager.getCropAndSetWallpaperIntent` pins the intent to the launcher
  and a configured cropper package, and Samsung ships neither — it *threw* on the
  tablet. `SystemWallpaperEditing` tries it first (a clean one-tap cropper on
  stock Android) and falls back to an **`ACTION_ATTACH_DATA` chooser** ("Use
  image as…"), which is what actually reaches the OEM editor. The chooser, not a
  bare launch, so a stale ATTACH_DATA default can't hijack it; the system
  resolver enumerates handlers out-of-process, so no `<queries>` and no API-30
  visibility trap. Cost the owner accepted: WhatsApp/Contacts show beside the
  wallpaper app in the list. Targeting the OEM component directly was tried and
  rejected — it bounced back to the launcher, and picking the wallpaper app by
  heuristic is per-brand-fragile.
- **It is SFW-only, and that is the same rule as the share sheet, not a new one.**
  The intent needs a `content://` URI, so the pixels reach a separate app that
  keeps its own wallpaper history — the ungated index the private tier exists to
  prevent. `mayExportBitmap` is now the one home for "explicit pixels never leave
  the app"; `shareOptionsFor` asks it too, so the two cannot drift. Enforced in
  the domain (`AdjustWallpaper`) and again in the UI that withholds the button.
- **Still owed: our own editor**, for the NSFW/private path and as the fallback
  when no system editor resolves. Decided shape: `BitmapRegionDecoder.decodeRegion`
  → `setBitmap`, which is deterministic where `visibleCropHint` is only a *hint*
  OEMs may reinterpret, and which decodes just the chosen sub-rect and so dodges
  §15's 6K OOM risk. `MainActivity`'s `setStream(..., null, ...)` crop hint stays
  null until then.
- ~~**Share sheet.**~~ **Built and verified on hardware** (2026-07-15). A wallpaper's detail screen shares its public Wallhaven link (any purity) or the image file itself. The image is **refused for explicit content** — the bitmap must not leave the device — the same rule as `StorageSettings.choicesFor`, enforced in `shareOptionsFor` and again in `ShareWallpaper.image`. Native `ACTION_SEND` behind a `WallpaperSharer` port, with a `FileProvider` one-shot grant for the image.
*Exit:* opt-in extras; none block Wave 1/2/3.

---

## 13. Non-functionals
- **Performance:** downsample on decode; disk-cache thumbs; paging with stable keys; const widgets to cut rebuilds.
- **Offline:** cached thumbs + favorites render from Drift; offline banner.
- **Resilience:** 429 backoff, network error mapping, retry affordances.
- **Theme/a11y:** Material 3, dynamic color (Wave 2), semantics labels on images, dynamic type.
- **Secrets:** API key encrypted, header-only, never logged; NSFW paths never logged.

## 14. Testing (TDD)
- Single command: `flutter test`.
- Domain use cases: pure-Dart unit tests. Mappers: against captured Wallhaven JSON fixtures.
- External I/O mocked with named fakes (`FakeWallhavenApi`, `FakeWallpaperApplier`, `FakeImageStore`).
- One widget test for browse → detail → set happy path.
- F.I.R.S.T; every new function tested; bug fixes get a regression test.

## 15. Risks

| Risk | Mitigation |
|---|---|
| 45/min rate limit | cache thumbs; throttle + backoff on JSON |
| OOM on 6K images | downsample on decode, cap to display size |
| OEM apply quirks / flicker | native sequential home/lock writes; test on your device early |
| NSFW leakage | non-indexing enforced in storage adapter; `FLAG_SECURE`; app-lock |
| Wallhaven API changes w/o notice (ToS says so) | isolate in `data/`, fixture-tested mappers, fail soft |
| Material You not byte-identical to native | acceptable; `dynamic_color` covers the palette loop |

## 16. Next step
Scaffold the Flutter project against §6 with `analysis_options.yaml` (strict-casts/inference/raw-types + lints) and the `CLAUDE.md` conventions, wire the `WallhavenApi` port + browse grid (Wave 0), then Wave 1.

---

## 17. Multi-source browsing (Wallhaven + others)

**Status:** designed, not built. Drafted 2026-07-24.

**The goal.** Wallhaven stops being *the* backend and becomes *a* backend, so an
anime-only booru (Konachan is the first candidate) — or anything else — can be
added as one adapter plus one registry entry, without a feature file learning
its name.

### 17.1 Shape of the thing

**One active source at a time.** A switcher in browse; switching resets the
query, because filters are not portable between sources. The *library* side —
favorites, download history, private library — stays unified and renders items
from any source side by side.

Rejected: merging/interleaving results into one grid. It needs a cross-source
pager, dedup, per-source rate-limit budgeting, and a merge order with no honest
meaning ("newest" across two sites that disagree about time). Revisit only if
switching proves annoying in the hand.

**Capabilities, not lowest-common-denominator.** Each adapter declares a
`SourceCapabilities`, and the filter sheet *renders from it* — Konachan simply
has no category selector. The failure mode being designed out is the obvious
alternative: accepting a filter the source can't honour and silently dropping
it, which looks to the user like the app ignoring them.

Also rejected: a sealed query type per source. Type-safe, but every browse
widget would have to switch on the source. Not worth it for two sources.

### 17.2 What each source must supply

| Concern | Contract |
|---|---|
| Identity | a `SourceId`; every `Wallpaper` carries it |
| Listing | search → a page of `Wallpaper`, given the common `SearchQuery` |
| Detail | full metadata for one id |
| Permalink | the public page URL for one id — **each source knows its own** |
| Safety mapping | its rating vocabulary → `Purity`, **failing closed** (§17.4) |
| Capabilities | which filters, sortings and credentials it actually supports |
| Rate limit | its own ceiling; the interceptor stops hardcoding Wallhaven's 45/min |

### 17.3 The couplings that have to be cut

Found by reading the tree, 2026-07-24. The `WallhavenApi` port itself is *not*
one of them — it is a 3-method domain port imported by 7 files, which is the
seam working as designed. These are the leaks around it.

1. **Identity is not source-qualified.** `Wallpaper.id` is a bare string and
   both Drift tables primary-key on it alone (`WallpaperColumns.primaryKey`).
   Wallhaven ids are base36 (`e7jvjd`) and booru ids are numeric, so nothing
   collides *today* — but Konachan #12345 and yande.re #12345 collide the day
   there are two boorus, and a favorites row would silently overwrite another
   site's wallpaper. Same bare id in `wallpaper_gallery_session.dart`'s
   `itemKey`.
   → `SourceId` + `WallpaperRef(source, id)`; a `source` column on both tables;
   composite PK; **schema v6** backfilling existing rows with `'wallhaven'`.
   `wallpaperFileName` already emits `wallhaven-<id>`, so that prefix becomes
   the source id for free and downloaded files keep their names.

2. **The domain encodes Wallhaven's wire format.** `SearchQuery.toQueryParameters()`
   builds Wallhaven's URL params; `Purity.toApiBits()` and
   `Category.toApiBits()` build its 3-bit masks. That is `data/`'s work sitting
   in `domain/`. It leaks further than it looks: `wallpaperListingIdentity()` —
   a *feature* function — uses the encoded query string as a shelf cache key,
   so a UI file transitively depends on Wallhaven's URL shape.
   → encoders move to `data/<source>/`; `SearchQuery` grows a source-agnostic
   stable `key` for the shelf identity.

3. **`Wallpaper.pageUrl` hardcodes `https://wallhaven.cc/w/$id`.** Used by
   share and the detail metadata screen.
   → the mapper supplies the permalink; the model stops knowing a domain name.

4. **`Category` does not generalize.** Konachan has no general/anime/people
   axis. (`Purity` *does* generalize — it is very nearly isomorphic to booru
   safe/questionable/explicit, which is lucky and load-bearing; see §17.4.)
   → `Wallpaper.category` becomes nullable, and the taxonomy text and filter
   sheet omit it when absent. Chosen over moving it to a per-source extras bag
   (cleaner domain, much wider diff) and over having Konachan assert
   `Category.anime` for everything (zero refactor, but the adapter would be
   claiming something the API never said — and it breaks on the first booru
   that isn't anime-exclusive).

5. **`WallpaperPage.lastPage` is required**, and `hasMore` is derived from it.
   The Moebooru family returns a bare JSON array with no page-count metadata:
   you learn you are at the end by receiving a short page. **Confirmed live**
   2026-07-24 — see §18.1.
   → `hasMore` becomes the stored primitive; `lastPage` becomes the optional
   extra that sources with a page count can still provide.

6. **`SearchWallpapers` hardcodes Wallhaven's key rule.** `_guardNsfwRequiresKey`
   refuses any NSFW query when no API key is stored — but Konachan serves
   explicit content anonymously (verified §18.1), so on a keyless source that
   guard would refuse a request the source would happily answer.
   → the guard reads the active source's capabilities instead of assuming.

7. **Detail models assume Wallhaven's field set.** `WallpaperDetails` requires
   `views` and `favorites`; `WallpaperTag` requires a numeric `id`. Konachan has
   no view count, and its tag ids need a second request (§18.4).
   → `views`, `favorites` and `WallpaperTag.id` become optional; the metadata
   screen renders what exists rather than a zero.

Smaller, all mechanical: `WallhavenFailure` → `SourceFailure` (a rename across
21 files); `SecretStore` goes from "the one secret" to per-source credentials;
the rate-limit interceptor takes its ceiling from the source. The tag blocklist
keys on Wallhaven's numeric tag id, which boorus have no equivalent for — but
it already *excludes* by name (Wallhaven's `-id:` exclude does not work), so
name-based blocking per source is close to what already happens.

### 17.4 The NSFW invariant, restated for many sources

CLAUDE.md's NSFW rules key on `Purity.nsfw`, and they must hold identically no
matter which site an image came from. That puts a hard requirement on every new
adapter: **an unrecognised rating maps to `Purity.nsfw`**, never to `sfw`. Same
fail-closed reasoning as `storedPurity` — over-protected is survivable,
under-protected means MediaStore-indexing an explicit image.

Two source-specific traps to check per adapter: a site whose ratings are
*coarser* than three levels must map conservatively (a two-level safe/unsafe
vocabulary sends "unsafe" to `nsfw`, not `sketchy`), and Konachan in particular
serves different content per hostname — `konachan.net` is SFW-only,
`konachan.com` is not.

### 17.5 Stages

Each stage ends green on `make ci` and is mergeable alone.

1. ~~**Identity and encoding.**~~ **Built** (`7b10ec2`, `ae5cc7a`, `1285154`,
   `76034cf`, 2026-07-24). §17.3 items 1–7 plus the renames. **No user-visible
   change at all** — verified by the suites passing essentially unchanged
   (Dart 944 green through the four commits). Note where the plan was refined
   in the building: `SearchQuery` grew a `key` (not the encoded string) for
   the shelf identity; the bit masks split into a *storage* codec
   (`stored_bits.dart`) kept in `domain/` and a *wire* encoder
   (`data/wallhaven/wallhaven_query.dart`), because a row on disk must keep
   reading forever whatever a source's API does. Schema v6 also backfills
   `page_url`, since the model stopped composing the permalink.
2. ~~**Registry and switcher.**~~ **Built** (`605a86f`, 2026-07-24).
   `wallpaper_sources.dart` is the registry; the active source is a Drift
   setting; the filter sheet renders from `SourceCapabilities`;
   `SearchWallpapers` reads the source's key rule instead of assuming.
   `FakeWallpaperSource` with `narrowCapabilities` proves the seam. **Owed on a
   device:** the v6 migration on a real accumulated database, and watching the
   sheet re-render on a switch — both wait for a second real source.
3. ~~**Konachan adapter.**~~ **Built** (`ffb2e95`, 2026-07-24). The first real
   second source — designed in §18, whose paging, rating and operator behaviour
   was **verified live on 2026-07-24** before any of it was planned against.
   `data/konachan/` holds the query encoder, the mapper and the adapter;
   `SourceId.konachan` and one registry entry wire it in. `make ci` green (Dart
   1007). **Owed on a device:** the §18.6 walk — the NSFW invariant on the new
   source, and observing `.net` actually serve safe mode — plus the v6 migration
   and the filter sheet re-rendering on a switch that stages 1–2 also owe.
4. **Cross-source polish — built.** The active source is visibly named in its
   selector; browse tabs and filter controls render from capabilities; and
   detail, share, and failure copy are source-aware. Per-source rate limits were
   already in the adapters. **Source badges** now name each tile's source on the
   library grids that can hold more than one (Favorites, Download History, the
   recent-downloads strip) — a bottom-left pill read from a root-level
   `WallpaperSourceLabelsScope`, off on the single-source browse wall. The
   The **private library** is badged too, since 2026-07-26 — and getting
   there turned up a real bug rather than a UI gap. `ImageStorage.fileName`
   hardcoded a `wallhaven-` prefix, so every Konachan download was named
   for Wallhaven **in all three tiers**; and because the app-private tier
   writes no history row, that name is the only record of a private
   image's source. `store()` now takes the source beside the id,
   `PrivateImage` carries a whole `WallpaperRef`, and `deletePrivate`
   keys on `source-id` so two sources' identical ids cannot delete each
   other's file. No migration: pre-existing files are all Wallhaven's and
   already carry that prefix.
5. **Jump to a wallpaper by its id — built** (`feat/id-jump`, 2026-07-26).
   Typing an id into the browse search box offers a chip that opens it; Enter
   still runs an ordinary text search, so a real six-character search term is
   never intercepted. `WallpaperSource.wallpaperIdIn` makes id shape the
   source's own business — it returns the **normalized** id rather than a bool,
   because Wallhaven's API is case-sensitive and a phone auto-capitalizes what
   you type. `NotFoundFailure` joins the sealed `SourceFailure` so a mistyped id
   names itself instead of reading as a malfunction. **Owed on a device:** see
   HANDOFF, which also records the measured Wallhaven id alphabet.

*Exit:* two sources browsable, one at a time; a wallpaper from either can be
favorited, downloaded, applied and deleted; no NSFW rule weakened by the second
source's arrival.

---

## 18. Konachan — the second source

**Status:** **built** (`ffb2e95`, 2026-07-24), with the first device-walk
software gaps fixed in the working tree; full device verification is still
owed.
Implements §17 stage 3. API behaviour below was **probed live on 2026-07-24**,
not read from documentation — Moebooru forks differ from each other and from
their docs, and this project's standing rule is that query operators get
confirmed against the live service. The build followed this design closely; two
refinements worth noting are recorded where they land (the `.net`-returns-`[]`
detail trap is handled by always querying `.com`; `ExactResolutions` is dropped
rather than mis-encoded, since Konachan has no exact-size list).

Konachan is Moebooru: `GET /post.json`, no versioned API root, no OpenAPI, and
a query language that lives entirely inside the `tags` parameter.

### 18.1 What was verified live

| Question | Answer (2026-07-24) |
|---|---|
| Response shape | a **bare JSON array** of posts — no `meta`, no page count |
| End of results | `page=99999` → `[]`; a short page means the end |
| Page size | `limit=500` returned 500; default is 40ish |
| Default order | `id` descending, i.e. newest first |
| Auth | **none needed** — explicit content served anonymously |
| Single post | there is **no `/post/{id}.json`**; `tags=id:406484` returns exactly 1 |
| Rate-limit headers | none exposed; Cloudflare-fronted |

### 18.2 `.net` and `.com` are ONE source, not two

This is the finding that shapes everything else. **The two hosts share one post
database and one id space** — post `406484` is the same wallpaper on both. `.net`
is a server-enforced `rating:s` view of `.com`.

Verified: of the newest 100 posts, `.com` returned 51 safe / 38 questionable /
11 explicit while `.net` returned **500 of 500 safe** over a larger sample; and
`.net` cannot be talked out of it — `tags=rating:e` → `[]`, `tags=rating:q` →
`[]`, and even a direct `tags=id:406483` lookup of a known questionable post →
`[]`.

So:

- **One `SourceId`: `konachan`.** Not two. A `WallpaperRef('konachan', '406484')`
  is stable no matter which host answered, so a favorite made in safe mode is
  the same row as the one made in unrestricted mode.
- **The host is chosen per request from the query's purity filter.** SFW-only →
  `konachan.net`; anything wider → `konachan.com`.
- **This is defence in depth, and it is worth taking.** While the user browses
  SFW-only, explicit content is excluded *by the server*, not by a tag string we
  assembled. A bug in our rating mapping cannot leak an explicit image into a
  safe browse, because `.net` will not serve one at any price.

One consequence to accept: image URLs carry the serving host, so the same
wallpaper cached in both modes occupies two cache entries. Keep the URLs the API
returned rather than rewriting the host — a rewrite would be a second place for
the safe/unrestricted distinction to be got wrong, and the cost is a few
duplicate thumbnails.

**Permalink:** `https://konachan.net/post/show/{id}` for a safe post,
`.com` otherwise — so sharing a safe wallpaper never sends someone to the
NSFW-capable domain. Consistent with `ShareWallpaper.link` already being
allowed at any purity.

### 18.3 Query mapping

Konachan has no `sorting`, `order`, `categories`, `purity`, `width` or `ratio`
parameters. **Everything is a token inside `tags`.**

| tela concept | Konachan encoding | Verified |
|---|---|---|
| `SearchTag` require / exclude | `tag` / `-tag` | ✅ |
| `AtLeastResolution` | `width:>=1920 height:>=1080` | ✅ |
| `ExactRatio(16,9)` | `ratio:16:9` | ✅ |
| `Sorting.dateAdded` | *(nothing — it is the default)* | ✅ |
| `Sorting.views` / `favorites` | `order:score` | ✅ |
| `TagLink` | the tag name itself — booru tags are **exact** | ✅ |
| `UploaderLink` | `user:<name>` | ✅ |
| `WallpaperColor` | **unsupported** — Konachan has no colour data | — |
| `Category` | **unsupported** — no such axis (§17.3 item 4) | — |
| `Sorting.relevance` / `toplist` / `hot` | **unsupported** | — |

**Purity sets need a single term, positive or negative.** Emitting one
`rating:` token per selected purity is the obvious implementation and it is
**silently wrong**: `tags=rating:s rating:q` does not OR, and does not error —
it returned 60 of 60 questionable, i.e. the last token simply won. All seven
non-empty subsets are expressible with one token:

| Purities wanted | Token |
|---|---|
| sfw | `rating:s` *(and prefer the `.net` host)* |
| sketchy | `rating:q` |
| nsfw | `rating:e` |
| sfw + sketchy | `-rating:e` |
| sfw + nsfw | `-rating:q` |
| sketchy + nsfw | `-rating:s` |
| all three | *(no token)* |

Verified: `-rating:e` → 32 safe / 28 questionable, zero explicit; `-rating:q` →
49 safe / 11 explicit, zero questionable.

**Tag spelling differs.** Konachan tags are underscore-joined (`black_hair`),
where Wallhaven wants quoted multi-word names. `SearchTag.token` quotes for
Wallhaven (per the standing note about unquoted names splitting into two
tokens); Konachan's encoder must instead convert spaces to underscores and must
**not** quote. This is exactly why §17 moves the encoder out of the domain
model — one `SearchTag` cannot serialise itself correctly for both.

**`Sorting.random` is a problem: `order:random` works but takes no seed.** Two
consecutive pages of one random listing shared zero items, but nothing pins the
shuffle, so paging can repeat images — the precise bug Wallhaven's `seed` exists
to prevent. **Ship v1 without random for Konachan** (declare it unsupported so
the sort control does not offer it) rather than shipping a sort that quietly
duplicates. Revisit only if there is a way to pin it.

### 18.4 Field mapping

**Rating → `Purity`**, and this is the mapping §17.4's fail-closed rule governs:

```
"s" → Purity.sfw        "q" → Purity.sketchy
"e" → Purity.nsfw       anything else → Purity.nsfw
```

**Images.** Konachan has no cropped thumbnail — every derivative preserves the
aspect ratio, so `thumbSmallUrl`'s doc comment ("cropped by Wallhaven to a fixed
300x200") becomes source-specific and needs rewording.

| tela field | Konachan field |
|---|---|
| `fullImageUrl` | `file_url` |
| `thumbLargeUrl` | `sample_url` (~1500px wide) |
| `thumbOriginalUrl`, `thumbSmallUrl` | `preview_url` (~150px wide) |
| `resolution` | `width`, `height` |
| `fileSizeBytes` | `file_size` |
| `colors` | **none** — empty list |

`preview_url` at ~150px is small for a phone masonry grid; `sample_url` is the
better-looking choice and much heavier. **Which one the grid uses is a
device-verification question, not a desk decision.** The tile itself is safe
either way — it sizes from its box, not from the decoded image (see the standing
note on `WallpaperTile` needing a tight box).

**Detail.** `wallpaperDetails(id)` is implemented as `tags=id:{n}`, since there
is no per-post endpoint. Watch the host rule: on `.net` that lookup returns `[]`
for a questionable or explicit post, which would surface as a mystery empty
detail screen rather than an error.

| tela field | Konachan field |
|---|---|
| `tags` | `tags` — one space-joined **string**, no ids (see below) |
| `uploader.username` | `author` (no group, no avatar → empty strings) |
| `source` | `source` — present, often a pixiv link |
| `fileType` | derived from `file_ext` (`"jpg"` → `image/jpeg`) |
| `ratio` | computed from width/height (Wallhaven sends it as a string) |
| `favorites` | `score` |
| `views` | **absent** → null (§17.3 item 7) |

**Tag ids cost an extra request.** `/tag.json?name=landscape` returns
`{id: 10630, name, count, type}`, but a post's own JSON carries only names. Do
**not** fan out a lookup per tag to populate `WallpaperTag.id` — Konachan tag
names are exact identifiers, so `TagLink` can narrow by name directly and needs
no id at all. Fetch an id only where one is genuinely required (the blocklist
table's key), and only for the tag the user actually blocked.

### 18.5 Client rules

- **Rate limit: 60/min, and be conservative.** Konachan publishes no
  `X-RateLimit-*` headers and sits behind Cloudflare, so there is no signal to
  back off against except failures. §17's per-source ceiling covers this;
  Wallhaven's 45/min stays its own.
- **Send a real `User-Agent`.** Boorus commonly reject default or absent ones,
  and a Cloudflare challenge would arrive as an unparseable HTML body rather
  than a clean failure.
- **No credentials.** Konachan declares `requiresCredentials: false`, which is
  what §17.3 item 6's capability-driven guard exists to read.

### 18.6 What "done" means

Beyond both suites green:

1. A Konachan wallpaper can be browsed, previewed, favorited, downloaded,
   applied, and deleted — the same loop as a Wallhaven one, from the same
   screens.
2. **Filename is `konachan-406484.jpg`**, matching `wallhaven-e7jvjd`'s shape,
   which `wallpaperFileName` already produces once it reads the source id.
3. **The NSFW invariant holds on the new source**, walked by hand on the device:
   an `e`-rated Konachan wallpaper is never MediaStore-indexed in any tier,
   lands in the private library, and is covered by `FLAG_SECURE` and the
   app-lock — exactly as a Wallhaven `nsfw` one is.
4. **Safe mode is served by `.net`**, confirmed by observing the request host,
   not just by observing that results look safe.
5. Switching sources resets the query and the grid, and does not strand paging
   state from the previous source.

The software regression for item 5 is now covered by a widget test that
switches from Wallhaven to Konachan while both have their default query.
Uploader filtering is likewise covered through each source's wire encoder.
Both paths still need their post-fix device re-walk.

*Risks:* Moebooru's `tags` grammar is positional and forgiving — wrong input
returns plausible wrong results instead of an error (the `rating:s rating:q`
trap is one instance already found), so mapper tests need **captured fixtures
plus live spot-checks**, not fixtures alone. Cloudflare may serve challenges to
a datacentre IP that a phone never sees, which would make CI flaky if any test
ever hits the network — none should.
