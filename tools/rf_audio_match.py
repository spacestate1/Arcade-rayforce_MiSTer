#!/usr/bin/env python3
"""Find WHERE (and at what pitch) an Audio Ring capture occurs in a reference.

rf_audio_ring.py answers "does the board play what the model computes at the
same moment" by correlating at one place. This answers the wider question
when that says no: does the board's 137 ms occur ANYWHERE in the reference,
at any playback rate, and if it is not in the mix, which ROM sample is it?

    python3 tools/rf_audio_match.py audio_ring.log \
        --ref dump/en4/model95.wav --ref dump/en4/en_mix.wav --rom gunlock.zip

Capture: an Audio Ring log (rf_uart.py output) or a mono 29761 Hz wav.
References: wavs at any rate (resampled to 29761 Hz, left channel).
ROM: the zip holding d66-01.ic2 / d66-02.ic3; the ES5505 plays these as
signed 8-bit samples (the model puts the byte in the high byte of the word).

Method: normalized cross-correlation (NCC) at EVERY lag, by FFT, with the
reference's sliding mean and energy removed so silence and level do not
matter. Repeated with the capture resampled by a set of rate ratios, so a
sample played at the wrong pitch still lands. Noise floor: 4096 samples
against N positions gives max |NCC| ~ sqrt(2 ln N / 4096) ~ 0.09 for a 95 s
reference; multiplied over the ratio scan, anything under ~0.15 is chance.
A real match at the right pitch is > 0.5; a right-sample-wrong-filter match
is 0.3-0.5 and peaks sharply at one ratio.
"""
import argparse
import io
import os
import re
import struct
import sys
import wave
import zipfile

import numpy as np

RATE = 29761                         # MAME's integer ES5505 rate, 15238090 // 512


def load_capture(path):
    if path.lower().endswith(".wav"):
        w = wave.open(path)
        d = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64)
        d = d.reshape(-1, w.getnchannels())[:, 0]
        if w.getframerate() != RATE:
            d = resample(d, w.getframerate() / RATE)
        return d, None
    rx = re.compile(r"^W ([0-9A-F]{6}) ([0-9A-F]{4}) ([0-3])")
    headers, entries = [], []
    for ln, line in enumerate(open(path, errors="ignore")):
        if line.startswith("==="):
            headers.append(ln)
        m = rx.match(line)
        if m:
            entries.append((ln, int(m.group(1), 16) >> 1, int(m.group(2), 16)))
    for h in headers:
        seg = [e for e in entries if h < e[0] <= h + 4200][:4096]
        if len(seg) == 4096:
            seg.sort(key=lambda e: e[1])
            a = np.array([struct.unpack("<h", struct.pack("<H", d))[0] for _, _, d in seg], dtype=np.float64)
            return a, seg[0][1]
    raise SystemExit(f"{path}: no complete 4096-entry pass")


def load_wav_left(path):
    w = wave.open(path)
    n, r, c = w.getnframes(), w.getframerate(), w.getnchannels()
    d = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float64).reshape(-1, c)[:, 0]
    if r != RATE:
        d = resample(d, r / RATE)
    return d


def load_rom(zpath):
    """The two sample ROMs as signed 8-bit PCM, in ES5505 address order."""
    z = zipfile.ZipFile(zpath)
    parts = []
    for name in ("d66-01.ic2", "d66-02.ic3"):
        b = np.frombuffer(z.read(name), dtype=np.int8).astype(np.float64)
        parts.append((name, b))
    return parts


def resample(x, step):
    """x read at 'step' input samples per output sample (linear)."""
    n = int(len(x) / step)
    t = np.arange(n) * step
    return np.interp(t, np.arange(len(x)), x)


def ncc_all(x, y, min_rms=8.0):
    """NCC of the short zero-mean window x against y at every start position.

    Returns an array of length len(y)-len(x)+1; positions whose window is
    quieter than min_rms are set to 0 (silence would otherwise divide by ~0).
    """
    n, N = len(x), len(y)
    if N < n:
        return np.zeros(0)
    x = x - x.mean()
    L = 1 << int(np.ceil(np.log2(N + n)))
    num = np.fft.irfft(np.fft.rfft(x[::-1], L) * np.fft.rfft(y, L), L)[n - 1:N]
    c1 = np.cumsum(np.concatenate(([0.0], y)))
    c2 = np.cumsum(np.concatenate(([0.0], y * y)))
    s1 = c1[n:N + 1] - c1[:N - n + 1]
    s2 = c2[n:N + 1] - c2[:N - n + 1]
    var = np.maximum(s2 - s1 * s1 / n, 0.0)
    out = num / (np.sqrt(var) * np.linalg.norm(x) + 1e-9)
    out[np.sqrt(var / n) < min_rms] = 0.0
    return out


def ratio_set(span, step):
    """2^(k*step) for |k*step| <= span, e.g. span=1 step=1/24 -> 0.5x..2x by quarter tones."""
    k = int(round(span / step))
    return [2.0 ** (i * step) for i in range(-k, k + 1)]


def peaks(x, rate, count=6):
    spec = np.abs(np.fft.rfft((x - x.mean()) * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / rate)
    # local maxima only, then the strongest
    lm = np.nonzero((spec[1:-1] > spec[:-2]) & (spec[1:-1] > spec[2:]))[0] + 1
    top = lm[np.argsort(spec[lm])[::-1][:count]]
    return [(f[i], spec[i] / spec.max()) for i in top]


def period(x, rate):
    """Fundamental period by autocorrelation, ignoring lags under 0.2 ms."""
    x = x - x.mean()
    ac = np.correlate(x, x, "full")[len(x) - 1:]
    ac /= ac[0] + 1e-9
    lo = int(rate * 0.0002)
    lm = np.nonzero((ac[lo + 1:-1] > ac[lo:-2]) & (ac[lo + 1:-1] > ac[lo + 2:]))[0] + lo + 1
    if len(lm) == 0:
        return None
    i = lm[np.argmax(ac[lm])]
    return rate / i, ac[i]


def search(name, cap, ref, ratios, top, min_rms):
    """Best (ncc, ratio, position) triples over the ratio set, best first."""
    hits = []
    for r in ratios:
        x = resample(cap, r)
        if len(x) < 512:
            continue
        c = ncc_all(x, ref, min_rms)
        if len(c) == 0:
            continue
        # keep the few best positions per ratio, at least 0.1 s apart
        order = np.argsort(np.abs(c))[::-1]
        kept = []
        for i in order[:2000]:
            if all(abs(i - j) > RATE // 10 for j in kept):
                kept.append(i)
            if len(kept) >= 3:
                break
        for i in kept:
            hits.append((c[i], r, i, len(x)))
    hits.sort(key=lambda h: -abs(h[0]))
    print(f"\n{name}: {len(ref)} samples ({len(ref) / RATE:.1f} s), {len(ratios)} ratios")
    for ncc, r, i, n in hits[:top]:
        print(f"  ncc {ncc:+.3f}  ratio {r:.4f} ({12 * np.log2(r):+.1f} st)  at {i / RATE:8.3f} s  (sample {i}, window {n})")
    return hits


def search_rom(cap, roms, ratios, top, min_rms):
    hits = []
    for r in ratios:
        x = resample(cap, r)
        if len(x) < 512:
            continue
        for name, rom in roms:
            c = ncc_all(x, rom, min_rms)
            order = np.argsort(np.abs(c))[::-1]
            kept = []
            for i in order[:2000]:
                if all(abs(i - j) > 2048 for j in kept):
                    kept.append(i)
                if len(kept) >= 3:
                    break
            for i in kept:
                hits.append((c[i], r, name, i, len(x)))
    hits.sort(key=lambda h: -abs(h[0]))
    print(f"\nROM: {', '.join(f'{n} {len(b)} bytes' for n, b in roms)}, {len(ratios)} ratios")
    print("  (ratio here = ROM bytes per output sample, i.e. the voice's playback step)")
    for ncc, r, name, i, n in hits[:top]:
        print(f"  ncc {ncc:+.3f}  step {r:.4f}  {name} offset 0x{i:06X}  (window {n} bytes)")
    return hits


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("capture", help="Audio Ring log or a 29761 Hz mono wav")
    ap.add_argument("--ref", action="append", default=[], help="reference wav (repeatable)")
    ap.add_argument("--rom", help="gunlock.zip, to identify the ROM sample being played")
    ap.add_argument("--span", type=float, default=1.0, help="rate scan +-span octaves (default 1)")
    ap.add_argument("--step", type=float, default=1 / 24, help="rate scan step in octaves (default 1/24 = quarter tone)")
    ap.add_argument("--rom-span", type=float, default=2.0, help="ROM step scan +-octaves (default 2)")
    ap.add_argument("--no-scan", action="store_true", help="ratio 1.0 only")
    ap.add_argument("--top", type=int, default=8)
    ap.add_argument("--min-rms", type=float, default=8.0, help="ignore reference windows quieter than this")
    ap.add_argument("--save-window", help="write the best reference window next to the capture as a stereo wav")
    a = ap.parse_args()

    cap, idx = load_capture(a.capture)
    print(f"capture: {len(cap)} samples ({len(cap) / RATE * 1000:.0f} ms), rms {np.sqrt((cap ** 2).mean()):.0f}, "
          f"peak {np.abs(cap).max():.0f}" + (f", ring index {idx} ({idx / RATE:.2f} s after the sound CPU's release)" if idx is not None else ""))
    print("spectral peaks (Hz, rel):", ", ".join(f"{f:.0f} ({m:.2f})" for f, m in peaks(cap, RATE)))
    p = period(cap, RATE)
    if p:
        print(f"autocorrelation fundamental: {p[0]:.1f} Hz (strength {p[1]:.2f})")

    ratios = [1.0] if a.no_scan else ratio_set(a.span, a.step)
    best = None
    for ref in a.ref:
        y = load_wav_left(ref)
        hits = search(os.path.basename(ref), cap, y, ratios, a.top, a.min_rms)
        if hits and (best is None or abs(hits[0][0]) > abs(best[0][0])):
            best = (hits[0], ref, y)

    if a.rom:
        rom_ratios = [1.0] if a.no_scan else ratio_set(a.rom_span, a.step)
        search_rom(cap, load_rom(a.rom), rom_ratios, a.top, a.min_rms)

    if best and a.save_window:
        (ncc, r, i, n), ref, y = best
        x = resample(cap, r)
        seg = y[i:i + n]
        g = np.abs(x).max() / (np.abs(seg).max() + 1e-9)
        st = np.stack([x, seg * g], axis=1)
        w = wave.open(a.save_window, "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(np.clip(st, -32768, 32767).astype("<i2").tobytes()); w.close()
        print(f"\nwrote {a.save_window}: L = capture (rate x{r:.3f}), R = {os.path.basename(ref)} at {i / RATE:.3f} s, ncc {ncc:+.3f}")


if __name__ == "__main__":
    main()
