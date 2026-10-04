r"""release.py --rc <rc> --all: the ONE command that takes a release candidate (or a new version after the catalog
edits of INSTALLER_V65.md section 4) to "ready to publish" (final pass part 2, 2026-10-03; Luka: "the installer being
able to be updated super fast").

Steps (each timed; the summary prints a table and what is left for a human):
  1. build      the pipeline (catalog, variants, main zip, release assets, generated includes) + the codecheck, TEST and
                RELEASE exes. An exe whose out folder records exactly these inputs (BUILD_INPUTS.json: code fingerprint,
                catalog, ISCC, defines) is reused; the others compile at the same time. Holds work\release.lock.
  2. tests      the test gate (tests\run_all.py, ~85 min, every Setup runs one at a time by design) - SKIPPED when a
                complete passing results file already exists for this catalog AND this installer code (that is
                exactly what --final accepts, so a re-run would prove nothing new). --retest / --cold force it. A
                passing results file it would overwrite is copied to tests\results\_prev\ first. It runs in the
                background while steps 3-4 go over the network.
  3. (retired 2026-10-03: the second download site; every hosted file is a GitHub release asset now)
  4. github     the PRIVATE repo's files (one commit, only when something changed) + the DRAFT release's assets: an
                asset already there with the catalog's size and GitHub's own sha256 digest is skipped, the rest upload
                3 at a time. Never public, never published.
  5. gates      after the tests: the --final gates (pages, changelog, tests for this catalog + code, tag not published).
  6. check      publish_github.py --check (read-only): exe <-> sidecar <-> catalog, base URL, draft assets = catalog,
                repo-file content scan incl. the whole history (cached per git blob).
  7. download   (--cold or --verify-download) every draft asset downloaded back with gh's login, size + SHA-256.
  8. drafts     v65\dist\_drafts\: RELEASE_FILES_<ver>.txt + the AUTO blocks (sizes, md5s) + a lint (pipeline\drafts.py).
--cold: everything is re-done except the per-RC products - file hashes re-read, main zip rebuilt, every exe compiled, the test gate re-run,
the history scan and every asset downloaded again. (Per-RC products - Lucy, Infinite Durations, G-PACK - are reused
when their inputs are unchanged; a NEW RC builds them: 47 s measured on rc7.)
Exit 0 = READY to publish (publish_github.py --publish is a separate, deliberate step); 1 = NOT READY (the report
says why); 2 = crashed.
"""
from __future__ import annotations

import argparse
import datetime
import json
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

from . import catalog_src, cfg, checks, drafts, ghstage, run_pipeline, util
from .util import BuildError, log, require, write_json


class Lane(threading.Thread):
    """a step that runs next to the others; .result / .error / .secs"""

    def __init__(self, name, fn):
        super().__init__(daemon=True, name=name)
        self.fn, self.result, self.error, self.secs = fn, None, None, None

    def run(self):
        t = time.time()
        try:
            self.result = self.fn()
        except BaseException as e:      # noqa: BLE001  (reported by the main thread)
            self.error = e
        self.secs = round(time.time() - t, 1)


def _catalog(tag: str) -> tuple[dict, str]:
    p = cfg.DIST / tag / "catalog.json"
    return json.loads(p.read_text(encoding="utf-8")), util.sha256_bytes(p.read_bytes())


def _results_files(tag: str, rc: str) -> list[Path]:
    return sorted(cfg.TESTS_RESULTS.glob("%s_%s_*.json" % (tag, rc)))


def run_tests(rc: str, tag: str, stamp: str) -> dict:
    """tests\\run_all.py --rc <rc> as a child process (it starts release.py --emit-only itself: the lock is free)"""
    prev = cfg.TESTS_RESULTS / "_prev"
    kept = []
    for p in _results_files(tag, rc):
        prev.mkdir(parents=True, exist_ok=True)
        dst = prev / ("%s.before_%s.json" % (p.stem, stamp))
        shutil.copyfile(p, dst)
        kept.append(str(dst))
    logp = cfg.LOGS / ("all_%s_run_all.log" % stamp)
    t = time.time()
    with open(logp, "w", encoding="utf-8") as fh:
        # 2026-10-03: refresh sb\_fixtures first. The pipeline rebuilds the main zip, and a stale fixture copy made
        # every Setup refuse the main download (rc8 gate: 0 passing installs). tests\fixtures.py replaces stale links.
        fx = subprocess.run(cfg.PY311 + [str(cfg.INST / "tests" / "fixtures.py")],
                            cwd=str(cfg.INST), stdout=fh, stderr=subprocess.STDOUT)
        fh.flush()
        if fx.returncode != 0:
            return {"exit": fx.returncode, "secs": round(time.time() - t, 1), "log": str(logp),
                    "tail": ["tests\\fixtures.py failed (exit %d): fixtures not refreshed, tests not run" % fx.returncode],
                    "previous_results_copied_to": kept}
        r = subprocess.run(cfg.PY311 + [str(cfg.INST / "tests" / "run_all.py"), "--rc", rc, "--tag", tag],
                           cwd=str(cfg.INST), stdout=fh, stderr=subprocess.STDOUT)
    tail = logp.read_text(encoding="utf-8", errors="replace").strip().splitlines()[-3:]
    return {"exit": r.returncode, "secs": round(time.time() - t, 1), "log": str(logp), "tail": tail,
            "previous_results_copied_to": kept}


def run(args, cmdline: str, stamp: str, acquire_lock, release_lock) -> int:
    t_all = time.time()
    T: dict[str, float] = {}
    rep = {"command": cmdline, "started": util.now_stamp(), "cold": bool(args.cold), "steps": {}}
    problems: list[str] = []

    # ---------------------------------------------------------------- 1. build (the only step that holds the lock)
    t = time.time()
    lock = acquire_lock()
    try:
        if args.cold:
            util._HC = {}                 # every file hash read again (the cache is rewritten at the end)
            util._HC_DIRTY = 1
        bargs = argparse.Namespace(rc=args.rc, emit_only=False, build="all", stage_github=False, final=False,
                                   force_products=False, force_infdur=False, force_zip=bool(args.cold),
                                   infdur_ack=args.infdur_ack, skip_selftest_zip=False,
                                   exe_cache=True, force_exe=bool(args.cold), parallel_iscc=True)
        brep = run_pipeline.run(bargs, cmdline, stamp)
        util.save_hashcache()
    finally:
        release_lock(lock)
    T["1 build"] = round(time.time() - t, 1)
    tag, rc, cat_sha, code_fp = brep["tag"], brep["rc"], brep["catalog_sha256"], brep["code_fingerprint"]
    rep["steps"]["build"] = {"rc": rc, "tag": tag, "catalog_sha256": cat_sha, "code_fingerprint": code_fp,
                             "counts": brep["counts"], "step_secs": brep.get("step_secs"),
                             "exes": {k: {"sha256": v["sha256"], "md5": v["md5"], "size": v["size"],
                                          "cached": bool(v.get("cached")), "secs": v["secs"]}
                                      for k, v in brep["builds"].items()},
                             "main_zip": brep.get("main_zip")}
    m, cat_sha2 = _catalog(tag)
    require(cat_sha2 == cat_sha, "dist\\%s\\catalog.json is not this build's catalog" % tag)
    src = catalog_src.load()

    # ---------------------------------------------------------------- 2. the test gate (background) if needed
    g0 = checks.final_gates(m, src, cat_sha, tag, code_fp, check_published=False)
    need_tests = bool(args.cold or args.retest or not g0["passing_results"])
    tests_lane = None
    if need_tests:
        why = "--cold" if args.cold else "--retest" if args.retest else "no complete passing results for catalog %s + code %s" % (
            cat_sha[:16], code_fp[:16])
        log("tests: running tests\\run_all.py --rc %s in the background (%s); log logs\\all_%s_run_all.log" % (rc, why, stamp))
        tests_lane = Lane("tests", lambda: run_tests(rc, tag, stamp))
        tests_lane.start()
    else:
        log("tests: reused %s (complete, passing, this catalog + this installer code, every (component, state) "
            "installed + verified + uninstalled) - the gate needs nothing new" % [Path(p).name for p in g0["passing_results"]])
        rep["steps"]["tests"] = {"reused": [Path(p).name for p in g0["passing_results"]]}
        T["2 tests"] = 0.0

    # ---------------------------------------------------------------- 4. GitHub (while the tests run)
    t = time.time()
    try:
        if args.no_upload:
            log("GitHub: --no-upload: staging skipped")
            rep["steps"]["github"] = {"skipped": "--no-upload"}
        else:
            rep["steps"]["github"] = ghstage.stage(m, src, tag)
    except BuildError as e:
        problems.append("GitHub staging: %s" % e)
        rep["steps"]["github"] = {"error": str(e)}
    T["4 github"] = round(time.time() - t, 1)

    # ---------------------------------------------------------------- 2'. wait for the tests
    if tests_lane is not None:
        if tests_lane.is_alive():
            log("tests: waiting for run_all (started %.0f min ago)" % ((time.time() - t_all - T["1 build"]) / 60))
        tests_lane.join()
        T["2 tests"] = tests_lane.secs
        if tests_lane.error:
            problems.append("tests crashed: %r" % tests_lane.error)
            rep["steps"]["tests"] = {"error": repr(tests_lane.error)}
        else:
            rep["steps"]["tests"] = tests_lane.result
            log("tests: run_all exit %s in %.0f min: %s" % (tests_lane.result["exit"], tests_lane.result["secs"] / 60,
                                                          " | ".join(tests_lane.result["tail"])))
        m, cat_sha3 = _catalog(tag)
        require(cat_sha3 == cat_sha, "the catalog changed while the tests ran (%s -> %s)" % (cat_sha[:16], cat_sha3[:16]))

    # ---------------------------------------------------------------- 5. --final gates (incl. "tag not published")
    t = time.time()
    fg = checks.final_gates(m, src, cat_sha, tag, code_fp)
    rep["steps"]["final_gates"] = {"problems": fg["problems"], "passing_results": [Path(p).name for p in fg["passing_results"]]}
    problems += ["--final gate: %s" % p for p in fg["problems"]]
    log("final gates: %s" % ("PASS (results %s)" % [Path(p).name for p in fg["passing_results"]] if not fg["problems"]
                              else "REFUSED: %s" % fg["problems"]))
    T["5 gates"] = round(time.time() - t, 1)

    # ---------------------------------------------------------------- 6. publish_github.py --check (read-only)
    t = time.time()
    try:
        sys.path.insert(0, str(cfg.INST))
        import publish_github as PG                     # noqa: E402  (the script's own checks, not a copy)
        if args.cold:
            try:
                ghstage.HISTORY_CACHE.unlink()
            except OSError:
                pass
        s = PG.gather(tag)
        rep["steps"]["publish_check"] = {"problems": s["problems"], "plan": s["plan"], "history": s["history"]}
        problems += ["publish check: %s" % p for p in s["problems"]]
        log("publish check: %s" % ("READY (nothing changed)" if not s["problems"] else "NOT READY: %s" % s["problems"][:6]))
    except BuildError as e:
        problems.append("publish check: %s" % e)
        rep["steps"]["publish_check"] = {"error": str(e)}
    T["6 publish check"] = round(time.time() - t, 1)

    # ---------------------------------------------------------------- 7. download every asset back (cold / asked)
    if args.cold or args.verify_download:
        t = time.time()
        try:
            v = ghstage.verify_by_download(dict(m, blobs=[b for b in m["blobs"] if not b.get("site")]), src, tag)
            rep["steps"]["verify_download"] = v
            ok = not (v["bad"] or v["missing"] or v["extra"])
            if not ok:
                problems.append("verify-download: bad %s missing %s extra %s" % (v["bad"][:3], v["missing"][:3], v["extra"][:3]))
            log("verify-download: %d/%d assets downloaded back match size + sha256 (%.1f MB, %.0f s)" % (
                v["ok"], v["checked"], v["bytes"] / 1048576, v["secs"]))
        except BuildError as e:
            problems.append("verify-download: %s" % e)
        T["7 verify-download"] = round(time.time() - t, 1)

    # ---------------------------------------------------------------- 8. drafts
    t = time.time()
    try:
        rep["steps"]["drafts"] = drafts.refresh(src, m, tag, None,
                                                rep["steps"].get("github") if isinstance(rep["steps"].get("github"), dict)
                                                else None)
    except (BuildError, OSError) as e:
        rep["steps"]["drafts"] = {"error": str(e)}
        problems.append("drafts: %s" % e)
    T["8 drafts"] = round(time.time() - t, 1)

    # ---------------------------------------------------------------- report
    total = round(time.time() - t_all, 1)
    rep.update(finished=util.now_stamp(), total_secs=total, step_secs=T, problems=problems, ready=not problems)
    rp = cfg.WORK / "products" / rc / ("ALL_REPORT_%s.json" % stamp)
    write_json(rp, rep)
    log("=" * 100)
    log("release.py --all%s, RC %s, tag %s: %s in %s" % (" --cold" if args.cold else "", rc, tag,
                                                          "READY to publish" if not problems else "NOT READY",
                                                          str(datetime.timedelta(seconds=int(total)))))
    for k in sorted(T):
        log("   %-20s %8.1f s%s" % (k, T[k], "  (in parallel with 4)" if k == "2 tests" and tests_lane else ""))
    for p in problems:
        log("   PROBLEM: %s" % p)
    gh = rep["steps"].get("github") or {}
    if gh.get("uploaded") is not None:
        log("   GitHub: %s, release draft=%s, %s assets (%s uploaded now, %s skipped by sha256)" % (
            gh.get("visibility"), gh.get("is_draft"), gh.get("assets_remote"), gh.get("uploaded"),
            gh.get("skipped_same_sha256")))
    for x in (rep["steps"].get("drafts") or {}).get("facts", {}).get("files", []):
        log("   %s: %s  %s B  md5 %s" % (x["kind"], x["name"], format(x["size"], ","), x["md5"]))
    log("   report: %s" % rp)
    log("   left for a human: publish_github.py --tag %s --publish --confirm \"PUBLISH %s\" (only after Luka's OK), then "
        "Luka uploads the two files above to Nexus (C:\\$MD\\EldenRing\\merge\\v65\\INSTALLER_V65.md section 2)" % (tag, tag))
    return 0 if not problems else 1
