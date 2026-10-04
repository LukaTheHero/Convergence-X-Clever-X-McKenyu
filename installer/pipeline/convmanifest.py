"""P8b: staging\\meta\\CXCXM_conv302_manifest.txt - the Convergence 3.0.2 integrity list, v6.4 format 2 unchanged
(port of v64\\installer\\build.py official_manifest / conv_manifest / write_conv_manifest). Flag O = every path any
v6.5 variant, obsolete row, user config or field writes. MD5 stays (check B is proven code). Deterministic text."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from . import cfg
from .legacy import me3_squeeze
from .util import hash_file, log, md5_file, require, sha256_file, write_text


def official_manifest(pinned_sha: str) -> dict:
    require(cfg.OFFICIAL_MANIFEST.is_file(), "pinned official manifest missing: %s" % cfg.OFFICIAL_MANIFEST)
    got = sha256_file(cfg.OFFICIAL_MANIFEST)
    require(got == pinned_sha, "%s sha256 %s != pinned %s (was it edited?)" % (cfg.OFFICIAL_MANIFEST.name, got, pinned_sha))
    data = json.loads(cfg.OFFICIAL_MANIFEST.read_text(encoding="utf-8-sig"))
    require(data.get("commitHash") == cfg.OFFICIAL_MANIFEST_COMMIT, "official manifest commitHash %s" % data.get("commitHash"))
    out = {}
    for rel, v in data["files"].items():
        require(set(v) == {"sha256", "size"}, "official manifest entry %s: keys %s" % (rel, sorted(v)))
        r = rel.replace("/", "\\")
        require(r.lower() not in out, "official manifest: duplicate path %s" % rel)
        out[r.lower()] = (r, int(v["size"]), v["sha256"].lower())
    require(len(out) == cfg.OFFICIAL_FILE_COUNT, "official manifest has %d files, expected %d" % (len(out), cfg.OFFICIAL_FILE_COUNT))
    return out


def bat_variable_names(text: str) -> list[str]:
    lines = text.splitlines()
    names = []
    for i, ln in enumerate(lines):
        if ln.strip().lower() == ":: variables":
            for nxt in lines[i + 1:]:
                m = re.match(r'(?i)^set\s+"?([A-Za-z0-9_]+)=', nxt.strip())
                if not m:
                    break
                names.append(m.group(1).lower())
            break
    return names


def bat_squeeze(line: str) -> str:
    return line.strip().lower().replace(" ", "").replace("\t", "").replace('"', "")


def bat_normalized_md5(text: str, names: list[str]) -> str:
    drop = tuple("set" + n + "=" for n in names)
    kept = [ln for ln in text.splitlines() if not bat_squeeze(ln).startswith(drop)]
    while kept and kept[-1].strip() == "":
        kept.pop()
    return hashlib.md5("\n".join(kept).encode("utf-16-le")).hexdigest()


def build(src: dict, written_rels: set, conv_originals: dict, rc_name: str):
    """-> (entries, keep, bat_names). conv_originals = {rel: sha256} the installer writes back (must be official)."""
    pristine = Path(src["inputs"]["convergence_pristine"])
    require(pristine.is_dir(), "pristine Convergence 3.0.2 folder missing: %s" % pristine)
    official = official_manifest(src["inputs"]["convergence_official_manifest_sha256"])
    overwritten = {r.lower() for r in written_rels} | {cfg.REG_REL.lower(), "version.txt"}
    profiles = {p.lower() for p in cfg.ME3_PROFILES}
    md5_set = {m.lower() for m in cfg.MD5_CHECKED}
    conv_o = {r.lower(): s for r, s in conv_originals.items()}
    bat_text = (pristine / cfg.BAT_REL).read_bytes().decode("utf-8-sig")
    bat_names = bat_variable_names(bat_text)
    require(bat_names, "%s: no ':: Variables' set lines found" % cfg.BAT_REL)
    entries, local = [], set()
    for p in sorted(pristine.rglob("*"), key=lambda x: str(x).lower()):
        if not p.is_file():
            continue
        rel = str(p.relative_to(pristine)).replace("/", "\\")
        low = rel.lower()
        local.add(low)
        name = p.name.lower()
        size = p.stat().st_size
        require("|" not in rel and all(32 <= ord(c) < 127 for c in rel), "unexpected file name: %r" % rel)
        off = official.get(low)
        if off is not None:
            require(off[1] == size, "%s: %d bytes here, %d in the official release" % (rel, size, off[1]))
        md5 = ""
        if low in profiles:
            flag = "P"
        elif low in overwritten:
            flag = "O"
            if low in conv_o:
                require(off is not None and sha256_file(p) == off[2] == conv_o[low],
                        "%s: the Convergence original the installer writes back is not the official 3.0.2 content" % rel)
        elif name.endswith(".log") or low.startswith("mod\\dll\\logs\\"):
            flag = "R"
        elif off is None:
            flag = "X"
        elif low == cfg.BAT_REL.lower():
            flag = "T"
            require(sha256_file(p) == off[2], "%s: content differs from the official release" % rel)
            md5 = bat_normalized_md5(bat_text, bat_names)
        elif name.endswith(".ini") or name.endswith(".toml"):
            flag = "C"
        else:
            flag = "S"
            ext = name.rsplit(".", 1)[1] if "." in name else ""
            require(ext in cfg.GAME_FORMAT_EXTS, "%s: required file of an unexpected type .%s" % (rel, ext))
            if low in md5_set or (low.startswith("mod\\dll\\") and low.count("\\") == 2 and name.endswith(".dll")):
                require(sha256_file(p) == off[2], "%s: content differs from the official release" % rel)
                md5 = md5_file(p)
        entries.append((flag, size, md5, rel))
    require(len(entries) == cfg.PRISTINE_FILE_COUNT, "pristine Convergence has %d files, expected %d" % (
        len(entries), cfg.PRISTINE_FILE_COUNT))
    missing = sorted(official[k][0] for k in official.keys() - local)
    require(not missing, "official 3.0.2 files missing from the pristine folder: %s" % missing[:10])
    for flag, _, _, rel in entries:
        if flag in "SCTP":
            require(rel.lower() in official, "%s is required (flag %s) but not in the official release" % (rel, flag))
    got_md5 = {e[3].lower() for e in entries if e[2] and e[0] == "S"}
    require(md5_set <= got_md5, "md5 files missing from the pristine folder: %s" % sorted(md5_set - got_md5))
    require(sum(1 for x in got_md5 if x.startswith("mod\\dll\\")) >= 5, "too few mod\\dll\\*.dll with md5")
    require(sum(1 for e in entries if e[0] == "P") == len(cfg.ME3_PROFILES), "the .me3 profiles are missing")
    require(sum(1 for e in entries if e[0] == "T") == 1, "%s is missing" % cfg.BAT_REL)
    flagged_o = {e[3].lower() for e in entries if e[0] == "O"}
    require(set(conv_o) <= flagged_o, "a restored Convergence original is not flagged O")
    keep = []
    for prof in cfg.ME3_PROFILES:
        seen = set()
        for line in (pristine / prof).read_text(encoding="utf-8-sig").splitlines():
            s = me3_squeeze(line)
            if not s or s.startswith("#") or s.startswith("[") or s.startswith("savefile="):
                continue
            require("|" not in s, "%s: '|' in a profile line" % prof)
            if s not in seen:
                seen.add(s)
                keep.append((prof, s))
        require(any("./../mod/dll/" in s for p_, s in keep if p_ == prof), "%s: no natives lines found" % prof)
    return entries, keep, bat_names


def render(entries, keep, bat_names, rc_name: str, version_short: str) -> tuple[str, str]:
    """-> (the file text with CRLF line ends, its sha256), nothing written (the --final gates run first)"""
    out = [
        cfg.CONV_MANIFEST_MAGIC,
        "# The Convergence 3.0.2 as the %s installer checks it. Generated by the v6.5 pipeline (pipeline\\convmanifest.py, "
        "RC %s)." % (version_short, rc_name),
        "# Official release: %s commit %s" % (cfg.OFFICIAL_REPO, cfg.OFFICIAL_COMMIT),
        "#   (%s, commitHash %s, %d files)" % (cfg.OFFICIAL_MANIFEST_PATH, cfg.OFFICIAL_MANIFEST_COMMIT, cfg.OFFICIAL_FILE_COUNT),
        "# F|flag|size|md5|path   S = official file: exact size (+md5 when given), C = official config (must exist),",
        "#                        T = Start_Convergence.bat (md5 of its text without the V settings lines),",
        "#                        R = runtime (ignored), X = not in the official release (known, never required),",
        "#                        O = written by the installer in some selection (checked after install),",
        "#                        P = .me3 profile",
        "# K|profile|line         a line (lowercase, no spaces, ' quotes) the .me3 profile must keep",
        "# V|name                 a ':: Variables' setting of Start_Convergence.bat (set name=...) players may change",
        "OFFICIAL=%s@%s" % (cfg.OFFICIAL_REPO, cfg.OFFICIAL_COMMIT[:8]),
        "COUNT=%d" % len(entries),
        "BYTES=%d" % sum(e[1] for e in entries),
    ]
    out += ["F|%s|%d|%s|%s" % (f, size, md5, rel) for f, size, md5, rel in entries]
    out += ["K|%s|%s" % (prof, line) for prof, line in keep]
    out += ["V|%s" % n for n in bat_names]
    text = "\r\n".join(out) + "\r\n"
    return text, hashlib.sha256(text.encode("utf-8")).hexdigest()


def write(entries, keep, bat_names, rc_name: str, version_short: str) -> dict:
    text, sha = render(entries, keep, bat_names, rc_name, version_short)
    p = write_text(cfg.STAGING_META / cfg.CONV_MANIFEST_NAME, text.replace("\r\n", "\n"), newline="\r\n")
    require(hash_file(p)["sha256"] == sha, "conv manifest: the written file differs from the rendered text")
    counts = {k: sum(1 for e in entries if e[0] == k) for k in "SCTRXOP"}
    log("conv manifest %s: %d files %s, %d with md5, %d .me3 lines to keep, batch settings %s" % (
        p.name, len(entries), counts, sum(1 for e in entries if e[2]), len(keep), bat_names))
    return {"sha256": hash_file(p)["sha256"], "count": len(entries), "flags": counts}
