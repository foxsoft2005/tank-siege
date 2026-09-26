"""
Generates all of the game's sound effects as .wav files in assets/sfx/.

This is OPTIONAL. The .wav files are already included, so you only need this
if you want to tweak a sound. Each sound is a small recipe of:
  - an oscillator (square / triangle / sine / noise)
  - a pitch sweep (start frequency -> end frequency)
  - a volume envelope (fast attack, then decay)
It's the same idea as classic tools like sfxr / jsfxr.

Usage (needs Python 3 + numpy):   python tools/make_sfx.py
Then switch back to Godot. It re-imports the changed files automatically.

Prefer a GUI? Try jsfxr (https://sfxr.me) or ChipTone and drop your .wav files
into assets/sfx/ with the same names.
"""

import os
import wave

import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
rng = np.random.default_rng(7)  # fixed seed = same sounds every time


# ------------------------------------------------------------------ building blocks

def t_axis(dur):
    return np.arange(int(RATE * dur)) / RATE


def sweep(f0, f1, dur, curve=1.0):
    """Frequency over time, going from f0 to f1 (curve > 1 = drops fast then slows)."""
    x = t_axis(dur) / dur
    return f0 + (f1 - f0) * x ** (1.0 / curve)


def osc(freqs, shape="square", duty=0.5):
    """Oscillator following a frequency array."""
    phase = np.cumsum(freqs / RATE) % 1.0
    if shape == "square":
        return np.where(phase < duty, 1.0, -1.0)
    if shape == "triangle":
        return 4.0 * np.abs(phase - 0.5) - 1.0
    if shape == "saw":
        return 2.0 * phase - 1.0
    return np.sin(2 * np.pi * phase)


def noise(dur, steps=None):
    """White noise. With `steps`, noise is held for N samples (grittier, NES-like)."""
    n = rng.uniform(-1, 1, int(RATE * dur))
    if steps:
        n = np.repeat(n[::steps], steps)[: len(n)]
    return n


def lowpass(x, start_hz, end_hz=None):
    """Simple one-pole low-pass filter; the cutoff can slide over time."""
    end_hz = start_hz if end_hz is None else end_hz
    cut = np.linspace(start_hz, end_hz, len(x))
    a = 1.0 - np.exp(-2 * np.pi * cut / RATE)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def env(dur, attack=0.004, power=1.5):
    """Volume envelope: quick fade in, then decay to 0."""
    t = t_axis(dur)
    e = np.clip(t / attack, 0, 1) * (1.0 - t / dur) ** power
    return e


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def note(freq, dur, shape="square", duty=0.5, vol=1.0, power=1.2):
    return osc(np.full(int(RATE * dur), float(freq)), shape, duty) * env(dur, power=power) * vol


def melody(notes, step, shape="square", duty=0.5, hold=1.0):
    """notes: list of frequencies (0 = rest). Each lasts `step` seconds."""
    parts = []
    for f in notes:
        if f == 0:
            parts.append(np.zeros(int(RATE * step)))
        else:
            parts.append(note(f, step * hold, shape, duty, power=0.8))
            pad = int(RATE * step) - int(RATE * step * hold)
            if pad > 0:
                parts.append(np.zeros(pad))
    return np.concatenate(parts)


def save(name, x, vol=0.8):
    x = np.asarray(x, dtype=float)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * vol
    fade = min(len(x), int(RATE * 0.005))  # tiny fade-out to avoid clicks
    x[-fade:] *= np.linspace(1, 0, fade)
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print("wrote", name + ".wav", f"{len(x) / RATE:.2f}s")


# Note frequencies (Hz) for the jingles
C4, D4, E4, F4, G4, A4, B4 = 262, 294, 330, 349, 392, 440, 494
C5, D5, E5, F5, G5, A5, B5 = 523, 587, 659, 698, 784, 880, 988
C6, E6, G6, C7 = 1047, 1319, 1568, 2093


# ------------------------------------------------------------------ the sounds

def main():
    os.makedirs(OUT, exist_ok=True)

    # --- shooting
    d = 0.11
    save("shoot", mix(osc(sweep(1100, 260, d, 2.0), "square", 0.25) * env(d),
                      lowpass(noise(0.04), 4000) * env(0.04) * 0.5), 0.55)
    d = 0.13
    save("enemy_shoot", osc(sweep(700, 150, d, 2.0), "square", 0.5) * env(d), 0.4)
    d = 0.07
    save("drone_shoot", osc(sweep(1700, 900, d), "triangle") * env(d), 0.35)

    # --- impacts
    d = 0.1
    save("hit_brick", mix(lowpass(noise(d, 3), 2500, 600) * env(d, power=2),
                          osc(sweep(180, 90, d), "square") * env(d, power=3) * 0.4), 0.6)
    d = 0.22
    ping = mix(osc(np.full(int(RATE * d), 1850.0), "sine"),
               osc(np.full(int(RATE * d), 2780.0), "sine") * 0.6,
               osc(np.full(int(RATE * d), 4100.0), "sine") * 0.3) * env(d, power=3)
    save("hit_steel", mix(ping, lowpass(noise(0.02), 6000) * 0.6), 0.45)
    d = 0.08
    save("bounce", osc(sweep(420, 1300, d), "triangle") * env(d, power=1), 0.45)
    d = 0.12
    save("armor_hit", mix(note(196, d, "square", 0.3), note(293, d, "square", 0.5, 0.6),
                          lowpass(noise(0.03), 5000) * 0.4), 0.5)

    # --- explosions
    d = 0.45
    save("explode_small", mix(lowpass(noise(d, 2), 3000, 200) * env(d, power=1.6),
                              osc(sweep(240, 40, d, 2), "square") * env(d, power=3) * 0.35), 0.7)
    d = 1.1
    save("explode_big", mix(lowpass(noise(d, 4), 2000, 90) * env(d, attack=0.01, power=1.4),
                            osc(sweep(120, 30, d, 2), "square") * env(d, power=2) * 0.5,
                            lowpass(noise(0.12), 8000) * env(0.12) * 0.7), 0.85)

    # --- base / power-ups
    d = 0.3
    save("shield_block", osc(sweep(500, 1400, d) + 60 * np.sin(2 * np.pi * 30 * t_axis(d)), "sine")
         * env(d, power=1), 0.5)
    save("powerup_appear", melody([C5, E5, G5, C6], 0.05, "square", 0.25), 0.4)
    save("powerup_pickup", melody([G4, C5, E5, G5, C6, E6, G6], 0.045, "square", 0.5), 0.45)

    # --- jingles
    save("stage_start", melody([C5, 0, G4, C5, E5, G5, 0, E5, G5], 0.09, "square", 0.25, 0.85), 0.45)
    save("stage_clear", mix(melody([C5, E5, G5, C6, 0, G5, C6], 0.1, "square", 0.25, 0.9),
                            melody([C4, C4, E4, G4, 0, E4, G4], 0.1, "triangle") * 0.6), 0.5)
    save("game_over", mix(melody([G4, 0, F4, 0, E4, 0, C4, C4, C4], 0.16, "square", 0.5, 0.9),
                          melody([C4 / 2] * 9, 0.16, "triangle") * 0.5), 0.5)

    # --- UI
    save("ui_move", note(1400, 0.035, "square", 0.25, power=2), 0.3)
    save("ui_pick", melody([E5, B5], 0.06, "square", 0.25), 0.4)
    save("pause", melody([B5, 0, E5], 0.05, "square", 0.5), 0.35)

    # --- combo tick (the game raises its pitch as the combo grows)
    d = 0.09
    save("combo", mix(osc(sweep(900, 1500, d), "square", 0.25) * env(d, power=1.2),
                      osc(sweep(1800, 3000, d), "triangle") * env(d, power=2) * 0.4), 0.4)

    # --- boss: warning siren, heavy hit, and other new enemy sounds
    d = 1.6
    t = t_axis(d)
    siren = 700 + 250 * np.sign(np.sin(2 * np.pi * 2.5 * t))
    save("boss_warning", osc(siren, "square", 0.5) * np.clip(t / 0.05, 0, 1) * (1 - t / d) ** 0.3, 0.4)
    d = 0.12
    save("boss_hit", mix(osc(sweep(160, 70, d), "square") * env(d, power=2),
                         lowpass(noise(d, 2), 3000, 800) * env(d, power=2) * 0.7), 0.5)
    d = 0.14
    save("deflect", mix(osc(sweep(2400, 1600, d), "triangle") * env(d, power=2),
                        osc(np.full(int(RATE * d), 3100.0), "sine") * env(d, power=3) * 0.5), 0.4)
    save("repair", melody([E5, G5, B5], 0.05, "triangle"), 0.35)
    d = 0.25
    save("fuse", osc(sweep(900, 1400, d), "square", 0.125) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 24 * t_axis(d)))), 0.3)
    d = 0.18
    save("snipe", mix(osc(sweep(2600, 300, d, 3), "saw") * env(d, power=2),
                      lowpass(noise(0.05), 7000) * env(0.05) * 0.6), 0.5)
    save("scrap", melody([C6, G6, C7], 0.04, "square", 0.25), 0.35)
    d = 0.35
    wobble = 1 + 0.08 * np.sin(2 * np.pi * 18 * t_axis(d))
    save("teleport", mix(osc(sweep(300, 1800, d, 0.6) * wobble, "sine") * env(d, power=1.2),
                         osc(sweep(600, 3600, d, 0.6), "triangle") * env(d, power=2) * 0.3), 0.45)

    # --- secret code accepted: sparkly rising arpeggio
    save("cheat", mix(melody([C5, E5, G5, C6, E6, G6, C7, G6, C7], 0.04, "square", 0.125),
                      melody([C4, 0, G4, 0, C5, 0, E5, 0, C6], 0.04, "triangle") * 0.6), 0.45)

    # --- achievements and the stats screen
    # Achievement unlocked: a bright little victory fanfare.
    save("achievement", mix(melody([G5, C6, E6, 0, C6, G6, G6, G6], 0.07, "square", 0.25, 0.85),
                            melody([C5, E5, G5, 0, E5, C6, C6, C6], 0.07, "triangle") * 0.6), 0.45)
    # Tally tick: the short blip while the stats screen counts up kills.
    save("tally", note(1900, 0.03, "square", 0.25, power=2.5), 0.28)
    # Medal: a stage award pops onto the stats screen.
    save("medal", mix(melody([E6, G6, C7], 0.05, "square", 0.125),
                      osc(sweep(2000, 3200, 0.15), "triangle") * env(0.15, power=2) * 0.4), 0.38)


if __name__ == "__main__":
    main()
