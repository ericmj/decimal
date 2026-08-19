#!/usr/bin/env python3
"""Compare two bench_resources.exs outputs and print per-metric deltas.

usage: bench_compare.py BASELINE CANDIDATE [--mode discard|retain|both]
"""
import sys

COLS = ["wall", "cpu", "reds", "alloc", "copy", "minor", "major", "peak"]


def parse(path):
    rows = {}
    for line in open(path):
        parts = line.split()
        if len(parts) < 10 or parts[-1].endswith("KB"):
            continue
        try:
            nums = [float(x) for x in parts[-8:]]
        except ValueError:
            continue
        mode = parts[-9]
        if mode not in ("discard", "retain"):
            continue
        name = " ".join(parts[:-9])
        rows[(name, mode)] = dict(zip(COLS, nums))
    return rows


def main():
    base, cand = parse(sys.argv[1]), parse(sys.argv[2])
    want = sys.argv[3] if len(sys.argv) > 3 else "both"

    print(f"{'operation':<18} {'mode':<8} " + " ".join(f"{c:>16}" for c in COLS))
    for key in base:
        if key not in cand:
            continue
        name, mode = key
        if want != "both" and mode != want:
            continue
        cells = []
        for col in COLS:
            b, c = base[key][col], cand[key][col]
            if b == 0 and c == 0:
                cells.append(f"{'-':>16}")
            elif b == 0:
                cells.append(f"{c:>10.1f} new")
            else:
                pct = (c - b) / b * 100
                cells.append(f"{c:>9.1f} {pct:+5.0f}%")
        print(f"{name:<18} {mode:<8} " + " ".join(cells))


if __name__ == "__main__":
    main()
