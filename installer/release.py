r"""v6.5 release pipeline: one command turns an RC into everything the Auto Installer v2 needs.

  cd C:\00000ConvergenceER\ClaudeWorkspace\clever_x_convergence_x_mckenyu\v65\installer
  py -3.11 -X utf8 release.py --rc rc7 --all              THE ONE COMMAND (final pass 2): build + test gate (only if
                                                           needed) + GitHub draft + --final gates +
                                                           publish check + release-kit drafts -> READY or NOT READY.
                                                           --cold re-does everything except the per-RC products
                                                           (reused while their inputs are unchanged).
                                                           pipeline\oneshot.py has the steps.
  py -3.11 -X utf8 release.py --rc rc2 --emit-only         products (cached) + compose + main zip (cached) + blobs +
                                                           generated\ + staging\meta + dist\<tag>\catalog.json; no ISCC
  py -3.11 -X utf8 release.py --rc rc2 --build codecheck    + ISCC /DCodeCheck  -> codecheck_output\
  py -3.11 -X utf8 release.py --rc rc2 --build test         + ISCC /DTestBuild  -> test_output\
  py -3.11 -X utf8 release.py --rc rc2 --build release      + ISCC release      -> output\ + dist\<tag>\ + v65\dist\
  py -3.11 -X utf8 release.py --rc rc2 --build all          codecheck + test + release
  py -3.11 -X utf8 release.py --rc rc2 --stage-github       private repo + DRAFT release + asset upload (never public)
  py -3.11 -X utf8 release.py --rc rc2 --build release --final   refuses TODO URLs, PLACEHOLDER changelog, missing tests
  --rc is REQUIRED (no default): rcN, or auto = the newest RC whose gates (incl. G-PACK) and NRM layer passed. A bare
  run never switches the installer to an RC nobody chose.

Contract: README_CONTRACT.md (CAT_FORMAT 1). Design: C:\$MD\EldenRing\merge\v65\INSTALLER_V65_DESIGN.md.
publish_github.py (only after Luka's OK) makes the repo public and publishes the draft release.
"""
from __future__ import annotations

import argparse
import sys
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from pipeline import cfg, util  # noqa: E402
from pipeline.util import BuildError, log, step  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rc", required=True, help="rcN (e.g. rc2), or auto = the newest RC whose gates passed; required")
    ap.add_argument("--emit-only", action="store_true", help="no ISCC")
    ap.add_argument("--build", choices=["none", "codecheck", "test", "release", "all"], default="none")
    ap.add_argument("--stage-github", action="store_true")
    ap.add_argument("--final", action="store_true")
    ap.add_argument("--force-products", action="store_true", help="rebuild Lucy and Infinite Durations")
    ap.add_argument("--force-infdur", action="store_true")
    ap.add_argument("--force-zip", action="store_true")
    ap.add_argument("--infdur-ack", default="", help="comma list of new finite SpEffect ids to accept")
    ap.add_argument("--skip-selftest-zip", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--allow-other-nrm-package", action="store_true",
                    help="TEST builds only: accept an RC whose NRM layer was built from another Nightreign Movement "
                         "package than the one the players download (the build is marked not releasable; --final, "
                         "--stage-github, --all and publish_github.py refuse it)")
    g = ap.add_argument_group("the one command (final pass part 2): release.py --rc <rc> --all [--cold]")
    g.add_argument("--all", action="store_true",
                   help="build (exes reused when their inputs are unchanged) + the test gate (only when no passing "
                        "results exist for this catalog + code) + GitHub draft + --final gates + "
                        "publish check + drafts; see pipeline\\oneshot.py")
    g.add_argument("--cold", action="store_true", help="--all re-doing everything: re-hash, rebuild the main zip, recompile the exes, re-test, re-scan the repo history, download back (per-RC products - Lucy, Infinite Durations, G-PACK - are reused while their inputs are unchanged)")
    g.add_argument("--retest", action="store_true", help="--all: run the test gate even when a passing one exists")
    g.add_argument("--verify-download", action="store_true", help="--all: download every draft asset back")
    g.add_argument("--no-upload", action="store_true", help="--all: check GitHub, upload nothing")
    args = ap.parse_args(argv)
    if args.emit_only and args.build != "none":
        ap.error("--emit-only and --build exclude each other")
    if args.all and (args.emit_only or args.build != "none" or args.stage_github or args.final):
        ap.error("--all does the build, the staging and the --final gates itself: give only --rc (+ --cold/--retest/...)")
    if (args.cold or args.retest or args.verify_download or args.no_upload) and not args.all:
        ap.error("--cold, --retest, --verify-download and --no-upload go with --all")
    if args.allow_other_nrm_package and (args.all or args.final or args.stage_github):
        ap.error("--allow-other-nrm-package makes a TEST build: it never goes with --all, --final or --stage-github")
    stamp = time.strftime("%Y%m%d_%H%M%S")
    logp = util.open_log(("all_%s.log" if args.all else "release_%s.log") % stamp)
    cmdline = "py -3.11 -X utf8 release.py " + " ".join(sys.argv[1:] if argv is None else argv)
    log("release.py start: %s (log %s, %s)" % (cmdline, logp, util.py_info()))
    t0 = time.time()
    if args.all:
        try:
            from pipeline import oneshot
            return oneshot.run(args, cmdline, stamp, acquire_lock, release_lock)
        except BuildError as e:
            log("FAILED: %s" % e)
            return 1
        except Exception:
            log("CRASHED:\n" + traceback.format_exc())
            return 2
        finally:
            util.save_hashcache()
    lock = acquire_lock()
    try:
        from pipeline import run_pipeline
        rep = run_pipeline.run(args, cmdline, stamp)
        rep["total_secs"] = round(time.time() - t0, 1)
        log("RELEASE PIPELINE OK in %.0f s (RC %s, catalog sha256 %s)" % (rep["total_secs"], rep["rc"], rep["catalog_sha256"]))
        return 0
    except BuildError as e:
        log("FAILED: %s" % e)
        return 1
    except Exception:
        log("CRASHED:\n" + traceback.format_exc())
        return 2
    finally:
        util.save_hashcache()
        release_lock(lock)


def _pid_alive(pid: int) -> bool:
    import ctypes
    h = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)      # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return False
    code = ctypes.c_ulong()
    ctypes.windll.kernel32.GetExitCodeProcess(h, ctypes.byref(code))
    ctypes.windll.kernel32.CloseHandle(h)
    return code.value == 259                                          # STILL_ACTIVE


def acquire_lock(wait_secs: int = 1800) -> Path:
    """one release.py at a time (both builder lanes may run it): work\\release.lock = pid + time; a lock whose process
    is gone (or older than 3 h) is taken over. Waits up to 30 minutes."""
    import json
    import os
    p = cfg.WORK / "release.lock"
    p.parent.mkdir(parents=True, exist_ok=True)
    t_end = time.time() + wait_secs
    said = False
    while True:
        try:
            fd = os.open(str(p), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, json.dumps({"pid": os.getpid(), "at": time.time(), "cmd": sys.argv[1:]}).encode())
            os.close(fd)
            return p
        except FileExistsError:
            try:
                info = json.loads(p.read_text(encoding="utf-8") or "{}")
            except (OSError, ValueError):
                info = {}
            stale = not info or not _pid_alive(int(info.get("pid", 0))) or time.time() - float(info.get("at", 0)) > 3 * 3600
            if stale:
                try:
                    p.unlink()
                except OSError:
                    pass
                continue
            if time.time() > t_end:
                raise SystemExit("another release.py (pid %s, %s) holds %s for too long" % (info.get("pid"), info.get("cmd"), p))
            if not said:
                log("waiting for another release.py (pid %s: %s) to finish" % (info.get("pid"), info.get("cmd")))
                said = True
            time.sleep(5)


def release_lock(p: Path) -> None:
    try:
        p.unlink()
    except OSError:
        pass


if __name__ == "__main__":
    sys.exit(main())
