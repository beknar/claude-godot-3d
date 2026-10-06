"""Paints the winged cyborg's textures (person/textures/).

Run from the project root:
    uv run --no-project --with numpy --with pillow python tools/generate_person_textures.py

armor_panels.png     packed panel map, same layout as the fighter's (R inset, G ink,
                     B tone, A height), with larger, sleeker plates for armour.
undersuit_panels.png the same packing: ribbed mechanical "muscle" running around a limb,
                     crossed by a few cable grooves.
feathers.png         four mechanical feathers side by side, each 256 x 1024 (root at
                     the top, tip at the bottom):
                         R ink (shaft, seams, rim)  G tone (barbs)  B height  A coverage
Colours are applied in the shaders. Previews are written as *_preview.png.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_textures import PanelCanvas  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "person" / "textures"

ARMOR = {
    "max_depth": 4,
    "min_size": 130,
    "stop_chance": [0.0, 0.05, 0.3, 0.6, 1.0],
    "long_cut_bias": 0.75,
    "line_widths": [9, 8, 7, 6],
    "detail_width": 5,
    "notch_chance": 0.35,
    "chamfer_chance": 0.3,
    "kinds": {"inset": 0.3, "outline": 0.25,
              "vent": 0.05, "slots": 0.45, "decal": 0.0, "hatch": 0.08, "blank": 0.42},
}

ARMOR_PALETTE = [
    (0.36, 0.47, 0.57),   # blue steel
    (0.22, 0.29, 0.36),   # inset plates
    (0.04, 0.05, 0.07),   # ink
    (0.62, 0.45, 0.26),   # bronze
]


def armor_texture():
    c = PanelCanvas(1024, 1024, seed=9061)
    c.ink_rect([0, 0, c.w, c.h], c.px(ARMOR["line_widths"][0]))
    c.subdivide(0, 0, c.w, c.h, 0, ARMOR)
    c.finish("armor_panels", ARMOR_PALETTE, OUT)


def undersuit_texture():
    # u (x) runs around the limb, v (y) along it: ribs are horizontal bands.
    c = PanelCanvas(512, 512, seed=315)
    rng = c.rng
    y = 0
    while y < c.h:
        rib = int(c.px(rng.uniform(26, 44)))
        y1 = min(c.h, y + rib)
        # Rounded rib: high in the middle, grooved at both ends.
        for k in range(y, y1):
            t = (k - y) / max(1, y1 - y)
            c.d_height.line([0, k, c.w, k], fill=int(95 + 90 * np.sin(np.pi * t) ** 0.6))
            c.d_tone.line([0, k, c.w, k], fill=int(255 * (0.38 + 0.2 * np.sin(np.pi * t))))
        c.ink_line(0, y1, c.w, y1, c.px(4), groove=60)
        y = y1
    # A few cable grooves running along the limb, cutting through the ribs.
    for x in rng.choice(np.arange(40, 470, 10), size=3, replace=False):
        x = c.px(int(x))
        w = c.px(rng.uniform(14, 22))
        c.d_inset.rectangle([x, 0, x + w, c.h], fill=255)
        c.d_height.rectangle([x, 0, x + w, c.h], fill=110)
        c.ink_line(x, 0, x, c.h, c.px(3), groove=80)
        c.ink_line(x + w, 0, x + w, c.h, c.px(3), groove=80)
    c.finish("undersuit_panels", [(0.12, 0.14, 0.17), (0.07, 0.08, 0.1), (0.02, 0.02, 0.03), (0.5, 0.5, 0.5)], OUT)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def feather(rng, w, h, variant):
    """One mechanical feather: returns (ink, tone, height, alpha) float arrays, h x w."""
    ss = 2
    W, H = w * ss, h * ss
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = yy / (H - 1)                      # 0 root .. 1 tip
    u = (xx / (W - 1)) * 2.0 - 1.0         # -1 leading edge .. +1 trailing edge
    au = np.abs(u)

    # Vane outline: narrow quill, widest about a third of the way down, pointed tip.
    rise = smoothstep(0.0, 0.32, v)
    taper = (1.0 - smoothstep(0.5 + 0.05 * variant, 1.0, v)) ** 0.75
    half = (0.10 + 0.86 * rise) * taper
    half = np.where(u < 0, half * (0.62 + 0.04 * variant), half)  # narrower leading vane

    # Barbs sweep from the shaft out toward the tip.
    barb = v - au * 0.11
    jag = 0.07 * (np.mod(barb * (38 + 6 * variant), 1.0))         # sawtooth edge
    inside = au < half * (1.0 - jag)

    # Ragged splits running in from the edge along the barb direction.
    split = np.zeros_like(inside)
    for _ in range(4 + variant):
        b0 = rng.uniform(0.25, 0.9)
        side = rng.choice([-1.0, 1.0])
        depth = rng.uniform(0.35, 0.8)
        width = rng.uniform(0.004, 0.009)
        on_side = (u * side) > 0
        split |= on_side & (np.abs(barb - b0) < width) & (au > half * (1.0 - depth))
    alpha = inside & ~split
    alpha &= (v > 0.02) | (au < 0.06)
    # Quill stub at the root.
    alpha |= (au < 0.05) & (v <= 0.04)

    shaft = np.exp(-(u / (0.035 * (1.15 - 0.6 * v))) ** 2)
    tone = 0.45 + 0.2 * np.sin(barb * 2 * np.pi * 70) + 0.1 * rng.standard_normal((H, W)) * 0.3
    tone = tone * (0.75 + 0.35 * v)                                 # tips catch more light

    # Plate seams: a couple of inked lines across the vane, like segmented metal.
    ink = shaft > 0.6
    for b0 in rng.uniform(0.3, 0.75, size=2):
        ink |= (np.abs(barb - b0) < 0.004) & (au > 0.06)
    height = 0.5 + 0.35 * shaft - 0.15 * ink + 0.05 * np.sin(barb * 2 * np.pi * 70)

    alpha_img = Image.fromarray((alpha * 255).astype(np.uint8))
    rim = np.asarray(alpha_img.filter(ImageFilter.MinFilter(7)), np.float32) / 255
    ink = ink | ((alpha > 0) & (rim < 0.5))

    def down(a):
        img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
        return np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255

    return down(ink.astype(np.float32)), down(tone), down(height), down(alpha.astype(np.float32))


def feather_texture():
    rng = np.random.default_rng(2077)
    cw, ch = 256, 1024
    layers = [np.zeros((ch, cw * 4), np.float32) for _ in range(4)]
    for i in range(4):
        for layer, part in zip(layers, feather(rng, cw, ch, i)):
            layer[:, i * cw:(i + 1) * cw] = part
    ink, tone, height, alpha = layers
    rgba = np.stack([ink, tone, height, alpha], axis=-1)
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT / "feathers.png", optimize=True)

    root, tip, ink_col = np.array([0.05, 0.06, 0.08]), np.array([0.20, 0.36, 0.40]), np.array([0.02, 0.02, 0.03])
    v = np.linspace(0, 1, ch)[:, None, None]
    col = (root * (1 - v) + tip * v) * (0.6 + 0.8 * tone[..., None])
    col = col * (1 - ink[..., None]) + ink_col * ink[..., None]
    bg = np.array([0.85, 0.85, 0.85])
    col = col * alpha[..., None] + bg * (1 - alpha[..., None])
    Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB").save(OUT / "feathers_preview.png", optimize=True)
    print(f"wrote feathers.png and feathers_preview.png  {cw * 4}x{ch}")


if __name__ == "__main__":
    armor_texture()
    undersuit_texture()
    feather_texture()
