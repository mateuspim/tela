# tela — visual identity

What the marks are, why they are shaped the way they are, and how to change
them without breaking the four places they are drawn.

`CLAUDE.md` is the code contract; this is the identity one.

## The two marks

tela has a **wordmark** and a **mark**, and they are separate widgets on
purpose.

| | what | where it lives |
|---|---|---|
| Wordmark | the name, set in Bricolage Grotesque, lowercase, tight | `lib/core/ui/tela_wordmark.dart` |
| Mark | four bands in a cyclic interlace, drawn as a square frame | `lib/core/ui/tela_mark.dart` |

**Use the wordmark** where the app has to *name* itself and there is room for
words. **Use the mark** where there is no room, or where the surface is not
ours — the launcher, the splash, a chip over someone else's photograph. **Use
the lockup** (mark stacked over wordmark) only in the navigation rail; it is
private to `tela_shell.dart` because that is the one place both belong.

## The mark

*Tela* is the canvas, and a canvas is cloth pulled over a stretcher: four bars,
each crossing over one neighbour and under the next. That is also the simplest
true weave — Latin *tela*, the web on a loom. The mark is that interlace and
nothing else. It is not a photograph, a mountain, or a picture frame with a
sunset in it, and it should not drift toward one.

The interlace runs in a cycle: **top over left, left over bottom, bottom over
right, right over top**, which is what makes the mark symmetric under a half
turn but not under a quarter turn.

### Construction

On a **108-unit grid** — the adaptive-icon canvas, so the numbers are used
verbatim by every renderer with nothing to re-derive:

| | value |
|---|---|
| frame outer extent | `29 … 79` (50 across, centred on 54) |
| band width | `12`, with pill ends of radius `6` |
| cut margin | `2.75` clearance around the band passing over |

The mark therefore inks under half the grid; the rest is clearance a launcher
mask needs. **That margin belongs to the icon, not to the mark.** In a widget
there is no mask, so `TelaMarkPainter` scales the *frame* onto its box, and
`TelaMark(size: 30)` means thirty logical pixels of mark. Scaling the whole grid
instead draws it at 46% — which is exactly what the rail lockup looked like on
the tablet on the first build, and is pinned now by *fills the box it is given*.

### Two constraints fixed those numbers

Both were settled by *rendering and looking*, not by argument. Neither is
negotiable, and each has a test that fails first if it is broken.

**1. The interlace is a cut, never a shade.** Material You's themed icon
discards our colours and tints one flat silhouette. So over-under has to
survive with no tone difference at all, which it does because each band is
physically *shortened* at the end that passes under. Express the crossings with
two tones instead and the themed icon collapses into a closed square. Pinned by
*paints four bands, each shortened where it passes under*.

**2. It must fit the circular launcher mask, which is tighter than the 72dp
safe square.** A round mask is a circle of radius 36 about the canvas centre,
and a square inscribed in that circle has a half-extent of only
`36/√2 ≈ 25.45` — well inside the 36 the safe square would allow. Drawn at the
safe square's full size, the band ends are sliced clean off under a round mask
and the interlace stops reading; this was checked under both a circle and a
squircle. Hence the 25 half-extent. Pinned by *the frame fits the launcher
circular mask*.

> An earlier draft of the mark was a 2×2 plain weave of pill segments. Rendered,
> it was **Slack's logo**, near enough to be embarrassing — that construction is
> theirs. Recorded so nobody re-derives it.

## Colour

**One fixed colour: `#7772E5`.** It is `TelaTheme.brandSeed` in
`lib/app/theme.dart` and `telaBrandSeed` in
`android/app/src/main/res/values/tela_brand.xml`.

The mark is deliberately **not** painted in `ColorScheme.primary`. tela lets the
user pick any accent or follow their wallpaper (`TelaTheme._withAccent`), and a
logo that moves with a user setting is not an identity. Material You users still
get a themed launcher icon — that is what the monochrome layer is for, and it is
the system's business, not ours.

The launcher icon adds two more, and only the launcher icon uses them:

| role | value | notes |
|---|---|---|
| ground | `#14122E` | `telaBrandGround`; also the splash |
| warp (left/right bands) | `#B0ADF2` | a light tint of the seed |
| weft (top/bottom bands) | `#7772E5` | the seed itself |

The two tones tell warp from weft. They do **not** carry the over-under — see
constraint 1. In Flutter the mark is a single colour, because there it sits on a
theme surface rather than a ground of its own.

## Clear space

Leave the width of one band (`12` on the grid, i.e. ⅙ of the mark's width) clear
on all four sides. The adaptive icon already has far more than that, by
construction.

## The four renderers, and how to change the mark

The geometry exists in **four** places. `assets/brand/tela_mark.svg` is the
normative one; the rest are derived from it.

1. `assets/brand/tela_mark.svg` — **the source**. Design only; deliberately not
   in `pubspec.yaml`'s asset bundle, so it never ships in the APK.
2. `android/app/src/main/res/drawable/ic_launcher_foreground.xml` — two-tone.
3. `android/app/src/main/res/drawable/ic_launcher_monochrome.xml` — one flat
   colour, for themed icons.
4. `lib/core/ui/tela_mark.dart` — `TelaMarkPainter`, for in-app use.

To change it:

```bash
# 1. edit assets/brand/tela_mark.svg
# 2. transcribe its paths into both Android vector drawables (same 108 viewport)
# 3. regenerate the legacy PNG mipmaps
for pair in "mdpi 48" "hdpi 72" "xhdpi 96" "xxhdpi 144" "xxxhdpi 192"; do
  set -- $pair
  rsvg-convert -w $2 -h $2 assets/brand/tela_mark.svg \
    -o android/app/src/main/res/mipmap-$1/ic_launcher.png
done
# 4. update the constants on TelaMark, and the numbers in this file
# 5. make test   # the geometry test names what you missed
```

The PNGs are belt-and-braces: `minSdk` is 29, so `mipmap-anydpi-v26` always
wins. They are regenerated anyway so a stale icon cannot resurface — Flutter's
default blue "F" sat in that directory until this pass.

**`make test` will not catch a bad *shape*, only a broken agreement.** After any
change, render the SVG and look at it under a circular mask, and check the
monochrome layer separately — the interlace is exactly what a silent regression
would eat.

## Splash

`drawable-v21/launch_background.xml` on API 29–30; `values-v31/styles.xml` on
API 31+, where the system splash screen takes over and `windowBackground` stops
governing. Both must be branded or modern devices get the platform default.

The splash ground is the **icon's** ground in both light and dark, not a theme
surface: tapping the icon should land on the thing you tapped. A theme-following
splash would need a second, darker mark to keep the light warp tint legible on a
pale ground — two marks to keep in step, for a band that shows for a few hundred
milliseconds.

## Typography

Bricolage Grotesque (`assets/fonts/`, OFL) on display and headline roles, and on
the wordmark. It is the display face only — body and label text stay on the
platform face, because a wall of other people's photographs is not the place to
also be arguing with a typeface.
