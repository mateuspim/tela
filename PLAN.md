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
| Omarchy sync | Wave 3 | parked, not blocking |
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

**Wave 3 — Search & discovery**
The filters Wave 2 named but did not finish, plus the two ways *into* a listing that tela prints on screen and does not let you follow.

- **Resolution filter.** Today `atleast` is imposed by the browse screen from the device screen and cannot be changed. It becomes a real filter: *Automatic* (the screen you are holding — still the default), *At least*, or *Exactly* (the `resolutions` param, which tela does not send at all yet), over buckets grouped by ratio plus a custom W×H. Retires `SearchQuery.atLeast`'s `copyWith`-cannot-clear trap.
- **Ratio filter, expanded.** `RatioChoice`'s portrait / landscape / any becomes a multi-select over Wallhaven's real vocabulary — its `portrait` / `landscape` keywords and the specific ratios — with the device's own reduced ratio offered first as the recommendation. Ratios are a **union** in the API, unlike `colors`, so chips rather than a radio.
- **Every sorting reachable.** Three of Wallhaven's seven (relevance, views, favorites) cannot be reached, because the tab *is* the sorting and there are four tabs. The tab bar becomes scrollable and gains Views and Favorites; **Relevance appears only when a search term is set**, and is selected on submit — it ranks against a term and means nothing without one.
- **Tags and the uploader become links.** A tag chip opens that tag's listing (`q=id:{tagId}` — Wallhaven's exact-tag operator, not a fuzzy `+name`), and the uploader opens theirs (`q=@username`). Both push a results screen, so Back returns to the wallpaper and the browse tabs are left as they were. **There is no user-profile endpoint in the API**: a "profile" can only be their uploads plus the avatar and group `/w/{id}` already carries, and the screen should say what it is rather than imply a profile.

*Exit:* the filter sheet answers everything wallhaven.cc's own filter bar does, and a wallpaper is a place you can navigate *from* — its tags and its uploader lead somewhere.

**Wave 4 — Nice-to-haves**
Crop/reposition editor before apply, daily auto-rotate (WorkManager), collections browser, share sheet, **Omarchy sync** (export favorites to an Aether-consumable format — closes the desktop↔mobile loop).
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
