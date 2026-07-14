# tela handoff

Updated: 2026-07-13

## Current milestone

Wave 0 is complete at `209101c`. Wave 1 slice 1 is implemented under the commit
subject `feat: add wallpaper apply core loop`.

The app now supports the thin product loop:

1. Tap a real Wallhaven tile.
2. Preview the full-resolution image with pinch zoom.
3. Tap **Set wallpaper** and choose Home, Lock, or Both.

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

## Verification

- `./tool/tela dart format .`: clean
- `./tool/tela analyze`: clean
- `./tool/tela test`: 42 tests pass
- Three-tap browse → detail → Both widget flow: covered
- Domain use case and all native target/error mappings: covered
- `./tool/tela build apk --debug`: passes
- `./tool/tela build apk --release`: passes
- Debug and release merged manifests inspected: `INTERNET` and
  `SET_WALLPAPER`; no
  `READ_EXTERNAL_STORAGE` or `READ_MEDIA_*`

No Android device was connected during the final pass (`flutter devices` showed
only Linux), so physical Home/Lock/Both application is not yet smoke-tested for
this slice.

## Start of next session

First, connect the Android 16 device and smoke-test Home, Lock, and Both with one
portrait and one large landscape wallpaper. Record any OEM behavior here.

Then implement Wave 1 slice 2: complete wallpaper detail. Add `/w/{id}` to
`WallhavenApi`, a non-nullable detail domain model, captured JSON fixture and
mapper tests, progressive preview loading, and metadata for file size, category,
purity, colors, tags, uploader, source, views, and favorites. Keep the apply
flow working throughout and commit the slice with this handoff updated.
