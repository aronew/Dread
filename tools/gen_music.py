#!/usr/bin/env python3
"""Procedural placeholder combat music for Dread.

Renders a seamless 16-bar, 140 BPM dark-synth loop (A minor: Am - F - C - G)
with kick, clap, hats, a sidechain-pumping saw bass, a pad and an echoing arp
that enters for the second half. Writes assets/audio/music/combat_loop.ogg
(via ffmpeg/libvorbis). Replace it with your own track at any time.

    python3 tools/gen_music.py
"""
import os
import subprocess
import wave

import numpy as np

SR = 32000
BPM = 140
BEAT = 60.0 / BPM
BARS = 16
TOTAL = BARS * 4 * BEAT
N = int(SR * TOTAL)
TAIL = int(SR * 2.0)
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "music")
rng = np.random.default_rng(140)

CHORDS = [  # (bass root Hz, chord tones as semitones above A4=440)
    (55.00, [0, 3, 7]),      # Am
    (43.65, [-4, 0, 3]),     # F
    (65.41, [3, 7, 10]),     # C
    (49.00, [-2, 2, 5]),     # G
]


def T(dur):
    return np.arange(int(SR * dur)) / SR


def env(t, a, d):
    return np.clip(t / max(a, 1e-5), 0, 1) * np.exp(-np.maximum(t - a, 0) / max(d, 1e-5))


def onepole_lp(x, cutoff):
    cut = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1.0 - np.exp(-2 * np.pi * cut / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def saw(freq, t):
    return 2.0 * ((freq * t) % 1.0) - 1.0


def place(buf, sig, t0):
    i = int(round(t0 * SR))
    end = min(i + len(sig), len(buf))
    buf[i:end] += sig[: end - i]


def kick():
    t = T(0.35)
    f = 42 + 110 * np.exp(-t / 0.03)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.001, 0.16)
    click = rng.standard_normal(len(t)) * env(t, 0.0002, 0.003) * 0.3
    return np.tanh((body + click) * 1.6)


def clap():
    t = T(0.3)
    n = rng.standard_normal(len(t))
    burst = sum(env(np.maximum(t - k * 0.011, 0), 0.0005, 0.01) * (t >= k * 0.011) for k in range(3))
    tail = env(t, 0.004, 0.09)
    sig = n * (burst * 0.8 + tail * 0.6)
    return onepole_lp(sig - onepole_lp(sig, 900), 6500) * 0.9


def hat(open_=False):
    t = T(0.18 if open_ else 0.05)
    n = rng.standard_normal(len(t))
    return (n - onepole_lp(n, 6500)) * env(t, 0.0005, 0.06 if open_ else 0.014) * 0.35


def render():
    drums = np.zeros(N + TAIL)
    bass = np.zeros(N + TAIL)
    pad = np.zeros(N + TAIL)
    arp = np.zeros(N + TAIL)
    duck = np.ones(N + TAIL)
    k, c = kick(), clap()
    for bar in range(BARS):
        for b in range(4):
            t0 = (bar * 4 + b) * BEAT
            place(drums, k, t0)
            # sidechain envelope
            i = int(t0 * SR)
            dl = int(BEAT * 0.6 * SR)
            ramp = np.linspace(0.25, 1.0, dl) ** 1.5
            duck[i:i + dl] = np.minimum(duck[i:i + dl], ramp[: len(duck[i:i + dl])])
            if b in (1, 3):
                place(drums, c, t0)
            for s in range(4):
                accent = 1.0 if s == 2 else 0.55
                place(drums, hat(open_=(s == 2 and b % 2 == 1)) * accent, t0 + s * BEAT / 4)
        if bar % 8 == 7:  # snare roll fill
            for s in range(8):
                place(drums, c * (0.3 + s * 0.08), (bar * 4 + 2) * BEAT + s * BEAT / 4)

    step = BEAT / 4
    pattern = [0, 0, 12, 0, 0, 12, 0, 7, 0, 0, 12, 0, 0, 12, 7, 12]
    for bar in range(BARS):
        root, tones = CHORDS[(bar // 2) % 4]
        for s in range(16):
            t0 = (bar * 16 + s) * step
            t = T(step * 0.95)
            f = root * 2 ** (pattern[s] / 12.0)
            raw = (saw(f, t) + saw(f * 1.006, t)) * 0.5
            cut = 180 + 1600 * np.exp(-t / 0.05) + (300 if bar >= 8 else 0)
            note = onepole_lp(onepole_lp(raw, cut), cut) * env(t, 0.002, 0.09)
            place(bass, note, t0)
        # pad: chord tones an octave below A4
        t = T(BEAT * 8 + 0.4)
        chord = np.zeros(len(t))
        for semi in tones:
            f = 220.0 * 2 ** (semi / 12.0)
            chord += saw(f, t) + saw(f * 1.004, t + 0.13) + saw(f * 0.996, t + 0.37)
        shape = np.clip(t / 0.6, 0, 1) * np.clip((BEAT * 8 + 0.4 - t) / 0.4, 0, 1)
        if bar % 2 == 0:
            place(pad, onepole_lp(chord * shape, 1100) * 0.05, bar * 4 * BEAT)
        # arp in the second half
        if bar >= 8:
            order = tones + [tones[0] + 12, tones[1] + 12, tones[2] + 12, tones[1] + 12, tones[0] + 12]
            for s in range(16):
                semi = order[s % len(order)] + 12
                f = 440.0 * 2 ** (semi / 12.0) / 2
                t = T(step * 0.9)
                sq = np.sign(np.sin(2 * np.pi * f * t)) * 0.5 + saw(f * 1.003, t) * 0.5
                note = onepole_lp(sq, 2600) * env(t, 0.002, 0.07) * 0.13
                place(arp, note, (bar * 16 + s) * step)
    # arp echo (3/16 note, feedback)
    d = int(step * 3 * SR)
    echo = arp.copy()
    for k_ in range(1, 4):
        echo[d * k_:] += arp[: len(arp) - d * k_] * (0.38 ** k_)
    mix = drums * 0.9 + (bass * 0.55 + pad + echo) * duck
    # wrap the tail into the start so the loop is seamless
    out = mix[:N].copy()
    out[:TAIL] += mix[N:N + TAIL]
    out = np.tanh(out * 1.3) / np.tanh(1.3)
    out /= np.max(np.abs(out)) / 0.89
    return out


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    x = render()
    wav_path = os.path.join(OUT_DIR, "combat_loop.wav")
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    ogg_path = os.path.join(OUT_DIR, "combat_loop.ogg")
    subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", wav_path,
                    "-c:a", "libvorbis", "-q:a", "5", ogg_path], check=True)
    os.remove(wav_path)
    print(f"  combat_loop.ogg  {TOTAL:.2f}s  ({os.path.getsize(ogg_path) // 1024} KB)")


if __name__ == "__main__":
    main()
