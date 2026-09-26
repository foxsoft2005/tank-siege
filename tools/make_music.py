"""
Composes and renders the game's chiptune music into assets/music/.

This is OPTIONAL. The .ogg files are already included. Use it if you want to
change the songs: edit the chords / melodies below and run

    python tools/make_music.py        (needs Python 3 + numpy, and ffmpeg for .ogg)

How it's built, like an old NES sound chip:
  - LEAD   : pulse (square) wave, 25% duty, with vibrato and a stereo echo
  - ARP    : fast 12.5% pulse arpeggio cycling through the chord notes
  - BASS   : triangle wave, octave-jumping eighth notes
  - DRUMS  : noise (snare/hats) + a falling sine "kick"
Every track is written to loop seamlessly: sound that runs past the end
wraps around to the start.
"""

import os
import shutil
import subprocess
import tempfile
import wave

import numpy as np

RATE = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "music")
rng = np.random.default_rng(3)

NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
              "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(name):
    """'A4' -> 69, 'C#5' -> 73"""
    return (int(name[-1]) + 1) * 12 + NOTE_INDEX[name[:-1]]


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


# Chords: root note + intervals (semitones)
CHORD_SHAPES = {"m": [0, 3, 7], "": [0, 4, 7], "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10]}


def chord(name):
    """'Am' -> (root midi in octave 3, intervals)"""
    for suffix in sorted(CHORD_SHAPES, key=len, reverse=True):
        root = name[: len(name) - len(suffix)] if suffix else name
        if name.endswith(suffix) and root in NOTE_INDEX:
            return 48 + NOTE_INDEX[root], CHORD_SHAPES[suffix]
    raise ValueError(name)


# ------------------------------------------------------------------ synth

class Track:
    def __init__(self, bpm, bars):
        self.step = 60.0 / bpm / 4  # one 16th note, in seconds
        self.bars = bars
        self.n = int(round(self.step * 16 * bars * RATE))
        self.left = np.zeros(self.n)
        self.right = np.zeros(self.n)

    def add(self, sig, start_step, pan=0.0, gain=1.0):
        """Mix a signal in, wrapping past the end so the loop is seamless."""
        start = int(round(start_step * self.step * RATE)) % self.n
        idx = (start + np.arange(len(sig))) % self.n
        np.add.at(self.left, idx, sig * gain * (1 - max(pan, 0)))
        np.add.at(self.right, idx, sig * gain * (1 + min(pan, 0)))


def pulse(freq, dur, duty=0.25, vibrato=0.0, release=0.03):
    t = np.arange(int(dur * RATE)) / RATE
    f = freq * (1 + vibrato * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.12) * 6, 0, 1))
    phase = np.cumsum(f / RATE) % 1.0
    sig = np.where(phase < duty, 1.0, -1.0)
    return sig * adsr(len(sig), release)


def triangle(freq, dur, release=0.02):
    t = np.arange(int(dur * RATE)) / RATE
    phase = (freq * t) % 1.0
    # NES-style: a stepped (4-bit) triangle has that gritty chip sound
    tri = np.round((4 * np.abs(phase - 0.5) - 1) * 7.5) / 7.5
    return tri * adsr(len(tri), release)


def adsr(n, release, attack=0.004, sustain=0.75, decay=0.08):
    a, d, r = int(attack * RATE), int(decay * RATE), int(release * RATE)
    env = np.full(n, sustain)
    env[: min(a, n)] = np.linspace(0, 1, min(a, n))
    if n > a:
        k = min(d, n - a)
        env[a: a + k] = np.linspace(1, sustain, k)
    if n > r:
        env[n - r:] *= np.linspace(1, 0, r)
    return env


def noise(dur, decay, steps=1):
    n = int(dur * RATE)
    x = rng.uniform(-1, 1, n)
    if steps > 1:
        x = np.repeat(x[::steps], steps)[:n]
    return x * np.exp(-np.arange(n) / RATE / decay)


def kick():
    d = 0.14
    t = np.arange(int(d * RATE)) / RATE
    f = 45 + 120 * np.exp(-t * 35)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 18)


def snare():
    d = 0.13
    t = np.arange(int(d * RATE)) / RATE
    return noise(d, 0.045, 2) * 0.8 + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.5


def hat():
    x = noise(0.04, 0.01)
    return x - np.convolve(x, np.ones(6) / 6, mode="same")  # crude high-pass


# ------------------------------------------------------------------ song building

def render(bpm, chords, lead, drums=True, arp_gain=0.16, lead_gain=0.33, bass_gain=0.38,
           lead_duty=0.25, lead_shape="pulse"):
    bars = len(chords)
    tr = Track(bpm, bars)
    s = tr.step

    # LEAD melody (+ echo 3 sixteenths later, panned right)
    pos = 0
    for name, length in lead:
        if name != ".":
            f = hz(midi(name))
            if lead_shape == "pulse":
                sig = pulse(f, length * s * 0.95, lead_duty, vibrato=0.006, release=0.04)
            else:
                sig = triangle(f, length * s * 0.95, release=0.08)
            tr.add(sig, pos, pan=-0.15, gain=lead_gain)
            tr.add(sig, pos + 3, pan=0.6, gain=lead_gain * 0.28)
        pos += length
    assert pos == bars * 16, f"melody is {pos} steps, expected {bars * 16}"

    for bar, name in enumerate(chords):
        root, shape = chord(name)
        # ARP: 16th notes cycling up and down the chord
        tones = [root + 12 + i for i in shape] + [root + 24]
        seq = tones + tones[-2:0:-1]
        for k in range(16):
            tr.add(pulse(hz(seq[k % len(seq)]), s * 0.8, 0.125, release=0.02),
                   bar * 16 + k, pan=0.35, gain=arp_gain)
        # BASS: eighth notes, root jumping octaves
        for k in range(8):
            m = root - 12 + (12 if k % 2 else 0)
            tr.add(triangle(hz(m), s * 1.7), bar * 16 + k * 2, gain=bass_gain)
        # DRUMS
        if drums:
            last_of_phrase = bar % 8 == 7
            for k in range(16):
                step = bar * 16 + k
                if k in (0, 8) or (k == 10 and bar % 2):
                    tr.add(kick(), step, gain=0.55)
                if k in (4, 12) or (last_of_phrase and k in (13, 14, 15)):
                    tr.add(snare(), step, gain=0.3)
                if k % 2 == 0:
                    tr.add(hat(), step, pan=0.2, gain=0.12 if k % 4 else 0.07)

    stereo = np.stack([tr.left, tr.right], axis=1)
    return stereo / np.max(np.abs(stereo)) * 0.85


def save(name, stereo):
    os.makedirs(OUT, exist_ok=True)
    data = (stereo * 32767).astype("<i2").tobytes()
    tmp = os.path.join(tempfile.gettempdir(), name + ".wav")
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    if shutil.which("ffmpeg"):
        out = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
                        "-c:a", "libvorbis", "-q:a", "5", out], check=True)
    else:
        out = os.path.join(OUT, name + ".wav")
        shutil.copy(tmp, out)
        print("  (ffmpeg not found: saved .wav instead. Delete the old .ogg so the game uses it)")
    os.remove(tmp)
    print("wrote", os.path.basename(out), f"{len(stereo) / RATE:.1f}s")


# ------------------------------------------------------------------ the songs
# Melodies are lists of (note, length in 16th notes). "." is a rest.
# Every bar must add up to 16.

def battle_a():
    """Stage theme 1: A minor, driving."""
    chords = ["Am", "F", "C", "G", "Am", "F", "G", "E"] * 2
    lead = [
        # --- part A
        ("A4", 2), ("C5", 2), ("E5", 2), ("A5", 4), ("G5", 2), ("E5", 2), ("C5", 2),
        ("F5", 4), ("E5", 2), ("C5", 2), ("A4", 4), ("C5", 2), ("D5", 2),
        ("E5", 6), ("D5", 2), ("C5", 2), ("D5", 2), ("E5", 2), ("G5", 2),
        ("D5", 8), ("B4", 4), ("G4", 4),
        ("A4", 2), ("C5", 2), ("E5", 2), ("A5", 4), ("B5", 2), ("C6", 4),
        ("A5", 4), ("G5", 2), ("F5", 2), ("E5", 4), ("F5", 2), ("G5", 2),
        ("B5", 4), ("A5", 2), ("G5", 2), ("D5", 4), ("G5", 4),
        ("G#5", 8), ("E5", 4), ("B4", 4),
        # --- part B
        ("E5", 2), ("E5", 2), ("A5", 2), ("E5", 2), ("C6", 2), ("B5", 2), ("A5", 2), ("E5", 2),
        ("F5", 2), ("F5", 2), ("A5", 2), ("F5", 2), ("C6", 4), ("A5", 4),
        ("G5", 2), ("G5", 2), ("C6", 2), ("G5", 2), ("E6", 4), ("D6", 2), ("C6", 2),
        ("B5", 4), ("D6", 4), ("B5", 4), ("G5", 4),
        ("A5", 2), ("B5", 2), ("C6", 2), ("E6", 2), ("D6", 2), ("C6", 2), ("B5", 2), ("A5", 2),
        ("C6", 4), ("A5", 4), ("F5", 4), ("A5", 4),
        ("B5", 2), ("C6", 2), ("D6", 4), ("G5", 4), ("B5", 4),
        ("G#5", 4), ("B5", 4), ("E6", 8),
    ]
    return render(150, chords, lead)


def battle_b():
    """Stage theme 2: D minor, a bit faster."""
    chords = ["Dm", "Bb", "C", "Am", "Dm", "Bb", "Gm", "A"] * 2
    lead = [
        # --- part A
        ("D5", 3), ("F5", 3), ("A5", 2), ("D6", 4), ("C6", 2), ("A5", 2),
        ("Bb5", 4), ("A5", 2), ("F5", 2), ("D5", 6), ("F5", 2),
        ("E5", 3), ("G5", 3), ("C6", 2), ("E6", 4), ("D6", 2), ("C6", 2),
        ("C6", 4), ("A5", 4), ("E5", 4), ("A5", 4),
        ("D6", 3), ("C6", 3), ("A5", 2), ("F5", 4), ("A5", 2), ("D6", 2),
        ("F6", 4), ("D6", 4), ("Bb5", 4), ("D6", 4),
        ("D6", 3), ("Bb5", 3), ("G5", 2), ("Bb5", 4), ("D6", 4),
        ("C#6", 8), ("E6", 4), ("A5", 4),
        # --- part B
        ("A5", 2), ("A5", 1), ("A5", 1), ("D6", 2), ("A5", 2), ("F5", 2), ("A5", 2), ("D6", 4),
        ("D6", 2), ("D6", 1), ("D6", 1), ("F6", 2), ("D6", 2), ("Bb5", 4), ("D6", 4),
        ("E6", 2), ("E6", 1), ("E6", 1), ("G6", 2), ("E6", 2), ("C6", 4), ("G5", 4),
        ("A5", 6), ("C6", 2), ("E6", 8),
        ("F6", 2), ("E6", 2), ("D6", 2), ("C6", 2), ("A5", 4), ("D6", 4),
        ("D6", 2), ("C6", 2), ("Bb5", 2), ("A5", 2), ("F5", 4), ("Bb5", 4),
        ("G5", 2), ("Bb5", 2), ("D6", 4), ("G6", 4), ("F6", 2), ("E6", 2),
        ("E6", 8), ("C#6", 4), ("A5", 4),
    ]
    return render(160, chords, lead)


def boss():
    """Boss fight: E minor, fast and relentless."""
    chords = ["Em", "C", "D", "B", "Em", "C", "Am", "B"] * 2
    lead = [
        # --- part A: stabbing riff
        ("E5", 2), ("E5", 1), ("E5", 1), ("G5", 2), ("E5", 2), ("B5", 4), ("A5", 2), ("G5", 2),
        ("E5", 2), ("E5", 1), ("E5", 1), ("G5", 2), ("E5", 2), ("C6", 4), ("B5", 2), ("G5", 2),
        ("F#5", 2), ("F#5", 1), ("F#5", 1), ("A5", 2), ("F#5", 2), ("D6", 4), ("C6", 2), ("A5", 2),
        ("B5", 6), ("A5", 2), ("F#5", 4), ("D#5", 4),
        ("E5", 2), ("G5", 2), ("B5", 2), ("E6", 2), ("D6", 2), ("B5", 2), ("G5", 2), ("E5", 2),
        ("C6", 2), ("B5", 2), ("G5", 2), ("E5", 2), ("G5", 4), ("C6", 4),
        ("A5", 2), ("C6", 2), ("E6", 4), ("D6", 2), ("C6", 2), ("B5", 2), ("A5", 2),
        ("B5", 8), ("D#6", 4), ("F#6", 4),
        # --- part B: higher, more urgent
        ("E6", 3), ("D6", 3), ("B5", 2), ("E6", 3), ("D6", 3), ("B5", 2),
        ("C6", 3), ("B5", 3), ("G5", 2), ("C6", 4), ("E6", 4),
        ("D6", 3), ("C6", 3), ("A5", 2), ("D6", 4), ("F#6", 4),
        ("D#6", 8), ("B5", 8),
        ("E6", 2), ("E6", 2), ("G6", 2), ("E6", 2), ("B6", 4), ("A6", 2), ("G6", 2),
        ("E6", 2), ("C6", 2), ("E6", 2), ("G6", 2), ("C7", 4), ("B6", 4),
        ("A6", 2), ("G6", 2), ("E6", 2), ("C6", 2), ("A5", 4), ("E6", 4),
        ("D#6", 4), ("F#6", 4), ("B6", 8),
    ]
    return render(172, chords, lead, lead_duty=0.5, arp_gain=0.18)


def upgrade():
    """Calm loop for the upgrade card screen: no drums, soft triangle lead."""
    chords = ["Cmaj7", "Am7", "Fmaj7", "G"] * 2
    lead = [
        ("E5", 8), ("G5", 4), ("B5", 4),
        ("C6", 8), ("A5", 8),
        ("A5", 4), ("G5", 4), ("F5", 4), ("E5", 4),
        ("D5", 12), ("G5", 4),
        ("E5", 4), ("G5", 4), ("C6", 4), ("B5", 4),
        ("A5", 8), ("E5", 8),
        ("F5", 4), ("A5", 4), ("C6", 4), ("E6", 4),
        ("D6", 8), ("B5", 8),
    ]
    return render(96, chords, lead, drums=False, arp_gain=0.12, lead_gain=0.45,
                  bass_gain=0.3, lead_shape="triangle")


if __name__ == "__main__":
    save("battle_a", battle_a())
    save("battle_b", battle_b())
    save("upgrade", upgrade())
    save("boss", boss())
