"""Finds bad pointer moves in a DockPin move capture (~/Library/Logs/DockPin/moves.log, see MoveTrace.swift).
Usage: python3 scripts/analyze-moves.py [moves.log]
Flags: crossings whose height changes in the real arrangement, the pointer turning up on another display
right after a crossing, and jumps DockPin didn't make (macOS or another app moving the pointer).
"""
import json
import os
import plistlib
import subprocess
import sys


def plans():
    raw = subprocess.run(["defaults", "export", "io.bringes.DockPin", "-"], capture_output=True).stdout
    prefs = plistlib.loads(raw)
    for key, value in prefs.items():
        if key.startswith("plan."):
            yield json.loads(value)


def rect(d):
    (x, y), (w, h) = d["frame"]
    return x, y, x + w, y + h


def inside(p, r):
    return r[0] <= p[0] < r[2] and r[1] <= p[1] < r[3]


def load(path):
    rows = []
    for line in open(path):
        if line.startswith("#"):
            continue
        f = line.split()
        num = lambda v: None if v == "-" else float(v)
        rows.append({"ms": float(f[0]), "at": (num(f[2]), num(f[3])), "delta": (num(f[6]), num(f[7])),
                     "prev": (num(f[10]), num(f[11])), "fixed": (num(f[12]), num(f[13]))})
    return rows


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Library/Logs/DockPin/moves.log")
    rows = load(path)
    # The plan in force: the one whose pinned displays hold the most captured points.
    plan = max(plans(), key=lambda p: sum(any(inside(r["at"], rect(d)) for d in p["pinned"]) for r in rows))
    pinned = {d["uuid"]: (d["name"], rect(d)) for d in plan["pinned"]}
    real = {d["uuid"]: rect(d) for d in plan["real"]}
    off = {u: (pinned[u][1][0] - real[u][0], pinned[u][1][1] - real[u][1]) for u in pinned}

    def where(p):
        return next((u for u, (_, r) in pinned.items() if inside(p, r)), None)

    def to_real(p):
        u = where(p)
        return u, (p[0] - off[u][0], p[1] - off[u][1]) if u else None

    name = lambda u: pinned[u][0] if u else "outside"
    print(f"{len(rows)} events, plan: {plan['edge']} Dock on {name(plan['targetUUID'])}")
    crossings = bad = 0
    for i, r in enumerate(rows):
        fixed, at, prev = r["fixed"], r["at"], r["prev"]
        if fixed[0] is not None and prev[0] is not None and where(fixed) != where(prev):
            crossings += 1
            (_, before), (u, after) = to_real(prev), to_real(fixed)
            if before and after and abs(after[1] - before[1]) > 8 and abs(after[0] - before[0]) > 0:
                bad += 1
                print(f"  height  {r['ms']:.0f} ms: {name(where(prev))} y {before[1]:.0f} -> {name(u)} y {after[1]:.0f} (real)")
            nxt = [x for x in rows[i + 1:i + 12] if x["ms"] - r["ms"] < 150]
            stray = [x for x in nxt if x["fixed"][0] is None and where(x["at"]) not in (where(fixed), None)
                     and abs(x["at"][0] - fixed[0]) + abs(x["at"][1] - fixed[1]) > 60]
            if stray:
                bad += 1
                s = stray[0]
                print(f"  stray   {r['ms']:.0f} ms: crossed to {name(where(fixed))} {fixed}, then at {s['at']} on {name(where(s['at']))}")
        if i and fixed[0] is None and prev[0] is not None:
            jump = abs(at[0] - prev[0]) + abs(at[1] - prev[1])
            if jump > 100:
                bad += 1
                print(f"  jump    {r['ms']:.0f} ms: {prev} -> {at} (delta {r['delta']}), not by DockPin")
    print(f"{crossings} crossings, {bad} flagged")


if __name__ == "__main__":
    main()
