"""Builds res://game/audio/engine_loop.ogg from a downloaded recording.

Source: "Spaceship hum low frequency" by AudioPapkin, Pixabay Content License
https://pixabay.com/sound-effects/film-special-effects-spaceship-hum-low-frequency-296518/

The licence forbids redistributing the sound on its own, so the MP3 isn't committed.
Download it into tools/source_audio/ (git-ignored), then run from the project root:

    uv run --no-project --with numpy --with imageio-ffmpeg python tools/make_engine_loop.py

The recording's last second fades out, so that is trimmed, and the ends are crossfaded
into each other so the loop has no seam. Godot loops the OGG through its import setting
(`loop=true` in engine_loop.ogg.import).
"""

import subprocess
from pathlib import Path

import imageio_ffmpeg
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "tools" / "source_audio" / "audiopapkin-spaceship-hum-low-frequency-296518.mp3"
OUT = ROOT / "game" / "audio" / "engine_loop.ogg"
SR = 44100
TRIM_START = 0.25  # seconds dropped from the start (mp3 encoder warm-up)
TRIM_END = 1.25    # seconds dropped from the end (fade-out)
CROSSFADE = 2.0    # seconds over which the tail blends into the head
OGG_QUALITY = 5    # libvorbis -q (about 160 kbit/s stereo)

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()


def decode(path):
    raw = subprocess.run(
        [FFMPEG, "-hide_banner", "-loglevel", "error", "-i", str(path),
         "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
        capture_output=True, check=True,
    ).stdout
    return np.frombuffer(raw, "<f4").reshape(-1, 2).astype(np.float64)


def make_loop(x):
    seg = x[int(TRIM_START * SR):len(x) - int(TRIM_END * SR)]
    n = int(CROSSFADE * SR)
    # Equal-power curves: the hum is mostly noise-like, so the two ends add in power.
    ramp = np.linspace(0.0, np.pi / 2, n)[:, None]
    loop = seg[:-n].copy()
    loop[:n] = seg[:n] * np.sin(ramp) + seg[-n:] * np.cos(ramp)
    # Playback runs loop[-1] = seg[-n-1] -> loop[0] ~ seg[-n]: continuous by construction.
    return loop


def encode(x, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
         "-f", "f32le", "-ac", "2", "-ar", str(SR), "-i", "-",
         "-c:a", "libvorbis", "-q:a", str(OGG_QUALITY), str(path)],
        input=np.clip(x, -1, 1).astype("<f4").tobytes(), check=True,
    )


if __name__ == "__main__":
    if not SOURCE.exists():
        raise SystemExit(f"missing {SOURCE.relative_to(ROOT)}; download it from the URL above")
    loop = make_loop(decode(SOURCE))
    encode(loop, OUT)
    print(f"wrote {OUT.relative_to(ROOT)}  ({len(loop) / SR:.2f}s loop, {OUT.stat().st_size // 1024} KiB)")
