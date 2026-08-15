"""Row-brightness profile of a crop, and the vertical shift between two of them.

Measures the parallax: the blurred backdrop is a smooth vertical gradient, so
the offset that best aligns two profiles is how far it drifted.
"""
import subprocess, sys, re

def profile(png, crop):
    out = subprocess.run(
        ['convert', png, '-crop', crop, '+repage', '-colorspace', 'gray',
         '-resize', '1x!', '-depth', '8', 'txt:-'],
        capture_output=True, text=True, check=True).stdout
    vals = []
    for line in out.splitlines()[1:]:
        m = re.search(r'gray\((\d+)\)', line) or re.search(r'#([0-9A-F]{2})', line)
        if m:
            v = m.group(1)
            vals.append(int(v, 16) if len(v) == 2 and not v.isdigit() else int(v))
    return vals

def best_shift(a, b, limit):
    """Shift of b relative to a, in rows, by least mean squared difference."""
    best, score = 0, None
    for s in range(-limit, limit + 1):
        pairs = [(a[i], b[i + s]) for i in range(len(a))
                 if 0 <= i + s < len(b)]
        if len(pairs) < len(a) // 2:
            continue
        mse = sum((x - y) ** 2 for x, y in pairs) / len(pairs)
        if score is None or mse < score:
            best, score = s, mse
    return best, score

if __name__ == '__main__':
    first, second, crop = sys.argv[1], sys.argv[2], sys.argv[3]
    limit = int(sys.argv[4]) if len(sys.argv) > 4 else 300
    a, b = profile(first, crop), profile(second, crop)
    shift, mse = best_shift(a, b, limit)
    same = sum((x - y) ** 2 for x, y in zip(a, b)) / len(a)
    print(f'rows={len(a)} best_shift={shift} mse_at_shift={mse:.1f} mse_at_zero={same:.1f}')
