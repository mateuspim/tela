# Measuring the UI on a real device

Three ten-line scripts that turn `adb exec-out screencap` into evidence, so a
claim about motion or contrast in the handoff is a number rather than an
impression. All three need only `python3` and ImageMagick's `convert`.

They exist because two device passes were nearly lost to the same two traps:
`screencap` is far too slow to sample an animation in time, and a blurred
backdrop correlates well against itself at almost any offset.

## `row_shift.py` — how far did a layer move?

```bash
python3 tool/device/row_shift.py before.png after.png '1400x200+100+250' 200
# rows=200 best_shift=-22 mse_at_shift=0.0 mse_at_zero=485.3
```

Cross-correlates the row-brightness profile of one crop between two frames and
reports the vertical shift that fits best. `mse_at_shift` near zero means a pure
translation — that is what proved Detail's blurred scenery drifts as the facts
pane scrolls while the fitted wallpaper stays pixel-identical.

**Its limit, learned the hard way:** over a smooth blur with no structure it will
happily report a confident shift that is noise, including for regions that
cannot have moved. Trust it where the crop has edges in it, and sanity-check by
running it on something you know is static.

## `row_cascade.py` — did a staggered animation run?

```bash
python3 tool/device/row_cascade.py entering.png settled.png '2400x150+80+360'
# ratio: [0.99, 0.99, 1.0, 0.97, 0.84, 0.73, 0.46, 0.31, 0.28]
```

Splits one row of tiles into nine buckets and divides each by its settled
brightness. A **monotonic left-to-right ramp** is `TileEntrance`'s cascade caught
mid-flight; image decoding cannot fake it, because the network answers in
whatever order it likes and not in tile order.

Capture the burst **on the device**, or the adb round trip outlasts the
animation:

```bash
adb shell "am start -n cc.pym.tela/.MainActivity >/dev/null; \
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do screencap -p /sdcard/f\$i.png; done"
```

## `icon_contrast.py` — can you still see the white controls?

```bash
python3 tool/device/icon_contrast.py shot.png '80x80+1510+90=download icon'
# ink=255.0 ground=152 contrast=2.88:1
```

Brightest 2% of a crop against its median, as a WCAG contrast ratio: the glyph
against whatever wallpaper it is sitting on. 3:1 is the floor for UI graphics.

## Before believing any of it

A black frame usually means the tablet locked, not that the app hung — see the
install rule in `HANDOFF.md`. Check the file size first: a loaded grid is
megabytes, a keyguarded screen is ~20KB.
