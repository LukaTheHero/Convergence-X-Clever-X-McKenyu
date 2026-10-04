"""Shared helpers: logging, hashing (cached), guarded writes, subprocesses."""
from __future__ import annotations

import datetime as _dt
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

from . import cfg


class BuildError(RuntimeError):
    pass


def require(cond, msg: str) -> None:
    if not cond:
        raise BuildError(msg)


# ------------------------------------------------------------------ logging
_LOG_FILE = None
_T0 = time.time()
STEP_TIMES: dict[str, float] = {}


def open_log(name: str) -> Path:
    global _LOG_FILE
    cfg.LOGS.mkdir(parents=True, exist_ok=True)
    p = cfg.LOGS / name
    _LOG_FILE = open(p, "a", encoding="utf-8")
    return p


def log(msg: str) -> None:
    line = "[%s +%5.0fs] %s" % (_dt.datetime.now().strftime("%H:%M:%S"), time.time() - _T0, msg)
    print(line, flush=True)
    if _LOG_FILE:
        _LOG_FILE.write(line + "\n")
        _LOG_FILE.flush()


class step:
    """with step("name"): ... -> logs and records the runtime"""

    def __init__(self, name):
        self.name = name

    def __enter__(self):
        self.t = time.time()
        log("== %s" % self.name)
        return self

    def __exit__(self, et, ev, tb):
        dt = time.time() - self.t
        STEP_TIMES[self.name] = round(STEP_TIMES.get(self.name, 0) + dt, 1)
        log("== %s %s in %.1f s" % (self.name, "done" if et is None else "FAILED", dt))
        return False


def now_stamp() -> str:
    return _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


# ------------------------------------------------------------------ hashing (cached by path + size + mtime)
_HC: dict | None = None
_HC_DIRTY = 0


def _hc():
    global _HC
    if _HC is None:
        try:
            _HC = json.loads(cfg.HASHCACHE.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            _HC = {}
    return _HC


def save_hashcache():
    global _HC_DIRTY
    if _HC is not None and _HC_DIRTY:
        cfg.HASHCACHE.parent.mkdir(parents=True, exist_ok=True)
        tmp = cfg.HASHCACHE.with_suffix(".tmp")
        tmp.write_text(json.dumps(_HC, separators=(",", ":")), encoding="utf-8")
        os.replace(tmp, cfg.HASHCACHE)
        _HC_DIRTY = 0


def hash_file(p) -> dict:
    """-> {"sha256", "md5", "size"} (cached on (normcase path, size, mtime_ns))"""
    global _HC_DIRTY
    p = os.path.abspath(str(p))
    st = os.stat(p)
    key = os.path.normcase(p)
    hc = _hc()
    e = hc.get(key)
    if e and e[0] == st.st_size and e[1] == st.st_mtime_ns:
        return {"sha256": e[2], "md5": e[3], "size": st.st_size}
    hs, hm = hashlib.sha256(), hashlib.md5()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(8 << 20), b""):
            hs.update(chunk)
            hm.update(chunk)
    st2 = os.stat(p)
    require(st2.st_size == st.st_size and st2.st_mtime_ns == st.st_mtime_ns, "file changed while hashing: %s" % p)
    hc[key] = [st.st_size, st.st_mtime_ns, hs.hexdigest(), hm.hexdigest()]
    _HC_DIRTY += 1
    if _HC_DIRTY >= 200:
        save_hashcache()
    return {"sha256": hs.hexdigest(), "md5": hm.hexdigest(), "size": st.st_size}


def sha256_file(p) -> str:
    return hash_file(p)["sha256"]


def md5_file(p) -> str:
    return hash_file(p)["md5"]


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def md5_bytes(b: bytes) -> str:
    return hashlib.md5(b).hexdigest()


def sha256_text_lines(lines) -> str:
    return hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()


# ------------------------------------------------------------------ guarded writes
def _under(p: Path, root: Path) -> bool:
    a = os.path.normcase(os.path.abspath(str(p)))
    b = os.path.normcase(os.path.abspath(str(root)))
    return a == b or a.startswith(b.rstrip("\\/") + os.sep)


EXTRA_ALLOWED: list[Path] = []


def guard_write(p) -> Path:
    p = Path(os.path.abspath(str(p)))
    for bad in cfg.FORBIDDEN_WRITE_ROOTS:
        require(not _under(p, bad), "REFUSED: write below a forbidden folder %s: %s" % (bad, p))
    require(any(_under(p, ok) for ok in cfg.ALLOWED_WRITE_ROOTS + EXTRA_ALLOWED),
            "REFUSED: write outside the pipeline's folders: %s" % p)
    return p


def write_text(p, text: str, newline: str = "\n", bom: bool = False) -> Path:
    p = guard_write(p)
    p.parent.mkdir(parents=True, exist_ok=True)
    data = text.replace("\r\n", "\n")
    if newline != "\n":
        data = data.replace("\n", newline)
    raw = (b"\xef\xbb\xbf" if bom else b"") + data.encode("utf-8")
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_bytes(raw)
    os.replace(tmp, p)
    return p


def write_json(p, obj, sort_keys=False) -> Path:
    return write_text(p, json.dumps(obj, indent=1, sort_keys=sort_keys, ensure_ascii=False) + "\n")


def read_json(p):
    return json.loads(Path(p).read_text(encoding="utf-8-sig"))


def copy_file(src, dst) -> Path:
    dst = guard_write(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + ".tmp")
    shutil.copyfile(src, tmp)
    os.replace(tmp, dst)
    return dst


def link_or_copy(src, dst) -> str:
    """hard link dst -> src (same volume), else copy. Replaces dst. -> 'link' | 'copy' | 'same'"""
    dst = guard_write(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        try:
            if os.path.samefile(src, dst):
                return "same"
        except OSError:
            pass
        dst.unlink()
    try:
        os.link(src, dst)
        return "link"
    except OSError:
        shutil.copyfile(src, dst)
        return "copy"


def rmtree_guarded(p):
    p = guard_write(p)
    if p.exists():
        shutil.rmtree(p)


# ------------------------------------------------------------------ subprocesses
def run(cmd, cwd=None, timeout=None, log_to=None, env=None) -> subprocess.CompletedProcess:
    flags = getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0)
    if env is None:          # no __pycache__ written into read-only input folders by the Python helpers we start
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    t = time.time()
    r = subprocess.run([str(c) for c in cmd], cwd=str(cwd) if cwd else None, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout, creationflags=flags, env=env)
    if log_to:
        write_text(log_to, "$ %s\n(cwd %s, exit %d, %.1f s)\n--- stdout\n%s\n--- stderr\n%s\n" % (
            " ".join('"%s"' % c if " " in str(c) else str(c) for c in cmd), cwd, r.returncode, time.time() - t,
            r.stdout, r.stderr))
    return r


def pascal_str(s: str) -> str:
    require("\n" not in s and "\r" not in s, "newline in pascal string: %r" % s)
    return "'" + s.replace("'", "''") + "'"


def files_under(d, skip_underscore=True, skip_json=False) -> list[str]:
    """relative paths (backslashes) of every file below d; '_' top folders / files skipped (build-out convention)"""
    out = []
    d = str(d)
    for dp, _, fs in os.walk(d):
        for f in fs:
            rel = os.path.relpath(os.path.join(dp, f), d)
            if skip_underscore and (rel.split(os.sep)[0].startswith("_") or f.startswith("_")):
                continue
            if skip_json and f.endswith(".json"):
                continue
            out.append(rel)
    return sorted(out, key=str.lower)


def win(rel: str) -> str:
    return rel.replace("/", "\\")


def ncase(p) -> str:
    return os.path.normcase(os.path.abspath(str(p)))


def fingerprint(obj) -> str:
    return hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def py_info():
    return "%s %s" % (sys.executable, sys.version.split()[0])
