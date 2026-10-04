"""P9b: ISCC runs (codecheck / test / release) at BELOW_NORMAL priority; the release exe is copied to dist\\<tag>\\ and
hard-linked into v65\\dist\\, with a sidecar dist\\<tag>\\RELEASE_EXE.json that binds the exe (sha256) to the catalog
and the installer code it was compiled from. The exe itself carries both in its version resource (ProductVersion =
"<version> cat <first 16 hex of the catalog sha256> code <first 16 hex of the code fingerprint>"; the fingerprint
is passed as /DCodeFp), read back by exe_catalog_sha() / exe_code_fp()."""
from __future__ import annotations

import ctypes
import re
import time
from ctypes import wintypes
from pathlib import Path

from . import cfg, util
from .codefp import code_fingerprint
from .util import BuildError, hash_file, log, require, run, write_json

DEFINES = {"codecheck": ["/DCodeCheck"], "test": ["/DTestBuild"], "release": []}
SIDECAR = "RELEASE_EXE.json"


def build_info_cat_sha() -> str:
    m = re.search(r'#define CatSha256 "([0-9a-f]{64})"', cfg.BUILD_INFO_ISS.read_text(encoding="utf-8"))
    require(m, "generated\\build_info.iss has no CatSha256")
    return m.group(1)


def compile_(kind: str) -> dict:
    require(cfg.ISCC.is_file(), "ISCC not found: %s" % cfg.ISCC)
    require(cfg.ISS.is_file(), "%s is missing (INNO lane)" % cfg.ISS)
    out_dir = util.guard_write(cfg.OUT_DIRS[kind])
    out_dir.mkdir(parents=True, exist_ok=True)
    cat_sha = build_info_cat_sha()
    code_fp = code_fingerprint()
    t0 = time.time()
    cmd = [cfg.ISCC, "/Qp", "/DFromPipeline", "/DCodeFp=" + code_fp] + DEFINES[kind] + ["/O%s" % out_dir, cfg.ISS]
    logp = cfg.LOGS / ("iscc_%s.log" % kind)
    r = run(cmd, cwd=cfg.INST, log_to=logp, timeout=7200)
    dt = time.time() - t0
    if r.returncode != 0:
        tail = "\n".join((r.stdout + "\n" + r.stderr).strip().splitlines()[-25:])
        raise BuildError("ISCC %s failed (exit %d, log %s):\n%s" % (kind, r.returncode, logp, tail))
    require(code_fingerprint() == code_fp and build_info_cat_sha() == cat_sha,
            "the installer sources or generated\\ changed while ISCC %s ran: build again" % kind)
    exes = sorted((p for p in out_dir.glob("*.exe") if p.stat().st_mtime >= t0 - 2), key=lambda p: p.stat().st_mtime)
    require(exes, "ISCC %s succeeded but wrote no new .exe into %s" % (kind, out_dir))
    exe = exes[-1]
    h = hash_file(exe)
    warns = [l.strip() for l in (r.stdout + r.stderr).splitlines() if "warning" in l.lower()]
    pv = exe_product_version(exe)
    require(same_id(cat_sha, exe_catalog_sha(exe)) and same_id(code_fp, exe_code_fp(exe)),
            "%s: its version resource does not carry this catalog sha256 and code fingerprint (%r)" % (exe.name, pv))
    log("ISCC %s OK in %.0f s: %s (%d B, sha256 %s, catalog %s, code %s)%s" % (
        kind, dt, exe, h["size"], h["sha256"][:16], cat_sha[:16], code_fp[:16],
        "; %d warning(s)" % len(warns) if warns else ""))
    res = {"kind": kind, "exe": str(exe), "size": h["size"], "sha256": h["sha256"], "md5": h["md5"], "secs": round(dt, 1),
           "catalog_sha256": cat_sha, "code_fingerprint": code_fp, "product_version": pv,
           "warnings": warns[:20], "command": " ".join('"%s"' % c if " " in str(c) else str(c) for c in cmd)}
    record_inputs(res)
    return res


def publish_release_exe(res: dict, tag: str, rc: str) -> dict:
    exe = Path(res["exe"])
    dst = cfg.DIST / tag / exe.name
    side_p = cfg.DIST / tag / SIDECAR
    same = False
    if dst.is_file() and side_p.is_file() and hash_file(dst)["sha256"] == res["sha256"]:
        try:
            old = util.read_json(side_p)
            same = all(old.get(k) == res[k] for k in ("sha256", "catalog_sha256", "code_fingerprint")) and (
                old.get("rc") == rc)
        except (OSError, ValueError):
            same = False
    if same:
        # the cached exe is already the one in dist\<tag>\ with its sidecar (release.py --all, exe cache): keep both
        # (the sidecar's "built" time stays the exe's own)
        lk = util.link_or_copy(dst, cfg.V65_DIST / exe.name)
        log("release exe in %s is already this build (sha256 %s); sidecar kept; %s in %s" % (
            dst.parent, res["sha256"][:16], lk, cfg.V65_DIST))
        return {"dist": str(dst), "v65_dist": str(cfg.V65_DIST / exe.name), "sidecar": str(side_p), "unchanged": True}
    util.copy_file(exe, dst)
    require(hash_file(dst)["sha256"] == res["sha256"], "release exe copy damaged")
    lk = util.link_or_copy(dst, cfg.V65_DIST / exe.name)
    side = {"exe": exe.name, "sha256": res["sha256"], "size": res["size"], "rc": rc,
            "catalog_sha256": res["catalog_sha256"], "code_fingerprint": res["code_fingerprint"],
            "product_version": res["product_version"], "built": util.now_stamp()}
    write_json(side_p, side)
    log("release exe -> %s (+ %s in %s); sidecar %s" % (dst, lk, cfg.V65_DIST, SIDECAR))
    return {"dist": str(dst), "v65_dist": str(cfg.V65_DIST / exe.name), "sidecar": str(side_p)}


# ------------------------------------------------------------------ the exe cache (release.py --all; final pass 2)
INPUTS_NAME = "BUILD_INPUTS.json"


def iscc_id() -> str:
    """ISCC.exe itself is an input too (another Inno version compiles other bytes)"""
    return hash_file(cfg.ISCC)["sha256"] if cfg.ISCC.is_file() else ""


def record_inputs(res: dict) -> None:
    """<out dir>/BUILD_INPUTS.json: what this exe was compiled from. Everything ISCC reads is covered: the .iss code,
    generated/*.iss and the [Files] source (the code fingerprint) + the catalog id + the Inno compiler + the defines."""
    out_dir = Path(res["exe"]).parent
    write_json(out_dir / INPUTS_NAME, {
        "kind": res["kind"], "exe": Path(res["exe"]).name, "sha256": res["sha256"], "size": res["size"],
        "md5": res["md5"], "catalog_sha256": res["catalog_sha256"], "code_fingerprint": res["code_fingerprint"],
        "iscc_sha256": iscc_id(), "defines": DEFINES[res["kind"]], "product_version": res["product_version"],
        "compiled": util.now_stamp()})


def cached_exe(kind: str, cat_sha: str, code_fp: str) -> dict | None:
    """-> compile_()'s result for an exe of this kind already compiled from exactly these inputs, else None"""
    p = cfg.OUT_DIRS[kind] / INPUTS_NAME
    try:
        rec = util.read_json(p)
    except (OSError, ValueError):
        return None
    exe = cfg.OUT_DIRS[kind] / rec.get("exe", "")
    if not (rec.get("kind") == kind and rec.get("catalog_sha256") == cat_sha and rec.get("code_fingerprint") == code_fp
            and rec.get("defines") == DEFINES[kind] and exe.is_file() and rec.get("iscc_sha256") == iscc_id()):
        return None
    h = hash_file(exe)
    if h["sha256"] != rec.get("sha256") or not (same_id(cat_sha, exe_catalog_sha(exe)) and same_id(code_fp, exe_code_fp(exe))):
        return None
    return {"kind": kind, "exe": str(exe), "size": h["size"], "sha256": h["sha256"], "md5": h["md5"], "secs": 0.0,
            "catalog_sha256": cat_sha, "code_fingerprint": code_fp, "product_version": exe_product_version(exe),
            "warnings": [], "command": "(cached: %s %s)" % (INPUTS_NAME, rec.get("compiled")), "cached": True}


# ------------------------------------------------------------------ the exe's own version resource
def exe_version_string(path, key: str = "ProductVersion") -> str:
    """one string of a Windows exe's version resource ('' when it has none)"""
    ver = ctypes.WinDLL("version", use_last_error=True)
    ver.GetFileVersionInfoSizeW.argtypes = [wintypes.LPCWSTR, ctypes.POINTER(wintypes.DWORD)]
    ver.GetFileVersionInfoSizeW.restype = wintypes.DWORD
    ver.GetFileVersionInfoW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p]
    ver.GetFileVersionInfoW.restype = wintypes.BOOL
    ver.VerQueryValueW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR, ctypes.POINTER(ctypes.c_void_p),
                                   ctypes.POINTER(wintypes.UINT)]
    ver.VerQueryValueW.restype = wintypes.BOOL
    dummy = wintypes.DWORD(0)
    n = ver.GetFileVersionInfoSizeW(str(path), ctypes.byref(dummy))
    if not n:
        return ""
    buf = ctypes.create_string_buffer(n)
    if not ver.GetFileVersionInfoW(str(path), 0, n, buf):
        return ""
    p, ln = ctypes.c_void_p(), wintypes.UINT(0)
    langs = []
    if ver.VerQueryValueW(buf, r"\VarFileInfo\Translation", ctypes.byref(p), ctypes.byref(ln)) and ln.value >= 4:
        arr = ctypes.cast(p, ctypes.POINTER(wintypes.WORD * (ln.value // 2))).contents
        langs = ["%04x%04x" % (arr[i], arr[i + 1]) for i in range(0, len(arr) - 1, 2)]
    for lc in langs + ["040904b0", "000004b0", "040904e4"]:
        if ver.VerQueryValueW(buf, r"\StringFileInfo\%s\%s" % (lc, key), ctypes.byref(p), ctypes.byref(ln)) \
                and ln.value:
            return ctypes.wstring_at(p, ln.value).rstrip("\0")
    return ""


def exe_product_version(path) -> str:
    return exe_version_string(path, "ProductVersion") + " | " + exe_version_string(path, "FileVersion")


# Inno keeps at most 50 characters of the ProductVersion string (FileVersion: 20), so an exe carries the first 16 hex
# digits of each id: ProductVersion = "<version> cat <16 hex of the catalog sha256> code <16 hex of the code fp>"
ID_LEN = 16


def exe_catalog_sha(path) -> str:
    """the catalog sha256 PREFIX (16 hex) compiled into an installer exe ('' when it carries none)"""
    m = re.search(r"\bcat ([0-9a-f]{%d})\b" % ID_LEN, exe_version_string(path, "ProductVersion"))
    return m.group(1) if m else ""


def exe_code_fp(path) -> str:
    """the installer code fingerprint PREFIX (16 hex, pipeline\\codefp.py) an exe was compiled from ('' = none)"""
    m = re.search(r"\bcode ([0-9a-f]{%d})\b" % ID_LEN, exe_version_string(path, "ProductVersion"))
    return m.group(1) if m else ""


def same_id(full: str, prefix: str) -> bool:
    """a full sha256 / fingerprint against the 16-hex prefix an exe carries"""
    return bool(full) and len(prefix or "") == ID_LEN and full.lower().startswith(prefix.lower())
