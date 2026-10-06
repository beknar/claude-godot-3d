"""Paints the fighter's panel textures in the style of the reference illustration:
irregular hull plates outlined in bold ink, darker inset panels, nested plates,
notched and chamfered plate edges, rounded access slots, slatted vents, round
hatches and striped decals.

Run from the project root:
    uv run --no-project --with numpy --with pillow python tools/generate_textures.py

Each texture is a packed mask map read by the fighter shaders (linear, not sRGB):
    R  inset-panel mask      (1 = darker inset plate)
    G  ink mask              (1 = black linework)
    B  tone                  (~0.35-0.6 per-plate brightness and line shadowing;
                              > 0.9 marks a striped decal)
    A  height                (0.5 = hull surface; lower = recessed, higher = raised)
Colours are applied in the shader, so the same texture serves any livery.
Preview bakes in the reference palette are written next to them as *_preview.png.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "fighter" / "textures"
SUPERSAMPLE = 2


class PanelCanvas:
    def __init__(self, width, height, seed):
        self.w, self.h = width * SUPERSAMPLE, height * SUPERSAMPLE
        self.out_size = (width, height)
        self.rng = np.random.default_rng(seed)
        self.ink = Image.new("L", (self.w, self.h), 0)
        self.inset = Image.new("L", (self.w, self.h), 0)
        self.tone = Image.new("L", (self.w, self.h), 128)
        self.height = Image.new("L", (self.w, self.h), 128)
        self.decal = Image.new("L", (self.w, self.h), 0)
        self.d_ink = ImageDraw.Draw(self.ink)
        self.d_inset = ImageDraw.Draw(self.inset)
        self.d_tone = ImageDraw.Draw(self.tone)
        self.d_height = ImageDraw.Draw(self.height)

    def px(self, v):
        return int(round(v * SUPERSAMPLE))

    # -- primitives -------------------------------------------------------
    def ink_line(self, x0, y0, x1, y1, width, groove=70):
        self.d_ink.line([x0, y0, x1, y1], fill=255, width=width)
        self.d_height.line([x0, y0, x1, y1], fill=groove, width=width + self.px(2))

    def ink_rect(self, box, width, radius=0):
        if radius:
            self.d_ink.rounded_rectangle(box, radius=radius, outline=255, width=width)
        else:
            self.d_ink.rectangle(box, outline=255, width=width)

    def _place(self, region, w, h, taken, gap):
        """Random spot for a w x h box inside region that keeps clear of `taken` boxes."""
        rx0, ry0, rx1, ry1 = region
        if w > rx1 - rx0 or h > ry1 - ry0:
            return None
        for _ in range(16):
            x = self.rng.uniform(rx0, rx1 - w)
            y = self.rng.uniform(ry0, ry1 - h)
            box = [int(x), int(y), int(x + w), int(y + h)]
            if all(box[2] + gap < t[0] or t[2] + gap < box[0] or box[3] + gap < t[1] or t[3] + gap < box[1]
                   for t in taken):
                taken.append(box)
                return box
        return None

    # -- panel layout -----------------------------------------------------
    def subdivide(self, x0, y0, x1, y1, depth, cfg):
        w, h = x1 - x0, y1 - y0
        min_size = self.px(cfg["min_size"])
        stop = cfg["stop_chance"][min(depth, len(cfg["stop_chance"]) - 1)]
        can_x = w >= 2 * min_size
        can_y = h >= 2 * min_size
        if depth >= cfg["max_depth"] or not (can_x or can_y) or self.rng.random() < stop:
            self.decorate(x0, y0, x1, y1, cfg)
            return
        # Mostly cut across the longer side, so plates stay chunky.
        cut_x = can_x and (not can_y or (w >= h) == (self.rng.random() < cfg["long_cut_bias"]))
        t = self.rng.uniform(0.3, 0.7)
        width = self.px(cfg["line_widths"][min(depth, len(cfg["line_widths"]) - 1)])
        if cut_x:
            xm = int(x0 + w * t)
            self.ink_line(xm, y0, xm, y1, width)
            self.subdivide(x0, y0, xm, y1, depth + 1, cfg)
            self.subdivide(xm, y0, x1, y1, depth + 1, cfg)
        else:
            ym = int(y0 + h * t)
            self.ink_line(x0, ym, x1, ym, width)
            self.subdivide(x0, y0, x1, ym, depth + 1, cfg)
            self.subdivide(x0, ym, x1, y1, depth + 1, cfg)

    def decorate(self, x0, y0, x1, y1, cfg):
        rng = self.rng
        pad = self.px(6)
        x0, y0, x1, y1 = x0 + pad, y0 + pad, x1 - pad, y1 - pad
        w, h = x1 - x0, y1 - y0
        if w < self.px(20) or h < self.px(20):
            return
        self.d_tone.rectangle([x0, y0, x1, y1], fill=int(255 * rng.uniform(0.4, 0.56)))
        thin = self.px(cfg["detail_width"])
        kinds = cfg["kinds"]
        region = [x0 + self.px(6), y0 + self.px(6), x1 - self.px(6), y1 - self.px(6)]
        taken = []
        gap = self.px(8)

        # Plate-shaping linework: notches running in from an edge, chamfered corners.
        if rng.random() < cfg["notch_chance"]:
            if rng.random() < 0.5:
                xn = int(x0 + w * rng.uniform(0.2, 0.8))
                from_top = rng.random() < 0.5
                yn = y0 - pad if from_top else y1 + pad
                ln = h * rng.uniform(0.2, 0.45)
                self.ink_line(xn, yn, xn, int(yn + ln if from_top else yn - ln), thin, groove=95)
            else:
                yn = int(y0 + h * rng.uniform(0.2, 0.8))
                from_left = rng.random() < 0.5
                xn = x0 - pad if from_left else x1 + pad
                ln = w * rng.uniform(0.2, 0.45)
                self.ink_line(xn, yn, int(xn + ln if from_left else xn - ln), yn, thin, groove=95)
        if rng.random() < cfg["chamfer_chance"]:
            c = min(w, h) * rng.uniform(0.15, 0.3)
            left, top = rng.random() < 0.5, rng.random() < 0.5
            cx, sx = (x0 - pad, 1) if left else (x1 + pad, -1)
            cy, sy = (y0 - pad, 1) if top else (y1 + pad, -1)
            self.ink_line(int(cx + sx * c), cy, cx, int(cy + sy * c), thin, groove=95)

        roll = rng.random()
        # Plates that become an inset are drawn whole.
        if roll < kinds["inset"]:
            m = max(self.px(10), int(min(w, h) * rng.uniform(0.1, 0.22)))
            box = [x0 + m, y0 + m, x1 - m, y1 - m]
            if box[2] - box[0] > self.px(16) and box[3] - box[1] > self.px(16):
                radius = self.px(rng.choice([0, 0, 6, 12]))
                raised = rng.random() < 0.35
                self.d_inset.rounded_rectangle(box, radius=radius, fill=255)
                self.d_height.rounded_rectangle(box, radius=radius, fill=165 if raised else 92)
                self.ink_rect(box, thin, radius)
                if rng.random() < 0.35:
                    m2 = int(min(box[2] - box[0], box[3] - box[1]) * 0.22)
                    inner = [box[0] + m2, box[1] + m2, box[2] - m2, box[3] - m2]
                    if inner[2] - inner[0] > self.px(12) and inner[3] - inner[1] > self.px(12):
                        self.d_inset.rectangle(inner, fill=0)
                        self.d_height.rectangle(inner, fill=140)
                        self.ink_rect(inner, thin)
            return
        # An inner outline (raised plate), sometimes with details inside it.
        if roll < kinds["inset"] + kinds["outline"]:
            m = max(self.px(8), int(min(w, h) * rng.uniform(0.08, 0.18)))
            box = [x0 + m, y0 + m, x1 - m, y1 - m]
            if box[2] - box[0] > self.px(16) and box[3] - box[1] > self.px(16):
                self.d_height.rectangle(box, fill=150)
                self.ink_rect(box, thin, self.px(rng.choice([0, 8])))
                region = [box[0] + self.px(10), box[1] + self.px(10), box[2] - self.px(10), box[3] - self.px(10)]
            if rng.random() < 0.5:
                return

        # Scatter a few small details, more on bigger plates.
        area = (w * h) / float(self.px(100) ** 2)
        count = 1 + int(min(3, area * rng.uniform(0.3, 0.7)))
        total = kinds["vent"] + kinds["slots"] + kinds["decal"] + kinds["hatch"] + kinds["blank"]
        for _ in range(count):
            pick = rng.random() * total
            if pick < kinds["vent"]:
                self.vent(region, taken, gap)
            elif pick < kinds["vent"] + kinds["slots"]:
                self.slot(region, taken, gap, thin)
            elif pick < kinds["vent"] + kinds["slots"] + kinds["decal"]:
                self.stripes(region, taken, gap)
            elif pick < kinds["vent"] + kinds["slots"] + kinds["decal"] + kinds["hatch"]:
                self.hatch(region, taken, gap, thin)

    # -- small details ----------------------------------------------------
    def vent(self, region, taken, gap):
        rng = self.rng
        vw, vh = self.px(rng.uniform(60, 140)), self.px(rng.uniform(24, 50))
        if rng.random() < 0.4:
            vw, vh = vh, vw
        box = self._place(region, vw, vh, taken, gap)
        if box is None:
            return
        self.d_ink.rectangle(box, fill=255)
        self.d_height.rectangle(box, fill=70)
        step, inset = self.px(10), self.px(3)
        if (box[2] - box[0]) >= (box[3] - box[1]):
            for sx in range(box[0] + step // 2, box[2] - step // 2, step):
                self._slat([sx, box[1] + inset, sx, box[3] - inset])
        else:
            for sy in range(box[1] + step // 2, box[3] - step // 2, step):
                self._slat([box[0] + inset, sy, box[2] - inset, sy])

    def _slat(self, seg):
        self.d_ink.line(seg, fill=0, width=self.px(4))
        self.d_inset.line(seg, fill=255, width=self.px(4))
        self.d_height.line(seg, fill=110, width=self.px(4))

    def slot(self, region, taken, gap, thin):
        rng = self.rng
        sw, sh = self.px(rng.uniform(40, 120)), self.px(rng.uniform(14, 34))
        if rng.random() < 0.5:
            sw, sh = sh, sw
        box = self._place(region, sw, sh, taken, gap)
        if box is None:
            return
        r = int(min(box[2] - box[0], box[3] - box[1]) / 2)
        self.d_height.rounded_rectangle(box, radius=r, fill=105)
        self.ink_rect(box, thin, r)

    def stripes(self, region, taken, gap):
        rng = self.rng
        box = self._place(region, self.px(rng.uniform(50, 90)), self.px(rng.uniform(26, 44)), taken, gap)
        if box is None:
            return
        # Diagonal stripes, like the reference's red and orange warning patches.
        stripe = Image.new("L", (box[2] - box[0], box[3] - box[1]), 0)
        sd = ImageDraw.Draw(stripe)
        step = self.px(9)
        for k in range(-stripe.height, stripe.width + stripe.height, step):
            sd.line([k, 0, k + stripe.height, stripe.height], fill=255, width=self.px(5))
        self.decal.paste(stripe, (box[0], box[1]))
        self.ink_rect(box, self.px(2))

    def hatch(self, region, taken, gap, thin):
        d = self.px(self.rng.uniform(40, 80))
        box = self._place(region, d, d, taken, gap)
        if box is None:
            return
        self.d_height.ellipse(box, fill=150)
        self.d_ink.ellipse(box, outline=255, width=thin)
        m = int(d * 0.3)
        self.d_ink.ellipse([box[0] + m, box[1] + m, box[2] - m, box[3] - m], outline=255, width=max(2, thin // 2))

    # -- output -----------------------------------------------------------
    def _wrap_blur(self, img, radius):
        """Gaussian blur that wraps around the edges, keeping the texture tileable."""
        tiled = Image.new("L", (self.w * 3, self.h * 3))
        for i in range(3):
            for j in range(3):
                tiled.paste(img, (i * self.w, j * self.h))
        tiled = tiled.filter(ImageFilter.GaussianBlur(radius))
        return tiled.crop((self.w, self.h, self.w * 2, self.h * 2))

    def finish(self, name, palette, out_dir=OUT):
        ink = np.asarray(self.ink, np.float32) / 255
        inset = np.asarray(self.inset, np.float32) / 255
        tone = np.asarray(self.tone, np.float32) / 255
        decal = np.asarray(self.decal, np.float32) / 255
        # Soft shadowing along the linework, like inked panel gaps.
        shadow = np.asarray(self._wrap_blur(self.ink, self.px(6)), np.float32) / 255
        tone = np.clip(tone * (1.0 - 0.35 * shadow), 0, 0.8)
        tone = np.where(decal > 0.5, 1.0, tone)
        height = np.asarray(self._wrap_blur(self.height, self.px(2.5)), np.float32) / 255

        rgba = np.stack([inset, ink, tone, height], axis=-1)
        img = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")
        img = img.resize(self.out_size, Image.LANCZOS)
        out_dir.mkdir(parents=True, exist_ok=True)
        img.save(out_dir / f"{name}.png", optimize=True)

        # Preview in the reference palette (what the shader produces, unlit).
        base, inset_col, ink_col, decal_col = (np.array(c, np.float32) for c in palette)
        shade = 0.82 + 0.26 * np.clip(tone / 0.8, 0, 1)
        col = (base * (1 - inset[..., None]) + inset_col * inset[..., None]) * shade[..., None]
        col = col * (1 - decal[..., None]) + decal_col * decal[..., None]
        col = col * (1 - ink[..., None]) + ink_col * ink[..., None]
        prev = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB").resize(self.out_size, Image.LANCZOS)
        prev.save(out_dir / f"{name}_preview.png", optimize=True)
        print(f"wrote {name}.png and {name}_preview.png  {self.out_size[0]}x{self.out_size[1]}")


HULL = {
    "max_depth": 7,
    "min_size": 55,
    "stop_chance": [0.0, 0.0, 0.0, 0.15, 0.35, 0.55, 0.7, 1.0],
    "long_cut_bias": 0.8,
    "line_widths": [7, 6, 5, 4.5, 4, 3.5, 3.5],
    "detail_width": 3.5,
    "notch_chance": 0.3,
    "chamfer_chance": 0.12,
    "kinds": {"inset": 0.24, "outline": 0.16,
              "vent": 0.12, "slots": 0.45, "decal": 0.07, "hatch": 0.05, "blank": 0.31},
}

NACELLE = {
    "max_depth": 5,
    "min_size": 60,
    "stop_chance": [0.0, 0.1, 0.25, 0.45, 0.6, 1.0],
    "long_cut_bias": 0.85,
    "line_widths": [6, 5, 4, 4, 3.5],
    "detail_width": 3.5,
    "notch_chance": 0.25,
    "chamfer_chance": 0.0,
    "kinds": {"inset": 0.3, "outline": 0.18,
              "vent": 0.12, "slots": 0.45, "decal": 0.1, "hatch": 0.0, "blank": 0.33},
}

REFERENCE_PALETTE = [
    (0.79, 0.82, 0.77),   # hull
    (0.50, 0.55, 0.57),   # inset plates
    (0.07, 0.08, 0.10),   # ink
    (0.85, 0.42, 0.40),   # decal
]


def hull_texture():
    c = PanelCanvas(1024, 1024, seed=4242)
    c.ink_rect([0, 0, c.w, c.h], c.px(HULL["line_widths"][0]))  # tile edges: half a seam per side
    c.subdivide(0, 0, c.w, c.h, 0, HULL)
    c.finish("hull_panels", REFERENCE_PALETTE)


def nacelle_texture():
    # u = around the nacelle (wraps), v = along it. Rings first, then panels per ring.
    c = PanelCanvas(1024, 640, seed=777)
    c.ink_rect([0, 0, c.w, c.h], c.px(NACELLE["line_widths"][0]))
    y = 0
    while y < c.h:
        ring = int(c.px(c.rng.uniform(90, 200)))
        y1 = min(c.h, y + ring) if c.h - (y + ring) > c.px(80) else c.h
        if y1 < c.h:
            c.ink_line(0, y1, c.w, y1, c.px(6))
        x = 0
        while x < c.w:
            pw = int(c.px(c.rng.uniform(180, 380)))
            x1 = min(c.w, x + pw) if c.w - (x + pw) > c.px(120) else c.w
            if x1 < c.w:
                c.ink_line(x1, y, x1, y1, c.px(5))
            c.subdivide(x, y, x1, y1, 2, NACELLE)
            x = x1
        y = y1
    c.finish("nacelle_panels", [REFERENCE_PALETTE[0], REFERENCE_PALETTE[1], REFERENCE_PALETTE[2], (0.95, 0.55, 0.15)])


if __name__ == "__main__":
    hull_texture()
    nacelle_texture()
