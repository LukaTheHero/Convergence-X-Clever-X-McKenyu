"""The release pipeline's step order (called by installer\\release.py)."""
from __future__ import annotations

import time
from pathlib import Path

from . import (catalog_src, cfg, checks, codefp, compose, convmanifest, emit_iss, emit_json, legacy, mainzip, model,
               products, rcinputs, sources, util, wall)
from .util import BuildError, hash_file, log, read_json, require, step, write_json


def sync_changelog(src: dict) -> dict:
    """catalog\\CHANGELOG_v6.5.txt = the release-kit lane's draft (v65\\dist\\_drafts\\CHANGELOG_v65.txt) unless it was
    edited by hand after the last copy; a PLACEHOLDER file when there is no draft (allowed for RC builds only)."""
    dst = Path(src["release"]["changelog_source"])
    stamp_p = dst.with_name(dst.name + ".sync.json")
    st = read_json(stamp_p) if stamp_p.exists() else {}
    draft = cfg.CHANGELOG_DRAFT
    cur = hash_file(dst)["sha256"] if dst.exists() else None
    if draft.exists():
        d = hash_file(draft)["sha256"]
        if cur is None or (cur == st.get("copied_sha256") and d != st.get("draft_sha256")):
            util.copy_file(draft, dst)
            st = {"draft": str(draft), "draft_sha256": d, "copied_sha256": hash_file(dst)["sha256"], "at": util.now_stamp()}
            write_json(stamp_p, st)
            log("changelog: copied the release-kit draft %s -> %s" % (draft, dst))
        elif cur != st.get("copied_sha256"):
            log("changelog: %s was edited by hand after the last copy - kept as is" % dst)
        else:
            log("changelog: %s up to date with the draft" % dst.name)
    elif cur is None:
        util.write_text(dst, "PLACEHOLDER - the v6.5 changelog text comes from the release-kit lane.\n", newline="\r\n")
        log("changelog: no draft found, wrote a PLACEHOLDER (refused by --final)")
    text = dst.read_text(encoding="utf-8", errors="replace")
    return {"file": str(dst), "sha256": hash_file(dst)["sha256"], "placeholder": "PLACEHOLDER" in text}


def pristine_me3(src) -> list[list[str]]:
    out = []
    for prof in cfg.ME3_PROFILES:
        raw = (Path(src["inputs"]["convergence_pristine"]) / prof).read_bytes().decode("utf-8")
        require(raw.isascii() and "\r\n" in raw and not raw.endswith("\n") and "\n" not in raw.replace("\r\n", ""),
                "pristine %s: expected ASCII, CRLF line ends and no final line break" % prof)
        out.append(raw.split("\r\n"))
    return out


def anim_components(comp: compose.Composer) -> list[dict]:
    base = comp.combo_tree({})
    out = []
    for c in comp.hot:
        for s in range(1, c["n_states"]):
            t = comp.combo_tree({c["id"]: s})
            if any(util.sha256_file(t[k]) != util.sha256_file(base[k]) if (k in t and k in base) else (k in t) != (k in base)
                   for k in ["mod\\chr\\" + n for n in cfg.WALL_FILES]):
                out.append(c)
                break
    return out


def run(args, cmdline: str, stamp: str) -> dict:
    T = {}
    rep = {"command": cmdline, "started": util.now_stamp(), "python": util.py_info()}
    with step("P1 catalog source"):
        src = catalog_src.load()
        tag = src["release"]["tag"]
        rep["tag"] = tag
        cl = sync_changelog(src)
        rep["changelog"] = cl
    with step("P2 RC inputs"):
        name = rcinputs.resolve_name(src, args.rc)
        rc = rcinputs.RC(src, name)
        rep["rc"] = name
        # release prep 2026-10-03: the NRM layer must be built from the package the players download (nrm_02)
        pkg = rcinputs.nrm_package_problems(src, name)
        if pkg:
            require(getattr(args, "allow_other_nrm_package", False),
                    "%s - or, for a TEST build only, give --allow-other-nrm-package" % "; ".join(pkg))
            rep["not_releasable"] = pkg
            log("WARNING - TEST BUILD ONLY, NOT RELEASABLE (--allow-other-nrm-package): %s. The files the layer ships "
                "unchanged that the players' download lacks become release assets here; --final, --stage-github, "
                "--all and publish_github.py refuse this build." % "; ".join(pkg))
    with step("P3 products"):
        ack = {int(x) for x in args.infdur_ack.split(",") if x.strip()}
        prod = products.build_products(src, rc, force_lucy=args.force_products,
                                       force_infdur=args.force_products or args.force_infdur, infdur_ack=ack)
        products.write_products_json(name, prod["json"])
    with step("P5 references"):
        refs = sources.load_refs(src)
    with step("P6 compose"):
        comp = compose.Composer(src, rc, prod, refs)
        comp.compose(Path(cl["file"]))
    with step("P4 wall"):
        anim = anim_components(comp)
        w = wall.measure(src, name, comp.comps, comp.combo_tree, anim)
        # 2026-10-03 (Luka): DMN + NRM keeps Wylder -> over the no-DLL limit, the installer forces ERCapacityExpansion
        w["forced"] = wall.check_forced(src, comp.comps, w, rc.dmn_ercap_only)
        rep["wall_forced"] = w["forced"]
        prod["json"]["wall"] = {"main": w["base"]}
        for k, v in w["measured"].items():      # labels "main+<comp>=<state>" -> contract names ("main+nrm")
            if k != "main":
                prod["json"]["wall"][k.replace("=1", "")] = v
    with step("P7 main zip"):
        # built in work\mainzip\<tag>\ and published into dist\<tag>\ (+ v65\dist\) only after the --final gates
        # (code review repair 2, D4: a refused --final leaves dist\ as it was)
        zname = src["release"]["main_zip_name"]
        zpath = cfg.DIST / tag / zname
        zwork = cfg.WORK / "mainzip" / tag / zname
        zplan = mainzip.plan(rc, refs, src)
        mz = mainzip.ensure(zplan, zwork, force=args.force_zip)
        rep["main_zip"] = {"path": str(zpath), "v65_dist": str(cfg.V65_DIST / zname), "work": str(zwork),
                           "size": mz["size"], "sha256": mz["sha256"], "members": len(mz["members"])}
    with step("P6 sources + never-host"):
        comp.variants_and_sources(mz["members"], (mz["size"], mz["sha256"]))
        nh = comp.never_host(mz["members"])
    with step("P6 natives, detection, obsolete"):
        natives = model.build_natives(src, rc, comp.cidx)
        det = legacy.detection(src, comp, comp.paths, natives)
        obs = legacy.obsolete(src, comp.paths)
    with step("P8 conv manifest (in memory)"):
        written = set(comp.paths) | {o["rel"] for o in obs} | {f["dest"] for f in src["fields"]}
        entries, keep, bat_names = convmanifest.build(src, written, comp.conv_originals, name)
        _cm_text, cm_sha = convmanifest.render(entries, keep, bat_names, name, src["release"]["version_short"])
    with step("P8 catalog model (in memory)"):
        m = model.build_model(src, rc, comp, w, refs, mz, zname, det, obs, cm_sha, len(entries), pristine_me3(src),
                              natives)
        cat_sha = util.sha256_bytes(emit_json.catalog_json_text(m).encode("utf-8"))
        rep["catalog_sha256"] = cat_sha
    rep["counts"] = {"components": len(m["components"]), "paths": len(m["paths"]), "variants": len(m["variants"]),
                     "archives": len(m["archives"]), "members": sum(len(a["members"]) for a in m["archives"]),
                     "blobs": len(m["blobs"]), "blob_mb": round(sum(b["size"] for b in m["blobs"]) / 1048576, 1),
                     "detection": len(m["detection"]), "obsolete": len(m["obsolete"]), "natives": len(m["natives"])}
    rep["wall"] = {"base": w["base"], "measured": w["measured"], "state_wall": w["state_wall"]}
    rep["builds"] = {}
    kinds = {"none": [], "codecheck": ["codecheck"], "test": ["test"], "release": ["release"],
             "all": ["codecheck", "test", "release"]}[args.build]
    rep["code_fingerprint"] = codefp.code_fingerprint()
    if args.final:
        # BEFORE anything is written into dist\, generated\, staging\meta or the hosting trees, compiled or copied:
        # a refused --final leaves them (and output\) as they were (code review repair 2, D4)
        with step("P9 --final gates"):
            # the gates include the published-tag check (repair 3: inside checks.final_gates)
            fg = checks.final_gates(m, src, cat_sha, tag, rep["code_fingerprint"])
            rep["final"] = fg
            if fg["problems"]:
                rep["finished"] = util.now_stamp()
                emit_json.build_report(cfg.WORK / "products" / name / ("BUILD_REPORT_%s.json" % stamp), rep)
            require(not fg["problems"], "--final refused (nothing was compiled or copied; nothing was written into "
                                        "dist\\, generated\\ or staging\\): %s" % fg["problems"])
    with step("P7 main zip -> dist"):
        util.link_or_copy(zwork, zpath)
        util.link_or_copy(zwork, cfg.V65_DIST / zname)
        require(hash_file(zpath)["sha256"] == mz["sha256"], "main zip in dist differs from the built one")
        prod["json"]["main_zip"] = str(zpath)
    with step("P8 conv manifest + catalog + emit"):
        cm = convmanifest.write(entries, keep, bat_names, name, src["release"]["version_short"])
        require(cm["sha256"] == cm_sha, "conv manifest written != rendered")
        cat_path, cat_sha2 = emit_json.write_catalog(m, tag)
        require(cat_sha2 == cat_sha, "catalog.json written != rendered")
        bstamp = util.now_stamp()
        emit_iss.emit(m, cat_sha, bstamp)
        rep["catalog"] = str(cat_path)
        prod["json"]["catalog_sha256"] = cat_sha
        products.write_products_json(name, prod["json"])
        repo = emit_json.repo_files(m, src, prod, cat_sha, set(comp.conv_originals.values()))
    with step("P7 blob store + hosting trees"):
        assets = {b["sha256"]: b["asset"] for b in m["blobs"]}
        bs = mainzip.stage_blobs(comp.blobs, assets, tag)
        rep["hosting"] = bs
    with step("P9 checks"):
        rep["checks"] = {"catalog": checks.catalog_checks(m, comp, refs, tag), "hosted": checks.hosted_checks(m, tag),
                         "never_host": nh, "gpack": {p: v["ok"] for p, v in prod["json"]["packcheck"].items()}}
    if kinds:
        from . import iscc
        with step("P9 [Files] check"):
            rep["checks"]["iss_sources"] = checks.iss_sources_check()
        # release.py --all (final pass 2): an exe whose out folder records exactly these inputs (code fingerprint,
        # catalog, ISCC, defines) is reused instead of compiled again (its md5 stays stable for the Nexus upload);
        # the ones still to compile run at the same time (separate out folders and logs; same read-only inputs)
        compiled: dict[str, dict] = {}
        todo = list(kinds)
        if getattr(args, "exe_cache", False) and not getattr(args, "force_exe", False):
            for k in kinds:
                c = iscc.cached_exe(k, cat_sha, rep["code_fingerprint"])
                if c:
                    compiled[k] = c
                    log("ISCC %s: reused %s (compiled from these exact inputs, sha256 %s)" % (k, c["exe"], c["sha256"][:16]))
            todo = [k for k in kinds if k not in compiled]
        if todo and getattr(args, "parallel_iscc", False) and len(todo) > 1:
            from concurrent.futures import ThreadPoolExecutor
            with step("P9 ISCC %s (parallel)" % "+".join(todo)):
                with ThreadPoolExecutor(max_workers=len(todo)) as ex:
                    for k, r in zip(todo, ex.map(iscc.compile_, todo)):
                        compiled[k] = r
        for k in kinds:
            with step("P9 ISCC %s" % k):
                r = compiled.get(k) or iscc.compile_(k)
                require(r["catalog_sha256"] == cat_sha, "ISCC %s compiled catalog %s, this run made %s" % (
                    k, r["catalog_sha256"][:16], cat_sha[:16]))
                if k in ("test", "release"):
                    r["exe_check"] = checks.exe_checks(Path(r["exe"]), refs, comp, uncompressed=(k == "test"))
                if k == "release":
                    r["published"] = iscc.publish_release_exe(r, tag, name)
                rep["builds"][k] = r
    if args.stage_github:
        from . import ghstage
        require(not rep.get("not_releasable"), "--stage-github refused: this build is not releasable: %s" %
                rep.get("not_releasable"))
        with step("P10 GitHub staging (private repo + draft release)"):
            rep["github"] = ghstage.stage(m, src, tag)
    rep["step_secs"] = dict(util.STEP_TIMES)
    rep["finished"] = util.now_stamp()
    if "release" in kinds:
        # dist\<tag>\BUILD_REPORT.json describes the release exe in dist\<tag>\ (other runs only write the work copy)
        emit_json.build_report(cfg.DIST / tag / "BUILD_REPORT.json", rep)
    emit_json.build_report(cfg.WORK / "products" / name / ("BUILD_REPORT_%s.json" % stamp), rep)
    return rep
