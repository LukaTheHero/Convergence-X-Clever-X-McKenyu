"""P9: release checks - Clever never bundled (name + content) in the exe / main zip / blobs; no McKenyu / NRM / Seamless
author bytes hosted; exactly one resolvable source per variant; every member resolvable in its reference; every blob
present with the right sha256 in every hosting tree; MAX_PATH budget; exe size; --final gates."""
from __future__ import annotations

import glob
import json
import re
from pathlib import Path

from . import cfg
from .codefp import code_fingerprint
from .util import BuildError, hash_file, log, read_json, require


def unsafe_rel(rel: str) -> str:
    """'' when rel is a relative path that stays inside the folder it is relative to (the installer's IsSafeRelPath,
    util.iss, plus: backslashes only), else why not"""
    if not isinstance(rel, str) or not rel:
        return "empty"
    if ":" in rel:
        return "':' (drive or stream)"
    if "/" in rel:
        return "'/' (use backslashes)"
    if rel.startswith("\\"):
        return "rooted"
    for part in rel.split("\\"):
        if part.replace(".", "").replace(" ", "") == "":
            return "component %r (empty, dots or spaces only)" % part
        if part != part.rstrip(". "):
            return "component %r ends with a dot or a space (Windows drops them)" % part
    return ""


def catalog_checks(model: dict, comp, refs, tag: str) -> dict:
    res = {}
    # every path the installer writes, removes or edits stays inside the Convergence folder
    rels = [("path", p["rel"]) for p in model["paths"]] + [("obsolete", o["rel"]) for o in model["obsolete"]] + \
        [("field", f["rel"]) for f in model["fields"]] + [("changelog", model["changelog_rel"])] + \
        [("detection", d["arg"]) for d in model["detection"] if d["kind"] in ("F", "H")] + \
        [("member tail %s" % a["id"], m["tail"]) for a in model["archives"] for m in a["members"]]
    bad = ["%s %r: %s" % (k, r, unsafe_rel(r)) for k, r in rels if unsafe_rel(r)]
    require(not bad, "unsafe relative paths in the catalog: %s" % bad[:10])
    res["safe_rels"] = len(rels)
    # one resolvable source per variant
    mems = [m for a in model["archives"] for m in a["members"]]
    marc = [ai for ai, a in enumerate(model["archives"]) for _ in a["members"]]
    for k, v in enumerate(model["variants"]):
        if v["src"] == "A":
            require(0 <= v["ref"] < len(mems), "variant %d: member index out of range" % k)
            m = mems[v["ref"]]
            a = model["archives"][marc[v["ref"]]]
            if a["mode"] == "P":
                require(m["sha256"] == v["sha256"] and m["size"] == v["size"],
                        "variant %d (%s): member %s sha/size differ" % (k, model["paths"][v["path"]]["rel"], m["name"]))
            else:
                require(v["sha256"] == "" and v["size"] == -1, "variant %d: mode V variant must be dynamic" % k)
        else:
            require(v["src"] == "B" and 0 <= v["ref"] < len(model["blobs"]), "variant %d: bad blob ref" % k)
            b = model["blobs"][v["ref"]]
            require(b["sha256"] == v["sha256"] and b["size"] == v["size"], "variant %d: blob sha/size differ" % k)
    res["variants"] = len(model["variants"])
    # every pinned member resolvable in its reference (by name + sha256)
    n = 0
    for a in model["archives"]:
        ref = refs[a["id"]]
        for m in a["members"]:
            if a["mode"] == "V":
                require(any(f["name"].lower() == m["name"].lower() for f in ref.files), "%s: member %s not in the reference" % (
                    a["id"], m["name"]))
            else:
                require(any(f["name"].lower() == m["name"].lower() and f["sha256"] == m["sha256"] for f in ref.files),
                        "%s: member %s (%s) not resolvable in its reference" % (a["id"], m["name"], m["sha256"][:12]))
            n += 1
        names = [m["name"].lower() for m in a["members"]]
        for g in a["globs"]:
            require(g.startswith("*") and "/" not in g and "\\" not in g, "%s: glob %s" % (a["id"], g))
        require(len(a["globs"]) == len(set(names)), "%s: globs do not cover exactly the member names" % a["id"])
    res["members_resolved"] = n
    # tables: sizes and indices
    for p in model["paths"]:
        for x in p["table"]:
            require(x >= -2 and x < len(model["variants"]), "path %s: table entry %d" % (p["rel"], x))
            if x >= 0:
                require(model["variants"][x]["path"] == model["paths"].index(p), "path %s: variant of another path" % p["rel"])
    # MAX_PATH budget
    require(model["max_rel_len"] <= cfg.MAX_REL_BUDGET, "MAX_REL_LEN %d > budget %d" % (model["max_rel_len"], cfg.MAX_REL_BUDGET))
    res["max_rel_len"] = model["max_rel_len"]
    # no TODO-style URLs in what the player sees, except the known empty archive URLs
    res["empty_nexus_urls"] = [a["id"] for a in model["archives"] if not a["nexus_url"]]
    log("catalog checks: %d variants each with one resolvable source, %d members resolvable by name + sha256, "
        "MAX_REL_LEN %d <= %d, archives without a Nexus URL: %s" % (
            res["variants"], n, model["max_rel_len"], cfg.MAX_REL_BUDGET, res["empty_nexus_urls"] or "none"))
    return res


def hosted_checks(model: dict, tag: str) -> dict:
    from .model import github_blobs
    gh = github_blobs(model)
    require(len(gh) == len(model["blobs"]), "a blob with another download site: retired on 2026-10-03")
    places = [(cfg.DIST / tag / "github" / tag, gh), (cfg.RELEASE_STAGING / tag, gh)]
    roots = [p for p, _ in places]
    for root, blobs in places:
        files = {p.name: p for p in root.iterdir() if p.is_file()} if root.exists() else {}
        want = {b["asset"]: b for b in blobs}
        require(set(files) == set(want), "%s: hosted files != catalog assets (+%s -%s)" % (
            root, sorted(set(files) - set(want))[:5], sorted(set(want) - set(files))[:5]))
        for name, b in want.items():
            h = hash_file(files[name])
            require(h["sha256"] == b["sha256"] and h["size"] == b["size"], "%s: %s sha256/size != catalog" % (root, name))
    for b in model["blobs"]:
        p = cfg.ASSETS / b["sha256"]
        require(p.exists() and hash_file(p)["sha256"] == b["sha256"], "blob store: %s" % b["sha256"])
    log("hosted checks: every one of the %d assets (all on the GitHub release) in %s matches the catalog's sha256 + "
        "size (and the blob store)" % (len(model["blobs"]), " and ".join(str(r) for r in roots)))
    return {"assets": len(model["blobs"]), "github_assets": len(gh), "roots": [str(r) for r in roots]}


def clever_signatures(refs, comp) -> list[tuple[str, bytes]]:
    sigs = []
    for c in comp.comps:
        if c.get("product") != "clever_parts":
            continue
        ref = refs[c["archives"][0]]
        for f in ref.files:
            data = (ref.path / f["tail"]).read_bytes()
            off = min(4096, max(0, len(data) // 2 - 64))
            sigs.append((f["tail"], data[off:off + 96]))
    return sigs


def exe_checks(exe: Path, refs, comp, uncompressed: bool) -> dict:
    size = exe.stat().st_size
    require(size < cfg.EXE_LIMIT, "%s is %d bytes (limit %d)" % (exe.name, size, cfg.EXE_LIMIT))
    out = {"exe": str(exe), "size": size, "sha256": hash_file(exe)["sha256"]}
    if uncompressed:
        data = exe.read_bytes()
        hits = [t for t, s in clever_signatures(refs, comp) if len(s) >= 64 and s in data]
        require(not hits, "CLEVER BYTES INSIDE THE EXE: %s" % hits[:5])
        out["clever_signature_scan"] = "0 of %d Clever file signatures found" % len(clever_signatures(refs, comp))
    log("exe check: %s %d bytes (< %d)%s" % (exe.name, size, cfg.EXE_LIMIT,
                                           ("; " + out["clever_signature_scan"]) if uncompressed else ""))
    return out


def iss_sources_check() -> dict:
    """the installer script may embed only staging\\meta files ([Files] Source lines)"""
    src_re = re.compile(r'^\s*Source\s*:(?!=)\s*(?:"([^"]*)"|([^;]*))', re.IGNORECASE)
    files = [cfg.ISS] + sorted(cfg.CODE_DIR.glob("*.iss")) + sorted(cfg.GENERATED.glob("*.iss"))
    srcs = []
    for f in files:
        if not f.exists():
            continue
        for n, line in enumerate(f.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            s = line.strip()
            if s.startswith(";") or s.startswith("//"):
                continue
            for m in src_re.finditer(line):
                src = (m.group(1) if m.group(1) is not None else m.group(2) or "").strip()
                if src:
                    srcs.append((f.name, n, src))
    # ISPP defines used in Source (e.g. {#ConvManifestSource}): every value it can take
    defs = {}
    def_re = re.compile(r'^\s*#\s*define\s+([A-Za-z_][A-Za-z0-9_]*)\s+"([^"]*)"', re.IGNORECASE)
    for f in files:
        if f.exists():
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                m = def_re.match(line)
                if m:
                    defs.setdefault(m.group(1), []).append(m.group(2))
    resolved = []
    for fname, n, s in srcs:
        m = re.fullmatch(r"\{#\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}", s)
        if m:
            vals = defs.get(m.group(1), [])
            require(vals, "%s:%d: Source %s uses an undefined ISPP name" % (fname, n, s))
            require(any(v.lower().startswith("staging\\meta\\") for v in vals),
                    "%s:%d: Source %s never points into staging\\meta (%s)" % (fname, n, s, vals))
            for v in vals:   # the stub value is code-check only (the .iss itself #errors otherwise)
                resolved.append((fname, n, v, v.lower().startswith("tests\\stub\\")))
        else:
            resolved.append((fname, n, s, False))
    bad = [x for x in resolved if not (x[2].lower().replace("/", "\\").startswith("staging\\meta\\") or x[3])
           or "clever" in x[2].lower() or "{" in x[2]]
    require(not bad, "[Files] Source outside staging\\meta: %s" % bad[:5])
    log("[Files] check: %d Source line(s) -> %s, all inside staging\\meta (stub values code-check only)" % (
        len(srcs), sorted({x[2] for x in resolved})))
    return {"sources": [x[2] for x in resolved]}


def required_pairs(model: dict) -> list[str]:
    """every (component, state) pair the test run must have installed, verified and uninstalled, as 'id:code':
    every state of every T/C component and state 1 of every R component; X placeholders are never installed
    (repair 3, code review MEDIUM)"""
    out = []
    for c in model["components"]:
        if c["kind"] == "X":
            continue
        codes = ["1"] if c["kind"] == "R" else [s["code"] for s in c["states"]]
        out += ["%s:%s" % (c["id"], code) for code in codes]
    return out


def final_gates(model: dict, src: dict, cat_sha: str, tag: str, code_fp: str | None = None,
                check_published: bool = True) -> dict:
    """the --final (and publish_github.py) gates. code_fp = the installer code fingerprint the release exe is built
    from (default: the current sources, pipeline\\codefp.py); test results count only for that fingerprint, and only
    when the run installed, verified and uninstalled every (component, state) pair of this catalog (results'
    coverage.verified_uninstalled, written by tests\\run_all.py; repair 3, code review MEDIUM: a component added to
    the catalog that no test ever installs can no longer pass). check_published: refuse a tag whose GitHub release is
    already published (its assets can never change; publish_github.py reads the release itself and passes False)."""
    problems = []
    if code_fp is None:
        code_fp = code_fingerprint()
    for a in model["archives"]:
        c = model["components"][a["comp"]]
        if not a["nexus_url"] or "TODO" in a["nexus_url"].upper():
            problems.append("archive %s (%s) has no Nexus URL%s" % (a["id"], c["id"], " (" + a["nexus_url_status"] + ")"
                                                                   if a.get("nexus_url_status") else ""))
        elif "INFERRED" in (a.get("nexus_url_status") or "").upper():
            # an unconfirmed page would be shown to every player (GitHub stage lane, 2026-10-01, code review INFO item)
            problems.append("archive %s (%s): its page %s is INFERRED, not confirmed - check it, then delete its "
                            "nexus_url_status in catalog\\catalog.src.json" % (a["id"], c["id"], a["nexus_url"]))
    for u in model["base_urls"] + [b["upstream"] for b in model["blobs"] if b["upstream"]]:
        if "TODO" in u.upper():
            problems.append("TODO in URL %s" % u)
    # release prep 2026-10-03: the RC's NRM layer must be built from the very package the players download (its
    # archive's package_version + zip sha256); a test build made with --allow-other-nrm-package never passes here
    from . import rcinputs
    problems += rcinputs.nrm_package_problems(src, model["rc"])
    # every earlier release of this installer must be a legacy catalog (repair 4, code review LOW: its own files at
    # paths an option can leave out would otherwise be taken for other mods' files)
    from . import legacy
    problems += legacy.legacy_catalog_problems(src, tag)
    cl = Path(src["release"]["changelog_source"]).read_text(encoding="utf-8", errors="replace")
    if "PLACEHOLDER" in cl:
        problems.append("the changelog %s contains PLACEHOLDER" % src["release"]["changelog_source"])
    need = required_pairs(model)
    ok_results, stale, uncovered = [], [], []
    for p in sorted(glob.glob(str(cfg.TESTS_RESULTS / ("%s_%s_*.json" % (tag, model["rc"]))))):
        try:
            r = json.loads(Path(p).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        passed = r.get("catalog_sha256") == cat_sha and r.get("golden_ok") and r.get("phases") and \
            r.get("complete") is True and all(ph.get("fail", 1) == 0 for ph in r["phases"].values()) and \
            all(ph in r["phases"] for ph in ("P0", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9"))
        have = set((r.get("coverage") or {}).get("verified_uninstalled", []))
        missing = [x for x in need if x not in have]
        if passed and r.get("code_fingerprint") == code_fp and not missing:
            ok_results.append(p)
        elif passed and r.get("code_fingerprint") == code_fp:
            uncovered.append("%s lacks %s" % (Path(p).name, ", ".join(missing[:12]) + (" ..." if len(missing) > 12 else "")))
        elif passed:
            stale.append(Path(p).name)
    if not ok_results:
        problems.append("no complete passing tests\\results\\%s_%s_*.json for catalog sha256 %s AND installer code "
                        "fingerprint %s that installed, verified and uninstalled every (component, state) of the "
                        "catalog%s%s (run tests\\run_all.py --rc %s)" % (
                            tag, model["rc"], cat_sha[:16], code_fp[:16],
                            "; made with older code: %s" % stale if stale else "",
                            "; not every (component, state) was covered: %s" % uncovered if uncovered else "",
                            model["rc"]))
    if check_published:
        # a tag whose GitHub release is already published can never get new assets (ghstage stages drafts only):
        # an exe built for it would fail every download (code review, LOW release-process item; repair 3 moved the
        # check here from run_pipeline so every user of the gates refuses it)
        from . import ghstage
        problems += ghstage.published_problems(src, tag)
    return {"problems": problems, "passing_results": ok_results, "code_fingerprint": code_fp,
            "required_pairs": need}
