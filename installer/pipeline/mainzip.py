"""P7: the deterministic main zip (members sorted, fixed timestamp, DEFLATE for text, STORED for the rest, no extra
fields; a rebuild gives the same bytes) + the blob store (assets\\<sha256>) + the hosting trees
(dist\\<tag>\\github\\<tag>\\<asset>, release_staging\\<tag>\\<asset>)."""
from __future__ import annotations

import hashlib
import os
import zipfile
from pathlib import Path

from . import cfg, util
from .util import hash_file, log, read_json, require, write_json


def plan(rc, refs, src) -> list[tuple[str, Path]]:
    """[(zip member name, file)] = every MAIN path whose content is not in a required third-party archive
    (Clever / McKenyu: the player's own downloads) + CHANGELOG.txt"""
    r_arch = [a["id"] for a in src["archives"] if a.get("enabled", True) and a["id"] != "main_v65"
              and [c for c in src["components"] if c["id"] == a["component"]][0]["kind"] == "R"]
    third = set()
    for aid in r_arch:
        third |= set(refs[aid].by_sha())
    out = []
    for rel, f in rc.main.items():
        if hash_file(f)["sha256"] in third:
            continue
        out.append((rel.replace("\\", "/"), Path(f)))
    out.append(("CHANGELOG.txt", Path(src["release"]["changelog_source"])))
    out.sort(key=lambda x: x[0])
    return out


def _zinfo(name: str, size: int) -> zipfile.ZipInfo:
    zi = zipfile.ZipInfo(name, date_time=cfg.MAIN_ZIP_DATE)
    zi.create_system = 0
    zi.create_version = 20
    zi.extract_version = 20
    zi.external_attr = 0x20          # FILE_ATTRIBUTE_ARCHIVE, no unix mode
    zi.compress_type = zipfile.ZIP_DEFLATED if os.path.splitext(name)[1].lower() in cfg.TEXT_EXTS else zipfile.ZIP_STORED
    zi.file_size = size
    return zi


def build(members: list[tuple[str, Path]], out: Path) -> dict:
    out = util.guard_write(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(out.name + ".tmp")
    with zipfile.ZipFile(tmp, "w", allowZip64=True) as z:
        for name, f in members:
            size = f.stat().st_size
            zi = _zinfo(name, size)
            with open(f, "rb") as src, z.open(zi, "w", force_zip64=size >= 0x7FFFFFFF) as dst:
                for chunk in iter(lambda: src.read(8 << 20), b""):
                    dst.write(chunk)
            if zi.compress_type == zipfile.ZIP_DEFLATED:
                pass
    os.replace(tmp, out)
    return hash_file(out)


def ensure(members: list[tuple[str, Path]], out: Path, force=False) -> dict:
    """build the zip unless an identical-input build exists. -> {size, sha256, md5, members:[...]}"""
    fp = util.fingerprint([(n, hash_file(f)["sha256"]) for n, f in members] + [list(cfg.MAIN_ZIP_DATE), "v1"])
    stamp = out.with_name(out.name + ".stamp.json")
    if not force and out.exists() and stamp.exists():
        s = read_json(stamp)
        h = hash_file(out)
        if s.get("fingerprint") == fp and s.get("sha256") == h["sha256"]:
            log("main zip up to date: %s (%d B, sha256 %s)" % (out.name, h["size"], h["sha256"][:16]))
            return s
    log("building main zip %s (%d members)" % (out.name, len(members)))
    h = build(members, out)
    mem = []
    for n, f in members:
        fh = hash_file(f)
        mem.append({"tail": n.replace("/", "\\"), "name": n.rsplit("/", 1)[-1], "sha256": fh["sha256"], "size": fh["size"]})
    verify(out, mem)
    s = {"fingerprint": fp, "size": h["size"], "sha256": h["sha256"], "md5": h["md5"], "members": mem}
    write_json(stamp, s)
    log("main zip: %d B (%.1f MB), sha256 %s, %d members" % (h["size"], h["size"] / 1048576, h["sha256"], len(mem)))
    return s


def verify(zp: Path, mem: list[dict]) -> None:
    """CRC test + member list + sha256 of every member read back from the zip"""
    want = {m["tail"].replace("\\", "/"): m for m in mem}
    with zipfile.ZipFile(zp) as z:
        infos = [i for i in z.infolist()]
        require([i.filename for i in infos] == sorted(want), "main zip member list/order differs from the plan")
        for i in infos:
            require(i.extra == b"" and i.date_time == cfg.MAIN_ZIP_DATE, "main zip member %s: extra/date" % i.filename)
            h = hashlib.sha256()
            with z.open(i) as f:
                for chunk in iter(lambda: f.read(8 << 20), b""):
                    h.update(chunk)
            require(h.hexdigest() == want[i.filename]["sha256"], "main zip member %s: sha256 read back differs" % i.filename)


# ------------------------------------------------------------------ blob store + hosting trees
def stage_blobs(blobs: dict, assets: dict, tag: str) -> dict:
    """blobs {sha: {file, size}}, assets {sha: asset name}. Copies into assets\\<sha256> (verified), hard-links every
    blob (= a GitHub release asset) into dist\\<tag>\\github\\<tag>\\ and release_staging\\<tag>\\; removes stale
    files there. -> stats"""
    store = cfg.ASSETS
    gh = cfg.DIST / tag / "github" / tag
    rs = cfg.RELEASE_STAGING / tag
    n_copy = 0
    for sha, b in sorted(blobs.items()):
        dst = store / sha
        if not (dst.exists() and hash_file(dst)["sha256"] == sha):
            util.copy_file(b["file"], dst)
            require(hash_file(dst)["sha256"] == sha, "blob copy damaged: %s" % dst)
            n_copy += 1
    roots = {gh: {}, rs: {}}
    for sha, b in blobs.items():
        roots[gh][assets[sha]] = sha
        roots[rs][assets[sha]] = sha
    # dist\<tag>\sites\ held the staged files of the retired second download site (2026-10-03): the pipeline's own
    # staging copies (hard links of the blob store) go with the tree
    sites_dir = cfg.DIST / tag / "sites"
    if sites_dir.exists():
        n_old = 0
        for p in sorted(sites_dir.rglob("*"), key=lambda x: -len(x.parts)):
            if p.is_file():
                util.guard_write(p).unlink()
                n_old += 1
            elif p.is_dir():
                util.guard_write(p).rmdir()
        util.guard_write(sites_dir).rmdir()
        log("blob store: removed the retired dist\\%s\\sites tree (%d staged file(s))" % (tag, n_old))
    for root, want in roots.items():
        util.guard_write(root).mkdir(parents=True, exist_ok=True)
        for p in root.iterdir():
            if p.is_file() and p.name not in want:
                util.guard_write(p).unlink()
        for name, sha in want.items():
            util.link_or_copy(store / sha, root / name)
    # stale blobs in the store are kept (cheap; a later RC may point back at them) but listed
    stale = [p.name for p in store.iterdir() if p.is_file() and p.name not in blobs and len(p.name) == 64]
    log("blob store: %d blobs (%d copied now, %.1f MB); hosting trees %s and %s hold exactly the catalog's assets; "
        "%d older blob(s) kept in the store" % (len(blobs), n_copy, sum(b["size"] for b in blobs.values()) / 1048576,
                                             gh, rs, len(stale)))
    return {"blobs": len(blobs), "copied": n_copy, "github_root": str(gh.parent), "release_staging": str(rs.parent),
            "stale_in_store": len(stale)}
