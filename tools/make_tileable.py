"""Make a nearly tileable texture seamless: in a narrow band at each edge,
cross-fade to a half-rolled copy (whose own edges wrap perfectly), then
downscale to 1024."""
import sys
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB").resize((1024, 1024), Image.LANCZOS)
a = np.asarray(im).astype(float)
n = a.shape[0]
r = np.roll(a, (n // 2, n // 2), axis=(0, 1))
band = int(n * 0.08)
ramp = np.clip(np.minimum(np.arange(n), n - 1 - np.arange(n)) / band, 0, 1)
ramp = ramp * ramp * (3 - 2 * ramp)
m = np.minimum(ramp[:, None], ramp[None, :])[..., None]
out = a * m + r * (1 - m)
Image.fromarray(out.clip(0, 255).astype(np.uint8)).save(dst, optimize=True)
