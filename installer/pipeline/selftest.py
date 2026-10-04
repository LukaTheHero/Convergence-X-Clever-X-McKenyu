r"""P11 / test plan P0 - pipeline self-test.

  cd v65\installer
  py -3.11 -X utf8 pipeline\selftest.py --rc rc2 [--skip-emit]

1. release.py --emit-only twice: catalog.json byte-identical; generated\catalog.iss identical except its stamp lines.
2. The main zip rebuilt from scratch into work\selftest\ is byte-identical to dist\<tag>\<main zip>.
3. Independent re-checks from the outputs (not from the pipeline's caches):
   - every hosted asset (dist\<tag>\github\<tag>, release_staging\<tag>, assets\) has the catalog's sha256 + size;
   - the main zip: no Clever part (by name or content), no file identical to any McKenyu / Clever / NRM / Seamless file;
   - no blob identical to any of those either;
   - G-PACK (packcheck.py, fresh run, no cache) passes on every regulation the installer can write;
   - pins are computed: every sha256 in catalog.json is recomputed from the files (main zip, members in the references,
     blobs, H detection rules from the legacy zips), and the pipeline's code holds no 64-hex literal.
Writes work\selftest\selftest_<rc>.json; exit 0 only when everything passes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from pipeline import catalog_src, cfg, mainzip, rcinputs, sources, util  # noqa: E402
from pipeline.util import hash_file, log, read_json  # noqa: E402

STAMP_RE = re.compile(r"(on \d{4}-\d\d-\d\d \d\d:\d\d:\d\d|CAT_BUILD_STAMP\s*=\s*'[^']*';)")


def sha_bytes(b):
    return hashlib.sha256(b).hexdigest()


def run_emit(rc, extra=()):
    t = time.time()
    r = subprocess.run(cfg.PY311 + [str(cfg.INST / "release.py"), "--rc", rc, "--emit-only"] + list(extra),
                       cwd=str(cfg.INST), capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, round(time.time() - t, 1), r.stdout[-1500:] + r.stderr[-1500:]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rc", default="rc2")
    ap.add_argument("--skip-emit", action="store_true")
    ap.add_argument("--allow-other-nrm-package", action="store_true",
                    help="passed to release.py --emit-only (a TEST build whose NRM layer is another package)")
    a = ap.parse_args()
    extra = ["--allow-other-nrm-package"] if a.allow_other_nrm_package else []
    util.open_log("selftest_%s.log" % time.strftime("%Y%m%d_%H%M%S"))
    res = {"rc": a.rc, "started": util.now_stamp(), "tests": {}}
    fails = []

    def ok(name, cond, detail):
        res["tests"][name] = {"ok": bool(cond), "detail": detail}
        log("%s %s: %s" % ("PASS" if cond else "FAIL", name, detail))
        if not cond:
            fails.append(name)

    src = catalog_src.load()
    tag = src["release"]["tag"]
    cat_p = cfg.DIST / tag / "catalog.json"
    # ---------------------------------------------------------------- 1. emit twice
    if not a.skip_emit:
        rc1, s1, o1 = run_emit(a.rc, extra)
        c1 = cat_p.read_bytes()
        i1 = STAMP_RE.sub("<stamp>", cfg.CATALOG_ISS.read_text(encoding="utf-8"))
        rc2, s2, o2 = run_emit(a.rc, extra)
        c2 = cat_p.read_bytes()
        i2 = STAMP_RE.sub("<stamp>", cfg.CATALOG_ISS.read_text(encoding="utf-8"))
        ok("emit_exit_codes", rc1 == 0 and rc2 == 0, "exit %d (%.0f s), %d (%.0f s)" % (rc1, s1, rc2, s2))
        ok("emit_twice_catalog_json_identical", c1 == c2, "sha256 %s / %s" % (sha_bytes(c1)[:16], sha_bytes(c2)[:16]))
        ok("emit_twice_catalog_iss_identical_but_stamps", i1 == i2, "%d / %d chars" % (len(i1), len(i2)))
        res["emit_secs"] = [s1, s2]
    m = json.loads(cat_p.read_text(encoding="utf-8"))
    cat_sha = hash_file(cat_p)["sha256"]
    res["catalog_sha256"] = cat_sha
    ok("catalog_rc", m["rc"] == a.rc, "catalog RC %s" % m["rc"])
    # ---------------------------------------------------------------- 2. main zip rebuild byte-identical
    rc = rcinputs.RC(src, a.rc)
    refs = sources.load_refs(src)
    zp = cfg.DIST / tag / src["release"]["main_zip_name"]
    plan = mainzip.plan(rc, refs, src)
    tmp = cfg.WORK / "selftest" / "rebuild.zip"
    t = time.time()
    h2 = mainzip.build(plan, tmp)
    h1 = hash_file(zp)
    ok("main_zip_rebuild_byte_identical", h1["sha256"] == h2["sha256"] and h1["size"] == h2["size"],
       "%s vs rebuild %s (%d B, %.0f s)" % (h1["sha256"][:16], h2["sha256"][:16], h2["size"], time.time() - t))
    util.guard_write(tmp).unlink()
    ok("main_zip_pin_equals_catalog", m["main_zip"]["sha256"] == h1["sha256"] and m["main_zip"]["size"] == h1["size"],
       "catalog %s / file %s" % (m["main_zip"]["sha256"][:16], h1["sha256"][:16]))
    mz = [a_ for a_ in m["archives"] if a_["id"] == "main_v65"][0]
    ok("main_zip_pinned_in_archive", mz["pins"] == [{"size": h1["size"], "sha256": h1["sha256"]}], str(mz["pins"]))
    # ---------------------------------------------------------------- 3. hosted assets
    bad = []
    gh_blobs = list(m["blobs"])
    places = [(cfg.DIST / tag / "github" / tag, gh_blobs), (cfg.RELEASE_STAGING / tag, gh_blobs)]
    bad += ["%s has another download site (retired 2026-10-03)" % b["asset"] for b in m["blobs"] if b.get("site")]
    for root, blobs in places:
        names = {p.name for p in root.iterdir() if p.is_file()} if root.exists() else set()
        if names != {b["asset"] for b in blobs}:
            bad.append("%s: file set differs" % root)
        for b in blobs:
            p = root / b["asset"]
            data = p.read_bytes() if p.exists() else b""
            if sha_bytes(data) != b["sha256"] or len(data) != b["size"]:
                bad.append("%s\\%s" % (root.name, b["asset"]))
    for b in m["blobs"]:
        p = cfg.ASSETS / b["sha256"]
        if not p.exists() or sha_bytes(p.read_bytes()) != b["sha256"]:
            bad.append("assets\\%s" % b["sha256"][:12])
    ok("hosted_blobs_sha256_match_catalog", not bad, "%d assets (all GitHub release assets) x 2 trees + the store, "
       "freshly read; bad %s" % (len(m["blobs"]), bad[:5]))
    # ---------------------------------------------------------------- 3b. never bundled / never hosted
    third = {}
    clever_names = set()
    for aid, ref in refs.items():
        if aid == "main_v65":
            continue
        for f in ref.files:
            third.setdefault(f["sha256"], "%s:%s" % (aid, f["tail"]))
            if aid == "clever_262" and f["tail"].lower().startswith("parts\\"):
                clever_names.add(f["name"].lower())
    zbad = []
    with zipfile.ZipFile(zp) as z:
        for i in z.infolist():
            name = i.filename.rsplit("/", 1)[-1].lower()
            h = hashlib.sha256()
            with z.open(i) as f:
                for chunk in iter(lambda: f.read(8 << 20), b""):
                    h.update(chunk)
            if name in clever_names:
                zbad.append("Clever part name %s" % i.filename)
            if h.hexdigest() in third:
                zbad.append("%s == %s" % (i.filename, third[h.hexdigest()]))
        n_members = len(z.infolist())
    ok("main_zip_no_clever_no_author_identical_file", not zbad,
       "%d members read back; vs %d Clever/McKenyu/DMN/NRM/Seamless contents and %d Clever part names; bad %s" % (
           n_members, len(third), len(clever_names), zbad[:5]))
    bbad = ["%s == %s" % (b["asset"], third[b["sha256"]]) for b in m["blobs"] if b["sha256"] in third]
    bbad += ["%s uses a Clever part name" % b["asset"] for b in m["blobs"] if any(
        pth.rsplit("\\", 1)[-1].lower() in clever_names for pth in b["paths"])]
    ok("blobs_no_author_identical_file", not bbad, "%d blobs; bad %s" % (len(m["blobs"]), bbad[:5]))
    # ---------------------------------------------------------------- 3c. G-PACK fresh
    prod = read_json(cfg.PRODUCTS / a.rc / "products.json")
    regs = sorted(prod["packcheck"])
    r = subprocess.run(cfg.PY311 + [src["inputs"]["packcheck"]] + regs, cwd=str(Path(src["inputs"]["packcheck"]).parent.parent),
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    passes = sum(1 for l in r.stdout.splitlines() if l.startswith("PACK-PASS"))
    ok("gpack_every_regulation_fresh", r.returncode == 0 and passes == len(regs),
       "packcheck.py exit %d, PACK-PASS %d of %d regulations (RC, Lucy plain/NRM, 8 InfDur editions)" % (
           r.returncode, passes, len(regs)))
    reg_variants = {v["sha256"] for v in m["variants"] if m["paths"][v["path"]]["rel"].lower() == "mod\\regulation.bin"}
    reg_files = {hash_file(p)["sha256"] for p in regs}
    ok("gpack_covers_every_installable_regulation", reg_variants <= reg_files,
       "%d regulation variants, all among the %d checked files" % (len(reg_variants), len(reg_files)))
    # ---------------------------------------------------------------- 3d. pins computed
    mism = []
    ref_sha = {aid: {(f["name"].lower(), f["sha256"]) for f in ref.files} for aid, ref in refs.items() if aid != "main_v65"}
    with zipfile.ZipFile(zp) as z:
        zsha = {}
        for i in z.infolist():
            zsha[(i.filename.rsplit("/", 1)[-1].lower(), sha_bytes(z.read(i)))] = 1
    for arch in m["archives"]:
        for mem in arch["members"]:
            if arch["mode"] == "V":
                continue
            key = (mem["name"].lower(), mem["sha256"])
            pool = zsha if arch["id"] == "main_v65" else ref_sha[arch["id"]]
            if key not in pool:
                mism.append("%s member %s" % (arch["id"], mem["name"]))
        for pin in arch["pins"]:
            pf = zp if arch["id"] == "main_v65" else Path(refs[arch["id"]].path)
            h = hash_file(pf)
            if (h["size"], h["sha256"]) != (pin["size"], pin["sha256"]):
                mism.append("%s pin" % arch["id"])
    for v in m["variants"]:
        if v["src"] == "B" and m["blobs"][v["ref"]]["sha256"] != v["sha256"]:
            mism.append("variant blob ref")
    code_hex = []
    for p in sorted((cfg.PIPE).rglob("*.py")):
        if "vendor" in p.parts:
            continue
        for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(r"(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])", line):
                code_hex.append("%s:%d" % (p.name, n))
    ok("pins_computed_not_hand_typed", not mism and not code_hex,
       "every member/pin/blob sha256 recomputed from the files (%d members, %d pins); 64-hex literals in pipeline code: %s" % (
           sum(len(x["members"]) for x in m["archives"]), sum(len(x["pins"]) for x in m["archives"]), code_hex or "none"))
    # ---------------------------------------------------------------- 3e. generated include agrees with catalog.json
    iss = cfg.CATALOG_ISS.read_text(encoding="utf-8")
    bi = cfg.BUILD_INFO_ISS.read_text(encoding="utf-8")
    ok("generated_include_matches_catalog", ("CAT_SHA256        = '%s';" % cat_sha) in iss and
       ('#define CatSha256 "%s"' % cat_sha) in bi and ("CAT_VAR_COUNT = %d;" % len(m["variants"])) in iss and
       "\r" not in iss and not iss.startswith("\ufeff"),
       "CAT_SHA256 / CatSha256 / counts / UTF-8 LF no BOM")
    res["finished"] = util.now_stamp()
    res["ok"] = not fails
    res["fails"] = fails
    util.write_json(cfg.WORK / "selftest" / ("selftest_%s.json" % a.rc), res)
    log("SELFTEST %s (%d tests, %d failed)" % ("PASSED" if not fails else "FAILED", len(res["tests"]), len(fails)))
    util.save_hashcache()
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
