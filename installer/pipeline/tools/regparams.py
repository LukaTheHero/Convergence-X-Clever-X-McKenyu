"""Regulation helper for the release pipeline (py -3.11 -X utf8; imports the v6.5 framework read-only).

usage:
  regparams.py members <out.json> <regulation.bin> [...]
      -> {path: {member name: md5 of the decrypted member}}
  regparams.py speffect-new <out.json> <base regulation.bin> <rc regulation.bin>
      -> {"new": [[id, effectEndurance, name], ...], "removed": [...], "changed_endurance": [[id, old, new], ...]}
"""
import hashlib
import json
import os
import sys

FW = r"C:\00000ConvergenceER\ClaudeWorkspace\clever_x_convergence_x_mckenyu\v65\opus\work"
sys.path.insert(0, FW)
sys.path.insert(0, os.path.join(FW, "_lib"))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
os.chdir(FW)
import oreg  # noqa: E402
import oparam  # noqa: E402
import pio  # noqa: E402
import v62fields as F  # noqa: E402


def members(path):
    return oreg.members(oreg.decrypt(os.path.abspath(path)))


def speffect_rows(path):
    blob = members(path)["SpEffectParam.param"]
    P = oparam.Param(blob)
    t = P.type_region.split(b"\0", 1)[0].decode("ascii", "replace")
    if not t or t not in pio.defs():
        t = str(pio.read_param(blob)[0].ParamType)
    lay = F.layout(t)
    out = {}
    for rid, row in P.by_id().items():
        data = row[2]
        out[rid] = (float(F.get(lay["effectEndurance"], data)), hashlib.md5(bytes(data)).hexdigest(),
                    str(row[3]) if len(row) > 3 and row[3] is not None else "")
    return out


cmd = sys.argv[1]
out_path = sys.argv[2]
if cmd == "members":
    res = {}
    for p in sys.argv[3:]:
        res[p] = {k: hashlib.md5(v).hexdigest() for k, v in members(p).items()}
elif cmd == "speffect-new":
    a, b = speffect_rows(sys.argv[3]), speffect_rows(sys.argv[4])
    res = {"new": [[i, b[i][0], b[i][2]] for i in sorted(set(b) - set(a))],
           "removed": sorted(set(a) - set(b)),
           "changed_endurance": [[i, a[i][0], b[i][0]] for i in sorted(set(a) & set(b)) if a[i][0] != b[i][0]],
           "changed_rows": len([i for i in set(a) & set(b) if a[i][1] != b[i][1]])}
else:
    raise SystemExit("unknown command %s" % cmd)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(res, f, indent=1)
print("OK", cmd, len(res))
