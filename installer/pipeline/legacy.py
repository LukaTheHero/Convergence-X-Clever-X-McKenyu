"""P6b: detection rules (presets: F file exists, N me3 native line, H file sha256) and obsolete files (paths of older
releases that v6.5 never writes, with each old content; old installer changelogs).

Older releases are read from catalog.src.json "legacy": the v6.3/v6.4 zips (keys v63, v64) and, since repair 4 (code
review LOW), "catalogs": the catalog.json of every earlier release of THIS installer (dist\<tag>\catalog.json, e.g.
v6.5.0 for v6.6). Every content such a catalog gives a path counts as that path's own (older) content: the detection
(H rules) and the installer's "-1" removal rule then know it, so an older install's own files are never taken for
another mod's; its paths that the new release no longer writes become obsolete rows, its changelog an old changelog,
its regulation variants InfDur states. --final refuses a build when an earlier dist\<tag>\catalog.json exists that
"catalogs" does not list (legacy_catalog_problems).

Since the NRM-era fix (2026-10-03, the rc8 one-command run's P4 / P10 DT failures) "packages" lists other authors'
packages an older release was built from or a player put in by hand (Nightreign Movement 1.0.0-beta.16 = v6.4's NRM
option and the v6.5 rc1-rc7 test builds; 0.2): every file under a "map" prefix, and every earlier version's sha256 the
package's own manifest lists ("manifest": install-files.json, files[].path + originalSHA256), is an older content of
its path. A package names its "component"; its contents may only meet that component's own paths (else the build
stops), and they are never obsolete rows (a package's other files are the player's, not ours). Paths an option writes
only while it is on but whose content another option also picks (the rc8 switch prep's nrm-extension.hks: NRM alone =
Wylder on, DMN + NRM = Wylder off; since Luka's DMN + Wylder decision of 2026-10-03 it is NRM's alone again) get the same
"older release" H rules as the paths that option writes alone (presence_paths)."""
from __future__ import annotations

import hashlib
import json
import re
import zipfile
from pathlib import Path

from . import cfg
from .util import log, read_json, require, sha256_file, write_json

# md5 pins of the older regulations (v64 build.py / v63 installer), used only to cross-check what we read from the zips
V64_REG_MD5 = {"plain": "13ad36fc1a99c5c922bb6ade488f4ca8", "nrm": "13ad36fc1a99c5c922bb6ade488f4ca8",
               "lucy": "9853e81d0cad729e2fa7d192ed0aef7b", "lucy_nrm": "98ae03405c95ff030f41e976de7c2863"}
V64_ED_MD5 = {"v1": "ea22f69b8760fcf4b67e4a9583e4c1cf", "v2": "821361f40b3fb1c076fbfbc5b4d85542",
              "v3": "ae0c24e86559136c3a219292e03b714f", "v4": "b5c2dfa52c977f955438bf71ba63e5c0"}
V64_LUCY_ED_MD5 = {"v1": "cc791dce8767fc0a80da43db7ba39d1f", "v2": "5d639076eb0858c106c733556da3da5a",
                   "v3": "410088a8ab3152eef0b8de850ba95593", "v4": "532fff1b1bbb16a35047fb55873ab473"}
V63_ED_MD5 = {"none": "dbae7b8c55c18479625d14537a64b4c9", "v1": "ed6c6ee6b92a907bf700400ffad17b26",
              "v2": "efd58b050286c70875a53af418b68a2f", "v3": "f65fffff93080566c054812d574d53d5",
              "v4": "b5c2ecf6c4e92774755e82eaf4cb754a"}


def me3_squeeze(line: str) -> str:
    return line.strip().lower().replace(" ", "").replace("\t", "").replace('"', "'")


def _zip_listing(zp: Path) -> list[dict]:
    """[{rel (backslashes), sha256, md5, size}] of every file member, cached by the zip's sha256"""
    cache_p = cfg.WORK / "legacy_cache.json"
    cache = read_json(cache_p) if cache_p.exists() else {}
    key = sha256_file(zp)
    if key in cache:
        return cache[key]
    out = []
    with zipfile.ZipFile(zp) as z:
        for i in z.infolist():
            if i.is_dir():
                continue
            hs, hm = hashlib.sha256(), hashlib.md5()
            with z.open(i) as f:
                for chunk in iter(lambda: f.read(8 << 20), b""):
                    hs.update(chunk)
                    hm.update(chunk)
            out.append({"rel": i.filename.replace("/", "\\"), "sha256": hs.hexdigest(), "md5": hm.hexdigest(),
                        "size": i.file_size})
    cache[key] = out
    write_json(cache_p, cache)
    return out


def _reg(listing, zname) -> dict:
    r = [m for m in listing if m["rel"].lower() == "mod\\regulation.bin"]
    require(len(r) == 1, "%s: no single mod\\regulation.bin" % zname)
    return r[0]


def legacy_regs(src: dict) -> list[dict]:
    """[{label, sha256, md5, state code}] of every older regulation (v6.4 + v6.3, editions and 'none')"""
    leg = src["legacy"]
    out = []
    for kind, zp in leg["v64"]["zips"].items():
        r = _reg(_zip_listing(Path(zp)), zp)
        require(r["md5"] == V64_REG_MD5[kind], "v6.4 %s zip regulation md5 %s != pin %s" % (kind, r["md5"], V64_REG_MD5[kind]))
        out.append({"label": "v6.4 %s" % kind, "sha256": r["sha256"], "md5": r["md5"], "code": "none"})
    for code, zp in leg["v64"]["infdur_plain_zips"].items():
        r = _reg(_zip_listing(Path(zp)), zp)
        require(r["md5"] == V64_ED_MD5[code], "v6.4 InfDur %s md5 %s != pin" % (code, r["md5"]))
        out.append({"label": "v6.4 InfDur %s" % code, "sha256": r["sha256"], "md5": r["md5"], "code": code})
    ld = Path(leg["v64"]["infdur_lucy_dist"])
    for code, md5 in V64_LUCY_ED_MD5.items():
        hits = []
        for zp in sorted(ld.glob("*.zip")):
            r = _reg(_zip_listing(zp), zp)
            if r["md5"] == md5:
                hits.append(r)
        require(len(hits) == 1, "v6.4 Lucy InfDur %s (md5 %s): %d zips in %s" % (code, md5, len(hits), ld))
        out.append({"label": "v6.4 Lucy InfDur %s" % code, "sha256": hits[0]["sha256"], "md5": md5, "code": code})
    for kind, zp in leg["v63"]["zips"].items():
        r = _reg(_zip_listing(Path(zp)), zp)
        require(r["md5"] == V63_ED_MD5["none"], "v6.3 zip regulation md5 %s != pin" % r["md5"])
        out.append({"label": "v6.3 %s" % kind, "sha256": r["sha256"], "md5": r["md5"], "code": "none"})
    for code, zp in leg["v63"]["infdur_plain_zips"].items():
        r = _reg(_zip_listing(Path(zp)), zp)
        require(r["md5"] == V63_ED_MD5[code], "v6.3 InfDur %s md5 %s != pin" % (code, r["md5"]))
        out.append({"label": "v6.3 InfDur %s" % code, "sha256": r["sha256"], "md5": r["md5"], "code": code})
    return out


def _tag_version(tag: str):
    m = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", tag or "")
    return tuple(int(x) for x in m.groups()) if m else None


def listed_catalogs(src: dict) -> list[Path]:
    """the earlier installer catalogs catalog.src.json legacy.catalogs lists (repair 4)"""
    return [Path(cfg.expand(p)) for p in src["legacy"].get("catalogs", [])]


def earlier_catalogs(tag: str, dist: Path | None = None) -> list[Path]:
    """dist\<t>\catalog.json of every release of this installer older than tag"""
    dist = cfg.DIST if dist is None else dist
    me = _tag_version(tag)
    out = []
    if me is None or not dist.is_dir():
        return out
    for d in sorted(dist.iterdir()):
        v = _tag_version(d.name)
        if d.is_dir() and v is not None and v < me and (d / "catalog.json").is_file():
            out.append(d / "catalog.json")
    return out


def legacy_catalog_problems(src: dict, tag: str, dist: Path | None = None) -> list[str]:
    """--final: every earlier release's catalog of this installer must be listed in legacy.catalogs, and every listed
    one must exist (repair 4, code review LOW: without it, v6.6 would take v6.5's own files at paths an option can
    leave out for other mods' files - moved by default, kept and still loaded with /FOREIGN=keep)"""
    probs = []
    listed = listed_catalogs(src)
    keys = {str(p.resolve()).lower() for p in listed}
    for p in listed:
        if not p.is_file():
            probs.append("catalog.src.json legacy.catalogs lists %s, which does not exist" % p)
    for p in earlier_catalogs(tag, dist):
        if str(p.resolve()).lower() not in keys:
            probs.append("%s is an earlier release of this installer but catalog\\catalog.src.json legacy.catalogs does "
                         "not list it: its own files at paths an option can leave out would be taken for other mods' "
                         "files" % p)
    return probs


def _catalog(cp: Path) -> dict:
    c = read_json(cp)
    require(c.get("format") in (1, 2) and isinstance(c.get("paths"), list) and isinstance(c.get("variants"), list),
            "legacy catalog %s: not a CAT_FORMAT 1 or 2 catalog.json" % cp)
    return c


def catalog_contents(cp: Path) -> dict[str, set]:
    """rel (lower case) -> every content an earlier installer catalog knows at that path: its static variants and its
    own H detection rules (the releases before it)"""
    c = _catalog(cp)
    out: dict[str, set] = {}
    for v in c["variants"]:
        if v.get("sha256"):
            out.setdefault(c["paths"][v["path"]]["rel"].lower(), set()).add(v["sha256"])
    for d in c.get("detection", []):
        if d.get("kind") == "H" and d.get("sha"):
            out.setdefault(d["arg"].lower(), set()).add(d["sha"])
    return out


def catalog_regs(cp: Path) -> list[dict]:
    """[{label, sha256, md5 '', code}] of an earlier installer catalog's regulation variants: the InfDur state code of
    each (from the regulation path's table)"""
    c = _catalog(cp)
    comps = c["components"]
    inf = [i for i, x in enumerate(comps) if x["id"] == "infdur"]
    reg = [p for p in c["paths"] if p["rel"].lower() == cfg.REG_REL.lower()]
    out = []
    if not inf or not reg:
        return out
    reg = reg[0]
    aff = reg.get("affects", [])
    counts = [len(comps[a]["states"]) for a in aff]
    for key, x in enumerate(reg["table"]):
        if x < 0:
            continue
        v = c["variants"][x]
        if not v.get("sha256"):
            continue
        rest, code = key, None
        for a, n in zip(aff, counts):
            if a == inf[0]:
                code = comps[a]["states"][rest % n]["code"]
            rest //= n
        if code is not None:
            out.append({"label": "%s InfDur %s" % (c.get("tag", cp.parent.name), code), "sha256": v["sha256"],
                        "md5": "", "code": code})
    return out


def _map_rel(name: str, prefixes: list) -> str | None:
    """a package member name (backslashes) -> its Convergence-relative path by the longest matching map prefix"""
    low = name.lower()
    for pre, dest in prefixes:
        if low.startswith(pre.lower()):
            return dest + name[len(pre):]
    return None


def package_contents(src: dict) -> list[dict]:
    """[{label, component, contents: rel (lower case) -> set(sha256), notes: (rel, sha256) -> where it comes from}]
    of every legacy.packages entry (NRM-era fix 2026-10-03): the files under its map prefixes + every sha256 its own
    manifest lists for a mapped path (the package's own version, which must equal its file, and every earlier one it
    names in originalSHA256)"""
    out = []
    for pk in src["legacy"].get("packages", []):
        zp = Path(pk["zip"])
        require(zp.is_file(), "legacy package %s: %s missing" % (pk["label"], zp))
        if pk.get("sha256"):
            require(sha256_file(zp) == pk["sha256"].lower(), "legacy package %s: %s is not the pinned zip (sha256 %s)" % (
                pk["label"], zp, pk["sha256"]))
        prefixes = sorted(((k.replace("/", "\\"), v) for k, v in pk["map"].items()), key=lambda kv: -len(kv[0]))
        require(all(v.lower().startswith("mod\\") and v.endswith("\\") for _, v in prefixes),
                "legacy package %s: every map destination is a folder under mod\\ ending in \\" % pk["label"])
        got: dict[str, set] = {}
        notes: dict[tuple, str] = {}
        for m in _zip_listing(zp):
            rel = _map_rel(m["rel"], prefixes)
            if rel:
                got.setdefault(rel.lower(), set()).add(m["sha256"])
                notes[(rel.lower(), m["sha256"])] = pk["label"]
        files = {k: set(v) for k, v in got.items()}
        if pk.get("manifest"):
            with zipfile.ZipFile(zp) as z:
                man = json.loads(z.read(pk["manifest"]).decode("utf-8-sig"))
            root = pk["manifest"].replace("/", "\\").rpartition("\\")[0]
            root = root + "\\" if root else ""
            n = 0
            for f in man.get("files", []):
                rel = _map_rel(root + f["path"].replace("/", "\\"), prefixes)
                require(rel is not None, "legacy package %s: manifest path %s is under no map prefix" % (
                    pk["label"], f["path"]))
                own = (f.get("sha256") or "").lower()
                require(not own or own in files.get(rel.lower(), {own}),
                        "legacy package %s: its manifest's sha256 of %s is not its file's" % (pk["label"], f["path"]))
                for sha in [own] + [x.lower() for x in f.get("originalSHA256", [])]:
                    if sha:
                        require(re.fullmatch(r"[0-9a-f]{64}", sha), "legacy package %s: manifest sha256 %r" % (
                            pk["label"], sha))
                        got.setdefault(rel.lower(), set()).add(sha)
                        notes.setdefault((rel.lower(), sha), pk["label"] if sha == own else
                                         "an earlier version named by the manifest of %s" % pk["label"])
                        n += 1
            require(n > 0, "legacy package %s: its manifest lists no sha256" % pk["label"])
        require(got, "legacy package %s: no member under its map prefixes" % pk["label"])
        out.append({"label": pk["label"], "component": pk["component"], "contents": got, "notes": notes})
    return out


def _release_contents(src: dict) -> dict[str, set]:
    """rel (lower case) -> every sha256 an older RELEASE holds at that path: the v6.3/v6.4 zips and every earlier
    installer catalog listed in legacy.catalogs (repair 4)"""
    leg = src["legacy"]
    zips = list(leg["v64"]["zips"].values()) + list(leg["v63"]["zips"].values()) + \
        list(leg["v64"].get("infdur_plain_zips", {}).values()) + list(leg["v63"].get("infdur_plain_zips", {}).values())
    out: dict[str, set] = {}
    for zp in zips:
        for m in _zip_listing(Path(zp)):
            out.setdefault(m["rel"].lower(), set()).add(m["sha256"])
    for cp in listed_catalogs(src):
        for rel, shas in catalog_contents(cp).items():
            out.setdefault(rel, set()).update(shas)
    return out


def legacy_contents(src: dict) -> dict[str, set]:
    """rel (lower case) -> every sha256 an older release or a legacy package holds at that path: the v6.3/v6.4 zips,
    every earlier installer catalog listed in legacy.catalogs (repair 4) and every legacy.packages entry (NRM-era fix)"""
    out = _release_contents(src)
    for pk in package_contents(src):
        for rel, shas in pk["contents"].items():
            out.setdefault(rel, set()).update(shas)
    return out


def own_paths(paths: dict, cid: str) -> list[dict]:
    """the paths only component cid writes: absent while it is off, a file in every other state (no user config);
    DLLs first, then by name"""
    out = []
    for p in paths.values():
        if p["flags"] == "U" or p["affects"] != [cid]:
            continue
        if p["table"][0] == ("ABSENT",) and all(x[0] in ("F", "D") for x in p["table"][1:]):
            out.append(p)
    out.sort(key=lambda p: (not p["rel"].lower().endswith(".dll"), p["rel"].lower()))
    return out


def _key_states(p: dict, n_states: dict) -> list[dict]:
    """[{component id: state}] of every key of path p's table (key = sum state_i * stride_i, affects order)"""
    out = []
    for key in range(len(p["table"])):
        rest, st = key, {}
        for a in p["affects"]:
            st[a] = rest % n_states[a]
            rest //= n_states[a]
        out.append(st)
    return out


def presence_comps(p: dict, n_states: dict) -> list[str]:
    """the components whose state alone decides whether path p exists: absent exactly while that component is off
    (every other key a file); [] for a path every selection writes or a user config"""
    if p["flags"] == "U" or ("ABSENT",) not in p["table"] or not all(
            x == ("ABSENT",) or x[0] in ("F", "D") for x in p["table"]):
        return []
    sts = _key_states(p, n_states)
    return [a for a in p["affects"]
            if all((x == ("ABSENT",)) == (st[a] == 0) for x, st in zip(p["table"], sts))]


def presence_paths(paths: dict, cid: str, n_states: dict) -> list[dict]:
    """the paths component cid writes only while it is on but whose content another option also picks (NRM-era fix
    2026-10-03; the rc8 switch prep's mod\\action\\script\\nrm-extension.hks affected nrm + dmn: Wylder on for NRM
    alone, Wylder off for DMN + NRM - NRM's alone again since the DMN + Wylder decision). own_paths() keeps the
    single-option paths (its first 3 are the full H detection set)"""
    out = [p for p in paths.values() if p["affects"] != [cid] and cid in p["affects"]
           and cid in presence_comps(p, n_states)]
    out.sort(key=lambda p: p["rel"].lower())
    return out


def detection(src: dict, comp, paths: dict, natives: list[dict]) -> list[dict]:
    """[{comp, kind F|N|H, arg, sha, state}] in evaluation order (the first matching rule of a component wins).

    Repair 3 (verifier 4 D2): a component is detected only by what is its own - a .me3 native (N); a file name the
    catalog declares as used by no other mod (components[].detect_files, F); a file that is any version of an
    author's file (a mode V archive member, F); or the sha256 of one of its own files (H: every v6.5 variant and
    every older release's content of up to 3 of its paths). A file NAME alone never counts: Lucy's parts include the
    base game's female body/face/hair names, which body, face and hair replacers use too.
    The H rules also list every older release's content at any other path only this component writes: the
    installer removes such a file (the option switched off) only when it holds one of the catalog's own contents for
    that path (a variant, or an H rule of it); anything else is another mod's file (moved or kept, never deleted as
    ours).
    NRM-era fix (2026-10-03): "older" includes legacy.packages (Nightreign Movement beta.16 and 0.2 with every earlier
    version their manifests name), and the paths a component writes only while it is on but whose content another
    option also picks (presence_paths) get the older contents no variant has, like the single-option paths."""
    rules = []
    comps = comp.comps
    by_id = {c["id"]: c for c in comps}
    n_states = {c["id"]: c["n_states"] for c in comps}
    nat_by_comp = {}
    for n in natives:
        nat_by_comp.setdefault(n["component"], []).append(n)
    rel_older = _release_contents(src)
    pkgs = package_contents(src)
    older: dict[str, set] = {k: set(v) for k, v in rel_older.items()}
    pkg_label: dict[tuple, str] = {}
    plow = {k.lower(): v for k, v in paths.items()}
    for pk in pkgs:
        require(pk["component"] in by_id, "legacy package %s: unknown component %s" % (pk["label"], pk["component"]))
        for rel, shas in pk["contents"].items():
            p = plow.get(rel)
            if p is not None:
                pres = presence_comps(p, n_states)
                require(not pres or pk["component"] in pres,
                        "legacy package %s (component %s): its file %s is at a path option %s writes alone - a package's "
                        "contents may only meet its own component's paths" % (pk["label"], pk["component"], p["rel"], pres))
            older.setdefault(rel, set()).update(shas)
            for sha in shas:
                pkg_label.setdefault((rel, sha), pk["notes"][(rel, sha)])

    def old_note(rel: str, sha: str) -> str:
        if sha in rel_older.get(rel.lower(), set()):
            return "older release"
        return "older package: %s" % pkg_label.get((rel.lower(), sha), "?")
    for c in comps:
        if c["kind"] not in ("T", "C") or c.get("product") == "infdur":
            continue
        cid = c["id"]
        for n in nat_by_comp.get(cid, []):
            rules.append({"comp": cid, "kind": "N", "arg": n["path_sq"], "sha": "", "state": 1})
        own = own_paths(paths, cid)
        own_rel = {p["rel"].lower(): p for p in own}
        # F: the names the catalog declares as this component's alone
        for rel in c.get("detect_files", []):
            require(rel.lower() in own_rel, "component %s: detect_files %s is not a path only %s writes (absent while "
                                            "it is off)" % (cid, rel, cid))
            rules.append({"comp": cid, "kind": "F", "arg": own_rel[rel.lower()]["rel"], "sha": "", "state": 1,
                          "note": "declared own name"})
        # F: any version of an author's file (mode V members: every content counts)
        dyn = [p for p in own if all(x[0] == "D" for x in p["table"][1:])]
        for p in dyn[:3]:
            rules.append({"comp": cid, "kind": "F", "arg": p["rel"], "sha": "", "state": 1, "note": "any version"})
        # H: its own files by sha256 (v6.5 variants + older releases' contents); beyond the first 3 paths only the
        # older contents that no variant has (for the '-1' removal rule)
        n_before = len(rules)
        pinned = [p for p in own if all(x[0] == "F" for x in p["table"][1:])]
        for i, p in enumerate(pinned):
            mine = {x[1] for x in p["table"][1:]}
            old = older.get(p["rel"].lower(), set())
            shas = sorted(mine | old) if i < 3 else sorted(old - mine)
            for sha in shas:
                rules.append({"comp": cid, "kind": "H", "arg": p["rel"], "sha": sha, "state": 1,
                              "note": ("v6.5" if sha in mine else old_note(p["rel"], sha))})
        # a hot option with no native, no own file name and no path of its own (Deflect Me Not changes only files
        # every selection has): its contents at up to 3 shared paths where every "on" content differs from every
        # "off" content (final pass 2026-10-03; without this a re-run with no switches would switch it off)
        if c.get("hot") and len(rules) == n_before and not nat_by_comp.get(cid):
            sig = 0
            for p in sorted(paths.values(), key=lambda p: p["rel"].lower()):
                if cid not in p["affects"] or p["flags"] == "U":
                    continue
                S = p["affects"]
                ns = [by_id[x]["n_states"] for x in S]
                pos = S.index(cid)
                on, off = set(), set()
                for key, x in enumerate(p["table"]):
                    rest, st = key, []
                    for n in ns:
                        st.append(rest % n)
                        rest //= n
                    (on if st[pos] >= 1 else off).add(x)
                if not on or (on & off) or any(x[0] != "F" for x in on):
                    continue
                for x in sorted(on):
                    rules.append({"comp": cid, "kind": "H", "arg": p["rel"], "sha": x[1], "state": 1,
                                  "note": "v6.5, only while %s is on" % cid})
                sig += 1
                if sig >= 3:
                    break
            require(sig > 0, "component %s: no way to detect it (no native, no own file, no content only it gives)" % cid)
        # NRM-era fix (2026-10-03): the paths cid writes only while it is on whose content another option also picks
        # (rc8: nrm-extension.hks, nrm + dmn) - every older content no variant has, for the '-1' removal rule and the
        # uninstall (v6.4's / rc1-rc7's merged beta.16 file 8e7b453a... was left behind as "another mod's file")
        for p in presence_paths(paths, cid, n_states):
            mine = {x[1] for x in p["table"] if x[0] == "F"}
            for sha in sorted(older.get(p["rel"].lower(), set()) - mine):
                rules.append({"comp": cid, "kind": "H", "arg": p["rel"], "sha": sha, "state": 1,
                              "note": old_note(p["rel"], sha)})
    # Infinite Durations: H on mod\regulation.bin for every v6.5 regulation variant and every older one
    inf = [c for c in comps if c.get("product") == "infdur"]
    if inf:
        c = inf[0]
        reg = paths[cfg.REG_REL]
        S = reg["affects"]
        ns = [by_id[x]["n_states"] for x in S]
        seen = {}
        for key, x in enumerate(reg["table"]):
            if x[0] != "F":
                continue
            rest, st = key, {}
            for sid, n in zip(S, ns):
                st[sid] = rest % n
                rest //= n
            code_i = st.get(c["id"], 0)
            if seen.setdefault(x[1], code_i) != code_i:
                raise RuntimeError("one regulation content maps to two InfDur states")
        for sha, s in sorted(seen.items(), key=lambda kv: (kv[1], kv[0])):
            rules.append({"comp": c["id"], "kind": "H", "arg": cfg.REG_REL, "sha": sha, "state": s,
                          "note": "v6.5 %s" % c["codes"][s]})
        for r in legacy_regs(src) + [x for cp in listed_catalogs(src) for x in catalog_regs(cp)]:
            if r["sha256"] in seen or r["code"] not in c["codes"]:
                continue
            s = c["codes"].index(r["code"])
            seen[r["sha256"]] = s
            rules.append({"comp": c["id"], "kind": "H", "arg": cfg.REG_REL, "sha": r["sha256"], "state": s,
                          "note": r["label"]})
    log("detection: %d rules (%s)" % (len(rules), ", ".join("%s %d" % (k, sum(1 for r in rules if r["kind"] == k))
                                                             for k in "FNH")))
    return rules


def obsolete(src: dict, paths: dict) -> list[dict]:
    """every mod\\ path of the older release zips that v6.5 never writes, once per old content; + old changelogs"""
    leg = src["legacy"]
    written = {p.lower() for p in paths}
    rows = {}
    zips = list(leg["v64"]["zips"].items()) + [("v6.3 " + k, z) for k, z in leg["v63"]["zips"].items()]
    for label, zp in zips:
        for m in _zip_listing(Path(zp)):
            rel = m["rel"]
            if not rel.lower().startswith("mod\\") or rel.lower() in written:
                continue
            rows.setdefault((rel.lower(), m["sha256"]), {"rel": rel, "sha256": m["sha256"],
                                                         "note": "from %s" % Path(zp).name})
    old_logs = [name for v in ("v63", "v64") for name in leg[v].get("changelog_names", [])]
    for cp in listed_catalogs(src):
        c = _catalog(cp)
        for v in c["variants"]:
            pth = c["paths"][v["path"]]
            rel = pth["rel"]
            if v.get("sha256") and pth.get("flags", "") != "U" and rel.lower().startswith("mod\\") and \
                    rel.lower() not in written:
                rows.setdefault((rel.lower(), v["sha256"]), {"rel": rel, "sha256": v["sha256"],
                                                             "note": "from the %s installer" % c.get("tag", cp.parent.name)})
        if c.get("changelog_rel"):
            old_logs.append(c["changelog_rel"])
    out = sorted(rows.values(), key=lambda r: (r["rel"].lower(), r["sha256"]))
    seen_logs = set()
    for name in old_logs:
        if name.lower() != src["release"]["changelog_dest"].lower() and name.lower() not in seen_logs:
            seen_logs.add(name.lower())
            out.append({"rel": name, "sha256": "", "note": "older installer's changelog"})
    log("obsolete: %d rows (%d distinct paths from older zips, %d old changelogs)" % (
        len(out), len({r["rel"].lower() for r in out if r["sha256"]}), sum(1 for r in out if not r["sha256"])))
    return out
