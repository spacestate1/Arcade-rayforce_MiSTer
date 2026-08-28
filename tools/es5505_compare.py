#!/usr/bin/env python3
"""Compare the ES5505 model's dry mix with MAME's -wavwrite output.

MAME's wav is the whole board (ES5505 -> ES5510 program -> MB87078 gains ->
MAME's resampler to 48 kHz), the model's is the ES5505 alone, so this is a
correlation check, not an equality: it says whether the model plays the
same notes at the same times. The exact test is the RTL against the model.

    python3 tools/es5505_compare.py model.wav dump/en3/en_mix.wav [--start 1.0 --len 3.0]
"""
import argparse, wave
import numpy as np

def load(path):
    w = wave.open(path); n = w.getnframes(); r = w.getframerate(); c = w.getnchannels()
    d = np.frombuffer(w.readframes(n), dtype='<i2').astype(np.float64).reshape(-1, c)
    return d.mean(axis=1), r

ap = argparse.ArgumentParser()
ap.add_argument("model"); ap.add_argument("mame")
ap.add_argument("--start", type=float, default=1.0); ap.add_argument("--len", type=float, default=3.0)
a = ap.parse_args()
m, rm = load(a.model); g, rg = load(a.mame)
# resample the model to MAME's rate, linear
t = np.arange(int(len(m) * rg / rm)) * (rm / rg)
mr = np.interp(t, np.arange(len(m)), m)
s0 = int(a.start * rg); n = int(a.len * rg)
x = mr[s0:s0 + n]; y = g[s0:s0 + n]
x = x - x.mean(); y = y - y.mean()
best = (0, -1.0)
for lag in range(-2400, 2401, 4):          # +-50 ms
    if lag >= 0: xx, yy = x[lag:], y[:len(y) - lag]
    else:        xx, yy = x[:len(x) + lag], y[-lag:]
    c = np.dot(xx, yy) / (np.linalg.norm(xx) * np.linalg.norm(yy) + 1e-9)
    if c > best[1]: best = (lag, c)
print(f"model {rm} Hz {len(m)/rm:.2f} s, mame {rg} Hz {len(g)/rg:.2f} s")
print(f"window {a.start}s +{a.len}s: best lag {best[0]/rg*1000:.1f} ms, correlation {best[1]:.3f}")
print(f"rms model {np.sqrt((x**2).mean()):.0f}, mame {np.sqrt((y**2).mean()):.0f}")
