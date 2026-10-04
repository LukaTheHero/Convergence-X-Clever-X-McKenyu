"""Clip-list counter (port of v65\\opus\\work\\_research\\adv_verify\\mapcount.py; READ-ONLY on every input).

The c0000 clip list = union of every TAE action id and every HKX animation id (bank*1e6 + sub) over the 16 c0000
animation binders (c0000, a00_hi/md/lo, a0x..a9x, dlc01, dlc02). mapcount.py's "all files incl. a00_md/lo" UNION.

usage: py -3.11 -X utf8 wallcount.py <spec.json> <out.json>
  spec = {"<label>": {"<binder name>": "<file path or empty>", ...}, ...}
  out  = {"<label>": {"total": n, "tae": n, "hkx": n, "hkx_only": n, "a998_040000": pos, "files": {name: md5}}}
"""
import hashlib
import json
import os
import re
import sys

FW = r"C:\00000ConvergenceER\ClaudeWorkspace\clever_x_convergence_x_mckenyu\v65\opus\work"
sys.path.insert(0, FW)
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
os.chdir(FW)
import ocore as C  # noqa: E402

RX = re.compile(r"^a(\d{3})_(\d{6})\.hkx$", re.I)
spec = json.load(open(sys.argv[1], encoding="utf-8"))
cache = {}


def scan(path):
    if path in cache:
        return cache[path]
    ms = C.members(path)
    hs, tae = set(), set()
    for mn, blob in ms.items():
        m = RX.match(mn)
        if m:
            hs.add(int(m.group(1)) * 1000000 + int(m.group(2)))
            continue
        if mn.lower().endswith(".tae") and mn[1:-4].isdigit():
            subs = C.tae_subs(blob)
            if subs is not None:
                bank = int(mn[1:-4])
                for s in subs:
                    tae.add(bank * 1000000 + s)
    cache[path] = (tae, hs, hashlib.md5(open(path, "rb").read()).hexdigest())
    return cache[path]


out = {}
for label, files in spec.items():
    tae, hk, md5s = set(), set(), {}
    for name, path in files.items():
        if not path:
            md5s[name] = None
            continue
        t, h, m = scan(path)
        tae |= t
        hk |= h
        md5s[name] = m
    u = sorted(tae | hk)
    pos = {x: i for i, x in enumerate(u)}
    out[label] = {"total": len(u), "tae": len(tae), "hkx": len(hk), "hkx_only": len(hk - tae),
                  "a998_040000": pos.get(998040000), "files": md5s}
    print("%s: total %d (tae %d, hkx %d, hkx-only %d), a998_040000 at %s" % (
        label, len(u), len(tae), len(hk), len(hk - tae), pos.get(998040000)))
json.dump(out, open(sys.argv[2], "w", encoding="utf-8"), indent=1)
