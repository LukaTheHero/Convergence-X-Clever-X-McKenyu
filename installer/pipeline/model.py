"""Turns the composition into the catalog model (= dist\\<tag>\\catalog.json): every array of the contract, in index
form, deterministic (no timestamps). generated\\catalog.iss is a straight translation of it (emit_iss.py)."""
from __future__ import annotations

import re
from pathlib import Path

from . import cfg
from .compose import ABSENT, LEAVE, asset_name
from .legacy import me3_squeeze
from .sources import globs_for
from .util import BuildError, require

SOURCE_TEXT = {"nexus": "your download (Nexus)", "github": "downloaded from GitHub", "installed": "your existing install"}
# 2 (final pass 2026-10-03): the installer reads a per-blob download site (BlobSite, '' = the release mirrors). Since
# 2026-10-03 the pipeline makes no site blob (every blob is a GitHub release asset); the field stays in the contract.
CAT_FORMAT = 2
STATE_TITLES = {"R": ["not installed", "always installed"], "T": ["off", "on"], "X": ["not available", "not available"]}


NEXUS_ID_RE = re.compile(r"^https://(?:www\.)?nexusmods\.com/[a-z0-9]+/mods/(\d+)(?:[/?#].*)?$")


def name_hints_with_id(a: dict) -> list[str]:
    """the archive's name hints + the Nexus mod id of its page (Nexus's own download names carry it as a word:
    'moveset_modpack 26.2 1928 ...zip', 'Seamless Co-op v1.9.9-510-1-9-9-...zip'; the installer matches a number only
    as a whole word). Repair 2, verifier 3 defect D2."""
    hints = list(a["name_hints"])
    m = NEXUS_ID_RE.match(a.get("nexus_url", "") or "")
    if m and m.group(1) not in hints:
        hints.append(m.group(1))
    return hints


def native_lines(n: dict, rc) -> list[str]:
    if "lines" in n:
        return list(n["lines"])
    kind, _, rest = n["lines_from"].partition(":")
    require(kind == "nrm_layer", "native %s: lines_from %s" % (n["id"], n["lines_from"]))
    text = (rc.nrm / rest).read_bytes().decode("utf-8")
    return text.replace("\r\n", "\n").strip("\n").split("\n")


def build_natives(src, rc, cidx) -> list[dict]:
    natives = []
    for n in src["natives"]:
        lines = native_lines(n, rc)
        pl = [l for l in lines if me3_squeeze(l).startswith("path=")]
        require(len(pl) == 1, "native %s: exactly one path line" % n["id"])
        require(n["match"] in me3_squeeze(pl[0]), "native %s: match %s not in its path line" % (n["id"], n["match"]))
        require(sum(1 for l in lines if l.strip() == "[[natives]]") == 1, "native %s: one [[natives]] header" % n["id"])
        require(all(chr(13) not in l for l in lines), "native %s: CR in a line" % n["id"])
        natives.append({"id": n["id"], "component": n["component"], "comp": cidx[n["component"]], "match": n["match"],
                        "path_sq": me3_squeeze(pl[0]), "foreign": n["foreign"], "lf": bool(n.get("lf")), "lines": lines})
    # array order = append order; Nightreign Movement's block must come last (its load_after list), when there is one
    require(natives and (natives[-1]["id"] == "nrm" or all(n["id"] != "nrm" for n in natives)),
            "the NRM native must be the last one")
    return natives


def build_model(src, rc, comp, wall, refs, main_zip, main_zip_name, detection, obsolete, conv_manifest_sha,
                conv_file_count, pristine_me3: list[list[str]], natives: list[dict]) -> dict:
    rel = src["release"]
    cidx = comp.cidx
    tag = rel["tag"]
    # ---------------------------------------------------------------- components + states
    comps, sstart = [], 0
    for c in comp.comps:
        sw = wall["state_wall"].get(c["id"], [0] * c["n_states"])
        if c["kind"] == "C":
            titles = [s["title"] for s in c["states"]]
        else:
            titles = STATE_TITLES[c["kind"]]
        comps.append({"id": c["id"], "switch": c.get("switch", ""), "title": c["title"], "desc": c["desc"],
                      "kind": c["kind"], "experimental": bool(c.get("experimental")),
                      "default": 1 if c["kind"] == "R" else int(c.get("default", 0)),
                      "state_start": sstart, "states": [{"code": code, "title": t, "wall": int(w)}
                                                        for code, t, w in zip(c["codes"], titles, sw)],
                      "credit": c.get("credit", ""), "source_text": SOURCE_TEXT[c["source"]], "source": c["source"],
                      "hot": bool(c.get("hot")), "archives": [a for a in c.get("archives", [])]})
        sstart += c["n_states"]
    # ---------------------------------------------------------------- rules
    rules = []
    for r in src["rules"]:
        ca, cb = comp.comps[cidx[r["a"]]], comp.comps[cidx[r["b"]]]
        rules.append({"kind": r["kind"], "a": cidx[r["a"]], "a_mask": sum(1 << ca["codes"].index(s) for s in r["a_states"]),
                      "b": cidx[r["b"]], "b_mask": sum(1 << cb["codes"].index(s) for s in r["b_states"]), "text": r["text"]})
    # ---------------------------------------------------------------- archives (enabled) + members + pins
    archives, aidx = [], {}
    for a in src["archives"]:
        if not a.get("enabled", True):
            continue
        aidx[a["id"]] = len(archives)
        ref = refs[a["id"]]
        mems = sorted(comp.used_members.get(a["id"], {}).values(), key=lambda m: (m["tail"].lower(), m["sha256"]))
        pins = [{"size": ref.pin[0], "sha256": ref.pin[1]}] if ref.pin else []
        if a["mode"] == "V":
            for m in mems:
                m["sha256"], m["size"] = "", -1
                # the tested version's bytes of this member (the installer's "tested version" verdict; never a
                # requirement: mode V takes any version the player chooses)
                m["tested_sha256"] = ref.tested.get(m["tail"], "")
                require(m["tested_sha256"], "%s: member %s has no tested hash (reference %s)" % (a["id"], m["tail"],
                                                                                                ref.path))
        archives.append({"id": a["id"], "comp": cidx[a["component"]], "title": a["title"], "author": a["author"],
                         "hint": a["hint"], "nexus_url": a.get("nexus_url", ""), "nexus_url_status": a.get("nexus_url_status", ""),
                         "name_hints": name_hints_with_id(a), "mode": a["mode"], "must_verify": bool(a.get("must_verify")),
                         "globs": globs_for([m["name"] for m in mems]), "pins": pins, "members": mems,
                         "reference": {"kind": ref.kind, "path": cfg.public_path(ref.path) if ref.path else main_zip_name},
                         "tested": {"version": a["reference"].get("tested_version", ""), "members": ref.tested}
                         if a["mode"] == "V" else None})
    mem_key_index = {}
    for ai, a in enumerate(archives):
        for mi, m in enumerate(a["members"]):
            mem_key_index[(a["id"], m["name"].lower(), m["sha256"])] = (ai, mi)
    # ---------------------------------------------------------------- blobs
    blob_list = []
    bidx = {}
    for sha, b in sorted(comp.blobs.items(), key=lambda kv: (sorted(kv[1]["paths"], key=str.lower)[0].lower(), kv[0])):
        bidx[sha] = len(blob_list)
        first = sorted(b["paths"], key=str.lower)[0]
        blob_list.append({"sha256": sha, "size": b["size"], "asset": asset_name(sha, first),
                          "tag": tag, "upstream": b.get("upstream", ""),
                          "paths": sorted(b["paths"], key=str.lower)})
    names = [b["asset"] for b in blob_list]
    require(len(names) == len(set(n.lower() for n in names)), "asset name collision")
    # ---------------------------------------------------------------- paths + variants
    path_list = list(comp.paths.values())
    pidx = {p["rel"].lower(): i for i, p in enumerate(path_list)}
    variants = []
    for v in comp.variants:
        e = {"path": pidx[v["path"].lower()], "sha256": v.get("sha256", ""), "size": v.get("size", -1), "src": v["src"]}
        if v["src"] == "A":
            name_l, sha = v["member_key"]
            ai, mi = mem_key_index[(v["arch"], name_l, sha)]
            # global member index = start of the archive + mi (filled after starts are known)
            e["ref_arch"], e["ref_member"] = ai, mi
        else:
            e["ref_blob"] = bidx[v["blob"]]
        variants.append(e)
    # global member numbering
    mstart = 0
    for a in archives:
        a["mem_start"] = mstart
        mstart += len(a["members"])
    pstart = 0
    for a in archives:
        a["pin_start"] = pstart
        pstart += len(a["pins"])
    for e in variants:
        if e["src"] == "A":
            e["ref"] = archives[e.pop("ref_arch")]["mem_start"] + e.pop("ref_member")
        else:
            e["ref"] = e.pop("ref_blob")
    paths, aff, tab = [], [], []
    for p in path_list:
        paths.append({"rel": p["rel"], "flags": p["flags"], "owner": cidx[p["owner"]], "aff_start": len(aff),
                      "affects": [cidx[x] for x in p["affects"]], "tab_start": len(tab), "table": p["tab_var"]})
        aff += [cidx[x] for x in p["affects"]]
        ns = 1
        for x in p["affects"]:
            ns *= comp.comps[cidx[x]]["n_states"]
        require(len(p["tab_var"]) == ns, "table size of %s" % p["rel"])
        tab += p["tab_var"]
    # ---------------------------------------------------------------- fields, credits
    fields = [{"comp": cidx[f["component"]], "id": f["id"], "switch": f["switch"], "label": f["label"], "rel": f["dest"],
               "section": f["section"], "key": f["key"], "secret": bool(f.get("secret"))} for f in src["fields"]]
    credits = [{"comp": -1, "text": t} for t in src["credits_always"]]
    for c in comp.comps:
        if c.get("credit") and c["kind"] != "X" and c["credit"] not in src["credits_always"]:
            credits.append({"comp": c["idx"], "text": c["credit"]})
        # the third-party authors whose work an option's own files are built from (release prep 2026-10-03: Lucy)
        for t in c.get("credits_extra", []) if c["kind"] != "X" else []:
            if t not in src["credits_always"] and {"comp": c["idx"], "text": t} not in credits:
                credits.append({"comp": c["idx"], "text": t})
    # ---------------------------------------------------------------- MAX_PATH budget
    rels = [p["rel"] for p in paths] + [o["rel"] for o in obsolete] + [f["rel"] for f in fields] + cfg.EXTRA_WRITTEN
    max_rel = max(len(r) for r in rels)
    max_dir = max(len(r.rsplit("\\", 1)[0]) for r in rels if "\\" in r)
    wall_dll = cidx.get(src["wall"].get("dll_component", ""), -1)
    model = {
        "format": CAT_FORMAT,
        "version": rel["version"], "version_short": rel["version_short"], "tag": tag, "mod_title": rel["mod_title"],
        "rc": rc.name, "built": "rc %s, BUILD_REPORT %s" % (rc.name, rc.report.get("label")),
        "changelog_rel": rel["changelog_dest"], "nexus_url": rel["nexus_url"],
        "installer_base_name": rel["installer_base_name"],
        "components": comps, "rules": rules, "paths": paths, "aff": aff, "tab": tab, "variants": variants,
        "archives": archives, "blobs": blob_list, "base_urls": list(rel["github"]["base_urls"]), "natives": natives,
        "pristine_me3": pristine_me3, "detection": [dict(d, comp=cidx[d["comp"]]) for d in detection],
        "obsolete": obsolete, "fields": fields, "credits": credits,
        "wall": {"base": wall["base"], "limit_nodll": src["wall"]["limit_without_dll"],
                 "limit_dll": src["wall"]["limit_with_dll"], "dll_comp": wall_dll, "measured": wall["measured"],
                 "combo_comps": [cidx[x] for x in wall.get("combo_comps", [])],
                 "combo_totals": list(wall.get("combo_totals", []))},
        "max_rel_len": max_rel, "max_rel_dir_len": max_dir,
        "main_zip": {"name": main_zip_name, "size": main_zip["size"], "sha256": main_zip["sha256"],
                     "members": len(main_zip["members"])},
        "conv_manifest": {"file": cfg.CONV_MANIFEST_NAME, "magic": cfg.CONV_MANIFEST_MAGIC, "sha256": conv_manifest_sha},
        "conv302_file_count": conv_file_count,
    }
    return model


def github_blobs(model: dict) -> list[dict]:
    """the blobs of the GitHub release (all of them since 2026-10-03; a blob with a "site" would be downloaded from
    that site instead - CAT_FORMAT 2 keeps the field, the pipeline no longer makes one)"""
    return [b for b in model["blobs"] if not b.get("site")]
