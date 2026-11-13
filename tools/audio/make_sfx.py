"""Generates placeholder WAV sound effects into audio/sfx/ and looping BGM into audio/bgm/.

No dependencies beyond the standard library. Run from the repo root:
    python3 tools/audio/make_sfx.py
"""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 22050
BGM_RATE = 16000
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "audio", "sfx")
BGM_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "audio", "bgm")


def write_wav(folder: str, name: str, samples: list[float], rate: int = SAMPLE_RATE) -> None:
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"{name}.wav")
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
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


def _epiano(freq: float, local_t: float, duration: float) -> float:
    if freq <= 0.0 or local_t < 0.0 or local_t >= duration:
        return 0.0
    attack = min(1.0, local_t / 0.015)
    release = min(1.0, (duration - local_t) / 0.04)
    decay = math.exp(-local_t * 2.4)
    fundamental = math.sin(2.0 * math.pi * freq * local_t)
    overtone = 0.25 * math.sin(2.0 * math.pi * freq * 2.0 * local_t) * math.exp(-local_t * 5.0)
    tine = 0.08 * math.sin(2.0 * math.pi * freq * 3.0 * local_t) * math.exp(-local_t * 10.0)
    return attack * release * decay * (fundamental + overtone + tine)


def make_menu_bgm() -> list[float]:
    # Warm 4-bar lo-fi electric piano loop (8.0 seconds, 120 BPM, 2.0s per bar).
    # Progression: Fmaj7 -> Em7 -> Dm7 -> G13 (in C major).
    bar_sec = 2.0
    total_sec = bar_sec * 4
    n = int(BGM_RATE * total_sec)
    chords = [
        (174.61, [261.63, 329.63, 349.23, 440.00]),  # Fmaj7
        (164.81, [246.94, 293.66, 329.63, 392.00]),  # Em7
        (146.83, [261.63, 293.66, 349.23, 440.00]),  # Dm7
        (196.00, [246.94, 329.63, 349.23, 440.00]),  # G13
    ]
    melody = [
        # (start_sec, duration_sec, freq)
        (0.0, 0.75, 523.25), (0.75, 0.75, 440.00), (1.5, 0.5, 392.00),
        (2.0, 1.0, 493.88), (3.0, 1.0, 392.00),
        (4.0, 0.75, 440.00), (4.75, 0.75, 349.23), (5.5, 0.5, 329.63),
        (6.0, 1.25, 392.00), (7.25, 0.75, 329.63),
    ]
    out = []
    for i in range(n):
        t = i / BGM_RATE
        bar_idx = min(3, int(t / bar_sec))
        bar_t = t - bar_idx * bar_sec
        bass_freq, notes = chords[bar_idx]
        sample = 0.0
        # Warm sub-bass on beats 1 and 3
        beat_t = bar_t % 1.0
        sample += _epiano(bass_freq, beat_t, 0.95) * 0.22
        # Soft rolled chord
        for k, f in enumerate(notes):
            sample += _epiano(f, bar_t - k * 0.03, bar_sec - k * 0.03) * 0.10
        # Gentle top melody
        for start, dur, mfreq in melody:
            if start <= t < start + dur:
                sample += _epiano(mfreq, t - start, dur) * 0.14
        out.append(sample * 0.65)
    return out


def make_shift_bgm() -> list[float]:
    # Steady, cozy 4-bar office work loop (8.0 seconds, 120 BPM, 0.25s per eighth note).
    # Progression: Cmaj7 -> Am7 -> Dm7 -> G7.
    bar_sec = 2.0
    step_sec = 0.25
    total_sec = bar_sec * 4
    n = int(BGM_RATE * total_sec)
    chords = [
        (130.81, [261.63, 329.63, 392.00, 493.88]),  # Cmaj7
        (110.00, [261.63, 329.63, 392.00, 440.00]),  # Am7
        (146.83, [261.63, 293.66, 349.23, 440.00]),  # Dm7
        (98.00,  [246.94, 293.66, 349.23, 392.00]),  # G7
    ]
    arp_pattern = [0, 1, 2, 3, 2, 1, 2, 0]
    out = []
    for i in range(n):
        t = i / BGM_RATE
        bar_idx = min(3, int(t / bar_sec))
        bar_t = t - bar_idx * bar_sec
        step_idx = int(bar_t / step_sec) % 8
        step_t = bar_t - step_idx * step_sec
        bass_freq, notes = chords[bar_idx]
        sample = 0.0
        # Walking pulse bass every half-second
        half_t = bar_t % 0.5
        b_mult = 1.0 if int(bar_t / 0.5) % 2 == 0 else 1.5
        sample += _epiano(bass_freq * b_mult, half_t, 0.48) * 0.20
        # Sustained pad chord
        for f in notes:
            sample += _epiano(f, bar_t, bar_sec) * 0.06
        # Gentle eighth-note Rhodes arpeggio
        arp_freq = notes[arp_pattern[step_idx]] * (2.0 if step_idx in (3, 6) else 1.0)
        sample += _epiano(arp_freq, step_t, step_sec * 0.95) * 0.12
        out.append(sample * 0.65)
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
        write_wav(OUT_DIR, name, samples, SAMPLE_RATE)
    bgm_tracks = {
        "menu": make_menu_bgm(),
        "shift": make_shift_bgm(),
    }
    for name, samples in bgm_tracks.items():
        write_wav(BGM_DIR, name, samples, BGM_RATE)
    print(f"Wrote {len(sounds)} SFX files and {len(bgm_tracks)} BGM files")


if __name__ == "__main__":
    main()
