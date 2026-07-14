# tela — CLAUDE.md

Conventions and hard rules for this project. Read before writing code.

## What this is

`tela` is a **Flutter, Android-first** app: a Wallhaven client whose whole job is
**browse → preview → set as wallpaper**, plus downloads. No backend, no accounts,
no cloud of our own. It is the wallpaper-browsing half of Aether, on the phone.

Roadmap, scope, and architecture rationale live in `PLAN.md`. This file is the
*how we write it* contract.

## Stack (locked)

| Concern | Choice |
|---|---|
| Language / UI | Dart + Flutter, Material 3 |
| State / DI | Riverpod |
| Routing | go_router |
| Networking | Dio (behind our own `WallhavenApi` interface) |
| Images | cached_network_image (+ `cacheWidth`/`ResizeImage` on decode) |
| Pagination | infinite_scroll_pagination |
| Local DB | Drift (typed SQL) |
| Secrets | flutter_secure_storage |
| Set wallpaper | Native Android method channel, behind our `WallpaperApplier` interface |
| Dynamic color | dynamic_color (Material You / Monet, Wave 2) |

## Architecture

Feature-first, Clean layering, ports/adapters. Domain is pure Dart with **zero
Flutter/plugin imports** — it must be testable as plain Dart.

```
lib/
├── main.dart
├── app/                  # App widget, router, theme, Riverpod root
├── core/
│   ├── network/          # Dio client, api-key + rate-limit interceptors, error mapping
│   ├── storage/          # three-tier storage adapters (see Domain rules)
│   ├── i18n/             # generated l10n
│   └── ui/               # design system: colors, type, spacing, shared widgets
├── domain/               # pure Dart: models, repository interfaces (ports), use cases
├── data/                 # DTOs, mappers, repository impls, Drift, plugin adapters
└── features/
    ├── browse/  search/  detail/  favorites/  settings/
```

Each feature owns its widgets + Riverpod providers. Cross-feature logic goes to
`domain`/`core`, never imported sideways between features.

## Code style

- Functions: **4–20 lines**. Longer → split.
- Files: **under 500 lines**. Split by responsibility.
- One thing per function; one responsibility per module (SRP).
- Names: specific and unique — aim for **<5 grep hits** across the codebase.
  Avoid `data`, `handler`, `manager`, `util`, `helper`.
  Note: Android's own type is `WallpaperManager`; **our** wrapper is
  `WallpaperApplier`, never `WallpaperManager`, to keep the rule intact.
- **No code duplication.** Extract shared logic into a function/module.
- Early returns over nested ifs. **Max 2 levels of indentation.**
- Exceptions must name the offending value **and** the expected shape, e.g.
  `throw ArgumentError('purity must be sfw|sketchy|nsfw, got "$raw"')`.

## Types & null safety (Dart)

- Sound null safety on. No `dynamic`. No untyped functions or collections
  (`List<Wallpaper>`, never bare `List`).
- Explicit types on all public APIs (params, returns, fields). Local `final`/`var`
  is fine only when the type is obvious on the same line.
- Enforce mechanically via `analysis_options.yaml`:
  `strict-casts`, `strict-inference`, `strict-raw-types` under `analyzer:
  language:`, plus a lint set (very_good_analysis or flutter_lints).
- Model domain states as enums/sealed classes, not stringly-typed values
  (`Purity`, `WallpaperTarget`, `StorageTier` are sealed/enum, not `String`).

## Comments

- **Keep existing comments** on refactor — they carry intent and provenance.
- Write **WHY, not WHAT**. Skip `// increment i` above `i++`.
- `///` docstrings on every public function/class: intent + one usage example.
- Reference issue numbers / commit SHAs when a line exists because of a specific
  bug or OEM quirk (e.g. `// Redmi lock-screen apply needs sequential write, see #42`).

## Tests

- Single command: **`flutter test`**.
- Every new function gets a test. Every bug fix gets a regression test.
- Mock external I/O (Wallhaven, Drift, filesystem, wallpaper plugin) with
  **named fake classes** (`FakeWallhavenApi`, `FakeWallpaperApplier`), not inline
  stubs and not mock-magic.
- F.I.R.S.T: fast, independent, repeatable, self-validating, timely.
- Domain use cases are plain-Dart unit tests. DTO→domain mappers are tested
  against captured Wallhaven JSON fixtures.

## Dependencies

- Inject through constructor/parameter (wired by Riverpod providers). No global
  singletons, no reaching through imports for state.
- **Wrap every third-party lib and platform API behind a thin project-owned
  interface** in `domain` (the port); the dependency lives only in its
  `data`/`core` adapter. Non-negotiable for: `WallhavenApi` (Dio),
  `WallpaperApplier` (Android method channel), `ImageStore` (three-tier),
  `SecretStore` (flutter_secure_storage). Swapping an implementation must touch
  one adapter, not features.
- Those four wrap a third-party package. `FavoritesRepository` and
  `SettingsRepository` are ports too, but pure-domain ones with no package behind
  them (Drift is an implementation detail of their adapters). Same rule, no
  vendor to swap.

## Domain rules (hard invariants)

**Wallhaven API**
- Base `https://wallhaven.cc/api/v1`. Rate limit **45 req/min** → throttle client-side
  and exponential-backoff on `429`.
- API key travels **only** in the `X-API-Key` header. Never in a query string,
  never in logs, never in analytics. SFW works with no key; `nsfw` purity requires
  a valid key (else `401`).
- DTOs never escape the data layer — map to domain models at the boundary.

**Three-tier storage** (destination configurable **per purity**, SFW and NSFW
independently, with a per-download override)
1. `sharedGallery` → MediaStore `Pictures/tela` (indexed, visible in Photos).
2. `filesOutsideGallery` → `.nomedia` dir on shared storage (file-manager/USB
   reachable, **not** in Photos) — the desktop-sync path.
3. `appPrivate` → app-internal storage (only tela can see it; gone on uninstall).

**NSFW handling — hard rules**
- NSFW files are **never** MediaStore-indexed, in **any** tier. Enforce in the
  storage adapter, not just as a UI default.
- The private library screen sets `FLAG_SECURE` (no thumbnails in the app
  switcher, no screenshots).
- Optional app-lock (biometric/PIN) gates the private library.
- Default routing: SFW → `sharedGallery`, NSFW → `appPrivate`.

**i18n**
- No hardcoded user-facing strings — everything through l10n (ARB). English is the
  only shipped locale for now; adding a locale must be a translation file, not a
  refactor.

## Naming (product)

Portuguese / Latin-rooted, matching `luma` / `volta` / `focal` / `pauta`. This app
is `tela` (pt: "screen / canvas"). Keep new module/feature names in the same register
where it reads naturally; don't force it on technical internals.

## Formatting

`dart format .` — the language default. No style discussion beyond that.
Run `flutter analyze` clean before every commit.

## Logging

- Structured (JSON) for debug/observability logs.
- Plain text only for genuinely user-facing output.
- **Never** log the API key, NSFW file paths, or full image URLs with keys attached.

## Commands

```bash
flutter analyze          # must be clean
dart format .            # format
flutter test             # all tests
flutter run              # dev (Android device/emulator)
flutter build apk --release
```
