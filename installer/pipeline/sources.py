"""P5: the archive references (what the players' downloads contain): Clever 26.2 folder, McKenyu 1.4 RAR5 (unpacked
once into work\\refcache), DMN EXP37.1 zip, Nightreign Movement 0.2 zip and Seamless (mode V, tested 2.0.1 zip
pinned). Every file is hashed (sha256 + size); compose.py picks the members the catalog needs. Plus the
case-insensitive bracket tar --include globs."""
from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

from . import cfg
from .util import BuildError, files_under, hash_file, log, read_json, require, sha256_file, write_json

SAFE_NAME = re.compile(r"^[A-Za-z0-9_.\- ()]+$")


class Ref:
    def __init__(self, arch: dict):
        self.arch = arch
        self.id = arch["id"]
        r = arch["reference"]
        self.kind = r["kind"]
        self.path = Path(r["path"]) if r.get("path") else None
        self.files: list[dict] = []        # {tail, name, sha256, size}
        self.pin = None                    # (size, sha256) of the whole archive file
        self.tested = {}                   # mode V: tail -> sha256 of the tested version
        self.unpacked = None               # rar: the refcache folder it was unpacked into (member files live there)

    def member_path(self, tail: str) -> Path:
        """the local file holding a member (folder / unpacked rar references only)"""
        return (self.unpacked or self.path) / tail

    def by_sha(self) -> dict:
        out = {}
        for i, f in enumerate(self.files):
            out.setdefault(f["sha256"], []).append(i)
        return out

    def find_member(self, tail: str):
        t = tail.lower().replace("/", "\\")
        hits = [f for f in self.files if f["tail"].lower() == t or f["tail"].lower().endswith("\\" + t)]
        require(len(hits) == 1, "%s: member %s found %d times in the reference" % (self.id, tail, len(hits)))
        return hits[0]


def _zip_files(zp: Path) -> list[dict]:
    cache_p = cfg.WORK / "refzip_cache.json"
    cache = read_json(cache_p) if cache_p.exists() else {}
    key = sha256_file(zp)
    if key in cache:
        return cache[key]
    out = []
    with zipfile.ZipFile(zp) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            h = hashlib.sha256()
            n = 0
            with z.open(info) as f:
                for chunk in iter(lambda: f.read(8 << 20), b""):
                    h.update(chunk)
                    n += len(chunk)
            tail = info.filename.replace("/", "\\")
            out.append({"tail": tail, "name": tail.rsplit("\\", 1)[-1], "sha256": h.hexdigest(), "size": n})
    cache[key] = out
    write_json(cache_p, cache)
    return out


SEVENZIP = Path(r"C:\Program Files\7-Zip\7z.exe")
TAR = Path(r"C:\Windows\System32\tar.exe")


def unpack_rar(rp: Path) -> Path:
    """a .rar reference (McKenyu's 1.4 pack is RAR5), unpacked once into work\\refcache\\<sha256[0:16]> and reused
    while that folder's stamp names the same archive: Windows tar first (bsdtar 3.8.8 reads RAR5: measured), 7-Zip as
    the fallback. -> the folder."""
    sha = sha256_file(rp)
    out = cfg.WORK / "refcache" / sha[:16]
    stamp = out / "_REFCACHE.json"
    if stamp.exists():
        try:
            st = read_json(stamp)
        except (OSError, ValueError):
            st = {}
        if st.get("sha256") == sha and st.get("files", 0) > 0:
            return out
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    how = ""
    if TAR.exists():
        r = subprocess.run([str(TAR), "-x", "-f", str(rp)], cwd=str(out), capture_output=True, text=True,
                           errors="replace", timeout=3600)
        if r.returncode == 0:
            how = "tar"
        else:
            log("refcache: tar could not unpack %s (exit %d): %s" % (rp.name, r.returncode, r.stderr[-300:]))
    if not how and SEVENZIP.exists():
        shutil.rmtree(out)
        out.mkdir(parents=True)
        r = subprocess.run([str(SEVENZIP), "x", "-y", "-bd", "-o" + str(out), str(rp)], capture_output=True, text=True,
                           errors="replace", timeout=3600)
        require(r.returncode == 0, "7-Zip could not unpack %s: %s" % (rp, r.stdout[-500:] + r.stderr[-500:]))
        how = "7-Zip"
    require(how, "no tool could unpack the reference %s" % rp)
    n = sum(1 for x in out.rglob("*") if x.is_file())
    require(n > 0, "the reference %s unpacked to nothing" % rp)
    write_json(stamp, {"archive": str(rp), "sha256": sha, "files": n, "by": how})
    log("refcache: %s unpacked by %s into %s (%d files)" % (rp.name, how, out, n))
    return out


def _fill(ref: Ref, a: dict) -> None:
    """reads one reference (folder / zip / rar) into ref.files (+ the whole-archive pin), after its anchor sha256"""
    r = a["reference"]
    if r.get("expect_sha256"):
        require(ref.path.is_file() and sha256_file(ref.path) == r["expect_sha256"].lower(),
                "%s: reference %s is not the pinned file (sha256 %s)" % (a["id"], ref.path, r["expect_sha256"][:16]))
    if ref.kind == "folder":
        require(ref.path.is_dir(), "reference folder missing: %s" % ref.path)
        for rel in files_under(ref.path, skip_underscore=False):
            h = hash_file(ref.path / rel)
            ref.files.append({"tail": rel, "name": rel.rsplit("\\", 1)[-1], "sha256": h["sha256"], "size": h["size"]})
    elif ref.kind == "zip":
        require(ref.path.is_file(), "reference zip missing: %s" % ref.path)
        ref.files = _zip_files(ref.path)
    elif ref.kind == "rar":
        require(ref.path.is_file(), "reference archive missing: %s" % ref.path)
        folder = unpack_rar(ref.path)
        for rel in files_under(folder, skip_underscore=False):
            if rel == "_REFCACHE.json":
                continue
            h = hash_file(folder / rel)
            ref.files.append({"tail": rel, "name": rel.rsplit("\\", 1)[-1], "sha256": h["sha256"], "size": h["size"]})
        ref.unpacked = folder
    if ref.kind in ("zip", "rar") and r.get("pin_whole_archive"):
        h = hash_file(ref.path)
        ref.pin = (h["size"], h["sha256"])


def load_refs(src: dict) -> dict:
    refs = {}
    for a in src["archives"]:
        if not a.get("enabled", True):
            log("archive %s: disabled, skipped" % a["id"])
            continue
        ref = Ref(a)
        if ref.kind in ("folder", "zip", "rar"):
            _fill(ref, a)
        elif ref.kind == "built":
            pass                                # main_v65: filled by mainzip.py
        else:
            raise BuildError("archive %s: reference kind %s cannot be used while enabled" % (a["id"], ref.kind))
        if a["mode"] == "V" and ref.kind != "built":
            for m in a["members"]:
                f = ref.find_member(m)
                ref.tested[m] = f["sha256"]
        if ref.files:
            log("reference %s (%s): %d files, %.1f MB%s" % (a["id"], ref.kind, len(ref.files),
                                                          sum(f["size"] for f in ref.files) / 1048576,
                                                          ", whole-archive pin %d B %s" % (ref.pin[0], ref.pin[1][:12]) if ref.pin else ""))
        refs[a["id"]] = ref
    return refs


def bracket(name: str) -> str:
    require(SAFE_NAME.match(name), "member name with characters a tar glob cannot express safely: %r" % name)
    out = []
    for ch in name:
        if ch.isalpha():
            out.append("[%s%s]" % (ch.upper(), ch.lower()))
        else:
            out.append(ch)
    return "*" + "".join(out)


def globs_for(names) -> list[str]:
    """minimal set: one case-insensitive pattern per distinct (case-folded) member name"""
    seen = {}
    for n in names:
        seen.setdefault(n.lower(), n)
    return [bracket(seen[k]) for k in sorted(seen)]
