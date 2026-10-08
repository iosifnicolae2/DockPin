"""Finds bad pointer moves in a DockPin move capture (~/Library/Logs/DockPin/moves.log, see MoveTrace.swift).
Usage: python3 scripts/analyze-moves.py [moves.log]
Flags: jumps whose height doesn't match the real arrangement, the pointer turning up back on the old display
right after a jump, landings at a display's top row the pointer wasn't near, and jumps DockPin didn't make.
"""
import json
import os
import plistlib
import subprocess
import sys


def plans():
    raw = subprocess.run(["defaults", "export", "io.bringes.DockPin", "-"], capture_output=True).stdout
    for key, value in plistlib.loads(raw).items():
        plan = json.loads(value) if key.startswith("plan.") else None
        if plan and "edge" in plan:  # plans saved before Dock positions existed have no edge
            yield plan


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
        if len(f) != 13:
            continue  # an older capture format
        num = lambda v: None if v == "-" else float(v)
        rows.append({"ms": float(f[0]), "at": (float(f[2]), float(f[3])), "delta": (float(f[6]), float(f[7])),
                     "action": f[10], "to": (num(f[11]), num(f[12]))})
    return rows


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Library/Logs/DockPin/moves.log")
    rows = load(path)
    plan = max(plans(), key=lambda p: sum(any(inside(r["at"], rect(d)) for d in p["pinned"]) for r in rows))
    pinned = {d["uuid"]: (d["name"], rect(d)) for d in plan["pinned"]}
    real = {d["uuid"]: rect(d) for d in plan["real"]}
    off = {u: (pinned[u][1][0] - real[u][0], pinned[u][1][1] - real[u][1]) for u in pinned}
    where = lambda p: next((u for u, (_, r) in pinned.items() if inside(p, r)), None)
    name = lambda u: pinned[u][0] if u else "outside"
    real_y = lambda p: p[1] - off[where(p)][1] if where(p) else None

    print(f"{len(rows)} events, plan: {plan['edge']} Dock on {name(plan['targetUUID'])}")
    jumps = flagged = 0
    shown = lambda r: r["to"] if r["action"] != "pass" else r["at"]
    for i, r in enumerate(rows):
        if r["action"] == "jump":
            jumps += 1
            before = rows[i - 1] if i else None
            if before and before["action"] == "pass" and where(shown(before)) != where(r["to"]):
                y0, y1 = real_y(shown(before)), real_y(r["to"])
                if y0 is not None and y1 is not None and abs(y1 - y0) > 12:
                    flagged += 1
                    print(f"  height {r['ms']:.0f} ms: {name(where(shown(before)))} real y {y0:.0f} -> {name(where(r['to']))} real y {y1:.0f}")
            later = [x for x in rows[i + 1:i + 40] if x["ms"] - r["ms"] < 400 and x["action"] == "pass"]
            back = [x for x in later if where(x["at"]) not in (where(r["to"]), None)]
            if back and abs(back[0]["at"][0] - r["to"][0]) + abs(back[0]["at"][1] - r["to"][1]) > 60:
                flagged += 1
                b = back[0]
                print(f"  back   {r['ms']:.0f} ms: jumped to {name(where(r['to']))} {r['to']}, then shown at {b['at']} on {name(where(b['at']))}")
        if i:
            prev, cur = shown(rows[i - 1]), shown(r)
            u = where(cur)
            if u and cur[1] - pinned[u][1][1] < 3 and prev[1] - pinned[u][1][1] > 60 and where(prev) != u:
                flagged += 1
                print(f"  top    {r['ms']:.0f} ms: {prev} on {name(where(prev))} -> top row of {name(u)} {cur} ({r['action']})")
            if r["action"] == "pass" and abs(cur[0] - prev[0]) + abs(cur[1] - prev[1]) > 100 and abs(r["delta"][0]) + abs(r["delta"][1]) < 100:
                flagged += 1
                print(f"  jump   {r['ms']:.0f} ms: {prev} -> {cur} (delta {r['delta']}), not by DockPin")
    print(f"{jumps} jumps, {flagged} flagged")


if __name__ == "__main__":
    main()
