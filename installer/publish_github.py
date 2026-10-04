r"""Publishing the installer's GitHub repo + release. --publish runs ONLY after Luka's explicit OK (decision T7,
2026-10-02: Claude runs it once Luka has looked at the release candidate; never on its own, never from a script).

  cd C:\00000ConvergenceER\ClaudeWorkspace\clever_x_convergence_x_mckenyu\v65\installer
  py -3.11 -X utf8 publish_github.py --tag v6.5.0 --check
        read-only: every check below, then the list of what --publish would change. Exit 0 = READY, 1 = NOT READY.
        (--check-only is the same.)
  py -3.11 -X utf8 publish_github.py --tag v6.5.0 --publish --confirm "PUBLISH v6.5.0"
        Only after Luka's OK. Refuses (nothing changed) unless every check passes. Then, in this order:
          1. commits the repo's files for this release (README, CREDITS, licence notes, releases/<tag>/catalog.json,
             the installer source) - pipeline\ghstage.py, the same content scan as --stage-github;
          2. repo -> PUBLIC (skipped when it already is);
          3. release <tag> -> published (GitHub creates the tag on the default branch);
          4. anonymous HEAD of every asset URL the release exe will request (no login; follows GitHub's redirect;
             size checked), retried for up to ~3 minutes while GitHub settles.
        Exit 0 = published and every asset reachable; 3 = published but some URL failed the anonymous check (run
        --verify-public again after a few minutes; the report names the URLs).
  py -3.11 -X utf8 publish_github.py --tag v6.5.0 --verify-public
        read-only: step 4 alone. Before publishing every GitHub asset URL answers 404.
  py -3.11 -X utf8 publish_github.py --tag v6.5.0 --verify-download
        read-only: downloads every asset WITH gh's login (works on a draft) into a temp folder and checks each file's
        size and sha256 against the catalog; the temp folder is deleted afterwards.

The checks (all read the real files; nothing is taken from generated\):
  - the release exe in dist\<tag>\ (named by the catalog) exists, its sha256 equals its sidecar RELEASE_EXE.json, the
    catalog id compiled INTO the exe (its version resource) is dist\<tag>\catalog.json's, and so is its code
    fingerprint;
  - BASEURL: the catalog's first mirror is exactly https://github.com/<owner>/<repo>/releases/download/ of the repo
    being published, the catalog's tag and every hosted file's tag are <tag>, and the release's tag is <tag> - so the
    URLs the exe downloads from (mirror + tag + "/" + asset, code\fetch.iss) are the URLs this release will have;
  - the repo exists (PRIVATE, or already PUBLIC), the release <tag> exists and is a DRAFT, and its assets (names,
    sizes, GitHub's sha256 digests) equal the catalog exactly;
  - the installer source in installer\ is the code the release exe was compiled from (the source that would be
    committed in step 1), and the repo files pass the content scan (text only, no machine details);
  - the --final gates (pipeline\checks.final_gates): every download has a page URL that is neither empty, TODO nor
    INFERRED, no PLACEHOLDER changelog, the RC's NRM layer is built from the package the players download, and a
    complete passing tests\results\<tag>_<rc>_*.json exists for this catalog AND for the installer code the exe was
    compiled from.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from pipeline import catalog_src, cfg, checks  # noqa: E402
from pipeline import ghstage  # noqa: E402
from pipeline.codefp import code_fingerprint  # noqa: E402
from pipeline.ghstage import Repo, gh  # noqa: E402
from pipeline.iscc import SIDECAR, exe_catalog_sha, exe_code_fp, same_id  # noqa: E402
from pipeline.util import BuildError, hash_file  # noqa: E402

EXIT_OK, EXIT_NOT_READY, EXIT_PUBLISHED_UNREACHABLE = 0, 1, 3


def release_exe_problems(tag: str, m: dict, cat_sha: str) -> tuple[list, dict]:
    problems = []
    exe = cfg.DIST / tag / (m.get("installer_base_name", "") + ".exe")
    side_p = cfg.DIST / tag / SIDECAR
    side = {}
    if not exe.is_file():
        problems.append("the release exe %s is missing (release.py --rc %s --build release)" % (exe, m.get("rc")))
        return problems, side
    if not side_p.is_file():
        problems.append("%s is missing: the exe was not built by this pipeline version (rebuild with --build release)"
                        % side_p.name)
    else:
        side = json.loads(side_p.read_text(encoding="utf-8"))
        if side.get("sha256") != hash_file(exe)["sha256"]:
            problems.append("%s is not the exe %s describes (sha256 differs): rebuild with --build release" % (
                exe.name, side_p.name))
    inside = exe_catalog_sha(exe)
    if not same_id(cat_sha, inside):
        problems.append("the exe was compiled with catalog %s, but dist\\%s\\catalog.json is %s (%s): build the release "
                        "exe again, or stage the RC the exe was built from" % (
                            inside[:16] or "(none)", tag, cat_sha[:16], m.get("rc")))
    code_in_exe = exe_code_fp(exe)
    if not code_in_exe:
        problems.append("the exe carries no code fingerprint (built before repair 1): rebuild with --build release")
    elif not same_id(side.get("code_fingerprint", ""), code_in_exe):
        problems.append("the sidecar's code fingerprint differs from the exe's own (%s)" % code_in_exe[:16])
    else:
        side["exe_code_fingerprint"] = side["code_fingerprint"]
    return problems, side


def expected_base_url(owner: str, repo: str) -> str:
    return "https://github.com/%s/%s/releases/download/" % (owner, repo)


def baseurl_problems(m: dict, owner: str, repo: str, tag: str, rel: dict | None) -> list[str]:
    """the URLs the exe downloads from (BaseUrls[0] + BlobTag + '/' + BlobAsset) must be this release's URLs"""
    problems = []
    want = expected_base_url(owner, repo)
    bases = m.get("base_urls") or []
    if not bases:
        problems.append("BASEURL: the catalog has no base URL")
    elif bases[0] != want:
        problems.append("BASEURL: the catalog's first mirror is %s, but this release's downloads live under %s - the exe "
                        "would download from somewhere else (rebuild with the right release.github block)" % (bases[0], want))
    if m.get("tag") != tag:
        problems.append("BASEURL: the catalog is for tag %s, not %s" % (m.get("tag"), tag))
    other = sorted({b["tag"] for b in m.get("blobs", []) if b.get("tag") != tag and not b.get("site")})
    if other:
        problems.append("BASEURL: hosted files point at other release tags %s (they would not be in release %s)" % (other, tag))
    if rel is not None and rel.get("tagName") != tag:
        problems.append("BASEURL: the GitHub release's tag is %s, not %s" % (rel.get("tagName"), tag))
    return problems


def asset_urls(m: dict) -> list[tuple[str, dict]]:
    """the first mirror's URL of every hosted file - what the release exe requests (code\\fetch.iss)"""
    return [(m["base_urls"][0] + b["tag"] + "/" + b["asset"], b) for b in m["blobs"] if not b.get("site")]


def gh_view(m: dict) -> dict:
    """the catalog with only the GitHub release's blobs (CAT_FORMAT 2: a blob with a "site" would be downloaded from
    that site and is never a release asset; the pipeline makes none since 2026-10-03)"""
    return dict(m, blobs=[b for b in m.get("blobs", []) if not b.get("site")])


# ------------------------------------------------------------------ anonymous reachability
class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def _request(url: str, method: str, extra: dict | None = None, timeout: float = 30):
    hdr = {"User-Agent": "CXCXM-publish-check/1"}
    hdr.update(extra or {})
    req = urllib.request.Request(url, method=method, headers=hdr)       # no Authorization header: anonymous
    try:
        r = _OPENER.open(req, timeout=timeout)
        try:
            return r.status, r.headers
        finally:
            r.close()
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.headers
        finally:
            e.close()


def anon_head(url: str, size: int | None = None, timeout: float = 30, max_hops: int = 6) -> dict:
    """anonymous HEAD, following redirects by hand (GitHub answers 302 to its asset host). When the last hop refuses
    HEAD (403/405), a 1-byte ranged GET reads the total size instead. -> {ok, status, length, hops, why}"""
    hops, cur, code, hdrs = [], url, 0, None
    try:
        for _ in range(max_hops):
            code, hdrs = _request(cur, "HEAD", timeout=timeout)
            hops.append("%d %s" % (code, urllib.parse.urlsplit(cur).netloc))
            loc = hdrs.get("Location") if hdrs else None
            if code in (301, 302, 303, 307, 308) and loc:
                cur = urllib.parse.urljoin(cur, loc)
                continue
            break
        length = int(hdrs.get("Content-Length") or -1) if hdrs else -1
        if code in (403, 405) and len(hops) > 1:
            code2, h2 = _request(cur, "GET", {"Range": "bytes=0-0"}, timeout=timeout)
            hops.append("%d %s (ranged GET)" % (code2, urllib.parse.urlsplit(cur).netloc))
            cr = (h2.get("Content-Range") or "") if h2 else ""
            if code2 in (200, 206):
                code = 200
                length = int(cr.rsplit("/", 1)[1]) if "/" in cr and cr.rsplit("/", 1)[1].isdigit() else int(
                    h2.get("Content-Length") or -1)
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"url": url, "ok": False, "status": None, "length": None, "hops": hops, "why": repr(e)[:200]}
    ok = code == 200 and (size is None or length == size)
    why = "" if ok else ("HTTP %s" % code if code != 200 else "size %d != catalog %d" % (length, size))
    return {"url": url, "ok": ok, "status": code, "length": length, "hops": hops, "why": why}


def verify_public(m: dict, retry_secs: float = 0, workers: int = 8) -> dict:
    """anonymous HEAD of every asset URL; failed ones are retried until retry_secs have passed"""
    from concurrent.futures import ThreadPoolExecutor
    urls = asset_urls(m)
    t_end = time.time() + retry_secs
    results: dict[str, dict] = {}
    todo = urls
    rounds = 0
    while True:
        rounds += 1
        with ThreadPoolExecutor(max_workers=workers) as ex:
            for r in ex.map(lambda ub: anon_head(ub[0], ub[1]["size"]), todo):
                results[r["url"]] = r
        todo = [(u, b) for u, b in urls if not results[u]["ok"]]
        if not todo or time.time() >= t_end:
            break
        time.sleep(15)
    bad = [results[u] for u, _ in urls if not results[u]["ok"]]
    return {"checked": len(urls), "ok": len(urls) - len(bad), "bad": bad, "rounds": rounds,
            "sample": results[urls[0][0]] if urls else None}


# ------------------------------------------------------------------ the checks + the plan
def gather(tag: str) -> dict:
    src = catalog_src.load()
    g = src["release"]["github"]
    cat_p = cfg.DIST / tag / "catalog.json"
    if not cat_p.is_file():
        raise BuildError("%s is missing (release.py --rc <rc> --build release for this tag first)" % cat_p)
    m = json.loads(cat_p.read_text(encoding="utf-8"))
    cat_sha = hash_file(cat_p)["sha256"]
    problems, side = release_exe_problems(tag, m, cat_sha)
    # test results must be for the code the EXE was compiled from (its own version resource says which)
    # the release itself is read below (a non-draft is refused there): the gates skip their own GitHub call
    fg = checks.final_gates(m, src, cat_sha, tag, side.get("exe_code_fingerprint") or "no-exe-code-fingerprint",
                            check_published=False)
    problems += ["--final gate: " + p for p in fg["problems"]]
    repo = Repo(g["owner"], g["repo"], tag)
    v = repo.view()
    rel = repo.release()
    problems += baseurl_problems(m, g["owner"], g["repo"], tag, rel)
    if v is None or rel is None:
        problems.append("repo or release missing (run release.py --rc %s --stage-github first)" % m.get("rc"))
    else:
        if v.get("visibility") not in ("PRIVATE", "PUBLIC"):
            problems.append("repo %s visibility is %s" % (repo.full, v.get("visibility")))
        if not rel.get("isDraft"):
            problems.append("release %s is not a draft any more (already published?)" % tag)
        have = {x["name"]: x for x in rel.get("assets", [])}
        want = {b["asset"]: b for b in m["blobs"] if not b.get("site")}
        if set(have) != set(want):
            problems.append("assets differ: missing %s extra %s" % (sorted(set(want) - set(have))[:5],
                                                                    sorted(set(have) - set(want))[:5]))
        bad = [n for n in want if n in have and (have[n].get("size") != want[n]["size"] or
                                                (have[n].get("digest", "").startswith("sha256:") and
                                                 have[n]["digest"][7:] != want[n]["sha256"]))]
        if bad:
            problems.append("assets with wrong size/sha256: %s" % bad[:5])
    # every hosted file is a GitHub release asset (the second download site was retired on 2026-10-03)
    if any(b.get("site") for b in m.get("blobs", [])):
        problems.append("the catalog has blobs on another download site (retired on 2026-10-03): rebuild")
    # the source that step 1 commits must be the code the release exe was compiled from
    fp_now = code_fingerprint()
    if side.get("code_fingerprint") and fp_now != side["code_fingerprint"]:
        problems.append("the installer source changed since the release exe was built (code %s now, exe %s): rebuild "
                        "(release.py --build release), re-test, or restore the source" % (fp_now[:16],
                                                                                          side["code_fingerprint"][:16]))
    plan, files = None, None
    if v is not None and cat_p.is_file():
        try:
            files = ghstage.repo_tree(m, src, tag)
            scan = ghstage.scan_repo_files(files)
            problems += ["repo file scan: " + s for s in scan[:20]]
            plan = repo.plan_tree(files, ghstage.default_branch(v))
            # publishing makes the whole history public: every older file version must pass the same scan
            hist, hcount = ghstage.history_problems(repo.full)
            problems += ["repo " + h for h in hist[:20]]
        except BuildError as e:
            problems.append("repo files: %s" % e)
            hcount = {}
    else:
        hcount = {}
    return {"src": src, "m": m, "cat_sha": cat_sha, "side": side, "repo": repo, "view": v, "rel": rel,
            "problems": problems, "plan": plan, "files": files, "final": fg, "history": hcount}


def print_state(s: dict, tag: str) -> None:
    m, v, rel, side = s["m"], s["view"] or {}, s["rel"] or {}, s["side"]
    exe = cfg.DIST / tag / (m.get("installer_base_name", "") + ".exe")
    print("repo %s: %s | release %s: draft=%s | catalog %s (RC %s, %d assets) | exe %s (catalog inside %s)" % (
        s["repo"].full, v.get("visibility"), tag, rel.get("isDraft"), s["cat_sha"][:16], m.get("rc"), len(gh_view(m)["blobs"]),
        (side.get("sha256") or "?")[:16], exe_catalog_sha(exe)[:16] if exe.is_file() else "-"))


def print_plan(s: dict, tag: str) -> None:
    m, v, rel, plan = s["m"], s["view"] or {}, s["rel"] or {}, s["plan"]
    urls = asset_urls(m) if m.get("base_urls") else []
    print("WHAT --publish WOULD CHANGE (nothing has changed):")
    if plan is None:
        print("  1. repo files: (cannot plan: repo missing)")
    elif plan["create"] or plan["update"] or plan["delete"]:
        print("  1. repo files: ONE commit on %s: %d new, %d changed, %d deleted, %d unchanged" % (
            plan["branch"], len(plan["create"]), len(plan["update"]), len(plan["delete"]), plan["unchanged"]))
        for k in ("create", "update", "delete"):
            if plan[k]:
                print("       %s: %s%s" % (k, ", ".join(plan[k][:8]), " (+%d more)" % (len(plan[k]) - 8)
                                          if len(plan[k]) > 8 else ""))
    else:
        print("  1. repo files: already current (%d files) - no commit" % plan["unchanged"])
    if v.get("visibility") == "PUBLIC":
        print("  2. repo %s: already PUBLIC - unchanged" % s["repo"].full)
    else:
        print("  2. repo %s: %s -> PUBLIC (the repo, its history and the installer source become public)" % (
            s["repo"].full, v.get("visibility")))
    head = (plan or {}).get("head") or "?"
    print("  3. release %s: %s -> PUBLISHED; GitHub creates tag %s on %s (head %s, plus the step-1 commit if any)" % (
        tag, "DRAFT" if rel.get("isDraft") else "not a draft", tag, plan["branch"] if plan else "?", head[:12]))
    print("  4. %d asset URLs go live = the URLs the release exe requests, e.g.\n       %s" % (
        len(urls), "\n       ".join(u for u, _ in urls[:3])))
    ups = sorted({b["upstream"] for b in m["blobs"] if b.get("upstream")})
    if ups:
        print("     (the exe tries these authors' own URLs first, then the URL above: %s)" % ", ".join(ups))
    print("  5. then an anonymous HEAD of all %d URLs (size checked)" % len(urls))
    h = s.get("history") or {}
    if h:
        print("  (history scanned: %d commit(s), %d file version(s) - all of it becomes public in step 2)" % (
            h.get("commits", 0), h.get("blobs", 0)))


def write_report(name: str, obj: dict) -> Path:
    p = cfg.LOGS / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(obj, indent=1, default=str) + "\n", encoding="utf-8")
    return p


def do_publish(s: dict, tag: str) -> int:
    repo, m = s["repo"], s["m"]
    stamp = time.strftime("%Y%m%d_%H%M%S")
    rep = {"tag": tag, "repo": repo.full, "catalog_sha256": s["cat_sha"], "started": stamp, "steps": {}}
    v = s["view"]
    branch = ghstage.default_branch(v)
    # 1. repo files (the same content scan as --stage-github; refuses before writing)
    r1 = repo.push_tree(s["files"], ghstage.commit_message(m, tag) + " (publish)", branch, allow_public=True)
    rep["steps"]["files"] = r1
    print("1. repo files: %d new, %d changed, %d deleted -> %s" % (len(r1["created"]), len(r1["updated"]),
                                                                  len(r1["deleted"]), r1["commit"] or "no commit"))
    # 2. repo -> public
    if (repo.view() or {}).get("visibility") != "PUBLIC":
        gh(["repo", "edit", repo.full, "--visibility", "public", "--accept-visibility-change-consequences"])
    v2 = repo.view() or {}
    rep["steps"]["visibility"] = v2.get("visibility")
    print("2. repo %s is %s" % (repo.full, v2.get("visibility")))
    # 3. release -> published
    rel = repo.release() or {}
    if rel.get("isDraft"):
        gh(["release", "edit", tag, "--repo", repo.full, "--draft=false"])
    rel = repo.release() or {}
    rep["steps"]["release"] = {"isDraft": rel.get("isDraft"), "tagName": rel.get("tagName"), "url": rel.get("url")}
    print("3. release %s draft=%s tag=%s %s" % (tag, rel.get("isDraft"), rel.get("tagName"), rel.get("url")))
    if v2.get("visibility") != "PUBLIC" or rel.get("isDraft") is not False or rel.get("tagName") != tag:
        p = write_report("publish_%s_%s.json" % (tag, stamp), rep)
        print("FAILED: the repo/release did not reach PUBLIC + published (report %s)" % p)
        return EXIT_PUBLISHED_UNREACHABLE
    # 4. anonymous HEAD of every asset URL
    vp = verify_public(m, retry_secs=180)
    rep["steps"]["anonymous_head"] = vp
    print("4. anonymous HEAD: %d/%d asset URLs reachable with the catalog's size (%d round(s)); e.g. %s -> %s" % (
        vp["ok"], vp["checked"], vp["rounds"], (vp["sample"] or {}).get("url"), (vp["sample"] or {}).get("hops")))
    p = write_report("publish_%s_%s.json" % (tag, stamp), rep)
    if vp["bad"]:
        print("NOT REACHABLE (run --verify-public again in a few minutes):\n  " + "\n  ".join(
            "%s: %s %s" % (b["url"], b["why"], b["hops"]) for b in vp["bad"][:20]))
        print("report: %s" % p)
        return EXIT_PUBLISHED_UNREACHABLE
    print("PUBLISHED: %s is PUBLIC, release %s is live, all %d asset URLs answer anonymously. Report: %s" % (
        repo.full, tag, vp["checked"], p))
    return EXIT_OK


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tag", required=True)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="read-only: checks + what --publish would change")
    mode.add_argument("--check-only", action="store_true", help="same as --check")
    mode.add_argument("--publish", action="store_true", help="only after Luka's OK, with --confirm \"PUBLISH <tag>\"")
    mode.add_argument("--verify-public", action="store_true", help="read-only: anonymous HEAD of every asset URL")
    mode.add_argument("--verify-download", action="store_true",
                      help="read-only: download every asset with gh's login, check size + sha256")
    ap.add_argument("--confirm", default="")
    a = ap.parse_args()
    if a.confirm and not (a.check or a.check_only or a.verify_public or a.verify_download):
        a.publish = True                       # the older form: --confirm "PUBLISH <tag>" alone
    if not (a.check or a.check_only or a.publish or a.verify_public or a.verify_download):
        print('nothing to do: pass --check, --verify-public, --verify-download, or (after Luka\'s OK) --publish '
              '--confirm "PUBLISH %s"' % a.tag)
        return EXIT_NOT_READY
    if a.publish and a.confirm != "PUBLISH %s" % a.tag:
        print('refused: --publish needs --confirm "PUBLISH %s" (exactly); nothing changed' % a.tag)
        return EXIT_NOT_READY
    if a.verify_public or a.verify_download:
        src = catalog_src.load()
        m = gh_view(json.loads((cfg.DIST / a.tag / "catalog.json").read_text(encoding="utf-8")))
        if a.verify_download:
            r = ghstage.verify_by_download(m, src, a.tag)
            p = write_report("verify_download_%s_%s.json" % (a.tag, time.strftime("%Y%m%d_%H%M%S")), r)
            print("verify-download %s (draft=%s): %d/%d assets downloaded with gh's login match the catalog's size + "
                  "sha256 (%.1f MB, %.0f s); missing %s, extra %s, bad %s. Report %s" % (
                      r["tag"], r["is_draft"], r["ok"], len(m["blobs"]), r["bytes"] / 1048576, r["secs"],
                      r["missing"] or "none", r["extra"] or "none", r["bad"] or "none", p))
            return EXIT_OK if r["ok"] == len(m["blobs"]) and not (r["bad"] or r["missing"] or r["extra"]) else \
                EXIT_NOT_READY
        vp = verify_public(m)
        p = write_report("verify_public_%s_%s.json" % (a.tag, time.strftime("%Y%m%d_%H%M%S")), vp)
        print("verify-public: %d/%d asset URLs answer an anonymous HEAD with the catalog's size; e.g. %s -> %s. Report %s"
              % (vp["ok"], vp["checked"], (vp["sample"] or {}).get("url"), (vp["sample"] or {}).get("hops"), p))
        for b in vp["bad"][:10]:
            print("  NOT REACHABLE %s: %s %s" % (b["url"], b["why"], b["hops"]))
        return EXIT_OK if not vp["bad"] else EXIT_PUBLISHED_UNREACHABLE
    s = gather(a.tag)
    print_state(s, a.tag)
    if s["problems"]:
        print("NOT READY:\n  " + "\n  ".join(s["problems"]))
        if not a.publish:
            print_plan(s, a.tag)
        else:
            print("refused: nothing changed")
        return EXIT_NOT_READY
    if not a.publish:
        print_plan(s, a.tag)
        print("READY to publish (nothing changed)")
        return EXIT_OK
    return do_publish(s, a.tag)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BuildError as e:
        print("FAILED: %s" % e)
        sys.exit(1)
