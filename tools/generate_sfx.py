"""Synthesizes the fighter's sound effects into res://game/audio/.

Run from the project root:  uv run --no-project --with numpy python tools/generate_sfx.py

Loops are built so they repeat seamlessly: tonal parts use frequencies with a whole
number of cycles per loop, and noise beds are synthesized in the frequency domain
(an inverse FFT is inherently periodic). Each looping file carries a RIFF 'smpl'
chunk, so Godot's importer (loop mode "Detect From WAV") loops it automatically.

The engine loop is a recording, not synthesized here: see make_engine_loop.py.
"""

import struct
import zlib
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "game" / "audio"
SEED = 20261004
# Reseeded per sound in __main__, so editing one sound never changes another's noise.
rng = np.random.default_rng(SEED)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def periodic_noise(seconds, shape):
    """Noise whose spectrum magnitude follows shape(freqs); loops perfectly."""
    n = int(SR * seconds)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    mags = shape(np.maximum(freqs, 1.0))
    mags[0] = 0.0
    phases = rng.uniform(0, 2 * np.pi, len(freqs))
    sig = np.fft.irfft(mags * np.exp(1j * phases), n)
    return sig / np.max(np.abs(sig))


def band(freqs, center, width):
    return np.exp(-0.5 * ((np.log(freqs) - np.log(center)) / width) ** 2)


def one_pole_lowpass(x, cutoffs):
    """Lowpass with a per-sample cutoff (Hz), for sweeps."""
    out = np.empty_like(x)
    a = 1.0 - np.exp(-2 * np.pi * np.asarray(cutoffs) / SR)
    a = np.broadcast_to(a, x.shape)
    y = 0.0
    for i in range(len(x)):
        y += a[i] * (x[i] - y)
        out[i] = y
    return out


def normalize(x, peak_db=-3.0):
    return x / np.max(np.abs(x)) * 10 ** (peak_db / 20)


def write_wav(name, signal, loop=False):
    if not loop:
        fade = min(len(signal), int(SR * 0.03))
        signal = signal.copy()
        signal[-fade:] *= np.linspace(1, 0, fade)
    data =(np.clip(signal, -1, 1) * 32767).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(data)) + data
    if loop:
        # 'smpl' chunk: one forward loop over the whole file.
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(signal) - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    riff = b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_bytes(riff)
    print(f"wrote {name}  ({len(signal) / SR:.2f}s{', loop' if loop else ''})")


def wind_loop():
    secs = 3.0
    t = t_axis(secs)
    gust = periodic_noise(secs, lambda f: band(f, 700, 0.8) + 0.5 * band(f, 2500, 0.5))
    swell = 1 + 0.35 * np.sin(2 * np.pi * (2 / secs) * t) + 0.15 * np.sin(2 * np.pi * (5 / secs) * t + 1)
    return normalize(gust * swell, -5)


def afterburner_loop():
    # Deep roar plus sparse crackle.
    secs = 2.0
    roar = periodic_noise(secs, lambda f: band(f, 120, 1.0) + 0.6 * band(f, 600, 0.7))
    crackle = np.zeros_like(roar)
    for pos in rng.integers(0, len(roar) - 400, 90):
        crackle[pos:pos + 400] += rng.uniform(-1, 1) * np.exp(-np.arange(400) / 60) * rng.normal(size=400)
    return normalize(roar + 0.35 * crackle, -3)


def boost_ignite():
    # Low thump + a whoosh whose brightness sweeps upward.
    secs = 1.4
    t = t_axis(secs)
    thump_freq = 40 + 90 * np.exp(-t * 12)
    thump = np.sin(2 * np.pi * np.cumsum(thump_freq) / SR) * np.exp(-t * 7)
    noise = rng.normal(size=len(t))
    cutoff = 300 + 5000 * (1 - np.exp(-t * 5))
    whoosh = one_pole_lowpass(noise, cutoff)
    whoosh = whoosh / np.max(np.abs(whoosh))
    env = np.minimum(t / 0.05, 1) * np.exp(-t * 2.2)
    return normalize(0.9 * thump + 0.8 * whoosh * env, -2)


def airbrake():
    # Mechanical clunk, then a descending hiss as the flaps bite.
    secs = 1.1
    t = t_axis(secs)
    clunk = np.sin(2 * np.pi * 90 * t) * np.exp(-t * 40) + 0.5 * rng.normal(size=len(t)) * np.exp(-t * 150)
    noise = rng.normal(size=len(t))
    hiss = noise - one_pole_lowpass(noise, 900)  # highpass
    hiss = one_pole_lowpass(hiss, 7000 - 4500 * t / secs)
    hiss = hiss / np.max(np.abs(hiss))
    env = np.minimum(t / 0.04, 1) * np.exp(-t * 2.8)
    return normalize(0.7 * clunk + 0.6 * hiss * env, -3)


def boost_empty():
    # Short falling buzz: "no fuel".
    secs = 0.3
    t = t_axis(secs)
    freq = 220 - 90 * t / secs
    phase = 2 * np.pi * np.cumsum(freq) / SR
    buzz = np.sign(np.sin(phase)) * 0.6 + np.sin(2 * phase) * 0.4
    buzz = one_pole_lowpass(buzz, 2500)
    env = np.minimum(t / 0.01, 1) * np.minimum((secs - t) / 0.05, 1)
    return normalize(buzz * env, -6)


def warning_beep():
    # Two quick beeps per 0.6 s loop.
    secs = 0.6
    t = t_axis(secs)
    sig = np.zeros_like(t)
    for start in (0.0, 0.16):
        seg = (t >= start) & (t < start + 0.1)
        local = t[seg] - start
        tone = np.sin(2 * np.pi * 1250 * local) + 0.3 * np.sin(2 * np.pi * 2500 * local)
        fade = np.minimum(local / 0.005, 1) * np.minimum((0.1 - local) / 0.005, 1)
        sig[seg] = tone * fade
    return normalize(sig, -8)


SOUNDS = [
    ("wind_loop.wav", wind_loop, True),
    ("afterburner_loop.wav", afterburner_loop, True),
    ("warning_beep_loop.wav", warning_beep, True),
    ("boost_ignite.wav", boost_ignite, False),
    ("airbrake.wav", airbrake, False),
    ("boost_empty.wav", boost_empty, False),
]

if __name__ == "__main__":
    for name, make, loop in SOUNDS:
        rng = np.random.default_rng([SEED, zlib.crc32(name.encode())])
        write_wav(name, make(), loop=loop)
