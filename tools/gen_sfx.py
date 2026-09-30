#!/usr/bin/env python3
"""Synthesizes the game's sound effects into assets/audio/sfx/*.wav.

Every sound is built from oscillators, filtered noise and envelopes, so the
output is fully reproducible: `python3 tools/gen_sfx.py` from the repo root.
"""

from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"
rng = np.random.default_rng(11)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, attack, decay_curve):
    """Linear attack, exponential decay; decay_curve is the time constant in s."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / decay_curve)


def sweep(f0, f1, dur, shape="sine"):
    t = t_axis(dur)
    f = f0 * (f1 / f0) ** (t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "sine":
        return np.sin(ph)
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1) - 1
    return np.sign(np.sin(ph))


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def band(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "bandpass", fs=SR, output="sos"), x)


def low(x, fc, order=2):
    return sosfilt(butter(order, fc, "lowpass", fs=SR, output="sos"), x)


def high(x, fc, order=2):
    return sosfilt(butter(order, fc, "highpass", fs=SR, output="sos"), x)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def delay(x, s):
    return np.concatenate([np.zeros(int(SR * s)), x])


def room(x, taps=((0.031, 0.35), (0.057, 0.25), (0.093, 0.18), (0.141, 0.1))):
    """Cheap basement reflections: a few low-passed echoes."""
    wet = [delay(low(x, 2500) * g, d) for d, g in taps]
    return mix(x, *wet)


def save(name, x, peak=0.85):
    x = x - np.mean(x)
    # Short fade-out so no sound ends with a click.
    fade = min(len(x), int(SR * 0.01))
    x[-fade:] *= np.linspace(1, 0, fade)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    OUT.mkdir(parents=True, exist_ok=True)
    wavfile.write(OUT / f"{name}.wav", SR, (x * 32767).astype(np.int16))
    print(f"{name}.wav  {len(x) / SR:.2f}s")


def step(dur, lo, hi, scuff):
    """Shoe on gritty concrete: a soft heel thump, a gritty scrape."""
    n = int(SR * dur)
    heel = low(noise(dur), 300) * env(n, 0.002, 0.02)
    grit = band(noise(dur), lo, hi) * env(n, 0.004, scuff)
    return room(mix(heel * 1.2, grit * 0.6))


def step_walk():
    return step(0.18, 1200, 5000, 0.03)


def step_run():
    # Harder impact and a longer scuff; louder because the stalker hears it.
    return mix(step(0.22, 900, 4500, 0.05), sweep(120, 60, 0.1) * env(int(SR * 0.1), 0.001, 0.03))


def stalker_step():
    # Heavy, slow boot: deep thud, a creak of leather and a drag of the sole.
    d = 0.6
    n = int(SR * d)
    thud = sweep(85, 40, d) * env(n, 0.003, 0.08)
    body = low(noise(d), 180) * env(n, 0.002, 0.05)
    drag = band(noise(0.35), 500, 2200) * env(int(SR * 0.35), 0.08, 0.08)
    creak = band(sweep(260, 190, 0.15, "saw"), 300, 1400) * env(int(SR * 0.15), 0.02, 0.04)
    return room(mix(thud * 1.1, body, delay(drag * 0.35, 0.05), delay(creak * 0.2, 0.02)))


def heartbeat():
    # Lub-dub: two low sine thumps, the second softer.
    def beat(f, g):
        d = 0.16
        return sweep(f, f * 0.6, d) * env(int(SR * d), 0.004, 0.035) * g
    return low(mix(beat(62, 1.0), delay(beat(55, 0.7), 0.17)), 200)


def key():
    # Metallic jingle: inharmonic partials, two quick strikes.
    def ring(f0):
        d = 0.9
        t = t_axis(d)
        partials = [(1.0, 1.0), (2.76, 0.5), (5.4, 0.3), (8.93, 0.15)]
        return sum(np.sin(2 * np.pi * f0 * r * t) * g * env(len(t), 0.001, 0.25 / r ** 0.5) for r, g in partials)
    return room(mix(ring(1480) * 0.7, delay(ring(1760) * 0.6, 0.09)))


def battery():
    click = high(noise(0.015), 2500) * np.linspace(1, 0, int(SR * 0.015))
    hum = low(sweep(110, 220, 0.4, "saw"), 1200) * env(int(SR * 0.4), 0.05, 0.12)
    return mix(click, delay(click * 0.7, 0.07), delay(hum * 0.4, 0.08))


def click():
    # Flashlight switch.
    a = high(noise(0.008), 3000) * np.linspace(1, 0, int(SR * 0.008))
    b = band(noise(0.02), 800, 3000) * env(int(SR * 0.02), 0.001, 0.005)
    return mix(a, delay(b * 0.8, 0.012))


def door():
    # Chains dropping, a heavy lock, then a long iron scrape as the door rises.
    d = 3.0
    n = int(SR * d)
    t = t_axis(d)
    clank = mix(*(delay(band(noise(0.2), 1500, 6000) * env(int(SR * 0.2), 0.001, 0.04) * g, s)
                  for s, g in ((0.0, 1.0), (0.12, 0.7), (0.21, 0.8), (0.33, 0.5))))
    lock = sweep(140, 70, 0.3) * env(int(SR * 0.3), 0.002, 0.07)
    wobble = 1 + 0.25 * np.sin(2 * np.pi * 3.1 * t) + 0.15 * np.sin(2 * np.pi * 7.3 * t)
    scrape = band(noise(d), 300, 1400) * wobble
    squeal = band(sweep(620, 540, d, "saw"), 500, 2500) * 0.15 * wobble
    shape = np.clip((t - 0.5) / 0.3, 0, 1) * np.clip((d - t) / 0.6, 0, 1)
    return room(mix(clank * 0.8, delay(lock, 0.4), (scrape + squeal) * shape * 0.6))


def alert():
    # The stalker notices: a rising, detuned saw swell with a breathy hiss.
    d = 1.3
    t = t_axis(d)
    swell = sum(sweep(70 * r, 110 * r, d, "saw") for r in (1.0, 1.013, 1.5, 2.02))
    swell = low(swell, 1600)
    hiss = band(noise(d), 2000, 7000) * 0.25
    shape = np.clip(t / 0.4, 0, 1) ** 2 * np.clip((d - t) / 0.3, 0, 1)
    return room(mix(swell * 0.6, hiss) * shape)


def caught():
    # Loud sting: a clashing cluster plus a noise burst, dropping in pitch.
    d = 2.2
    cluster = sum(sweep(f, f * 0.7, d, "saw") for f in (220, 233, 311, 330, 466))
    cluster = low(cluster, 3000) * env(int(SR * d), 0.005, 0.6)
    burst = band(noise(0.6), 200, 5000) * env(int(SR * 0.6), 0.002, 0.15)
    boom = sweep(70, 30, 1.2) * env(int(SR * 1.2), 0.002, 0.35)
    return room(mix(cluster * 0.5, burst * 0.8, boom * 1.2))


def escape():
    # Relief: a slow, open major chord that swells and fades.
    d = 3.5
    t = t_axis(d)
    chord = sum(sweep(f, f, d, "tri") * g for f, g in ((196.0, 1.0), (293.66, 0.7), (392.0, 0.6), (493.88, 0.4)))
    shape = np.clip(t / 0.8, 0, 1) * np.clip((d - t) / 1.8, 0, 1)
    return room(low(chord, 2500) * shape)


if __name__ == "__main__":
    for name, fn in [
        ("step_walk", step_walk), ("step_run", step_run), ("stalker_step", stalker_step),
        ("heartbeat", heartbeat), ("key", key), ("battery", battery), ("click", click),
        ("door", door), ("alert", alert), ("caught", caught), ("escape", escape),
    ]:
        save(name, fn())
