"""Icon-vs-background contrast in a crop, in WCAG relative-luminance terms."""
import subprocess, sys, re

def lum(v):
    c = v / 255
    c = c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return c

def report(png, crop, label):
    out = subprocess.run(['convert', png, '-crop', crop, '+repage', '-colorspace', 'gray',
                          '-depth', '8', 'txt:-'], capture_output=True, text=True, check=True).stdout
    v = sorted(int(m.group(1)) for m in re.finditer(r'graya\((\d+)', out))
    n = len(v)
    ink = sum(v[-n // 50:]) / (n // 50)          # brightest 2% = the glyph's core
    ground = v[n // 2]                            # median = what it sits on
    ratio = (lum(ink) + 0.05) / (lum(ground) + 0.05)
    print(f'{label:22s} ink={ink:5.1f} ground={ground:3d} contrast={ratio:.2f}:1')

for spec in sys.argv[2:]:
    crop, label = spec.split('=')
    report(sys.argv[1], crop, label)
