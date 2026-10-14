"""Generate a nautical-chart background (depth contours + soundings) as SVG.

    python make_chart.py WIDTH HEIGHT OUT.svg [SEED]

Depth is a coastline distance field roughened with fractal noise, so the
contours bunch against the shore and loosen offshore like a real chart.
"""
import sys

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def fbm(shape, seed, octaves=5):
    rng = np.random.default_rng(seed)
    h, w = shape
    out = np.zeros(shape)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = 3 * 2 ** o
        grid = rng.standard_normal((n + 1, n + 1))
        # Bilinear upsample of a random lattice = cheap value noise.
        ys = np.linspace(0, n, h)
        xs = np.linspace(0, n, w)
        y0 = np.floor(ys).astype(int).clip(0, n - 1)
        x0 = np.floor(xs).astype(int).clip(0, n - 1)
        fy = (ys - y0)[:, None]
        fx = (xs - x0)[None, :]
        fy = fy * fy * (3 - 2 * fy)
        fx = fx * fx * (3 - 2 * fx)
        a = grid[y0][:, x0]
        b = grid[y0][:, x0 + 1]
        c = grid[y0 + 1][:, x0]
        d = grid[y0 + 1][:, x0 + 1]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
        total += amp
        amp *= 0.5
    return out / total


def main():
    W, H, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    seed = int(sys.argv[4]) if len(sys.argv) > 4 else 7
    gw, gh = W // 4, H // 4
    yy, xx = np.mgrid[0:gh, 0:gw] / max(gw, gh)

    # Coast runs down the left edge and bends out along the top: a bay.
    n = fbm((gh, gw), seed)
    coast = 0.12 + 0.06 * np.sin(yy * 7 + 1.3) + 0.05 * n
    dist = np.minimum(xx - coast, (yy - 0.05 - 0.04 * np.sin(xx * 5)) * 1.4)
    depth = dist * 120 + 18 * fbm((gh, gw), seed + 1, 6)
    depth = np.maximum(depth, -5)

    fig = plt.figure(figsize=(gw / 100, gh / 100), dpi=100)
    ax = fig.add_axes([0, 0, 1, 1])
    levels = [0, 2, 5, 10, 15, 20, 30, 40, 50, 60, 75, 90, 110]
    cs = ax.contour(depth, levels=levels)
    plt.close(fig)

    sx, sy = W / gw, H / gh
    paths = []
    for lvl, segs in zip(cs.levels, cs.allsegs):
        for seg in segs:
            if len(seg) < 6:
                continue
            pts = " ".join(f"{x * sx:.1f},{y * sy:.1f}" for x, y in seg[::2])
            cls = "c0" if lvl == 0 else ("c10" if lvl in (10, 20, 50, 110) else "c")
            paths.append(f'<polyline class="{cls}" points="{pts}"/>')

    # Land mask as a filled path (depth < 0) via a contourf at the zero level.
    fig = plt.figure(figsize=(gw / 100, gh / 100), dpi=100)
    ax = fig.add_axes([0, 0, 1, 1])
    cf = ax.contourf(depth, levels=[-10, 0])
    plt.close(fig)
    land = []
    for path in cf.get_paths():
        d = []
        for poly in path.to_polygons():
            d.append("M" + "L".join(f"{x * sx:.1f},{y * sy:.1f}" for x, y in poly) + "Z")
        land.append(f'<path class="land" d="{"".join(d)}"/>')

    # Soundings: depth numbers on a jittered grid, only in the water.
    rng = np.random.default_rng(seed + 2)
    soundings = []
    step = 150
    for y in range(step // 2, H, step):
        for x in range(step // 2, W, step):
            jx, jy = x + rng.integers(-50, 50), y + rng.integers(-50, 50)
            gx, gy = min(int(jx / sx), gw - 1), min(int(jy / sy), gh - 1)
            if gx < 0 or gy < 0:
                continue
            dv = depth[gy, gx]
            if dv < 2 or rng.random() < 0.35:
                continue
            whole = int(dv)
            frac = int((dv - whole) * 10)
            soundings.append(
                f'<text x="{jx}" y="{jy}" class="s">{whole}<tspan class="sf" dy="6">{frac}</tspan></text>'
            )

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">
<style>
.c{{fill:none;stroke:rgba(92,178,240,.12);stroke-width:1.4}}
.c10{{fill:none;stroke:rgba(92,178,240,.24);stroke-width:2}}
.c0{{fill:none;stroke:rgba(38,209,250,.55);stroke-width:3}}
.land{{fill:#0C1C28}}
.s{{font:500 19px 'Spline Sans Mono',monospace;fill:rgba(150,196,230,.30)}}
.sf{{font-size:13px}}
</style>
{''.join(land)}
{''.join(paths)}
{''.join(soundings)}
</svg>"""
    open(out, "w").write(svg)
    print(out, len(paths), "contours", len(soundings), "soundings")


if __name__ == "__main__":
    main()
