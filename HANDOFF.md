# tela handoff

Updated: 2026-07-13

## Current milestone

Wave 0 is complete at `209101c`. Wave 1 slice 1 is committed as
`bcba151` (`feat: add wallpaper apply core loop`). Wave 1 slice 2 is ready to
commit.

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

## Verification

- `./tool/tela dart format .`: clean
- `./tool/tela analyze`: clean
- `./tool/tela test`: 45 tests pass
- Three-tap browse → detail → Both widget flow: covered
- Domain use case and all native target/error mappings: covered
- `/w/{id}` is covered by a detail JSON fixture, mapper boundary tests, and a
  detail widget metadata test
- `./tool/tela build apk --debug`: passes
- `./tool/tela build apk --release`: passes
- Debug and release merged manifests inspected: `INTERNET` and
  `SET_WALLPAPER`; no
  `READ_EXTERNAL_STORAGE` or `READ_MEDIA_*`

The Android 16 tablet was initially visible to Flutter, but its ADB USB
transport disappeared before install (`flutter install` later listed only
Linux). Physical Home/Lock/Both application remains smoke-test pending.

## Start of next session

Reconnect the Android 16 device and smoke-test Home, Lock, and Both with one
portrait and one large landscape wallpaper. Record any OEM behavior here.

Then continue Wave 1 with download storage: introduce the domain-owned
`ImageStore` port and three-tier routing, enforcing the NSFW non-indexing rule
inside its adapter. Keep browsing, detail, and the apply flow working throughout.
