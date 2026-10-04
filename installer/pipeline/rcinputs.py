"""P2: resolve the RC (rcN | auto), check its gates exactly as deploy_v65.py does (ported, not imported), and resolve
the MAIN tree (v6.5 base + the RC build chain), the NRM layer made from that chain and the DMN layers.

NRM tiers (rc8 switch prep, 2026-10-03, as deploy_v65.py RC8): the NRM option ships the layer of the catalog's
inputs.nrm_tier (T2W = Wylder on; the option title promises Wylder's skills).

DMN + NRM (Luka 2026-10-03, after field-testing RC8 + Wylder + DMN + ERCap: "everything positive"): the DMN layer made on
the NRM layer itself (rc8: dmn_nrmw_rc8 on nrm_rc8, Wylder ON). It is 187 entries past the old animation wall, so its
report fails exactly G-WALL + G-VOL-REC by design and it is accepted ONLY as an ERCap state (dmn_layer_problems, the
checks of deploy_v65.py --dmn-nrmw ported: DMN_ERCAP_STATE.json of dmn\\dmn_ercap_state.py accepted, same roots, same
manifest, M2 last index in 32,668..65,433, every shipped file unchanged) and only where the catalog allows it
(inputs.dmn_ercap_only_layers). The installer then adds ERCapacityExpansion for every selection with DMN + NRM (the
catalog's D rule + the measured wall table; pipeline\\wall.py check_forced). The rc8 switch prep's Wylder-off sibling
arrangement (nrm_<rc>_T2 + dmn_nrm_<rc>) is retired: a DMN + NRM layer made on another NRM layer is refused."""
from __future__ import annotations

import os
import re
from pathlib import Path

from . import cfg
from .util import BuildError, files_under, log, md5_file, ncase, read_json, require


class RC:
    """name, build dir, chain, base, nrm layer, MAIN tree {rel under the Convergence folder ('mod\\...'): file}"""

    def __init__(self, src: dict, name: str):
        inp = src["inputs"]
        self.name = name
        self.build_root = Path(inp["rc_build_root"])
        self.base = Path(inp["base_dir"])
        self.base_roots = [ncase(self.base)] + [ncase(p) for p in inp.get("base_roots_extra", [])]
        self.build = self.build_root / name
        require(self.build.is_dir(), "RC build folder missing: %s" % self.build)
        problems = check_build(self.build, self.base, self.base_roots)
        require(not problems, "RC %s fails its checks: %s" % (name, problems))
        self.report = read_json(self.build / "BUILD_REPORT.json")
        self.gates = read_json(self.build / "GATES.json")
        self.chain = [self.build] + [Path(r) for r in self.report["roots"] if ncase(r) not in self.base_roots]
        self.nrm = nrm_dir(src, name)
        problems = check_nrm(self.nrm, self.chain)
        require(not problems, "NRM layer of %s fails its checks: %s" % (name, problems))
        self.nrm_report = read_json(self.nrm / "NRM_LAYER_REPORT.json")
        self.nrm_ini = self.nrm / "_installer" / "first_install" / "dll" / "NightreignMovement.ini"
        self.nrm_block = self.nrm / "_me3" / "natives_block_nrm.toml"
        require(self.nrm_ini.is_file() and self.nrm_block.is_file(), "NRM layer lacks its INI or natives block")
        # MAIN tree, as deploy_v65.py res(): the chain first, then the base
        tree: dict[str, Path] = {}
        for rel in files_under(self.base, skip_underscore=False):
            tree["mod\\" + rel] = self.base / rel
        self.overlay = {}
        for r in reversed(self.chain):
            for rel in files_under(r, skip_underscore=True, skip_json=True):
                tree["mod\\" + rel] = Path(r) / rel
                self.overlay["mod\\" + rel] = Path(r) / rel
        self.main = dict(sorted(tree.items(), key=lambda kv: kv[0].lower()))
        lower = [k.lower() for k in self.main]
        require(len(lower) == len(set(lower)), "MAIN tree has case-duplicate paths")
        # NRM shipping files (the report's list = the files the NRM state ships from the layer)
        ship = [r.replace("/", "\\") for r in self.nrm_report.get("shipping_files", [])]
        require(ship, "NRM_LAYER_REPORT.json has no shipping_files")
        listed = set(x.lower() for x in ship)
        on_disk = set(x.lower() for x in files_under(self.nrm, skip_underscore=True, skip_json=True))
        require(listed == on_disk, "NRM layer files on disk != shipping_files: +%s -%s" % (
            sorted(on_disk - listed)[:5], sorted(listed - on_disk)[:5]))
        self.nrm_files = {"mod\\" + r: self.nrm / r for r in sorted(ship, key=str.lower)}
        # the Deflect Me Not layers (final pass 2026-10-03), when the catalog has an enabled DMN component
        self.dmn = self.dmn_nrm = None
        self.dmn_files, self.dmn_nrm_files = {}, {}
        # 'plain' / 'nrm' -> the ERCap-only state of that DMN layer (Luka 2026-10-03: DMN + NRM keeps Wylder; the
        # installer adds ERCapacityExpansion for it)
        self.dmn_ercap_only: dict[str, dict] = {}
        if dmn_wanted(src) and inp.get("dmn_layer_pattern"):
            self.dmn = Path(inp["dmn_layer_pattern"].replace("{rc}", name))
            self.dmn_nrm = dmn_nrm_dir(src, name, self.nrm, self.chain)
            for key, lay, roots in (("plain", self.dmn, self.chain), ("nrm", self.dmn_nrm, [self.nrm] + self.chain)):
                problems, eo = dmn_layer_problems(src, key, lay, roots)
                require(not problems, "DMN layer %s fails its checks: %s" % (lay, problems))
                if eo:
                    self.dmn_ercap_only[key] = eo
            self.dmn_files = dmn_files(self.dmn)
            self.dmn_nrm_files = dmn_files(self.dmn_nrm)
        log("RC %s: build %s | label %r | fixes %s | chain %s | MAIN %d paths (%d from the chain) | NRM layer %s (tier %s, "
            "NRM %s): %d files%s" % (
                name, self.build, self.report.get("label"), [f["id"] for f in self.report.get("fixes", [])],
                [str(c) for c in self.chain], len(self.main), len(self.overlay), self.nrm.name,
                self.nrm_report.get("tier"), nrm_package(self.nrm_report)["version"] or "?", len(self.nrm_files),
                " | DMN layers %s: %d files, %s: %d files%s" % (
                    self.dmn.name, len(self.dmn_files), self.dmn_nrm.name, len(self.dmn_nrm_files),
                    "".join(" | %s (%s) is an ERCap-only state: M2 list %d, last index %d (%d past the no-DLL wall), "
                            "accepted by %s" % (
                                (self.dmn if k == "plain" else self.dmn_nrm).name, k, v["m2"]["list"], v["m2"]["last"],
                                v["m2"]["past_wall"], v["state_file"]) for k, v in sorted(self.dmn_ercap_only.items())))
                if self.dmn else ""))

    def res(self, rel_mod: str):
        """file the v6.5 package ships at mod-relative rel (chain first, then base); None if neither has it"""
        p = self.main.get("mod\\" + rel_mod)
        return p


def _layer_tier(lay: Path) -> str:
    try:
        return str(read_json(lay / "NRM_LAYER_REPORT.json").get("tier") or "")
    except (OSError, ValueError):
        return ""


def nrm_dir(src: dict, rc_name: str) -> Path:
    """the RC's NRM layer folder = the layer the NRM option ships: among inputs.nrm_layer_pattern +
    inputs.nrm_layer_alternates (nrm_<rc>, nrm_<rc>_T2W, nrm_<rc>_T2; beta.16 RCs only have nrm_<rc>_T2) the first that
    holds an NRM_LAYER_REPORT.json with the tier inputs.nrm_tier names (rc8 switch prep 2026-10-03: T2W = Wylder on;
    the RC8 lane builds nrm_rc8 = T2W for the NRM state and nrm_rc8_T2 = Wylder off only as the DMN + NRM base);
    else the first that holds a report (nrm_package_problems then names the tier); else the pattern itself (its checks
    then say what is missing)"""
    inp = src["inputs"]
    cands = [Path(p.replace("{rc}", rc_name)) for p in [inp["nrm_layer_pattern"]] + list(inp.get("nrm_layer_alternates", []))]
    have = [c for c in cands if (c / "NRM_LAYER_REPORT.json").is_file()]
    want = inp.get("nrm_tier")
    for c in have:
        if want and _layer_tier(c) == want:
            return c
    return have[0] if have else cands[0]


def dmn_nrm_dir(src: dict, rc_name: str, nrm: Path, chain) -> Path:
    """the RC's DMN + NRM layer: among inputs.dmn_nrm_layer_pattern + inputs.dmn_nrm_layer_alternates (rc8:
    dmn_nrmw_rc8, then dmn_nrm_<rc>) the first whose DMN_LAYER_REPORT.json was made from exactly the NRM layer + the
    chain; else the first that holds a report (its checks then say why it is refused - e.g. rc8's retired dmn_nrm_rc8,
    made on the Wylder-off sibling nrm_rc8_T2); else the pattern itself"""
    inp = src["inputs"]
    cands = [Path(p.replace("{rc}", rc_name)) for p in [inp["dmn_nrm_layer_pattern"]] +
             list(inp.get("dmn_nrm_layer_alternates", []))]
    want = [ncase(r) for r in [nrm] + list(chain)]
    have = []
    for c in cands:
        try:
            r = read_json(c / "DMN_LAYER_REPORT.json")
        except (OSError, ValueError):
            continue
        have.append(c)
        if [ncase(x) for x in r.get("merge_roots", [])] == want:
            return c
    return have[0] if have else cands[0]


# deploy_v65.py --dmn-nrmw (2026-10-03): the hard gates such a layer may fail - G-WALL by design, and G-VOL-REC only
# because G-WALL failed (the canary rule "G-WALL may fail, nothing else", applied to a layer)
ERCAP_ONLY_FAILS = {"G-WALL", "G-VOL-REC"}
ERCAP_M2_LAST = (32667, 65433)          # an ERCap-only state: M2 last index above the no-DLL safety line, under the DLL's


def dmn_ercap_state_problems(lay: Path, rep: dict, roots, key: str) -> tuple[list[str], dict]:
    """the ERCap-only acceptance of a DMN layer whose report fails exactly ERCAP_ONLY_FAILS (port of deploy_v65.py
    --dmn-nrmw, 2026-10-03): its DMN_ERCAP_STATE.json (dmn\\dmn_ercap_state.py) accepted, made from these roots and
    for this folder, the same manifest as the report, M2 last index in 32,668..65,433; the report by dmn_layer.py, the
    DMN + NRM variant for the 'nrm' layer; every shipped file unchanged since the layer wrote it (md5 == manifest).
    -> (problems, {m2, m1, verdict, state_file, state_md5})"""
    out = []
    sp = lay / "DMN_ERCAP_STATE.json"
    try:
        es = read_json(sp)
    except (OSError, ValueError) as e:
        return ["fails %s (allowed only as an ERCap state) but its DMN_ERCAP_STATE.json is missing or unreadable (%s): "
                "run dmn\\dmn_ercap_state.py on it" % (sorted(rep.get("fail") or []), e)], {}
    want = [ncase(r) for r in roots]
    if rep.get("tool") != "dmn/dmn_layer.py":
        out.append("report tool %r is not dmn/dmn_layer.py" % rep.get("tool"))
    if key == "nrm" and (rep.get("info") or {}).get("variant") != "dmn_nrm":
        out.append("variant %r, not dmn_nrm" % (rep.get("info") or {}).get("variant"))
    if not (es.get("tool") == "dmn/dmn_ercap_state.py" and es.get("accepted") is True):
        out.append("DMN_ERCAP_STATE.json: tool %r accepted %r (refused)" % (es.get("tool"), es.get("accepted")))
    if [ncase(r) for r in es.get("merge_roots", [])] != want:
        out.append("DMN_ERCAP_STATE.json made from %s, not from %s" % (es.get("merge_roots"), [str(r) for r in roots]))
    if ncase(es.get("layer", "")) != ncase(lay):
        out.append("DMN_ERCAP_STATE.json is for %s, not this layer" % es.get("layer"))
    man = rep.get("manifest") or {}
    if not man or (es.get("layer_report") or {}).get("manifest") != man:
        out.append("DMN_ERCAP_STATE.json is stale: its manifest differs from the layer report's")
    m2 = es.get("m2") or {}
    if not (isinstance(m2.get("last"), int) and ERCAP_M2_LAST[0] < m2["last"] <= ERCAP_M2_LAST[1]):
        out.append("M2 last index %r is not an ERCap-only state (%d < last <= %d)" % (m2.get("last"), *ERCAP_M2_LAST))
    ship = [x.replace("/", "\\") for x in rep.get("shipping_files", [])]
    if "regulation.bin" in [x.lower() for x in ship]:
        out.append("an ERCap-only DMN layer must not ship regulation.bin")
    bad = [r for r in ship if (lay / r).is_file() and md5_file(lay / r) != str(man.get(r, "")).lower()]
    if bad or set(x.lower() for x in ship) != set(x.lower() for x in man):
        out.append("files changed since the layer wrote them (or not in its manifest): %s" % (
            bad or sorted(set(x.lower() for x in ship) ^ set(x.lower() for x in man)))[:6])
    info = {"m2": {k: m2.get(k) for k in ("list", "last", "past_wall", "dll_room", "a998_040000")},
            "m1": es.get("m1") or {}, "verdict": es.get("verdict", ""), "state_file": str(sp),
            "state_md5": md5_file(sp)}
    return out, info


def dmn_layer_problems(src: dict | None, key: str, lay: Path, roots) -> tuple[list[str], dict]:
    """a DMN layer (dmn\\dmn_layer.py) must be made from exactly these roots (newest first), ship exactly its
    shipping_files and report fail [] - or (2026-10-03, Luka's DMN + Wylder decision) fail exactly G-WALL + G-VOL-REC
    as an accepted ERCap-only state (dmn_ercap_state_problems) where the catalog allows it (inputs.dmn_ercap_only_layers
    names key 'plain' / 'nrm'). -> (problems, ERCap-only info or {})"""
    try:
        r = read_json(lay / "DMN_LAYER_REPORT.json")
    except (OSError, ValueError) as e:
        return ["DMN layer report unreadable: %s (%s)" % (lay, e)], {}
    out = []
    eo = {}
    fail = r.get("fail")
    if fail != []:
        allowed = key in ((src or {}).get("inputs", {}).get("dmn_ercap_only_layers") or [])
        if isinstance(fail, list) and set(fail) == ERCAP_ONLY_FAILS and allowed:
            p, eo = dmn_ercap_state_problems(lay, r, roots, key)
            out += p
        elif isinstance(fail, list) and set(fail) == ERCAP_ONLY_FAILS:
            out.append("fail = %s: an ERCap-only state, which inputs.dmn_ercap_only_layers does not allow for the %r "
                       "layer" % (fail, key))
        else:
            out.append("fail = %s" % fail)
    if [ncase(x) for x in r.get("merge_roots", [])] != [ncase(x) for x in roots]:
        out.append("made from %s, not from %s" % (r.get("merge_roots"), [str(x) for x in roots]))
    ship = [x.replace("/", "\\") for x in r.get("shipping_files", [])]
    if not ship:
        out.append("no shipping_files")
    on_disk = set(x.lower() for x in files_under(lay, skip_underscore=True, skip_json=True))
    if set(x.lower() for x in ship) != on_disk:
        out.append("files on disk != shipping_files: +%s -%s" % (sorted(on_disk - set(x.lower() for x in ship))[:5],
                                                                  sorted(set(x.lower() for x in ship) - on_disk)[:5]))
    return out, (eo if not out else {})


def nrm_package(report: dict) -> dict:
    """{version, zip_sha256} of the Nightreign Movement package an NRM layer was built from: the report's own
    'nrm_version' + 'package.zip_sha256' (nrm_layer.py since the 0.2 port), else the version its G-PKG gate names
    (older layers: 'NRM package 1.0.0-beta.16 (CONVERGENCE): ...'; no zip hash)"""
    ver = str(report.get("nrm_version") or "")
    if not ver:
        m = re.search(r"NRM package (\S+)", str(((report.get("gates") or {}).get("G-PKG") or {}).get("detail", "")))
        ver = m.group(1) if m else ""
    pkg = report.get("package") or {}
    return {"version": ver, "zip_sha256": str(pkg.get("zip_sha256") or "").lower()}


def nrm_package_problems(src: dict, rc_name: str) -> list[str]:
    """release prep 2026-10-03: the players download Nightreign Movement from its own page (archive of the 'nrm'
    product). The RC's NRM layer must be built from exactly that package - the archive's package_version and, when the
    layer's report records it, the archive's zip sha256 - or the files it ships unchanged are not in the players'
    download (they would become release assets of another author's files). [] = fine / no such archive."""
    comps = [c for c in src["components"] if c.get("product") == "nrm" and c.get("kind") != "X"]
    if not comps or not comps[0].get("archives"):
        return []
    arch = [a for a in src["archives"] if a["id"] in comps[0]["archives"] and a.get("enabled", True)]
    if not arch:
        return []
    a = arch[0]
    want_v = a.get("package_version", "")
    want_sha = (a.get("reference", {}).get("expect_sha256") or "").lower()
    lay = nrm_dir(src, rc_name)
    try:
        rep = read_json(lay / "NRM_LAYER_REPORT.json")
        got = nrm_package(rep)
    except (OSError, ValueError) as e:
        return ["NRM layer report unreadable: %s (%s)" % (lay, e)]
    out = []
    # rc8 switch prep: the option ships the tier the catalog names (its title promises it), never a Wylder-off layer
    want_t = src["inputs"].get("nrm_tier")
    if want_t and rep.get("tier") != want_t:
        out.append("the NRM layer %s is tier %s, but the NRM option ships tier %s (inputs.nrm_tier): build the RC's NRM "
                   "layer with --tier %s (nrm_<rc>)" % (lay.name, rep.get("tier"), want_t, want_t))
    if want_v and got["version"] != want_v:
        out.append("the NRM layer %s was built from Nightreign Movement %s, but players download %s (archive %s): "
                   "build the RC's NRM layer from that package" % (lay.name, got["version"] or "(unknown)", want_v,
                                                                   a["id"]))
    elif got["zip_sha256"] and want_sha and got["zip_sha256"] != want_sha:
        # 2026-10-04: the players download the Nexus 1.2 zip (the reference); the layer was built from neiroxgod's 0.2
        # package (layer_package), whose files the Nexus zip holds byte for byte. Accepted only for that pinned package,
        # and only when every file of it the layer ships unchanged is in the reference or a declared hosted notice.
        lp = a.get("layer_package") or {}
        if not lp or got["zip_sha256"] != lp.get("expect_sha256", "").lower():
            out.append("the NRM layer %s was built from a Nightreign Movement %s zip with sha256 %s, archive %s pins %s%s" % (
                lay.name, got["version"], got["zip_sha256"][:16], a["id"], want_sha[:16],
                " (layer_package %s)" % lp["expect_sha256"][:16] if lp else ""))
        else:
            out += layer_package_problems(a, lay)
    return out


def layer_package_problems(a: dict, lay: Path) -> list[str]:
    """2026-10-04: every file of the archive's layer_package that the layer ships unchanged (same sha256) must be in
    the archive's reference (the players' download) by name + sha256, or be one of layer_package.hosted. [] = fine."""
    from . import sources                       # late: sources imports nothing of this module
    from .util import hash_file
    lp = a["layer_package"]
    try:
        pkg = sources.layer_package_files(a)
    except BuildError as e:
        return [str(e)]
    ref = sources.Ref(a)
    ref.files = sources._zip_files(ref.path) if ref.path and ref.path.is_file() else []
    if not ref.files:
        return ["archive %s: reference zip missing: %s" % (a["id"], ref.path)]
    have = {(f["name"].lower(), f["sha256"]) for f in ref.files}
    # the files the layer SHIPS (its report's shipping_files, as RC.nrm_files; its '_' folders - e.g. _nrm\pkg, the
    # unpacked package it was built from - are never installed)
    try:
        ship = [r.replace("/", "\\") for r in read_json(lay / "NRM_LAYER_REPORT.json").get("shipping_files", [])]
    except (OSError, ValueError):
        ship = []
    ship = ship or files_under(lay, skip_underscore=True, skip_json=True)
    lay_shas = {hash_file(lay / rel)["sha256"] for rel in ship}
    hosted = [t.lower() for t in lp.get("hosted", [])]
    out, n_ok = [], 0
    for f in pkg:
        if f["sha256"] not in lay_shas:
            continue
        t = f["tail"].lower()
        if (f["name"].lower(), f["sha256"]) in have:
            n_ok += 1
        elif not any(t == h or t.endswith("\\" + h) for h in hosted):
            out.append("the NRM layer %s ships %s of its package unchanged, but the players' download %s lacks it" % (
                lay.name, f["tail"], ref.path.name))
    if not out:
        log("NRM layer %s: built from the layer package (sha256 %s); its %d files the layer ships unchanged are all in "
            "the players' download %s, + %d declared hosted notices" % (lay.name, lp["expect_sha256"][:16], n_ok,
                                                                       ref.path.name, len(hosted)))
    return out


def dmn_wanted(src: dict) -> bool:
    """True when the catalog has an enabled (not X) component built from the DMN layers"""
    return any(c.get("product") == "dmn" and c.get("kind") != "X" for c in src["components"])


def check_dmn(lay: Path, roots, src: dict | None = None, key: str = "plain") -> list[str]:
    """dmn_layer_problems without the ERCap-only info (no src = no ERCap-only layer allowed)"""
    return dmn_layer_problems(src, key, lay, roots)[0]


def dmn_files(lay: Path) -> dict:
    r = read_json(lay / "DMN_LAYER_REPORT.json")
    ship = [x.replace("/", "\\") for x in r["shipping_files"]]
    return {"mod\\" + x: lay / x for x in sorted(ship, key=str.lower)}


def check_build(build: Path, base: Path, base_roots) -> list[str]:
    out = []
    try:
        g = read_json(build / "GATES.json")
        rep = read_json(build / "BUILD_REPORT.json")
    except (OSError, ValueError) as e:
        return ["unreadable GATES/BUILD_REPORT: %s" % e]
    if g.get("fail") != []:
        out.append("GATES fail = %s" % g.get("fail"))
    if not ("G-PACK" in g.get("hard", {}) and g["hard"]["G-PACK"].get("ok")):
        out.append("no passing G-PACK")
    roots = [ncase(r) for r in rep.get("roots", [])]
    if ncase(base) not in roots:
        out.append("not built on the v6.5 base (roots %s)" % rep.get("roots"))
    return out


def check_nrm(nrm: Path, chain) -> list[str]:
    try:
        nr = read_json(nrm / "NRM_LAYER_REPORT.json")
    except (OSError, ValueError) as e:
        return ["NRM layer report unreadable: %s (%s)" % (nrm, e)]
    out = []
    if nr.get("fail") != []:
        out.append("NRM layer fail = %s" % nr.get("fail"))
    if [ncase(r) for r in nr.get("merge_roots", [])] != [ncase(r) for r in chain]:
        out.append("NRM layer made from %s, not from the chain %s" % (nr.get("merge_roots"), [str(c) for c in chain]))
    return out


def resolve_name(src: dict, arg: str) -> str:
    root = Path(src["inputs"]["rc_build_root"])
    if arg != "auto":
        require(re.fullmatch(r"rc\d+", arg), "--rc must be rcN or auto (got %r)" % arg)
        return arg
    cands = sorted((int(m.group(1)), d.name) for d in root.iterdir()
                   if d.is_dir() and (m := re.fullmatch(r"rc(\d+)", d.name)))
    base = Path(src["inputs"]["base_dir"])
    base_roots = [ncase(base)] + [ncase(p) for p in src["inputs"].get("base_roots_extra", [])]
    for _, name in reversed(cands):
        b = root / name
        p = check_build(b, base, base_roots)
        if p:
            log("--rc auto: %s skipped (%s)" % (name, "; ".join(p)))
            continue
        rep = read_json(b / "BUILD_REPORT.json")
        chain = [b] + [Path(r) for r in rep["roots"] if ncase(r) not in base_roots]
        nrm = nrm_dir(src, name)
        p = check_nrm(nrm, chain)
        if not p and dmn_wanted(src) and src["inputs"].get("dmn_layer_pattern"):
            dn = dmn_nrm_dir(src, name, nrm, chain)
            p = check_dmn(Path(src["inputs"]["dmn_layer_pattern"].replace("{rc}", name)), chain, src, "plain") + \
                check_dmn(dn, [nrm] + chain, src, "nrm")
        if p:
            log("--rc auto: %s skipped (%s)" % (name, "; ".join(p)))
            continue
        log("--rc auto -> %s" % name)
        return name
    raise BuildError("--rc auto: no RC passes its gates and has a passing NRM layer")
