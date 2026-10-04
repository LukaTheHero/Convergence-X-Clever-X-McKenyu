r"""v6.5 release pipeline - every path, token and fixed constant in one place.

Tokens used in catalog\catalog.src.json:
  ${WS}   = C:\00000ConvergenceER\ClaudeWorkspace
  ${CCM}  = ${WS}\clever_x_convergence_x_mckenyu
  ${V65}  = ${CCM}\v65
  ${INST} = ${V65}\installer
"""
from __future__ import annotations

import json
import os
from pathlib import Path

WS = Path(r"C:\00000ConvergenceER\ClaudeWorkspace")
CCM = WS / "clever_x_convergence_x_mckenyu"
V65 = CCM / "v65"
INST = V65 / "installer"
TOKENS = {"${WS}": str(WS), "${CCM}": str(CCM), "${V65}": str(V65), "${INST}": str(INST)}

PIPE = INST / "pipeline"
TOOLS = PIPE / "tools"
VENDOR_INFDUR = PIPE / "vendor" / "infdur"
CATALOG_DIR = INST / "catalog"
CATALOG_SRC = CATALOG_DIR / "catalog.src.json"
CHANGELOG_DRAFT = V65 / "dist" / "_drafts" / "CHANGELOG_v65.txt"     # release-kit lane's text (read-only for us)
UPSTREAM = INST / "upstream"
OFFICIAL_MANIFEST = UPSTREAM / "convergence_302_manifest_v2.json"
GENERATED = INST / "generated"
CATALOG_ISS = GENERATED / "catalog.iss"
BUILD_INFO_ISS = GENERATED / "build_info.iss"
STAGING_META = INST / "staging" / "meta"
WORK = INST / "work"
PRODUCTS = WORK / "products"
INFDUR_RUNS = WORK / "infdur"
HASHCACHE = WORK / "hashcache.json"
ASSETS = INST / "assets"                     # blob store: assets\<sha256> (copies; everything else hard-links to it)
DIST = INST / "dist"
RELEASE_STAGING = INST / "release_staging"   # what goes to GitHub: <tag>\<asset> + repo\...
V65_DIST = V65 / "dist"                      # Luka's place for the release files (main zip + exe hard links)
LOGS = INST / "logs"
TESTS_RESULTS = INST / "tests" / "results"
ISS = INST / "CXCXM_v65_Installer.iss"
CODE_DIR = INST / "code"
OUT_DIRS = {"codecheck": INST / "codecheck_output", "test": INST / "test_output", "release": INST / "output"}

# the user-profile folders come from the environment (no user name in the source that goes to GitHub)
LOCALAPPDATA = Path(os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData" / "Local"))
USERPROFILE = Path(os.environ.get("USERPROFILE") or Path.home())
ISCC = LOCALAPPDATA / "Programs" / "Inno Setup 6" / "ISCC.exe"
PY311 = ["py", "-3.11", "-X", "utf8"]
PY314 = ["py", "-3.14", "-X", "utf8"]

# Build-PC specific settings live in LOCAL files catalog\*.local.json (never pushed: ghstage.source_files takes only
# catalog.src.json and the changelog from catalog\). Lucy's build: her workspace folder, recipe arguments and her own
# build checks come from catalog\lucy_build.local.json ({"root": ..., "recipe": [...], "build_checks": [...]}).
LUCY_LOCAL = CATALOG_DIR / "lucy_build.local.json"


def _local_json(p: Path) -> dict:
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _lucy_local() -> dict:
    return _local_json(LUCY_LOCAL)


def local_settings(key: str) -> list:
    """every catalog\\*.local.json's list under key, in file-name order (a missing or unreadable file adds nothing)"""
    out = []
    for p in sorted(CATALOG_DIR.glob("*.local.json")):
        v = _local_json(p).get(key)
        if isinstance(v, list):
            out += [x for x in v if isinstance(x, str) and x]
    return out


def private_markers() -> list[str]:
    """texts no public file may hold (ghstage's repo content scan), read at run time from the LOCAL files only: their
    'private_markers' lists, plus the MARKERS list of every script a 'private_markers_from' entry names (read with
    ast, never run). [] = not configured on this PC (the repo scan then refuses to pass)."""
    import ast
    out = list(local_settings("private_markers"))
    for src in local_settings("private_markers_from"):
        try:
            tree = ast.parse(Path(src).read_text(encoding="utf-8"))
        except (OSError, ValueError, SyntaxError):
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "MARKERS" for t in node.targets):
                try:
                    vals = ast.literal_eval(node.value)
                except ValueError:
                    continue
                out += [x for x in vals if isinstance(x, str) and x]
    seen, uniq = set(), []
    for x in out:
        if x not in seen:
            seen.add(x)
            uniq.append(x)
    return uniq


_LUCY = _lucy_local()
LUCY_CONFIGURED = bool(_LUCY.get("root")) and isinstance(_LUCY.get("recipe"), list) and bool(_LUCY.get("recipe"))
LUCY_ROOT = Path(_LUCY["root"]) if _LUCY.get("root") else WS / "_lucy_workspace_not_configured"
LUCY_RECIPE = [str(x) for x in _LUCY.get("recipe", [])] if LUCY_CONFIGURED else []
# Lucy's own checks on each of her builds ({"script", "args" with {build} / {base}, "python": "3.11" | "3.14", "cwd"});
# products.lucy_build_checks refuses a Lucy build when none is configured
LUCY_BUILD_CHECKS = [c for c in (_LUCY.get("build_checks") or []) if isinstance(c, dict) and c.get("script")] \
    if LUCY_CONFIGURED else []
LANGS = "araae deude engus frafr itait jpnjp korkr polpl porbr rusru spaar spaes thath zhocn zhotw".split()
LUCY_ICON_MENU = [r"menu\hi\01_common.sblytbnd.dcx", r"menu\hi\01_common.tpf.dcx"]
# the regulation param members Lucy's recipe changes (measured rc2 + rc3: every other member equals the RC's); a Lucy
# regulation that differs from its RC regulation anywhere else was built on another RC and is never reused
LUCY_PARAM_MEMBERS = ["CharMakeMenuListItemParam.param", "EquipParamProtector.param", "FaceParam.param",
                      "ShopLineupParam.param"]

# Convergence 3.0.2 integrity manifest (v6.4 format 2, unchanged)
OFFICIAL_REPO = "The-Convergence-Team/ConvergenceER-Public"
OFFICIAL_COMMIT = "633a4b8a8e43d3f262faa41251dabbaf9a973847"
OFFICIAL_MANIFEST_COMMIT = "9aa1561a07a7ee643379870c63fc833c344c96a7"
OFFICIAL_FILE_COUNT = 4081
OFFICIAL_MANIFEST_PATH = "DownloaderContent/manifest_v2.json"
PRISTINE_FILE_COUNT = 4265
GAME_FORMAT_EXTS = {"dcx", "js", "hks", "wem", "bk2", "gfx", "hkxbdt", "hkxbhd", "dll", "bnk", "exe", "txt",
                    "", "anibnd", "tpfbdt", "tpfbhd", "behbnd", "bin"}
CONV_MANIFEST_NAME = "CXCXM_conv302_manifest.txt"
CONV_MANIFEST_MAGIC = "CXCXM-CONV302-MANIFEST 2"
ME3_PROFILES = ["me3\\convergence.me3", "me3\\convergence - seamless.me3"]
BAT_REL = "Start_Convergence.bat"
MD5_CHECKED = ["me3\\Windows\\me3.exe", "me3\\Windows\\me3_mod_host.dll", "me3\\Windows\\me3-launcher.exe"]
REG_REL = "mod\\regulation.bin"

# files the installer writes besides the catalog paths (MAX_PATH budget, conv manifest O flags)
EXTRA_WRITTEN = ["me3\\convergence.me3", "me3\\convergence - seamless.me3", "CXCXM_INSTALLED.txt",
                 "CXCXM_BACKUP_MANIFEST.txt"]

# wall (clip list): the 16 c0000 animation binders, resolved: install tree -> pristine Convergence mod -> vanilla chr
WALL_FILES = (["c0000.anibnd.dcx", "c0000_a00_hi.anibnd.dcx", "c0000_a00_md.anibnd.dcx", "c0000_a00_lo.anibnd.dcx"] +
              ["c0000_a%dx.anibnd.dcx" % i for i in range(10)] + ["c0000_dlc01.anibnd.dcx", "c0000_dlc02.anibnd.dcx"])

MAIN_ZIP_DATE = (2026, 1, 1, 0, 0, 0)
TEXT_EXTS = {".txt", ".lua", ".hks", ".json", ".ini", ".toml", ".md", ".xml", ".csv"}
EXE_LIMIT = 20 * 1024 * 1024
MAX_REL_BUDGET = 150          # longest relative path we accept (leaves ~110 chars for the install folder)

# never write below these (overnight plan + contract hard rules; build-PC folders that must stay untouched come from the
# LOCAL files' "forbidden_write_roots" lists)
FORBIDDEN_WRITE_ROOTS = [
    WS / "TESTINSTALL",
    Path(r"C:\Program Files (x86)\Steam"),
    Path(r"C:\Program Files\Steam"),
    USERPROFILE / "Downloads",
    Path("C:\\$Recycle.Bin"),
    WS / "clever_x_convergence_x_mckenyu_INF_DURATIONS" / "v64",
] + [CCM / ("v%d" % n) for n in range(40, 65)] + [Path(p) for p in local_settings("forbidden_write_roots")]
ALLOWED_WRITE_ROOTS = [INST, V65_DIST, Path(os.environ.get("TEMP") or (LOCALAPPDATA / "Temp"))]


def lucy_names(rc: str):
    """-> {suffix: (base name, build name)} exactly as deploy_v65.py names them"""
    return {suf: ("merge_v65%s%s" % (rc.lower(), suf), "lucy_merge_v65%s%s" % (rc.lower(), suf)) for suf in ("", "_nrm")}


def lucy_write_roots(rc: str):
    out = []
    for b, o in lucy_names(rc).values():
        out += [LUCY_ROOT / "base" / b, LUCY_ROOT / "build" / o]
    return out


def expand(s: str) -> str:
    for k, v in TOKENS.items():
        s = s.replace(k, v)
    return s


def public_path(p) -> str:
    """a local path as a PUBLIC file may show it (final repair 2026-10-03; catalog.json is public): under its workspace
    token (${INST}, ${V65}, ${CCM}, ${WS}, the longest first), or the file name alone outside them - never a drive
    letter or a machine folder."""
    s = str(p)
    for k in ("${INST}", "${V65}", "${CCM}", "${WS}"):
        v = TOKENS[k]
        if s.lower() == v.lower() or s.lower().startswith(v.lower() + "\\"):
            return k + s[len(v):]
    return Path(s).name
