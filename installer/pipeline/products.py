"""P3: the products an RC needs besides its own build: Lucy (plain + NRM, EXACT BUILD RECIPE) and her own build
checks, Lucy + NRM's icon pair (NRM 0.2), the Lucy regulation param equality, Infinite Durations V1-V4 on the RC and
on the Lucy regulation (vendored build65.py), the component files taken from zips (arrows DLL, ERCapacityExpansion
DLL + LICENSE), and the packaging laws on every regulation the installer can write. Writes work\\products\\<rc>\\products.json (contract section 10)."""
from __future__ import annotations

import json
import os
import shutil
import zipfile
from pathlib import Path

from . import cfg, util
from .util import (BuildError, files_under, hash_file, log, md5_file, read_json, require, run, sha256_file,
                   write_json, write_text)


def pdir(rc_name: str) -> Path:
    return cfg.PRODUCTS / rc_name


# ------------------------------------------------------------------ Lucy
def lucy_plan(rc, suf: str) -> dict:
    """the files Lucy's recipe adds to (its --base), exactly as deploy_v65.py's lucy_base_plan (so the pipeline reuses
    the Lucy builds the RC lane made for the field test, byte for byte): the RC chain's regulation, menu\\hi\\01_common
    pair and item_dlc02 binders; for the _nrm base the NRM layer's item_dlc02 wherever it ships one (NRM 0.2: engus,
    rusru - Wylder's goods texts) and its menu_dlc02 (every NRM version: the Grace-menu lines). The 01_common pair
    always comes from the chain: Lucy's packed icons replace it, and NRM's own icon change is put into her pair
    afterwards (ensure_nrm_menu). The regulation always comes from the chain (Lucy plain == Lucy NRM in params)."""
    nrm_ship = {r.replace("/", "\\").lower() for r in (rc.nrm_report.get("shipping_files") or [])} if suf else set()
    plan = {}
    for rel in ["regulation.bin"] + cfg.LUCY_ICON_MENU + [r"msg\%s\item_dlc02.msgbnd.dcx" % l for l in cfg.LANGS]:
        plan[rel] = (rc.nrm / rel) if (suf and rel.startswith("msg") and rel.lower() in nrm_ship) else rc.res(rel)
    for l in cfg.LANGS:
        rel = r"msg\%s\menu_dlc02.msgbnd.dcx" % l
        plan[rel] = (rc.nrm / rel) if suf else rc.res(rel)
    missing = [r for r, p in plan.items() if not p or not Path(p).exists()]
    require(not missing, "Lucy base sources missing (%s): %s" % (suf or "plain", missing))
    return plan


def ensure_lucy(rc, force: bool = False) -> dict:
    require(cfg.LUCY_CONFIGURED and cfg.LUCY_ROOT.is_dir(),
            "Lucy's workspace is not configured: %s must name its folder (root) and build recipe (recipe) - a LOCAL "
            "file, never pushed (final repair 2026-10-03)" % cfg.LUCY_LOCAL)
    for rel in cfg.LUCY_ICON_MENU:
        ref = cfg.LUCY_ROOT / "base" / "merge_v63" / rel
        require(md5_file(rc.res(rel)) == md5_file(ref),
                "%s differs from the one Lucy's icons were built from (merge_v63): rebuild the icons first" % rel)
    out = {}
    for suf, (bname, oname) in cfg.lucy_names(rc.name).items():
        bdir, odir = cfg.LUCY_ROOT / "base" / bname, cfg.LUCY_ROOT / "build" / oname
        plan = lucy_plan(rc, suf)
        plan_md5 = {r: md5_file(p) for r, p in sorted(plan.items())}
        fresh_base = bdir.is_dir() and all((bdir / r).exists() and md5_file(bdir / r) == plan_md5[r] for r in plan) \
            and sorted(x.lower() for x in files_under(bdir, skip_underscore=False)) == sorted(x.lower() for x in list(plan) + ["SOURCE.txt"])
        built_on = None
        try:
            built_on = read_json(odir / "build_report.json")["regulation"]["edition"]["base"]
        except (OSError, ValueError, KeyError, TypeError):
            built_on = None
        # the build is tied to the base CONTENT, not just its folder name: work\products\<rc>\lucy_stamp_<x>.json
        # records the base md5s it was built from and the regulation it produced. A build made before the stamps
        # existed is adopted only when it is newer than its base (SOURCE.txt is written when the base is made);
        # lucy_param_equality then also checks the regulation content against the RC's.
        stamp_p = pdir(rc.name) / ("lucy_stamp%s.json" % (suf or "_plain"))
        out_reg = odir / "mod" / "regulation.bin"
        why = ""
        if not (fresh_base and built_on == bname and out_reg.exists()) or force:
            why = "forced" if force else "base or build missing or made from another base"
        elif stamp_p.exists():
            st = read_json(stamp_p)
            if st.get("base") != bname or st.get("base_md5") != plan_md5:
                why = "the base content changed since the build (stamp)"
            elif st.get("build_regulation_sha256") != sha256_file(out_reg):
                why = "the build's regulation changed since the stamp"
        else:
            try:
                newer = (odir / "build_report.json").stat().st_mtime > (bdir / "SOURCE.txt").stat().st_mtime
            except OSError:
                newer = False
            if not newer:
                why = "no stamp, and the build is not newer than its base"
        reuse = not why
        log("Lucy%s: base %s (%s) -> build %s (%s)" % (suf or " plain", bname, "up to date" if fresh_base else "to (re)create",
                                                       oname, "reuse" if reuse else "to build: " + why))
        if not reuse:
            util.EXTRA_ALLOWED.extend(cfg.lucy_write_roots(rc.name))
            if not fresh_base:
                util.rmtree_guarded(bdir)
                for rel, srcp in plan.items():
                    util.copy_file(srcp, bdir / rel)
                write_text(bdir / "SOURCE.txt",
                           "Merge v6.5 build %s%s: regulation + item_dlc02 + menu\\hi\\01_common + menu_dlc02 resolved "
                           "through [%s] then v65\\opus\\build\\base (shipped v6.4)%s. Created by "
                           "v65\\installer\\pipeline\\products.py %s.\n" % (
                               rc.name, " + Nightreign Movement" if suf else "", "; ".join(str(c) for c in rc.chain),
                               "; from the NRM layer %s: %s" % (rc.nrm, sorted(
                                   r for r, q in plan.items() if str(q).lower().startswith(str(rc.nrm).lower())))
                               if suf else "", util.now_stamp()))
            py314 = shutil.which("python")
            ver = run([py314, "-c", "import sys; print('%d.%d' % sys.version_info[:2])"]).stdout.strip() if py314 else ""
            cmd = ([py314] if ver == "3.14" else cfg.PY314[:2]) + [
                cfg.LUCY_ROOT / "scripts" / "build_all.py", oname] + list(cfg.LUCY_RECIPE) + ["--base=" + bname]
            logp = cfg.LOGS / ("lucy_%s.log" % oname)
            r = run(cmd, cwd=cfg.V65 / "opus" / "work", log_to=logp, timeout=3600)
            require(r.returncode == 0 and "BUILD OK" in r.stdout, "Lucy build %s failed (log %s)" % (oname, logp))
            log("   built %s" % odir)
        mod = odir / "mod"
        files = {"mod\\" + rel: mod / rel for rel in files_under(mod, skip_underscore=False)}
        require(files.get("mod\\regulation.bin"), "Lucy build %s has no regulation.bin" % oname)
        st = {"base": bname, "base_md5": plan_md5, "build": oname, "build_regulation_sha256": sha256_file(out_reg),
              "rc": rc.name, "how": "built by the pipeline" if not reuse else "adopted (built before the stamps existed)",
              "at": util.now_stamp()}
        old = read_json(stamp_p) if stamp_p.exists() else None
        if not (reuse and old and all(old.get(k) == st[k] for k in ("base", "base_md5", "build_regulation_sha256"))):
            write_json(stamp_p, st)
        out[suf or "plain"] = {"base": bname, "build": oname, "mod": mod, "files": files, "reused": reuse}
    out["nrm"] = out.pop("_nrm")
    return out


def ensure_nrm_menu(src: dict, rc, lucy: dict) -> dict:
    """{mod rel: file} of Lucy + NRM's menu\\hi\\01_common pair, {} when the NRM layer does not ship that pair (beta.16).
    NRM 0.2 changes the pair Lucy ships (its skill icons; she ships her own icon in it): the Lucy + NRM selection gets
    Lucy's pair with NRM's changed layout + texture put in, by the RC lane's composer (inputs.nrm_menu_composer, a 3-way
    at member level that asserts no clash and re-reads what it wrote). The pair deploy_v65.py composed for the field
    test (inputs.nrm_menu_tested_pattern) is adopted when its sources are exactly this build's (same bytes as tested);
    else the composer runs into work\\lucy_nrm_menu\\<rc>\\. Either way the result must be what the composer's own
    report says it wrote, and - when the tested pair exists with the same sources - byte-identical to it."""
    inp = src["inputs"]
    if not all((rc.nrm / rel).is_file() for rel in cfg.LUCY_ICON_MENU):
        return {}
    roots = {str(rc.res(rel))[:-len(rel) - 1] for rel in cfg.LUCY_ICON_MENU}
    require(len(roots) == 1, "the build's two 01_common files come from different roots: %s" % roots)
    srcs = {"base": Path(roots.pop()), "nrm": rc.nrm, "lucy": lucy["plain"]["mod"]}
    want = {k: {rel: md5_file(d / rel) for rel in cfg.LUCY_ICON_MENU} for k, d in srcs.items()}
    out = cfg.WORK / "lucy_nrm_menu" / rc.name

    def fresh(d: Path) -> bool:
        try:
            rep_ = read_json(d / "LUCY_NRM_MENU.json")
        except (OSError, ValueError):
            return False
        return rep_.get("sources") == want and all(
            (d / rel).is_file() and md5_file(d / rel) == (rep_.get("out") or {}).get(rel) for rel in cfg.LUCY_ICON_MENU)

    tested = Path(inp["nrm_menu_tested_pattern"].replace("{rc}", rc.name)) if inp.get("nrm_menu_tested_pattern") else None
    how = "up to date"
    if not fresh(out):
        if tested and fresh(tested):
            for rel in cfg.LUCY_ICON_MENU + ["LUCY_NRM_MENU.json"]:
                util.copy_file(tested / rel, out / rel)
            how = "adopted the pair deploy_v65.py composed for the field test (%s)" % tested
        else:
            require(inp.get("nrm_menu_composer") and Path(inp["nrm_menu_composer"]).is_file(),
                    "Lucy + NRM menu: the composer inputs.nrm_menu_composer is missing (%s)" % inp.get("nrm_menu_composer"))
            util.guard_write(out).mkdir(parents=True, exist_ok=True)
            logp = cfg.LOGS / ("lucy_nrm_menu_%s.log" % rc.name)
            r = run(cfg.PY311 + [inp["nrm_menu_composer"], "--base", srcs["base"], "--nrm", srcs["nrm"], "--lucy",
                                 srcs["lucy"], "--out", out], cwd=Path(inp["framework"]), log_to=logp, timeout=1800)
            require(r.returncode == 0 and "LUCY+NRM MENU OK" in r.stdout and fresh(out),
                    "Lucy + NRM menu: the composer failed (log %s)" % logp)
            how = "composed now"
    rep_ = read_json(out / "LUCY_NRM_MENU.json")
    if tested and (tested / "LUCY_NRM_MENU.json").is_file():
        trep = read_json(tested / "LUCY_NRM_MENU.json")
        if trep.get("sources") == want:
            require(trep.get("out") == rep_.get("out"), "Lucy + NRM menu: the pair here %s differs from the field-tested "
                    "pair %s made from the same sources" % (rep_.get("out"), trep.get("out")))
            how += "; == the field-tested pair"
    log("Lucy + NRM menu %s: %s (NRM changed %s / %s; Lucy's own %s kept)" % (
        out, how, rep_.get("nrm_changed_layouts"), rep_.get("nrm_changed_textures"), len(rep_.get("lucy_own") or [])))
    return {"mod\\" + rel: out / rel for rel in cfg.LUCY_ICON_MENU}


def lucy_build_checks(rc, lucy: dict) -> dict:
    """Lucy's own build checks on both of the RC's Lucy builds (rc8 switch prep 2026-10-03): the checks her own
    workspace provides, named in the LOCAL file (cfg.LUCY_LOCAL 'build_checks': script, args with {build} / {base},
    python, cwd); each must exit 0; none configured = refused (fail closed). Verdicts are cached per (check, every
    input file's md5)."""
    checks = cfg.LUCY_BUILD_CHECKS
    require(checks, "Lucy's own build checks are not configured: %s must list them under 'build_checks' (LOCAL file, "
            "never pushed)" % cfg.LUCY_LOCAL)
    cache_p = pdir(rc.name) / "lucy_checks.json"
    cache = read_json(cache_p) if cache_p.exists() else {}
    out = {}
    for suf, (bname, oname) in cfg.lucy_names(rc.name).items():
        mod = cfg.LUCY_ROOT / "build" / oname / "mod"
        base = cfg.LUCY_ROOT / "base" / bname
        ins = {"build": {r: md5_file(mod / r) for r in files_under(mod, skip_underscore=False)},
               "base": {r: md5_file(base / r) for r in files_under(base, skip_underscore=False)}}
        for i, c in enumerate(checks):
            script = Path(c["script"])
            key = util.fingerprint([c, sha256_file(script), ins])
            label = "%s check %d (%s)" % (oname, i + 1, script.name)
            if cache.get(label, {}).get("key") == key and cache[label].get("ok"):
                log("Lucy build check %s: passed (cached)" % label)
                out[label] = cache[label]
                continue
            args = [str(a).replace("{build}", oname).replace("{base}", bname) for a in c.get("args", [])]
            py = cfg.PY311 if c.get("python") == "3.11" else cfg.PY314
            logp = cfg.LOGS / ("lucy_check_%s_%d.log" % (oname, i + 1))
            r = run(py + [script] + args, cwd=cfg.expand(c.get("cwd") or str(cfg.V65 / "opus" / "work")), log_to=logp,
                    timeout=3600)
            last = (r.stdout.strip().splitlines() or [""])[0]
            res = {"key": key, "ok": r.returncode == 0, "summary": last[:300], "at": util.now_stamp()}
            cache[label] = res
            write_json(cache_p, cache)
            require(r.returncode == 0, "Lucy build check %s FAILED (exit %d, log %s): %s" % (
                label, r.returncode, logp, (r.stdout + r.stderr)[-800:]))
            log("Lucy build check %s: passed (%s)" % (label, last[:200]))
            out[label] = res
    return out


def tool_sha(p) -> str:
    """the sha256 of a checking tool: part of every cache key of its verdicts (a changed tool re-checks everything)"""
    return sha256_file(p)


def lucy_param_equality(rc, lucy: dict) -> dict:
    """Lucy plain == Lucy NRM in every param member, AND each equals the RC's regulation in every member except the
    ones Lucy's recipe changes (cfg.LUCY_PARAM_MEMBERS): a Lucy regulation built on another RC fails here."""
    rc_name = rc.name
    r0 = rc.res("regulation.bin")
    a, b = lucy["plain"]["files"]["mod\\regulation.bin"], lucy["nrm"]["files"]["mod\\regulation.bin"]
    tool = cfg.TOOLS / "regparams.py"
    key = "%s|%s|%s|tool %s|lucy %s" % (sha256_file(a), sha256_file(b), sha256_file(r0), tool_sha(tool),
                                        ",".join(cfg.LUCY_PARAM_MEMBERS))
    cache = pdir(rc_name) / "lucy_params.json"
    if cache.exists():
        c = read_json(cache)
        if c.get("key") == key:
            require(c["equal"], "Lucy plain and Lucy NRM regulations differ in params (cached): %s" % c.get("diff"))
            require(c.get("vs_rc_ok"), "Lucy regulation vs the %s regulation (cached): %s" % (rc_name, c.get("vs_rc_diff")))
            log("Lucy regulation params: plain == NRM, and == %s except Lucy's %d members (%d members, cached)" % (
                rc_name, len(cfg.LUCY_PARAM_MEMBERS), c.get("members", 0)))
            return c
    tmp = pdir(rc_name) / "_lucy_params_out.json"
    util.guard_write(tmp).parent.mkdir(parents=True, exist_ok=True)
    r = run(cfg.PY311 + [tool, "members", tmp, a, b, r0], cwd=cfg.V65 / "opus" / "work",
            log_to=cfg.LOGS / ("regparams_lucy_%s.log" % rc_name), timeout=1800)
    require(r.returncode == 0, "regparams.py failed: %s" % r.stderr[-2000:])
    res = json.loads(tmp.read_text(encoding="utf-8"))
    tmp.unlink()
    ma, mb, m0 = res[str(a)], res[str(b)], res[str(r0)]
    diff = sorted(k for k in set(ma) | set(mb) if ma.get(k) != mb.get(k))
    vs_rc = sorted(k for k in set(ma) | set(m0) if ma.get(k) != m0.get(k))
    vs_rc_ok = vs_rc == sorted(cfg.LUCY_PARAM_MEMBERS)
    c = {"key": key, "equal": not diff, "members": len(ma), "diff": diff, "vs_rc_ok": vs_rc_ok, "vs_rc_diff": vs_rc}
    write_json(cache, c)
    require(not diff, "Lucy plain and Lucy NRM regulations differ in params: %s" % diff)
    require(vs_rc_ok, "the Lucy regulation differs from the %s regulation in %s (expected exactly Lucy's members %s): "
            "it was built on another RC - rebuild with --force-products" % (rc_name, vs_rc, cfg.LUCY_PARAM_MEMBERS))
    log("Lucy regulation params: plain == NRM (%d members identical); vs %s only Lucy's %s differ" % (
        len(ma), rc_name, vs_rc))
    return c


# ------------------------------------------------------------------ Infinite Durations
def merge_final_ids() -> set:
    return {int(c["id"]) for c in json.load(open(cfg.VENDOR_INFDUR / "merge_final.json"))}


def new_speffect_rows(rc_name: str, base_reg, reg, label: str) -> dict:
    key = "%s|%s|tool %s" % (sha256_file(base_reg), sha256_file(reg), tool_sha(cfg.TOOLS / "regparams.py"))
    cache = pdir(rc_name) / ("speffect_new_%s.json" % label)
    if cache.exists():
        c = read_json(cache)
        if c.get("key") == key:
            return c
    tmp = pdir(rc_name) / ("_speffect_%s.json" % label)
    util.guard_write(tmp).parent.mkdir(parents=True, exist_ok=True)
    r = run(cfg.PY311 + [cfg.TOOLS / "regparams.py", "speffect-new", tmp, base_reg, reg], cwd=cfg.V65 / "opus" / "work",
            log_to=cfg.LOGS / ("regparams_speffect_%s_%s.log" % (rc_name, label)), timeout=1800)
    require(r.returncode == 0, "regparams.py speffect-new failed: %s" % r.stderr[-2000:])
    c = json.loads(tmp.read_text(encoding="utf-8"))
    tmp.unlink()
    c["key"] = key
    write_json(cache, c)
    return c


def infdur_check_new_rows(rc, lucy, ack: set) -> dict:
    listed = merge_final_ids()
    out = {}
    for label, base_reg, reg in (("rc_vs_base", rc.base / "regulation.bin", rc.res("regulation.bin")),
                                 ("lucy_vs_rc", rc.res("regulation.bin"), lucy["plain"]["files"]["mod\\regulation.bin"])):
        c = new_speffect_rows(rc.name, base_reg, reg, label)
        finite = [(i, d, n) for i, d, n in c["new"] if d > 0]
        unlisted = [(i, d, n) for i, d, n in finite if i not in listed and i not in ack]
        log("InfDur new-row check %s: %d new SpEffect rows, %d with a finite duration, unlisted %s (merge_final.json lists %s)" % (
            label, len(c["new"]), len(finite), [i for i, _, _ in unlisted] or "none",
            [i for i, _, _ in finite if i in listed] or "-"))
        require(not unlisted,
                "Infinite Durations: new SpEffect row(s) with a finite duration that merge_final.json does not list: %s. "
                "Add them to pipeline\\vendor\\infdur\\merge_final.json (category aow_weapon_buff / aow_buff) or accept with "
                "--infdur-ack %s" % (unlisted, ",".join(str(i) for i, _, _ in unlisted)))
        out[label] = {"new": c["new"], "finite_listed": [i for i, _, _ in finite if i in listed],
                      "acked": [i for i, _, _ in finite if i in ack]}
    return out


def ensure_infdur(rc, lucy, force: bool = False) -> dict:
    b65 = cfg.VENDOR_INFDUR / "build65.py"
    mf = cfg.VENDOR_INFDUR / "merge_final.json"
    inputs = {"plain": (rc.res("regulation.bin"), rc.res(r"msg\engus\item_dlc02.msgbnd.dcx")),
              "lucy": (lucy["plain"]["files"]["mod\\regulation.bin"],
                       lucy["plain"]["files"]["mod\\msg\\engus\\item_dlc02.msgbnd.dcx"])}
    out = {}
    for kind, (reg, msg) in inputs.items():
        run_name = "v65_%s_%s" % (rc.name, kind)
        rdir = cfg.INFDUR_RUNS / run_name
        stamp = {"reg": sha256_file(reg), "msg": sha256_file(msg), "build65": sha256_file(b65), "merge_final": sha256_file(mf),
                 "ver": "V6.5"}
        regs = {"v%d" % n: rdir / "build" / ("V%d" % n) / "regulation.bin" for n in range(1, 5)}
        sp = rdir / "pipeline_stamp.json"
        ok = (not force) and sp.exists() and read_json(sp) == stamp and all(p.exists() for p in regs.values())
        if not ok:
            log("InfDur %s: building (%s)" % (run_name, "forced" if force else "inputs changed or missing"))
            util.guard_write(rdir)
            r = run(cfg.PY314 + [b65, "--reg", reg, "--run", run_name, "--msg", msg, "--ver", "V6.5"],
                    cwd=cfg.VENDOR_INFDUR, log_to=cfg.LOGS / ("infdur_%s.log" % run_name), timeout=3600)
            require(r.returncode == 0 and "ALL 4 V6.5 ADD-ONS BUILT AND VERIFIED" in r.stdout,
                    "InfDur build %s failed (log logs\\infdur_%s.log): %s" % (run_name, run_name, (r.stdout + r.stderr)[-1500:]))
            man = read_json(rdir / "manifest.json")
            require(man["input_md5"] == hash_file(reg)["md5"], "InfDur manifest input md5 mismatch")
            write_json(sp, stamp)
        else:
            log("InfDur %s: up to date (reused)" % run_name)
        out[kind] = {k: v for k, v in regs.items()}
        out[kind + "_run"] = rdir
    return out


# ------------------------------------------------------------------ files from zips (arrows, ercap)
def zip_member_file(rc_name: str, comp_id: str, f: dict) -> Path:
    # stored under the FULL destination path: two files[] entries with the same file name in different folders
    # (a multi-language mod) must never overwrite each other here
    dst = pdir(rc_name) / "files" / comp_id / f["dest"]
    with zipfile.ZipFile(f["from_zip"]) as z:
        data = z.read(f["member"])
    if not dst.exists() or dst.read_bytes() != data:
        util.guard_write(dst).parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(data)
    if f.get("expect_md5"):
        require(util.md5_bytes(data) == f["expect_md5"].lower(),
                "%s: %s md5 %s != %s" % (comp_id, f["member"], util.md5_bytes(data), f["expect_md5"]))
    if f.get("expect_sha256"):
        require(util.sha256_bytes(data) == f["expect_sha256"].lower(),
                "%s: %s sha256 %s != %s" % (comp_id, f["member"], util.sha256_bytes(data), f["expect_sha256"]))
    return dst


def ercap_sums_check(src: dict) -> None:
    c = [x for x in src["components"] if x["id"] == "ercap"]
    if not c:
        return
    c = c[0]
    za = c.get("zip_anchor")
    sums = Path(za["path"]).with_name("SHA256SUMS.txt") if za else None
    if not sums or not sums.exists():
        log("ERCap: no SHA256SUMS.txt next to the release zip (anchors checked by sha256 only)")
        return
    text = sums.read_text(encoding="utf-8", errors="replace").lower()
    want = [za["expect_sha256"].lower()] + [f["expect_sha256"].lower() for f in c.get("files", []) if f.get("expect_sha256")]
    missing = [h for h in want if h not in text]
    require(not missing, "ERCap: the author's SHA256SUMS.txt does not list %s" % missing)
    log("ERCap: zip + DLL sha256 equal the author's SHA256SUMS.txt")


def component_files(src: dict, rc_name: str) -> dict:
    out = {}
    for c in src["components"]:
        for f in c.get("files", []):
            out.setdefault(c["id"], {})[f["dest"]] = {"file": zip_member_file(rc_name, c["id"], f),
                                                      "upstream": f.get("upstream_url", "")}
    # each dest got its own file with its own member's bytes (no collision)
    for cid, fs in out.items():
        files = [str(v["file"]).lower() for v in fs.values()]
        require(len(files) == len(set(files)), "component %s: two files[] entries share one product file" % cid)
        for f in [x for c in src["components"] if c["id"] == cid for x in c.get("files", [])]:
            with zipfile.ZipFile(f["from_zip"]) as z:
                require(util.sha256_bytes(z.read(f["member"])) == sha256_file(fs[f["dest"]]["file"]),
                        "component %s: product file for %s does not hold member %s" % (cid, f["dest"], f["member"]))
    return out


# ------------------------------------------------------------------ packaging laws
def packcheck(regs: list[Path], packcheck_py: Path) -> dict:
    """G-PACK verdicts, cached by (regulation sha256, packcheck.py sha256): a new packaging law in packcheck.py is
    applied to every regulation again"""
    cache_p = cfg.WORK / "packcheck_cache.json"
    cache = read_json(cache_p) if cache_p.exists() else {}
    tsha = tool_sha(packcheck_py)
    shas = {str(p): sha256_file(p) + "|packcheck " + tsha for p in regs}
    todo = sorted({p for p, s in shas.items() if s not in cache})
    if todo:
        r = run(cfg.PY311 + [packcheck_py] + todo, cwd=packcheck_py.parent.parent,
                log_to=cfg.LOGS / "packcheck_last.log", timeout=3600)
        for line in r.stdout.splitlines():
            for tag, ok in (("PACK-PASS ", True), ("PACK-FAIL ", False)):
                if line.startswith(tag):
                    rest = line[len(tag):]
                    for p in todo:
                        if rest.startswith(p + " "):
                            cache[shas[p]] = {"ok": ok, "detail": rest[len(p) + 1:], "first_path": p}
        missing = [p for p in todo if shas[p] not in cache]
        require(not missing, "packcheck gave no verdict for %s (exit %d): %s" % (missing, r.returncode, r.stderr[-1500:]))
        write_json(cache_p, cache)
    res = {p: cache[s] for p, s in shas.items()}
    bad = [p for p, v in res.items() if not v["ok"]]
    require(not bad, "PACKAGING LAW VIOLATION (G-PACK) on %s" % bad)
    log("G-PACK: PACK-PASS on all %d regulations (%d distinct; %d checked now, rest cached; packcheck.py %s)" % (
        len(regs), len(set(shas.values())), len(todo), tsha[:12]))
    return {p: {"sha256": shas[p].split("|", 1)[0], "packcheck_sha256": tsha, **v} for p, v in res.items()}


# ------------------------------------------------------------------ all
def build_products(src: dict, rc, force_lucy=False, force_infdur=False, infdur_ack=frozenset()) -> dict:
    lucy = ensure_lucy(rc, force=force_lucy)
    lucy_checks = lucy_build_checks(rc, lucy)
    nrm_menu = ensure_nrm_menu(src, rc, lucy)
    lucy_eq = lucy_param_equality(rc, lucy)
    # the catalog's own acknowledged SpEffect ids (DMN's rows, final pass) + the command line's
    ack = set(int(x) for x in src["inputs"].get("infdur_ack", [])) | set(infdur_ack)
    newrows = infdur_check_new_rows(rc, lucy, ack)
    infdur = ensure_infdur(rc, lucy, force=force_infdur)
    ercap_sums_check(src)
    cfiles = component_files(src, rc.name)
    regs = [rc.res("regulation.bin"), lucy["plain"]["files"]["mod\\regulation.bin"], lucy["nrm"]["files"]["mod\\regulation.bin"]]
    regs += [infdur[k][e] for k in ("plain", "lucy") for e in ("v1", "v2", "v3", "v4")]
    if (rc.nrm / "regulation.bin").exists():
        regs.append(rc.nrm / "regulation.bin")
    pack = packcheck(regs, Path(src["inputs"]["packcheck"]))
    refs = {}
    for a in src["archives"]:
        if a.get("enabled", True) and a["reference"]["kind"] in ("folder", "zip"):
            refs[a["id"]] = a["reference"]["path"]
    prod = {
        "rc": rc.name,
        "chain": [str(c) for c in rc.chain],
        "base": str(rc.base),
        "main_tree_paths": len(rc.main),
        "nrm_layer": str(rc.nrm),
        "nrm_ini": str(rc.nrm_ini),
        "nrm_block": str(rc.nrm_block),
        "dmn": {"plain": str(rc.dmn), "nrm": str(rc.dmn_nrm)} if rc.dmn else {},
        "nrm_tier": rc.nrm_report.get("tier"),
        # 2026-10-03 (Luka): the DMN layers that are ERCap-only states ('nrm' = dmn_nrmw_<rc>); the installer adds
        # ERCapacityExpansion for every selection that uses one (the oracle derives the same from the layer's own
        # DMN_ERCAP_STATE.json). The rc8 switch prep's nrm_sibling / nrm_dmn_base are gone.
        "dmn_ercap_only": {k: {"m2": v["m2"], "state_file": v["state_file"], "state_md5": v["state_md5"]}
                           for k, v in rc.dmn_ercap_only.items()},
        "nrm_menu": {k: str(v) for k, v in nrm_menu.items()},
        "lucy": {"plain": str(lucy["plain"]["mod"]), "nrm": str(lucy["nrm"]["mod"]),
                 "regulation_canonical": str(lucy["plain"]["files"]["mod\\regulation.bin"]),
                 "params_equal": lucy_eq["equal"], "build_checks": {k: v["summary"] for k, v in lucy_checks.items()}},
        "infdur": {"plain": {k: str(v) for k, v in infdur["plain"].items()},
                   "lucy": {k: str(v) for k, v in infdur["lucy"].items()},
                   "runs": {"plain": str(infdur["plain_run"]), "lucy": str(infdur["lucy_run"])},
                   "new_row_check": newrows},
        "arrows_dll": str(cfiles.get("arrows", {}).get("mod\\dll\\infinite_arrows.dll", {}).get("file", "")),
        "ercap": {"dll": str(cfiles.get("ercap", {}).get("mod\\dll\\CapacityExpansion.dll", {}).get("file", "")),
                  "license": str(cfiles.get("ercap", {}).get("mod\\dll\\licenses\\ERCapacityExpansion\\LICENSE.txt", {}).get("file", ""))},
        "component_files": {c: {d: str(v["file"]) for d, v in fs.items()} for c, fs in cfiles.items()},
        "convergence_pristine": src["inputs"]["convergence_pristine"],
        "references": refs,
        "packcheck": pack,
        "main_zip": "",
        "wall": {},
    }
    return {"json": prod, "lucy": lucy, "infdur": infdur, "files": cfiles, "nrm_menu": nrm_menu}


def write_products_json(rc_name: str, prod_json: dict) -> Path:
    return write_json(pdir(rc_name) / "products.json", prod_json)
