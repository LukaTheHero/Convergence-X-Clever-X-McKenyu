"""release.py --all, last step: the release-kit drafts (v65\\dist\\_drafts\\, the texts Luka pastes into Nexus, Discord
and the bot-KB handoff) get the facts of the files this run built (final pass part 2, 2026-10-03).

  1. RELEASE_FILES_<V65>.txt (generated, overwritten every run): the two files Luka uploads to Nexus (name, size, md5,
     sha256), the release exe's catalog + code ids, the GitHub repo / release, the RC.
  2. Every draft that holds a block between a line containing [AUTO:RELEASE-FILES BEGIN] and a line containing
     [AUTO:RELEASE-FILES END] gets that block rewritten with the same facts (the upload sheet, the KB handoff).
  3. Lint, reported (never fatal): a "{{...}}" placeholder left in any draft; a file name "<...> V6.5 - <...>.zip/.exe"
     that is not one of the two files this run built.
The prose itself is written by hand; this step only keeps the numbers right, so a rebuild never leaves an old md5 in
a text Luka pastes.
"""
from __future__ import annotations

import re
from pathlib import Path

from . import cfg, util
from .util import hash_file, log

BEGIN, END = "[AUTO:RELEASE-FILES BEGIN]", "[AUTO:RELEASE-FILES END]"


def drafts_dir() -> Path:
    return cfg.CHANGELOG_DRAFT.parent


def facts(src: dict, m: dict, tag: str, sites: dict | None = None, gh: dict | None = None) -> dict:
    rel = src["release"]
    zp = cfg.DIST / tag / rel["main_zip_name"]
    ep = cfg.DIST / tag / (rel["installer_base_name"] + ".exe")
    side = util.read_json(cfg.DIST / tag / "RELEASE_EXE.json") if (cfg.DIST / tag / "RELEASE_EXE.json").is_file() else {}
    g = rel["github"]
    repo_url = "https://github.com/%s/%s" % (g["owner"], g["repo"])
    out = {"version": rel["version"], "version_short": rel["version_short"], "tag": tag, "rc": m.get("rc"),
           "nexus_url": rel["nexus_url"], "repo_url": repo_url, "release_url": "%s/releases/tag/%s" % (repo_url, tag),
           "files": [], "catalog_sha256": util.sha256_file(cfg.DIST / tag / "catalog.json"),
           "code_fingerprint": side.get("code_fingerprint", ""),
           "github_assets": len(m["blobs"]),
           "github_mb": round(sum(b["size"] for b in m["blobs"]) / 1048576, 1)}
    for kind, p in (("main zip", zp), ("installer exe", ep)):
        if p.is_file():
            h = hash_file(p)
            out["files"].append({"kind": kind, "name": p.name, "path": str(p), "v65_dist": str(cfg.V65_DIST / p.name),
                                 "size": h["size"], "md5": h["md5"], "sha256": h["sha256"]})
    out["github_state"] = {k: gh.get(k) for k in ("visibility", "is_draft", "assets_remote")} \
        if gh and gh.get("visibility") else None
    return out


def block_lines(f: dict, stamp: bool = True) -> list[str]:
    """stamp=False for the AUTO blocks: an unchanged build then leaves the drafts byte for byte as they are"""
    L = ["Release files of %s (tag %s, RC %s) - written by release.py --all%s; do not edit by hand." % (
        f["version_short"], f["tag"], f["rc"], (" on %s" % util.now_stamp()) if stamp else "")]
    for x in f["files"]:
        L.append("- %s: %s" % (x["kind"], x["name"]))
        L.append("    %s bytes, md5 %s" % (format(x["size"], ","), x["md5"]))
        L.append("    sha256 %s" % x["sha256"])
        L.append("    in %s (+ a hard link in %s)" % (str(Path(x["path"]).parent), str(Path(x["v65_dist"]).parent)))
    L.append("- catalog sha256 %s; installer code %s" % (f["catalog_sha256"], f["code_fingerprint"][:16] or "?"))
    L.append("- GitHub: %s (release %s): %d assets, %.1f MB%s" % (
        f["repo_url"], f["release_url"], f["github_assets"], f["github_mb"],
        "; state now: %s, draft=%s, %s assets on GitHub" % (f["github_state"]["visibility"], f["github_state"]["is_draft"],
                                                         f["github_state"]["assets_remote"]) if f.get("github_state") else ""))
    L.append("- Nexus page: %s" % f["nexus_url"])
    return L


def write_release_files(f: dict) -> Path:
    name = "RELEASE_FILES_%s.txt" % f["version_short"].upper().replace(".", "")
    p = drafts_dir() / name
    util.write_text(p, "\n".join(block_lines(f)) + "\n", newline="\r\n")
    return p


def refresh(src: dict, m: dict, tag: str, sites: dict | None = None, gh: dict | None = None) -> dict:
    d = drafts_dir()
    f = facts(src, m, tag, sites, gh)
    rf = write_release_files(f)
    blk = block_lines(f, stamp=False)
    updated, lint = [], []
    names = {x["name"] for x in f["files"]}
    file_rx = re.compile(r"Convergence X Clever X Mc[Kk]enyu [Vv][\d.]+ - [A-Za-z ]+\.(?:zip|exe)")
    for p in sorted(d.iterdir()):
        if not p.is_file() or p.suffix.lower() not in (".txt", ".md") or p == rf or ".pre_" in p.name:
            continue
        raw = p.read_bytes()
        crlf = b"\r\n" in raw
        text = raw.decode("utf-8-sig", errors="replace").replace("\r\n", "\n")
        lines = text.split("\n")
        bi = [i for i, l in enumerate(lines) if BEGIN in l]
        ei = [i for i, l in enumerate(lines) if END in l]
        if bi and ei and ei[0] > bi[0]:
            new = lines[:bi[0] + 1] + blk + lines[ei[0]:]
            if new != lines:
                util.write_text(p, "\n".join(new), newline="\r\n" if crlf else "\n", bom=raw.startswith(b"\xef\xbb\xbf"))
                updated.append(p.name)
            text = "\n".join(new)
        for n, l in enumerate(text.split("\n"), 1):
            if "{{" in l and "}}" in l:
                lint.append("%s:%d placeholder left: %s" % (p.name, n, l.strip()[:120]))
            for hit in file_rx.findall(l):
                if hit.strip() not in names:
                    lint.append("%s:%d names a file this build did not make: %r" % (p.name, n, hit.strip()))
    log("drafts: %s written; AUTO block refreshed in %s; lint: %s" % (
        rf.name, updated or "none (no change)", ("%d finding(s): " % len(lint)) + "; ".join(lint[:6]) if lint else "clean"))
    return {"release_files": str(rf), "updated": updated, "lint": lint, "facts": f}
