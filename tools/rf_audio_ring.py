#!/usr/bin/env python3
"""Turn an Audio Ring capture into a wav and compare it with the model.

    .venv/bin/python3 tools/setcfg.py 18            # Self Test Off + UART Debug = Audio Ring
    .venv/bin/python3 tools/rf_deploy.py --rbf <rbf> --no-shot
    .venv/bin/python3 tools/rf_uart.py -t 15 -o audio_ring.log
    python3 tools/rf_audio_ring.py audio_ring.log model45.wav

The ring holds the first N AUDIO_L samples (N = the ring's depth: 2048 from B15, 4096 before) from the moment the board's
sound exceeds silence (Rayforce.sv, "Audio Ring"), 69 ms at 29761 Hz. The
model's wav (es5505_model.py --out) is the dry mix of the same game run
from reset, so the same moment exists in it: this finds the model's first
non-silent sample and correlates the two 137 ms windows at the best lag.
A correlation near 1 means the board plays what the model computes; near 0
means it plays something else, and the wav says what.
"""
import re
import struct
import sys
import wave

import numpy as np


def ring_samples(path):
    rx = re.compile(r"^W ([0-9A-F]{6}) ([0-9A-F]{4}) ([0-3])")
    headers, entries = [], []
    for ln, line in enumerate(open(path, errors="ignore")):
        if line.startswith("==="):
            headers.append(ln)
        m = rx.match(line)
        if m:
            entries.append((ln, int(m.group(1), 16) >> 1, int(m.group(2), 16)))
    for h in headers:
        nxt = min([x for x in headers if x > h], default=10 ** 9)
        seg = [e for e in entries if h < e[0] < nxt]
        if len(seg) >= 1024:
            seg.sort(key=lambda e: e[1])            # by sample index
            print(f"capture starts at sample {seg[0][1]} after the sound CPU's release ({seg[0][1] / 29761:.2f} s)")
            return np.array([struct.unpack("<h", struct.pack("<H", d))[0] for _, _, d in seg], dtype=np.float64)
    raise SystemExit("no complete 4096-entry pass in the capture")


def main():
    cap = sys.argv[1]
    mdl = sys.argv[2] if len(sys.argv) > 2 else "model45.wav"
    a = ring_samples(cap)
    out = cap.rsplit(".", 1)[0] + ".wav"
    w = wave.open(out, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(29761)
    w.writeframes(np.clip(a, -32768, 32767).astype("<i2").tobytes()); w.close()
    print(f"{cap}: 4096 samples -> {out}; rms {np.sqrt((a**2).mean()):.0f}, peak {np.abs(a).max():.0f}")

    mw = wave.open(mdl); n = mw.getnframes(); r = mw.getframerate(); c = mw.getnchannels()
    m = np.frombuffer(mw.readframes(n), dtype="<i2").astype(np.float64).reshape(-1, c)[:, 0]
    if r != 29761:
        print(f"model wav is {r} Hz, expected 29761")
    thr = np.nonzero(np.abs(m) > 256)[0]
    if len(thr) == 0:
        raise SystemExit("model is silent")
    s0 = thr[0]
    print(f"model's sound starts at sample {s0} ({s0 / r:.2f} s)")
    best = (0, -1.0)
    x = a - a.mean()
    for lag in range(-400, 401):
        seg = m[s0 + lag: s0 + lag + 4096]
        if len(seg) < 4096:
            continue
        y = seg - seg.mean()
        cc = np.dot(x, y) / (np.linalg.norm(x) * np.linalg.norm(y) + 1e-9)
        if cc > best[1]:
            best = (lag, cc)
    print(f"best lag {best[0]} samples: correlation {best[1]:.3f}")
    # a coarse spectral sanity check: where is the energy
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / 29761)
    top = np.argsort(spec)[-5:][::-1]
    print("strongest bins (Hz):", ", ".join(f"{f[i]:.0f}" for i in top))


if __name__ == "__main__":
    main()
