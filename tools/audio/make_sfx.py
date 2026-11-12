"""Generates placeholder WAV sound effects into audio/sfx/.

No dependencies beyond the standard library. Run from the repo root:
    python3 tools/audio/make_sfx.py
"""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "audio", "sfx")


def write_wav(name: str, samples: list[float]) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"{name}.wav")
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for s in samples:
            clamped = max(-1.0, min(1.0, s))
            frames.extend(struct.pack("<h", int(clamped * 32767)))
        wav.writeframes(bytes(frames))


def make_click() -> list[float]:
    n = int(SAMPLE_RATE * 0.025)
    rng = random.Random(101)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 180.0)
        tone = math.sin(2.0 * math.pi * (900.0 - 500.0 * (i / n)) * t)
        noise = (rng.random() * 2.0 - 1.0) * 0.35
        out.append((tone * 0.65 + noise) * env * 0.35)
    return out


def make_bell() -> list[float]:
    n = int(SAMPLE_RATE * 0.38)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        attack = min(1.0, t / 0.003)
        p1 = math.sin(2.0 * math.pi * 1568.0 * t) * math.exp(-t * 9.0)
        p2 = math.sin(2.0 * math.pi * 3136.0 * t) * math.exp(-t * 16.0) * 0.45
        p3 = math.sin(2.0 * math.pi * 4978.0 * t) * math.exp(-t * 28.0) * 0.25
        out.append(attack * (p1 + p2 + p3) * 0.38)
    return out


def make_stamp() -> list[float]:
    n = int(SAMPLE_RATE * 0.11)
    rng = random.Random(202)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 38.0)
        freq = 150.0 * math.exp(-t * 22.0) + 48.0
        thud = math.sin(2.0 * math.pi * freq * t)
        clack = (rng.random() * 2.0 - 1.0) * math.exp(-t * 95.0) * 0.7
        out.append((thud * 0.8 + clack) * env * 0.65)
    return out


def make_stamp_lift() -> list[float]:
    n = int(SAMPLE_RATE * 0.065)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.sin(math.pi * (i / n)) * math.exp(-t * 18.0)
        freq = 240.0 + 260.0 * (i / n)
        out.append(math.sin(2.0 * math.pi * freq * t) * env * 0.35)
    return out


def make_paper_slide() -> list[float]:
    n = int(SAMPLE_RATE * 0.16)
    rng = random.Random(303)
    out = []
    prev = 0.0
    prev2 = 0.0
    for i in range(n):
        u = i / n
        env = math.sin(math.pi * u) ** 1.4 * (0.75 + 0.25 * math.sin(2.0 * math.pi * 3.0 * u))
        white = rng.random() * 2.0 - 1.0
        # Simple band-pass smoothing for a soft paper rustle.
        filtered = 0.45 * white + 0.35 * prev - 0.2 * prev2
        prev2 = prev
        prev = white
        out.append(filtered * env * 0.38)
    return out


def make_scan() -> list[float]:
    n = int(SAMPLE_RATE * 0.12)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        if t < 0.05:
            freq = 1950.0
            env = math.exp(-t * 25.0)
        elif t < 0.065:
            freq = 0.0
            env = 0.0
        else:
            freq = 2600.0
            env = math.exp(-(t - 0.065) * 30.0)
        tone = math.sin(2.0 * math.pi * freq * t) if freq > 0.0 else 0.0
        out.append(tone * env * 0.32)
    return out


def make_flag() -> list[float]:
    n = int(SAMPLE_RATE * 0.085)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        freq = 880.0 if t < 0.04 else 1320.0
        local_t = t if t < 0.04 else t - 0.04
        env = math.exp(-local_t * 45.0)
        out.append(math.sin(2.0 * math.pi * freq * t) * env * 0.32)
    return out


def make_correct() -> list[float]:
    n = int(SAMPLE_RATE * 0.20)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        if t < 0.085:
            freq = 523.25  # C5
            env = math.exp(-t * 14.0)
        else:
            freq = 783.99  # G5
            env = math.exp(-(t - 0.085) * 14.0)
        s = math.sin(2.0 * math.pi * freq * t) + 0.25 * math.sin(2.0 * math.pi * freq * 2.0 * t)
        out.append(s * env * 0.32)
    return out


def make_wrong() -> list[float]:
    n = int(SAMPLE_RATE * 0.24)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        freq = 220.0 if t < 0.10 else 164.81
        local_t = t if t < 0.10 else t - 0.10
        env = math.exp(-local_t * 12.0)
        # Soft triangle/saw blend for a retro buzzer feel.
        s = 0.65 * math.sin(2.0 * math.pi * freq * t) + 0.35 * math.sin(2.0 * math.pi * freq * 3.0 * t)
        out.append(s * env * 0.36)
    return out


def make_alert() -> list[float]:
    n = int(SAMPLE_RATE * 0.24)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        if t < 0.11:
            freq = 659.25  # E5
            env = math.exp(-t * 14.0)
        else:
            freq = 880.0   # A5
            env = math.exp(-(t - 0.11) * 12.0)
        s = math.sin(2.0 * math.pi * freq * t) + 0.2 * math.sin(2.0 * math.pi * freq * 2.0 * t)
        out.append(s * env * 0.32)
    return out


def main() -> None:
    sounds = {
        "click": make_click(),
        "bell": make_bell(),
        "stamp": make_stamp(),
        "stamp_lift": make_stamp_lift(),
        "paper_slide": make_paper_slide(),
        "scan": make_scan(),
        "flag": make_flag(),
        "correct": make_correct(),
        "wrong": make_wrong(),
        "alert": make_alert(),
    }
    for name, samples in sounds.items():
        write_wav(name, samples)
    print(f"Wrote {len(sounds)} WAV files to {os.path.relpath(OUT_DIR)}")


if __name__ == "__main__":
    main()

