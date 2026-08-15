"""Per-tile brightness across one row, for the entrance cascade."""
import subprocess, sys, re
def buckets(png, crop, n=9):
    out = subprocess.run(['convert', png, '-crop', crop, '+repage', '-colorspace', 'gray',
                          '-resize', f'{n}x1!', '-depth', '8', 'txt:-'],
                         capture_output=True, text=True, check=True).stdout
    return [int(m.group(1)) for m in re.finditer(r'graya\((\d+)', out)]
a = buckets(sys.argv[1], sys.argv[3]); b = buckets(sys.argv[2], sys.argv[3])
print('entering :', a)
print('settled  :', b)
print('ratio    :', [round(x / y, 2) if y else 0 for x, y in zip(a, b)])
