"""P6: composition (INSTALLER_V65_DESIGN.md section 3.4): hot table over the hot components (lucy x nrm x infdur),
Convergence originals, user-config LEAVE, affects reduction, toggle components, changelog path, source assignment
(Clever/McKenyu archive > on-in-every-selection archive > main zip > blob) and the never-host asserts."""
from __future__ import annotations

import itertools
import re
from pathlib import Path

from . import cfg
from .catalog_src import comp_states
from .util import BuildError, hash_file, log, require

ABSENT = ("ABSENT",)
LEAVE = ("LEAVE",)


def content_of(path) -> tuple:
    h = hash_file(path)
    return ("F", h["sha256"])


class Composer:
    def __init__(self, src, rc, prod, refs):
        self.src, self.rc, self.prod, self.refs = src, rc, prod, refs
        self.comps = []
        for i, c in enumerate(src["components"]):
            st = comp_states(c)
            self.comps.append(dict(c, idx=i, n_states=len(st), codes=[s["code"] for s in st]))
        self.cidx = {c["id"]: c["idx"] for c in self.comps}
        self.hot = [c for c in self.comps if c.get("hot") and c["kind"] != "X"]
        for c in self.hot:
            require(c["kind"] in ("T", "C"), "hot component %s must be a toggle or choice" % c["id"])
            require(c.get("product") in ("lucy", "nrm", "infdur", "dmn"),
                    "hot component %s: no product builder for %r (add products.py:build_<x>)" % (c["id"], c.get("product")))
        self.content_file: dict[str, Path] = {}     # sha256 -> a local file holding it
        self.content_size: dict[str, int] = {}
        self.user_config: dict[str, dict] = {}      # rel -> {comp, from}
        self.conv = Path(src["inputs"]["convergence_pristine"])

    # ------------------------------------------------------------------ helpers
    def note(self, path) -> tuple:
        h = hash_file(path)
        self.content_file.setdefault(h["sha256"], Path(path))
        self.content_size[h["sha256"]] = h["size"]
        return ("F", h["sha256"])

    def hot_state(self, st: dict, cid: str) -> int:
        return st.get(cid, 0)

    def combo_tree(self, st: dict) -> dict:
        """full tree {rel: file} of a hot combination (states by comp id; missing = 0); no user-config files"""
        T = dict(self.rc.main)
        lucy = self.prod["lucy"]
        has = {c["product"]: self.hot_state(st, c["id"]) for c in self.hot}
        nrm_on = has.get("nrm", 0) >= 1
        lucy_on = has.get("lucy", 0) >= 1
        if nrm_on:
            T.update(self.rc.nrm_files)
        # Deflect Me Not (final pass 2026-10-03): its layer on the chain, or the one on NRM + the chain (rc8: dmn_nrmw
        # on the Wylder NRM layer itself, an ERCap-only state - Luka 2026-10-03; the installer adds ERCapacityExpansion)
        if has.get("dmn", 0) >= 1:
            require(self.rc.dmn, "a DMN state is composed but the RC has no DMN layers")
            T.update(self.rc.dmn_nrm_files if nrm_on else self.rc.dmn_files)
        if lucy_on:
            T.update(lucy["nrm" if nrm_on else "plain"]["files"])
            T[cfg.REG_REL] = lucy["plain"]["files"][cfg.REG_REL]       # one Lucy regulation (params asserted equal)
            if nrm_on:
                # NRM 0.2 changes Lucy's two icon files too: Lucy + NRM = Lucy's pair with NRM's changes put in
                T.update(self.prod.get("nrm_menu") or {})
        ed = has.get("infdur", 0)
        if ed:
            comp = [c for c in self.hot if c["product"] == "infdur"][0]
            T[cfg.REG_REL] = self.prod["infdur"]["lucy" if lucy_on else "plain"][comp["codes"][ed]]
        return T

    def combo_user_config(self, st: dict) -> dict:
        out = {}
        for c in self.hot:
            if self.hot_state(st, c["id"]) >= 1:
                for u in c.get("user_config", []):
                    out[u["dest"]] = self.resolve_from(u["from"])
        return out

    def resolve_from(self, spec: str):
        kind, _, rest = spec.partition(":")
        if kind == "nrm_layer":
            return self.rc.nrm / rest
        if kind == "archive":
            aid, _, member = rest.partition(":")
            return ("D", aid, self.archive_member_tail(aid, member))
        raise BuildError("unknown 'from' spec %r" % spec)

    def archive_member_tail(self, aid: str, member: str) -> str:
        """a mode V archive's member as its FULL reference path (SeamlessCoop\\ersc_settings.ini, not just the file
        name): the installer's tie-break and package-folder rule need the real path inside the pack"""
        arch = [a for a in self.src["archives"] if a["id"] == aid]
        require(arch, "'from' names an unknown archive %s" % aid)
        mems = arch[0].get("members") or []
        if member in mems:
            return member
        hits = [m for m in mems if m.lower() == member.lower() or m.lower().endswith("\\" + member.lower())]
        require(len(hits) == 1, "archive %s: member %r matches %d of its members %s" % (aid, member, len(hits), mems))
        return hits[0]

    # ------------------------------------------------------------------ the hot table
    def hot_table(self):
        combos = [dict(zip([c["id"] for c in self.hot], states))
                  for states in itertools.product(*[range(c["n_states"]) for c in self.hot])]
        trees, ucs = [], []
        for st in combos:
            trees.append(self.combo_tree(st))
            ucs.append(self.combo_user_config(st))
        union = set()
        for t in trees:
            union |= set(t)
        uc_rels = set()
        for u in ucs:
            uc_rels |= set(u)
        for c in self.hot:
            for u in c.get("user_config", []):
                self.user_config[u["dest"]] = {"comp": c["id"], "from": u["from"]}
        require(not (union & uc_rels), "a user-config path is also a normal path: %s" % (union & uc_rels))
        per_path = {}
        conv_orig = {}
        for rel in sorted(union | uc_rels, key=str.lower):
            vals = []
            for t, u in zip(trees, ucs):
                if rel in uc_rels:
                    if rel in u:
                        x = u[rel]
                        vals.append(x if isinstance(x, tuple) else self.note(x))
                    else:
                        vals.append(LEAVE)
                elif rel in t:
                    vals.append(self.note(t[rel]))
                elif (self.conv / rel).is_file():
                    v = self.note(self.conv / rel)
                    conv_orig[rel] = v[1]
                    vals.append(v)
                else:
                    vals.append(ABSENT)
            per_path[rel] = vals
        self.conv_originals = conv_orig
        return combos, per_path

    def reduce(self, combos, vals):
        """smallest subset S of hot comps (catalog order) that determines the content -> (S ids, table)"""
        ids = [c["id"] for c in self.hot]
        for k in range(len(ids) + 1):
            for S in itertools.combinations(ids, k):
                m = {}
                ok = True
                for st, v in zip(combos, vals):
                    key = tuple(st[x] for x in S)
                    if m.setdefault(key, v) != v:
                        ok = False
                        break
                if ok:
                    ns = [self.comps[self.cidx[x]]["n_states"] for x in S]
                    table = []
                    for key in range(_prod(ns)):
                        states, rest = [], key
                        for n in ns:
                            states.append(rest % n)
                            rest //= n
                        table.append(m[tuple(states)])
                    return list(S), table
        raise BuildError("affects reduction failed")

    # ------------------------------------------------------------------ everything
    def compose(self, changelog_file: Path):
        combos, per_path = self.hot_table()
        paths = {}
        hot_ids = [c["id"] for c in self.hot]
        for rel, vals in per_path.items():
            S, table = self.reduce(combos, vals)
            owner = "main" if rel in self.rc.main else (S[0] if S else "main")
            if rel in self.user_config:
                owner = self.user_config[rel]["comp"]
            paths[rel] = {"rel": rel, "flags": "U" if rel in self.user_config else "", "owner": owner,
                          "affects": S, "table": table, "kind": "hot"}
        # toggles / non-hot components with their own files
        for c in self.comps:
            if c.get("hot") or c["kind"] == "X":
                continue
            own = {}
            for f in c.get("files", []):
                fp = self.prod["files"][c["id"]][f["dest"]]["file"]
                own[f["dest"]] = self.note(fp)
            if c.get("product") == "seamless":
                arch = [a for a in self.src["archives"] if a["component"] == c["id"]][0]
                for m in arch["members"]:
                    own[m] = ("D", arch["id"], m)
            ucd = {u["dest"]: u for u in c.get("user_config", [])}
            for d, u in ucd.items():
                x = self.resolve_from(u["from"])
                own[d] = x if isinstance(x, tuple) else self.note(x)
                self.user_config[d] = {"comp": c["id"], "from": u["from"]}
            if c.get("product") == "clever_parts":
                ref = self.refs[c["archives"][0]]
                for f in ref.files:
                    if f["tail"].lower().startswith("parts\\"):
                        own["mod\\parts\\" + f["name"]] = ("F", f["sha256"])
                        self.content_size[f["sha256"]] = f["size"]
                        self.content_file.setdefault(f["sha256"], ref.path / f["tail"])
            # the animation wall is measured over the hot combinations only (run_pipeline.anim_components): a
            # non-hot component that ships a c0000 animation binder would never be counted, so the installer could
            # not force ERCapacityExpansion (or refuse) for it. Refuse such a catalog until the wall measures it.
            binders = {("mod\\chr\\" + n).lower() for n in cfg.WALL_FILES}
            anim = sorted(r for r in own if r.lower() in binders)
            require(not anim, "component %s (not hot) ships the c0000 animation binder(s) %s: the animation wall would "
                    "not count them. Make it a hot component (measured per combination) or extend wall.py first." % (
                        c["id"], anim))
            for rel, v in own.items():
                hit = [p for p in paths if p.lower() == rel.lower()]
                require(not hit, "path %s is claimed by %s and by %s (only hot components may share paths)" % (
                    rel, c["id"], paths[hit[0]]["owner"] if hit else "?"))
                if c["kind"] == "R":
                    paths[rel] = {"rel": rel, "flags": "", "owner": c["id"], "affects": [], "table": [v], "kind": "R"}
                else:
                    off = LEAVE if rel in ucd else ABSENT
                    tab = [off] + [v] * (c["n_states"] - 1)
                    paths[rel] = {"rel": rel, "flags": "U" if rel in ucd else "", "owner": c["id"], "affects": [c["id"]],
                                  "table": tab, "kind": "toggle"}
        # the installed changelog = the main zip's CHANGELOG.txt
        dest = self.src["release"]["changelog_dest"]
        require(dest not in paths, "changelog path collides")
        paths[dest] = {"rel": dest, "flags": "", "owner": "main", "affects": [], "table": [self.note(changelog_file)],
                       "kind": "changelog"}
        self.changelog = {"rel": dest, "sha256": paths[dest]["table"][0][1], "file": changelog_file}
        self.paths = dict(sorted(paths.items(), key=lambda kv: kv[0].lower()))
        lower = [p.lower() for p in self.paths]
        require(len(lower) == len(set(lower)), "case-duplicate paths")
        for p in self.paths.values():
            for x in p["table"]:
                require(x in (ABSENT, LEAVE) or x[0] in ("F", "D"), "bad table entry %s" % (x,))
            if p["flags"] == "U":
                require(all(x != ABSENT for x in p["table"]), "user-config %s must never be ABSENT" % p["rel"])
        n_aff = {}
        for p in self.paths.values():
            if p["kind"] == "hot":
                k = "+".join(p["affects"]) or "none"
                n_aff[k] = n_aff.get(k, 0) + 1
        log("hot table: %d combinations, %d paths; affects %s; Convergence originals %d; total paths %d" % (
            len(combos), sum(1 for p in self.paths.values() if p["kind"] == "hot"), n_aff, len(self.conv_originals),
            len(self.paths)))
        return self.paths

    # ------------------------------------------------------------------ variants + sources
    def variants_and_sources(self, main_zip_members: list[dict], main_zip_pin):
        """main_zip_members: [{tail, name, sha256, size}] of the main zip (built by mainzip.py)"""
        self.refs["main_v65"].files = list(main_zip_members)
        self.refs["main_v65"].pin = main_zip_pin
        variants = []
        vindex = {}
        for p in self.paths.values():
            p["tab_var"] = []
            for x in p["table"]:
                if x == ABSENT:
                    p["tab_var"].append(-1)
                elif x == LEAVE:
                    p["tab_var"].append(-2)
                else:
                    key = (p["rel"].lower(), x)
                    if key not in vindex:
                        vindex[key] = len(variants)
                        variants.append({"path": p["rel"], "content": x})
                    p["tab_var"].append(vindex[key])
        comp = {c["id"]: c for c in self.comps}
        arch_by_id = {a["id"]: a for a in self.src["archives"] if a.get("enabled", True)}
        r_archives = [a for a in self.src["archives"] if a.get("enabled", True) and comp[a["component"]]["kind"] == "R"
                      and a["component"] != "main"]
        main_shas = {m["sha256"] for m in main_zip_members}
        used_members: dict[str, dict] = {}        # arch id -> {(name lower, sha or member tail): member dict}
        blobs: dict[str, dict] = {}

        def use_member(aid, sha, path_rel):
            ref = self.refs[aid]
            cands = [f for f in ref.files if f["sha256"] == sha]
            base = path_rel.rsplit("\\", 1)[-1].lower()
            cands.sort(key=lambda f: (f["name"].lower() != base, not f["tail"].lower().endswith(path_rel.lower()),
                                      f["tail"].lower()))
            f = cands[0]
            k = (f["name"].lower(), sha)
            um = used_members.setdefault(aid, {})
            if k not in um:
                um[k] = {"name": f["name"], "tail": f["tail"], "sha256": sha, "size": f["size"]}
            return k

        for k, v in enumerate(variants):
            p = self.paths[v["path"]]
            x = v["content"]
            if x[0] == "D":
                aid, member = x[1], x[2]
                um = used_members.setdefault(aid, {})
                key = (member.rsplit("\\", 1)[-1].lower(), "")
                um.setdefault(key, {"name": member.rsplit("\\", 1)[-1], "tail": member, "sha256": "", "size": -1})
                v.update(src="A", arch=aid, member_key=key, sha256="", size=-1)
                continue
            sha = x[1]
            v["sha256"], v["size"] = sha, self.content_size[sha]
            # (a) Clever / McKenyu (required archives other than main)
            hit = None
            for a in r_archives:
                if sha in self.refs[a["id"]].by_sha():
                    hit = a["id"]
                    break
            # (b) an archive of a component that is on in EVERY selection wanting this variant
            if hit is None:
                for a in arch_by_id.values():
                    c = comp[a["component"]]
                    if c["kind"] == "R" or c["source"] != "nexus" or a["id"] == "main_v65":
                        continue
                    if not self.on_whenever_wanted(p, k, c["id"]):
                        continue
                    if sha in self.refs[a["id"]].by_sha():
                        hit = a["id"]
                        break
            # (c) the main zip
            if hit is None and comp["main"]["source"] == "nexus" and sha in main_shas:
                hit = "main_v65"
            if hit is not None:
                v.update(src="A", arch=hit, member_key=use_member(hit, sha, v["path"]))
            else:
                b = blobs.setdefault(sha, {"sha256": sha, "size": self.content_size[sha], "paths": [],
                                           "file": self.content_file[sha], "upstream": ""})
                b["paths"].append(v["path"])
                v.update(src="B", blob=sha)
        # upstream URLs (ERCap DLL: the author's release asset first)
        for cid, fs in self.prod["files"].items():
            for dest, f in fs.items():
                if f.get("upstream"):
                    sha = hash_file(f["file"])["sha256"]
                    if sha in blobs:
                        blobs[sha]["upstream"] = f["upstream"]
        # verify-only members (catalog archives[].verify_members): files only the author's own pack has. They are
        # never installed, but an archive is accepted only when they are there too - so a package that merely
        # carries copies of the author's files (the merge's own v6.4 zips held all 80 McKenyu files) is refused.
        for a in arch_by_id.values():
            for tail in a.get("verify_members", []):
                require(a["mode"] == "P", "archive %s: verify_members need mode P" % a["id"])
                f = self.refs[a["id"]].find_member(tail)
                require(f["sha256"] not in main_shas, "archive %s: verify member %s is also in the main zip" % (
                    a["id"], tail))
                um = used_members.setdefault(a["id"], {})
                um.setdefault((f["name"].lower(), f["sha256"]), {"name": f["name"], "tail": f["tail"],
                                                                 "sha256": f["sha256"], "size": f["size"]})
        # the main zip's members are all of its files (every one is ours and every one is needed)
        um = used_members.setdefault("main_v65", {})
        for m in main_zip_members:
            um.setdefault((m["name"].lower(), m["sha256"]), dict(m))
        self.variants, self.used_members, self.blobs = variants, used_members, blobs
        n_src = {}
        for v in variants:
            k = v["src"] + ":" + (v.get("arch") or "blob")
            n_src[k] = n_src.get(k, 0) + 1
        log("variants: %d (%s); blobs %d, %.1f MB" % (len(variants), n_src, len(blobs),
                                                    sum(b["size"] for b in blobs.values()) / 1048576))
        return variants

    def on_whenever_wanted(self, p, k, cid) -> bool:
        if p["kind"] == "toggle":
            return p["owner"] == cid
        if cid not in p["affects"]:
            return False
        S = p["affects"]
        ns = [self.comps[self.cidx[x]]["n_states"] for x in S]
        pos = S.index(cid)
        for key, var in enumerate(p["tab_var"]):
            if var != k:
                continue
            rest = key
            states = []
            for n in ns:
                states.append(rest % n)
                rest //= n
            if states[pos] < 1:
                return False
        return True

    # ------------------------------------------------------------------ never-host
    def never_host(self, main_zip_members):
        forbidden = {}
        for aid, ref in self.refs.items():
            if aid == "main_v65":
                continue
            for f in ref.files:
                forbidden.setdefault(f["sha256"], "%s:%s" % (aid, f["tail"]))
        # 2026-10-04: an archive's layer_package (the package its layer was built from, e.g. NRM's 0.2 zip next to the
        # Nexus 1.2 download) counts as the players' own too, except its declared 'hosted' tails (licence notices the
        # players' download lacks; they must ship with the DLL)
        n_hosted = 0
        for a in self.src["archives"]:
            lp = a.get("layer_package") if a.get("enabled", True) else None
            if not lp:
                continue
            from . import sources
            hosted = [t.lower() for t in lp.get("hosted", [])]
            for f in sources.layer_package_files(a):
                t = f["tail"].lower()
                if any(t == h or t.endswith("\\" + h) for h in hosted):
                    n_hosted += 1
                    continue
                forbidden.setdefault(f["sha256"], "%s (layer package):%s" % (a["id"], f["tail"]))
        clever_names = set()
        for c in self.comps:
            if c.get("product") == "clever_parts":
                for f in self.refs[c["archives"][0]].files:
                    if f["tail"].lower().startswith("parts\\"):
                        clever_names.add(f["name"].lower())
        bad = []
        for sha, b in self.blobs.items():
            if sha in forbidden:
                bad.append("blob %s (%s) == %s" % (sha[:12], b["paths"][0], forbidden[sha]))
            for pth in b["paths"]:
                if pth.rsplit("\\", 1)[-1].lower() in clever_names:
                    bad.append("blob for a Clever part name: %s" % pth)
        for m in main_zip_members:
            if m["sha256"] in forbidden:
                bad.append("main zip member %s == %s" % (m["tail"], forbidden[m["sha256"]]))
            if m["name"].lower() in clever_names:
                bad.append("main zip member with a Clever part name: %s" % m["tail"])
        require(not bad, "NEVER-HOST RULE BROKEN: %s" % bad[:10])
        log("never-host: no blob and no main-zip member has the bytes of any of %d files of the players' own downloads "
            "(%s; layer packages: %d declared hosted notices exempt); no Clever part name hosted (%d names)" % (
                len(forbidden), ", ".join(sorted(a for a in self.refs if a != "main_v65")), n_hosted, len(clever_names)))
        return {"forbidden_contents": len(forbidden), "clever_names": len(clever_names), "layer_package_hosted": n_hosted}


def _prod(ns):
    out = 1
    for n in ns:
        out *= n
    return out


ASSET_SAFE = re.compile(r"[^A-Za-z0-9._-]")


def asset_name(sha: str, path_rel: str) -> str:
    base = path_rel.rsplit("\\", 1)[-1]
    return "%s-%s" % (sha[:16], ASSET_SAFE.sub("_", base))
