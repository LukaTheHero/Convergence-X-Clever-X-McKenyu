"""catalog\\catalog.src.json loader + schema validation (INSTALLER_V65_DESIGN.md section 3.2)."""
from __future__ import annotations

import json
import re

from . import cfg
from .checks import unsafe_rel
from .util import BuildError, require, sha256_file

ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
SWITCH_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
# an https:// web address with a host; no blanks, quotes or control characters
HTTPS_RE = re.compile(r"^https://[A-Za-z0-9.-]+(?::\d+)?(?:/[^\s\"'<>\\^`{|}]*)?$")
KINDS = {"R", "T", "C", "X"}
SOURCES = {"nexus", "github", "installed"}


def iss_switch_names() -> tuple[set, set]:
    """(Inno Setup's own switch names, the installer's fixed switch names), read from code\\catalogrt.iss
    (IsInnoSwitchName and OurSwitchNames): the installer's command-line check and this validation use ONE list
    (repair 3, code review LOW: the old copy here lacked ADMIN, NOGROUP, NOSTYLE, DARKMODE, SL5, ...)."""
    text = (cfg.CODE_DIR / "catalogrt.iss").read_text(encoding="utf-8")
    i = text.index("function IsInnoSwitchName")
    inno = set(re.findall(r"N = '([A-Z0-9?-]+)'", text[i:text.index("\nend;", i)]))
    i = text.index("procedure OurSwitchNames")
    fixed = set(re.findall(r"Names\.Add\('([A-Z0-9_]+)'\)", text[i:text.index("\nend;", i)]))
    require({"SILENT", "VERYSILENT", "LOG", "TASKS", "ADMIN", "NOSTYLE", "NOREDIRECTIONGUARD"} <= inno,
            "code\\catalogrt.iss IsInnoSwitchName: Inno's switch list not found (%d names read)" % len(inno))
    require({"CONVDIR", "COMPONENTS", "SELECT", "FOREIGN", "BASEURL", "GAMEOK", "TESTUNIT"} <= fixed,
            "code\\catalogrt.iss OurSwitchNames: the fixed switch list not found (%d names read)" % len(fixed))
    return inno, fixed


def switch_problem(sw: str, inno: set, fixed: set) -> str:
    """'' when sw can be a component's or a field's own switch, else why not"""
    if not SWITCH_RE.match(sw) or len(sw) < 3:
        return "not an upper-case name of 3 or more letters, digits and _"
    if sw in inno:
        return "an Inno Setup switch"
    if sw in fixed:
        return "one of the installer's fixed switches"
    if sw.startswith("ARCHIVE_"):
        return "ARCHIVE_<id> names the downloads"
    if sw.startswith("TEST"):
        return "TEST... names the test builds' switches"
    return ""


def _expand(o):
    if isinstance(o, str):
        return cfg.expand(o)
    if isinstance(o, list):
        return [_expand(x) for x in o]
    if isinstance(o, dict):
        return {k: _expand(v) for k, v in o.items()}
    return o


def _strip_comments(o):
    if isinstance(o, dict):
        return {k: _strip_comments(v) for k, v in o.items() if not k.startswith("_")}
    if isinstance(o, list):
        return [_strip_comments(x) for x in o]
    return o


def comp_states(c: dict) -> list[dict]:
    """[{code, title}] for any kind (R: one effective state '1' but two codes 0/1 for the key arithmetic)"""
    if c["kind"] == "C":
        return c["states"]
    return [{"code": "0", "title": "off"}, {"code": "1", "title": "on"}]


def load() -> dict:
    raw = json.loads(cfg.CATALOG_SRC.read_text(encoding="utf-8"))
    src = _expand(_strip_comments(raw))
    validate(src)
    return src


def validate(s: dict) -> None:
    require(s.get("format") == 1, "catalog.src.json: format must be 1")
    for k in ("release", "inputs", "wall", "components", "archives", "natives", "fields", "rules", "credits_always",
              "legacy"):
        require(k in s, "catalog.src.json: missing top-level key %r" % k)
    rel = s["release"]
    for k in ("version", "version_short", "tag", "mod_title", "nexus_url", "installer_base_name", "main_zip_name",
              "changelog_source", "changelog_dest", "github"):
        require(k in rel, "release.%s missing" % k)
    require(re.fullmatch(r"\d+\.\d+\.\d+", rel["version"]), "release.version must be x.y.z")
    gh = rel["github"]
    for k in ("owner", "repo", "base_urls"):
        require(k in gh, "release.github.%s missing" % k)
    require(gh.get("visibility_until_publish", "private") == "private", "github visibility before publish must be private")
    require(all(u.endswith("/") for u in gh["base_urls"]) and gh["base_urls"], "base_urls must end in /")
    # every address the installer opens or downloads from is an https:// web address (code review repair 2, D9:
    # the Downloads page ShellExecs nexus_url; a typo must never open a local program)
    require(HTTPS_RE.match(rel["nexus_url"]), "release.nexus_url %r: not an https:// address" % rel["nexus_url"])
    for u in gh["base_urls"]:
        require(HTTPS_RE.match(u), "release.github.base_urls %r: not an https:// address" % u)

    comps = s["components"]
    ids = [c["id"] for c in comps]
    require(len(ids) == len(set(ids)), "duplicate component ids")
    switches = set()
    inno, fixed = iss_switch_names()
    for c in comps:
        cid = c["id"]
        require(ID_RE.match(cid), "component id %r: lower-case [a-z0-9_]" % cid)
        require(c.get("kind") in KINDS, "component %s: kind %r" % (cid, c.get("kind")))
        require(c.get("source") in SOURCES, "component %s: source %r" % (cid, c.get("source")))
        for k in ("title", "desc", "credit"):
            require(isinstance(c.get(k), str), "component %s: %s missing" % (cid, k))
        require("(experimental" not in c["title"].lower(),
                "component %s: the installer appends ' (experimental)' itself; keep it out of the title" % cid)
        sw = c.get("switch", "")
        if c["kind"] == "R":
            require(sw == "", "component %s: required components have no switch" % cid)
        else:
            why = switch_problem(sw, inno, fixed)
            require(not why, "component %s: switch %r: %s" % (cid, sw, why))
            require(sw not in switches, "duplicate switch %s" % sw)
            switches.add(sw)
        if c["kind"] == "C":
            st = c.get("states")
            require(isinstance(st, list) and len(st) >= 2, "component %s: C needs states[]" % cid)
            codes = [x["code"] for x in st]
            require(len(set(codes)) == len(codes) and all(re.fullmatch(r"[a-z0-9]+", x) for x in codes),
                    "component %s: state codes %s" % (cid, codes))
            require(0 <= c.get("default", 0) < len(st), "component %s: default" % cid)
        else:
            require("states" not in c, "component %s: states only for kind C" % cid)
            require(c.get("default", 0) in (0, 1), "component %s: default" % cid)
        if c["kind"] == "X":
            require(c.get("default", 0) == 0, "component %s: X components default 0" % cid)
        for a in c.get("archives", []):
            require(a in [x["id"] for x in s["archives"]], "component %s: unknown archive %s" % (cid, a))
        require("hosted" not in c, "component %s: hosted[] was retired on 2026-10-03 (every other author's mod is "
                "the player's own download: source 'nexus' + an archive)" % cid)
        ce = c.get("credits_extra", [])
        require(isinstance(ce, list) and all(isinstance(x, str) and x.strip() and x.isprintable() for x in ce),
                "component %s: credits_extra must be a list of one-line texts" % cid)
        for n in c.get("natives", []):
            require(n in [x["id"] for x in s["natives"]], "component %s: unknown native %s" % (cid, n))
        for f in c.get("fields", []):
            require(f in [x["id"] for x in s["fields"]], "component %s: unknown field %s" % (cid, f))
        for f in c.get("files", []):
            require("dest" in f and "from_zip" in f and "member" in f, "component %s: files entry %s" % (cid, f))
            require(not f.get("upstream_url") or HTTPS_RE.match(f["upstream_url"]),
                    "component %s: upstream_url %r: not an https:// address" % (cid, f.get("upstream_url")))
            require(not unsafe_rel(f["dest"]), "component %s: dest %s: %s" % (cid, f["dest"], unsafe_rel(f["dest"])))
        df = c.get("detect_files", [])
        require(isinstance(df, list) and all(isinstance(x, str) and not unsafe_rel(x) for x in df),
                "component %s: detect_files must be a list of relative paths (backslashes)" % cid)
        dests = [f["dest"].lower() for f in c.get("files", [])]
        require(len(dests) == len(set(dests)), "component %s: two files[] entries with the same dest" % cid)
        for u in c.get("user_config", []):
            require("dest" in u and "from" in u, "component %s: user_config %s" % (cid, u))
            require(not unsafe_rel(u["dest"]), "component %s: user_config dest %s: %s" % (cid, u["dest"],
                                                                                         unsafe_rel(u["dest"])))
        za = c.get("zip_anchor")
        if za:
            require(sha256_file(za["path"]) == za["expect_sha256"].lower(),
                    "component %s: zip anchor %s sha256 != %s" % (cid, za["path"], za["expect_sha256"]))
    require("main" in ids, "component 'main' missing")

    arch_ids = [a["id"] for a in s["archives"]]
    require(len(arch_ids) == len(set(arch_ids)), "duplicate archive ids")
    for a in s["archives"]:
        require(ID_RE.match(a["id"]), "archive id %r" % a["id"])
        require(a["component"] in ids, "archive %s: unknown component %s" % (a["id"], a["component"]))
        require(a.get("mode") in ("P", "V"), "archive %s: mode" % a["id"])
        require(isinstance(a.get("name_hints"), list) and all(h == h.lower() and "|" not in h for h in a["name_hints"]),
                "archive %s: name_hints must be lower-case, no '|'" % a["id"])
        ref = a.get("reference", {})
        require(ref.get("kind") in ("built", "folder", "zip", "rar", "none"), "archive %s: reference.kind" % a["id"])
        if a.get("enabled", True) and ref["kind"] in ("folder", "zip", "rar"):
            require("path" in ref, "archive %s: reference.path" % a["id"])
        require(not ref.get("expect_sha256") or re.fullmatch(r"[0-9a-f]{64}", ref["expect_sha256"]),
                "archive %s: reference.expect_sha256 must be 64 lower-case hex" % a["id"])
        if a["mode"] == "V":
            require(a.get("members"), "archive %s: mode V needs members[]" % a["id"])
            for m in a["members"]:
                require("/" not in m and not m.startswith("\\") and ":" not in m and ".." not in m.split("\\"),
                        "archive %s: member %r must be a relative path with backslashes" % (a["id"], m))
        vm = a.get("verify_members", [])
        require(isinstance(vm, list) and all(isinstance(x, str) and x for x in vm),
                "archive %s: verify_members must be a list of reference paths" % a["id"])
        require(not vm or a["mode"] == "P", "archive %s: verify_members need mode P" % a["id"])
        for k in ("title", "author", "hint"):
            require(isinstance(a.get(k), str), "archive %s: %s" % (a["id"], k))
        require(isinstance(a.get("nexus_url", ""), str) and (a.get("nexus_url", "") == "" or HTTPS_RE.match(a["nexus_url"])),
                "archive %s: nexus_url %r: empty or an https:// address" % (a["id"], a.get("nexus_url")))
        require(isinstance(a.get("package_version", ""), str), "archive %s: package_version must be a string" % a["id"])

    # a second download site for files of another author's package (canalpa.com for Nightreign Movement beta.16) was
    # retired on 2026-10-03: every other author's mod is the player's own download, every hosted file is a release asset
    require("sites" not in s and "hosted" not in s,
            "catalog.src.json: 'sites' / 'hosted' were retired on 2026-10-03 (no mod needs a second download site)")

    nat_ids = [n["id"] for n in s["natives"]]
    require(len(nat_ids) == len(set(nat_ids)), "duplicate native ids")
    for n in s["natives"]:
        require(n["component"] in ids, "native %s: component" % n["id"])
        # R re-point one foreign table; S strip every table; K = S while on, keep the player's own copy while off
        require(n.get("foreign") in ("R", "S", "K"), "native %s: foreign" % n["id"])
        require(("lines" in n) != ("lines_from" in n), "native %s: lines xor lines_from" % n["id"])
        require(n["match"] == n["match"].lower() and " " not in n["match"], "native %s: match must be squeezed" % n["id"])

    require(not unsafe_rel(rel["changelog_dest"]), "release.changelog_dest: %s" % unsafe_rel(rel["changelog_dest"]))
    for f in s["fields"]:
        require(f["component"] in ids, "field %s: component" % f["id"])
        require(not unsafe_rel(f["dest"]), "field %s: dest %s: %s" % (f["id"], f["dest"], unsafe_rel(f["dest"])))
        why = switch_problem(f["switch"], inno, fixed)
        require(not why, "field %s: switch %r: %s" % (f["id"], f["switch"], why))
        require(f["switch"] not in switches, "field %s: switch %s is used twice" % (f["id"], f["switch"]))
        switches.add(f["switch"])

    # D (2026-10-03, Luka's DMN + Wylder decision): a and b TOGETHER need the DLL component (wall.dll_component); the
    # installer switches it on by itself and shows the text as the reason (contract 3.2 / 5.2)
    dll = s["wall"].get("dll_component", "")
    for r in s["rules"]:
        require(r["kind"] in ("Q", "X", "W", "D"), "rule kind %r" % r["kind"])
        require(isinstance(r.get("text"), str) and r["text"].strip() and r["text"].isprintable(),
                "rule %s %s/%s: text must be a one-line text" % (r["kind"], r.get("a"), r.get("b")))
        for side in ("a", "b"):
            require(r[side] in ids, "rule: unknown component %s" % r[side])
            c = comps[ids.index(r[side])]
            codes = [x["code"] for x in comp_states(c)]
            for st in r[side + "_states"]:
                require(st in codes, "rule: state %s not a state of %s" % (st, r[side]))
        if r["kind"] == "D":
            require(dll in ids and comps[ids.index(dll)]["kind"] == "T",
                    "rule D %s/%s: wall.dll_component %r must name a toggle (T) component" % (r["a"], r["b"], dll))
            require(r["a"] != dll and r["b"] != dll and r["a"] != r["b"],
                    "rule D %s/%s: names the DLL component itself or one component twice" % (r["a"], r["b"]))
            require(all(st != comp_states(comps[ids.index(r[x])])[0]["code"] for x in ("a", "b")
                        for st in r[x + "_states"]),
                    "rule D %s/%s: a D rule holds only while both options are on (no 'off' state)" % (r["a"], r["b"]))
    # the Wylder-off sibling arrangement (rc8 switch prep) was retired on 2026-10-03 (Luka: DMN + NRM keeps Wylder,
    # with ERCapacityExpansion added automatically)
    inp = s["inputs"]
    require(not {"dmn_nrm_sibling_tier", "dmn_nrm_sibling_files"} & set(inp),
            "catalog.src.json inputs: dmn_nrm_sibling_tier / dmn_nrm_sibling_files were retired on 2026-10-03 (DMN + "
            "NRM is the ERCap-only layer dmn_nrmw_<rc> made on the NRM layer itself; see dmn_ercap_only_layers)")
    eo = inp.get("dmn_ercap_only_layers", [])
    require(isinstance(eo, list) and set(eo) <= {"plain", "nrm"},
            "inputs.dmn_ercap_only_layers must be a list of 'plain' / 'nrm' (got %r)" % (eo,))
    require(not eo or (dll in ids and comps[ids.index(dll)]["kind"] == "T"),
            "inputs.dmn_ercap_only_layers needs wall.dll_component (%r) to be a toggle (T) component" % dll)

    # the ARCHIVE_<id> names the archives make (a component switch can never take one: switch_problem)
    arch_sw = ["ARCHIVE_" + a["id"].upper() for a in s["archives"]]
    require(len(arch_sw) == len(set(arch_sw)), "two archives make the same ARCHIVE_<id> switch")


def comp_index(src: dict) -> dict:
    return {c["id"]: i for i, c in enumerate(src["components"])}


def get_comp(src: dict, cid: str) -> dict:
    for c in src["components"]:
        if c["id"] == cid:
            return c
    raise BuildError("no component %s" % cid)


def get_arch(src: dict, aid: str) -> dict:
    for a in src["archives"]:
        if a["id"] == aid:
            return a
    raise BuildError("no archive %s" % aid)
