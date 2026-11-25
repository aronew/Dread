#!/usr/bin/env python3
"""Procedural placeholder SFX generator for Dread.

Writes 16-bit mono WAVs into assets/audio/sfx/. Every file is a placeholder: drop
your own sound with the same basename (wav/ogg/mp3) to replace it.

    python3 tools/gen_sfx.py
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")
rng = np.random.default_rng(7)


def T(dur):
    return np.arange(int(SR * dur)) / SR


def env(t, attack=0.002, decay=0.1):
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-5))


def sweep(t, f0, f1, curve=4.0, shape="sine"):
    dur = t[-1] if len(t) else 1.0
    f = f1 + (f0 - f1) * np.exp(-t / max(dur / curve, 1e-5))
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "square":
        return np.sign(np.sin(ph))
    if shape == "saw":
        return 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    return np.sin(ph)


def noise(t):
    return rng.standard_normal(len(t))


def onepole_lp(x, cutoff):
    """cutoff: float Hz or array of Hz per sample."""
    cut = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1.0 - np.exp(-2 * np.pi * cut / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def hp(x, cutoff):
    return x - onepole_lp(x, cutoff)


def bp(x, lo, hi):
    return onepole_lp(hp(x, lo), hi)


def drive(x, amount=2.0):
    return np.tanh(x * amount) / np.tanh(amount)


def room(x, mix=0.18, length=0.25):
    out = np.concatenate([x, np.zeros(int(SR * length))])
    wet = np.zeros_like(out)
    for d, g in [(0.029, 0.5), (0.037, 0.42), (0.053, 0.35), (0.071, 0.28), (0.097, 0.2)]:
        n = int(d * SR)
        k = 1
        while n * k < len(out) and g ** k > 0.01:
            wet[n * k:] += out[: len(out) - n * k] * (g ** k)
            k += 1
    return out * (1 - mix) + onepole_lp(wet, 3500) * mix


def pad(x, dur):
    n = int(SR * dur)
    return x[:n] if len(x) >= n else np.concatenate([x, np.zeros(n - len(x))])


def mixdown(*parts):
    n = max(len(p) for p in parts)
    return sum(pad(p, n / SR) for p in parts)


def save(name, x, peak=0.92):
    x = np.asarray(x, dtype=float)
    fade = min(len(x), int(0.01 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    m = np.max(np.abs(x)) or 1.0
    data = (x / m * peak * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  {name}.wav  {len(x) / SR:.2f}s")


def gen():
    os.makedirs(OUT, exist_ok=True)

    t = T(0.28)
    thump = sweep(t, 190, 45, 6) * env(t, 0.001, 0.05)
    crack = hp(noise(t), 1800) * env(t, 0.0005, 0.025)
    zap = sweep(t, 2400, 300, 8, "square") * env(t, 0.001, 0.03) * 0.25
    save("rifle_fire", room(drive(thump * 1.1 + crack * 0.7 + zap, 2.5), 0.12, 0.15))

    t = T(0.5)
    boom = sweep(t, 120, 32, 5) * env(t, 0.002, 0.14)
    blast = onepole_lp(noise(t), np.linspace(6000, 400, len(t))) * env(t, 0.001, 0.12)
    plasma = sweep(t, 1600, 120, 6, "saw") * env(t, 0.001, 0.06) * 0.3
    save("shotgun_fire", room(drive(boom * 1.2 + blast * 1.3 + plasma, 3.0), 0.15, 0.25))

    t = T(0.09)
    save("dry_fire", bp(noise(t), 1500, 5000) * env(t, 0.0005, 0.01) + sweep(t, 900, 600) * env(t, 0.001, 0.015) * 0.4, 0.5)

    t = T(0.1)
    save("bullet_impact", bp(noise(t), 2000, 7000) * env(t, 0.0005, 0.018) + sweep(t, 3200, 1800) * env(t, 0.0, 0.01) * 0.3, 0.6)

    t = T(0.18)
    squelch = onepole_lp(noise(t), 900 + 700 * np.sin(t * 90)) * env(t, 0.002, 0.05)
    save("flesh_hit", drive(squelch * 1.5 + sweep(t, 320, 110) * env(t, 0.001, 0.05) * 0.8, 2.0), 0.7)

    t = T(0.35)
    ping = sum(np.sin(2 * np.pi * f * t) * env(t, 0.0005, d) for f, d in [(1250, 0.12), (1870, 0.09), (2620, 0.06)])
    save("crit_hit", ping * 0.6 + pad(onepole_lp(noise(T(0.1)), 1200) * env(T(0.1), 0.001, 0.03), 0.35), 0.8)

    t = T(0.26)
    shape = np.sin(np.pi * np.clip(t / 0.24, 0, 1)) ** 2
    cut = 400 + 3800 * np.sin(np.pi * np.clip(t / 0.24, 0, 1))
    hum = sweep(t, 220, 900, 2, "saw") * shape * 0.12
    save("melee_swing", onepole_lp(hp(noise(t), 300), cut) * shape * 1.6 + hum, 0.75)

    t = T(0.4)
    thud = sweep(t, 140, 38, 5) * env(t, 0.001, 0.08)
    crunch = drive(bp(noise(t), 300, 3500) * env(t, 0.001, 0.05), 4.0)
    ring = sum(np.sin(2 * np.pi * f * t) * env(t, 0.001, 0.15) for f in (620, 935)) * 0.2
    save("melee_hit", room(drive(thud * 1.4 + crunch + ring, 2.0), 0.15, 0.2))

    t = T(0.9)
    swell = onepole_lp(noise(t), 2000) * np.clip(t / 0.08, 0, 1) * np.exp(-t / 0.25)
    boom = sweep(t, 90, 24, 4) * env(t, 0.003, 0.3)
    crunch = drive(bp(noise(t), 200, 3000) * env(t, 0.001, 0.08), 5.0)
    ring = sum(np.sin(2 * np.pi * f * t) * env(t, 0.002, 0.4) for f in (330, 495, 742)) * 0.15
    save("finisher", room(drive(boom * 1.5 + crunch + swell * 0.6 + ring, 2.0), 0.25, 0.4))

    t = T(0.32)
    shape = np.clip(t / 0.03, 0, 1) * np.exp(-t / 0.1)
    jet = onepole_lp(noise(t), np.linspace(800, 5000, len(t))) * shape
    save("dash", jet * 1.3 + sweep(t, 180, 700, 2) * shape * 0.3, 0.7)

    t = T(0.4)
    hiss = hp(noise(t), 2500) * np.clip(t / 0.01, 0, 1) * np.exp(-t / 0.15)
    fwoomp = sweep(t, 320, 70, 4) * env(t, 0.003, 0.08)
    save("rocket_launch", hiss * 0.6 + fwoomp, 0.7)

    t = T(1.3)
    boom = sweep(t, 75, 22, 4) * env(t, 0.003, 0.35)
    rumble = onepole_lp(noise(t), np.linspace(4000, 150, len(t))) * env(t, 0.001, 0.4)
    crackle = (rng.random(len(t)) > 0.995) * rng.standard_normal(len(t)) * np.exp(-t / 0.5)
    save("explosion", room(drive(boom * 1.6 + rumble * 1.4 + crackle * 2.0, 3.0), 0.2, 0.4))

    t = T(0.7)
    charge = sweep(t, 90, 900, 2, "saw") * env(t, 0.002, 0.18) * 0.5
    burst = onepole_lp(noise(t), 3000) * env(t, 0.001, 0.12)
    ring = np.sin(2 * np.pi * 180 * t) * env(t, 0.002, 0.3) * 0.6
    save("nova", room(drive(charge + burst + ring, 2.0), 0.25, 0.3))

    t = T(0.5)
    splat = onepole_lp(noise(t), 700 + 500 * np.sin(t * 60)) * env(t, 0.002, 0.09)
    gurgle = sweep(t, 220, 55, 3) * env(t, 0.003, 0.12) * (0.6 + 0.4 * np.sin(2 * np.pi * 35 * t))
    save("enemy_die", room(drive(splat * 1.6 + gurgle, 2.5), 0.12, 0.2), 0.8)

    t = T(0.32)
    spit = bp(noise(t), 500, 2200) * env(t, 0.003, 0.06)
    blob = sweep(t, 520, 180, 3) * env(t, 0.003, 0.08) * (0.7 + 0.3 * np.sin(2 * np.pi * 45 * t))
    save("enemy_spit", spit + blob, 0.7)

    t = T(0.5)
    sizzle = hp(noise(t), 3000) * env(t, 0.002, 0.18) * (0.6 + 0.4 * (rng.random(len(t)) > 0.7))
    save("spit_impact", sizzle + onepole_lp(noise(t), 500) * env(t, 0.001, 0.04), 0.6)

    t = T(1.1)
    vib = 1 + 0.06 * np.sin(2 * np.pi * 7 * t)
    growl = sweep(t, 95 * vib, 60 * vib, 2, "saw") * np.clip(t / 0.12, 0, 1) * np.exp(-t / 0.6)
    formant = bp(noise(t), 350, 950) * np.clip(t / 0.1, 0, 1) * np.exp(-t / 0.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * t))
    save("brute_roar", room(drive(onepole_lp(growl, 1400) * 1.2 + formant, 3.0), 0.25, 0.4))

    t = T(1.4)
    boom = sweep(t, 60, 18, 4) * env(t, 0.002, 0.45)
    rubble = onepole_lp(noise(t), np.linspace(2500, 120, len(t))) * env(t, 0.001, 0.35)
    crack = drive(hp(noise(t), 1000) * env(t, 0.0005, 0.03), 4.0)
    save("brute_slam", room(drive(boom * 2.0 + rubble * 1.2 + crack * 0.8, 3.5), 0.22, 0.45))

    t = T(0.34)
    vib = 1 + 0.12 * np.sin(2 * np.pi * 38 * t)
    scr = sweep(t, 950 * vib, 1700 * vib, 1.5, "saw") * env(t, 0.01, 0.12)
    save("swarmer_screech", onepole_lp(scr, 4200) * 0.8 + bp(noise(t), 1500, 5000) * env(t, 0.005, 0.08) * 0.4, 0.55)

    t = T(0.32)
    clank = sum(np.sin(2 * np.pi * f * t) * env(t, 0.0005, 0.07) for f in (410, 690, 1130)) * 0.5
    save("player_hurt", drive(clank + sweep(t, 160, 50) * env(t, 0.001, 0.06) + bp(noise(t), 400, 3000) * env(t, 0.0005, 0.03), 2.0), 0.8)

    t = T(0.3)
    arp = np.zeros(len(t))
    for i, f in enumerate((523, 659, 880, 1046)):
        tt = np.clip(t - i * 0.04, 0, None)
        arp += np.sin(2 * np.pi * f * tt) * env(tt, 0.002, 0.07) * (t >= i * 0.04)
    save("pickup_health", arp, 0.55)

    t = T(0.2)
    save("pickup_energy", (sweep(t, 400, 1700, 1.2) + sweep(t, 405, 1710, 1.2)) * env(t, 0.002, 0.06), 0.45)

    t = T(0.85)
    sw = np.clip(t / 0.7, 0, 1) ** 2 * np.exp(-np.maximum(t - 0.7, 0) / 0.05)
    drone = sweep(t, 45, 160, 1, "saw") * sw
    save("spawn_portal", onepole_lp(drone, 900) * 0.7 + onepole_lp(noise(t), 1500 + 3000 * sw) * sw * 0.6, 0.6)

    t = T(1.0)
    tone = np.where((t % 0.25) < 0.125, sweep(t, 440, 440, 1, "square"), sweep(t, 330, 330, 1, "square"))
    save("wave_start", onepole_lp(tone * np.clip(t / 0.01, 0, 1) * np.exp(-t / 0.6), 1800), 0.5)

    t = T(1.4)
    chord = sum(np.sin(2 * np.pi * f * t) * env(t, 0.01 + i * 0.06, 0.6) for i, f in enumerate((523, 659, 784, 1046)))
    save("wave_clear", room(chord, 0.3, 0.4), 0.55)

    t = T(0.16)
    clk = np.zeros(len(t))
    for start in (0.0, 0.07):
        tt = np.clip(t - start, 0, None)
        clk += bp(noise(t), 1200, 6000) * env(tt, 0.0005, 0.012) * (t >= start)
    save("weapon_switch", clk, 0.55)

    t = T(0.5)
    glass = sum(np.sin(2 * np.pi * f * t) * env(t, 0.0005, 0.15) for f in (1580, 2370, 3160)) * 0.4
    save("stagger", room(glass + sweep(t, 120, 40) * env(t, 0.001, 0.12) + hp(noise(t), 3000) * env(t, 0.0005, 0.04), 0.2, 0.2), 0.7)


if __name__ == "__main__":
    gen()
