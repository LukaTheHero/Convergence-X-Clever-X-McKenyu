"""P8c: dist\\<tag>\\catalog.json (its sha256 = CAT_SHA256), the GitHub repo's text files and
dist\\<tag>\\BUILD_REPORT.json.

Repo text files (written to dist\\<tag>\\repo\\ and release_staging\\repo\\; pipeline\\ghstage.py commits them together
with releases/<tag>/catalog.json and the installer source):
  README.md                     what the repo is, how players use the installer, credits, every mod from its own page
  CREDITS.md                    every credit line the installer shows, per option
  LICENSE-NOTES.md              who owns what; ERCapacityExpansion's MIT notice; no game files in git
  LICENSES/ERCapacityExpansion-MIT.txt, LICENSES/<components[].licenses name> (fromsoftware-rs-MIT.txt)
  .gitignore                    game-file and archive extensions (the git tree holds text only)
  releases/<tag>/ASSETS.md      the release's asset table (asset -> size -> installed as)
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from . import cfg
from .util import hash_file, log, require, sha256_bytes, write_json, write_text

# a Windows drive path as JSON spells it ("C:\\..."); final repair 2026-10-03: catalog.json is public (the repo's
# releases/<tag>/catalog.json), so it holds no local path - archive references are written by cfg.public_path
_DRIVE_PATH_JSON = re.compile(r"(?<![A-Za-z])[A-Za-z]:\\\\")


def catalog_json_text(model: dict) -> str:
    t = json.dumps(model, indent=1, ensure_ascii=False, sort_keys=False) + "\n"
    m = _DRIVE_PATH_JSON.search(t)
    require(not m, "catalog.json would hold a local drive path (%r...): it is public; write such paths with "
                   "cfg.public_path" % (t[m.start():m.start() + 80] if m else ""))
    return t


def write_catalog(model: dict, tag: str) -> tuple[Path, str]:
    p = write_text(cfg.DIST / tag / "catalog.json", catalog_json_text(model))
    sha = hash_file(p)["sha256"]
    log("catalog.json: %s (sha256 %s)" % (p, sha))
    return p, sha


def _page(url: str) -> str:
    """a player-facing link (the ?tab=files suffix kept: it opens the Files tab)"""
    return url if url else ""


def _credit_name(text: str) -> str:
    return text.split(" - ")[0]


def asset_url(model: dict, blob: dict) -> str:
    """the first URL of one hosted file = what the installer downloads (code\\fetch.iss: BaseUrls[i] + BlobTag + '/' +
    BlobAsset)"""
    return (blob.get("site") or model["base_urls"][0]) + blob["tag"] + "/" + blob["asset"]


def readme_text(model: dict, src: dict, cat_sha: str) -> str:
    rel = src["release"]
    tag = rel["tag"]
    comps = model["components"]
    arch_by_comp: dict[int, list] = {}
    for a in model["archives"]:
        arch_by_comp.setdefault(a["comp"], []).append(a)
    req, opt = [], []
    for i, c in enumerate(comps):
        if c.get("source") != "nexus" or c["id"] == "main":
            continue
        for a in arch_by_comp.get(i, []):
            line = "%s: %s" % (a["title"], _page(a["nexus_url"]) or "(page link added before release)")
            (req if c.get("kind") == "R" else opt).append(line)
    own = [c["title"].split(" - ")[0] for c in comps if c.get("source") == "github" and "Canalpa" in c.get("credit", "")]
    hosted_other = [c["title"].split(" - ")[0] for c in comps
                    if c.get("source") == "github" and "Canalpa" not in c.get("credit", "")]
    L = [
        "# %s - Auto Installer" % rel["mod_title"].rsplit(" v", 1)[0],
        "",
        "**%s** is an Elden Ring merge by Canalpa (Luka): The Convergence together with Clever's Moveset" %
        rel["mod_title"].rsplit(" v", 1)[0],
        "Modpack and McKenyu's Modpack, plus optional add-ons. Merge page: %s" % rel["nexus_url"],
        "",
        "From v6.5 on, players install the merge with the **Auto Installer**, one small .exe from the merge's Nexus",
        "page. This repository holds:",
        "",
        "- `installer/` - the installer's source: the Inno Setup 6 script (`%s`, `code/*.iss`) and the Python release" %
        cfg.ISS.name,
        "  pipeline (`release.py`, `pipeline/`) that builds the files, the catalog and the exe from a release candidate.",
        "- `releases/<tag>/catalog.json` - what each release installs: every file, its SHA-256 and where it comes from.",
        "- **Releases** - the files the installer downloads: the merge's own files and the merged versions of files that",
        "  several mods change. They are not a mod on their own (see below).",
        "",
        "## How players use it",
        "",
        "1. Install The Convergence 3.0.2 from its own site (convergencemod.com).",
        "2. On the merge's Nexus page (Files tab), download the Main Files zip and the Auto Installer.",
        "3. Download the other mods from their own pages:",
    ]
    L += ["   - required: %s" % x for x in req]
    L += ["   - only if you tick it in the installer: %s" % x for x in opt]
    L += [
        "4. Run the Auto Installer and tick the options you want. It finds your Convergence folder and your downloads",
        "   (in Downloads, or you pick them), checks every file by SHA-256, downloads the merge's own files from this",
        "   repository's release (checked by SHA-256 too), installs your picks and checks the result. It keeps a backup",
        "   of everything it replaces.",
        "5. Start the game the usual way for The Convergence.",
        "",
        "Run the installer again to change your picks. Uninstall it from Windows' Apps list: the Convergence folder goes",
        "back to how it was before.",
        "",
        "## Every mod comes from its own page",
        "",
        "The installer never re-hosts another author's mod. For every mod made by someone else, the player downloads",
        "the author's own file from the author's own page, and the installer checks that file before it uses it. The",
        "files in this repository's releases only complete an install that is built from those downloads; on their own",
        "they do nothing. The options made by Canalpa (%s) download from this repository's release." % ", ".join(own),
    ]
    if hosted_other:
        L.append("%s download%s from %s author's own GitHub release first; this repository keeps a fallback copy." % (
            " and ".join(hosted_other), "s" if len(hosted_other) == 1 else "", "its" if len(hosted_other) == 1 else "each"))
    L += [
        "",
        "## Credits",
        "",
    ]
    for c in model["credits"]:
        L.append("- %s" % c["text"])
    for c in src["components"]:
        if c.get("kind") == "X" and c.get("credit"):
            title = c.get("title", "")
            L.append("- %s - planned as a later installer option%s" % (
                c["credit"], " (%s)" % title.split(" - ", 1)[1] if " - " in title else ""))
    L += [
        "",
        "Per-option credits: [CREDITS.md](CREDITS.md). Who owns what, and the licence texts of the parts that have one",
        "(ERCapacityExpansion, fromsoftware-rs): [LICENSE-NOTES.md](LICENSE-NOTES.md), [LICENSES/](LICENSES/).",
        "",
        "## Release %s" % tag,
        "",
        "- Release candidate: `%s`" % model["rc"],
        "- Catalog sha256: `%s` ([catalog.json](releases/%s/catalog.json))" % (cat_sha, tag),
        "- %d release assets, %.1f MB, listed in [releases/%s/ASSETS.md](releases/%s/ASSETS.md). Each asset is named" % (
            len(_gh(model)), sum(b["size"] for b in _gh(model)) / 1048576, tag, tag),
        "  `<first 16 hex of its sha256>-<file name>`; the installer downloads it from",
        "  `%s%s/<asset>` and checks its SHA-256 before anything in the game folder changes." % (
            model["base_urls"][0], tag),
        "",
        "## Building (maintainer)",
        "",
        "`installer/release.py --rc <rc> --all` turns a release candidate into the main zip, the hosted files, the",
        "catalog, the installer exe, the test gate and this repository's draft release in one command",
        "(`installer/pipeline/oneshot.py` lists the steps). The pipeline reads its",
        "inputs (the release candidate builds and the authors' original downloads, used as references) from the",
        "maintainer's PC, so it does not run anywhere else. The contract between the pipeline and the Inno code:",
        "[installer/README_CONTRACT.md](installer/README_CONTRACT.md).",
        "",
    ]
    return "\n".join(L)


def _gh(model: dict) -> list[dict]:
    """the GitHub release's blobs (all of them; CAT_FORMAT 2 would let a blob with a "site" come from that site)"""
    return [b for b in model["blobs"] if not b.get("site")]


def assets_text(model: dict, tag: str) -> str:
    lines = [
        "# Release %s - assets" % tag,
        "",
        "Every file the installer can download for %s. URL = `%s%s/<asset>`. The installer checks each file's" % (
            tag, model["base_urls"][0], tag),
        "size and SHA-256 (the hex at the start of the name is the first 16 hex of its SHA-256; the full value is in",
        "[catalog.json](catalog.json)).",
        "",
        "| asset | size | installed as |",
        "|---|---:|---|",
    ]
    for b in _gh(model):
        lines.append("| `%s` | %d | %s |" % (b["asset"], b["size"], "<br>".join("`%s`" % p for p in b["paths"][:3]) +
                                            (" (+%d more)" % (len(b["paths"]) - 3) if len(b["paths"]) > 3 else "")))
    lines.append("")
    return "\n".join(lines)


def credits_text(model: dict, n_conv_orig: int) -> str:
    comps = model["components"]
    cl = ["# Credits", "", "The installer shows the credits of every option you pick. All of them:", ""]
    for c in model["credits"]:
        who = "always" if c["comp"] < 0 else comps[c["comp"]]["title"]
        cl.append("- %s  _(%s)_" % (c["text"], who))
    cl += ["", "The other authors' mods are not re-hosted here as mods: the installer asks you to download each one from",
           "its own page and checks your file, and nothing here works without those downloads. What is here: the",
           "merge's own files, the merged versions of files that several mods change, ERCapacityExpansion's DLL",
           "(MIT-licensed, see LICENSES/; downloaded from the author's own GitHub release first, this copy is the",
           "fallback), and %d unchanged files of The Convergence 3.0.2 that the installer puts back when an option that" % (
               n_conv_orig),
           "replaced them is switched off (your own copies may already be overwritten by an older manual install).",
           "You still need The Convergence itself from its own site.", ""]
    return "\n".join(cl)


def component_licenses(src: dict) -> list[dict]:
    """the licence texts the enabled options' own files carry (catalog components[].licenses: name, from,
    expect_sha256, what); rc8 switch prep 2026-10-03: fromsoftware-rs in infinite_arrows.dll"""
    out = []
    for c in src.get("components", []):
        if c.get("kind") == "X":
            continue
        for lic in c.get("licenses", []):
            data = Path(lic["from"]).read_bytes()
            require(sha256_bytes(data) == lic["expect_sha256"].lower(),
                    "component %s: licence %s is not the pinned text (sha256)" % (c["id"], lic["from"]))
            out.append(dict(lic, comp=c["id"], text=data.decode("utf-8")))
    return out


def license_notes_text(model: dict, n_conv_orig: int, licenses: list | None = None) -> str:
    comps = model["components"]
    # authors whose content is merged into hosted files: the required mods and the hot (merged) options
    others = [_credit_name(c["text"]) for c in model["credits"]
              if c["comp"] >= 0 and "Canalpa" not in c["text"].split(" - ")[0]
              and comps[c["comp"]].get("source") == "nexus" and c["text"] == comps[c["comp"]].get("credit")
              and (comps[c["comp"]].get("kind") == "R" or comps[c["comp"]].get("hot"))]
    # the third-party authors whose work an option's own files are built from (release prep 2026-10-03: Lucy's
    # armor, hair and body mesh): every credit row of an option besides its own credit line
    parts = {}
    for c in model["credits"]:
        if c["comp"] >= 0 and c["text"] != comps[c["comp"]].get("credit"):
            parts.setdefault(c["comp"], []).append(c["text"])
    part_lines = []
    for ci, texts in sorted(parts.items()):
        part_lines += ["- **%s** (by Canalpa) is built with parts of other authors' work: %s. The rights to those parts" % (
            comps[ci]["title"].split(" - ")[0], "; ".join(texts)),
                       "  stay with their authors; they are credited on the installer's Credits page and in "
                       "[CREDITS.md](CREDITS.md)."]
    return "\n".join([
        "# Licence notes",
        "",
        "- **The installer source and the merge's own files** (`installer/`, `releases/`, and the release assets made",
        "  by Canalpa): (c) Canalpa (Luka). No open-source licence is granted for them; ask before reusing them outside",
        "  this merge.",
        "- **Merged files in the release assets** contain reworked parts of other authors' work (%s, and The" %
        ", ".join(others),
        "  Convergence). They are made for this merge, credited in [CREDITS.md](CREDITS.md), and only work together",
        "  with each author's original download from the author's own page. The rights to that content stay with its",
        "  authors.",
    ] + part_lines + [
        "- **%s**. Full text: [LICENSES/%s](LICENSES/%s)." % (lic["what"][:1].upper() + lic["what"][1:], lic["name"],
                                                            lic["name"]) for lic in (licenses or [])
    ] + [
        "- **ERCapacityExpansion** (`CapacityExpansion.dll` asset) by KamiyamaShiki0704: MIT License, Copyright (c) 2026",
        "  KamiyamaShiki0704. Full text: [LICENSES/ERCapacityExpansion-MIT.txt](LICENSES/ERCapacityExpansion-MIT.txt);",
        "  the installer also puts it next to the DLL. The installer downloads the DLL from the author's own GitHub",
        "  release first; the copy here is the fallback.",
        "- **%d unchanged files of The Convergence 3.0.2**: (c) The Convergence Team. They are hosted only so the" % (
            n_conv_orig),
        "  installer can put them back when an option that replaced them is switched off. The Convergence itself is",
        "  installed from its own site.",
        "- **Inno Setup** (the installer is built with it): (c) Jordan Russell and Martijn Laan, under the Inno Setup",
        "  License. The installer unpacks .rar and .zip downloads with 7-Zip's 7z.dll (by Igor Pavlov, GNU LGPL with the",
        "  unRAR licence restriction, 7-zip.org), which Inno Setup builds into it.",
        "- **me3** and **Scripts-Data-Exposer-FS** ship with The Convergence, not with this repository.",
        "- **Elden Ring** is (c) FromSoftware / Bandai Namco. The git tree of this repository holds text only (source,",
        "  catalog, docs); game-format files exist only as release assets.",
        "",
    ])


GITIGNORE = "\n".join([
    "# This repository's git tree holds text only (installer source, catalog, docs).",
    "# Game-format files and archives go to the GitHub release as assets, never into git.",
    "*.dcx", "*.bin", "*.dll", "*.exe", "*.hks", "*.bnd", "*.tpf", "*.bdt", "*.bhd", "*.wem", "*.bnk", "*.bk2",
    "*.zip", "*.rar", "*.7z", "*.me3",
    "__pycache__/", "*.pyc", "*.log",
    "",
])


def repo_files(model: dict, src: dict, prod: dict, cat_sha: str, conv_original_shas: set | None = None) -> dict:
    tag = src["release"]["tag"]
    n_conv = len([b for b in model["blobs"] if b["sha256"] in (conv_original_shas or set())])
    out = {"README.md": readme_text(model, src, cat_sha), "CREDITS.md": credits_text(model, n_conv),
           "releases/%s/ASSETS.md" % tag: assets_text(model, tag)}
    lics = component_licenses(src)
    out["LICENSE-NOTES.md"] = license_notes_text(model, n_conv, lics)
    out[".gitignore"] = GITIGNORE
    lic = prod["json"]["ercap"]["license"]
    if lic:
        out["LICENSES/ERCapacityExpansion-MIT.txt"] = Path(lic).read_text(encoding="utf-8", errors="replace")
    for x in lics:
        out["LICENSES/" + x["name"]] = x["text"]
    written = {}
    for name, text in out.items():
        for root in (cfg.DIST / tag / "repo", cfg.RELEASE_STAGING / "repo"):
            write_text(root / name.replace("/", "\\"), text)
        written[name] = str(cfg.DIST / tag / "repo" / name.replace("/", "\\"))
    log("repo files: %s (in dist\\%s\\repo and release_staging\\repo)" % (sorted(out), tag))
    return written


def build_report(path: Path, report: dict) -> Path:
    return write_json(path, report)
