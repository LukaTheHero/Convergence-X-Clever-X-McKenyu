r"""Local stand-in for the GitHub release downloads (127.0.0.1 only).

  py -3.11 -X utf8 pipeline\serve_local.py [--root DIR] [--port 8765]
  default root = installer\release_staging (layout <tag>\<asset>, the same as dist\<tag>\github), so the installer runs with
  /BASEURL=http://127.0.0.1:8765/ /UPSTREAM=0
The INNO lane's tests\httpserve.py (fault switches --missing/--corrupt/--slow) serves dist\<tag>\github the same way.
"""
import argparse
import functools
import http.server
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.join(os.path.dirname(HERE), "release_staging")


class Handler(http.server.SimpleHTTPRequestHandler):
    def list_directory(self, path):          # no directory listings
        self.send_error(404, "not found")
        return None

    def log_message(self, fmt, *args):
        sys.stdout.write("%s - %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=DEFAULT_ROOT)
    ap.add_argument("--port", type=int, default=8765)
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    if not os.path.isdir(root):
        raise SystemExit("root folder missing: %s (run release.py first)" % root)
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", a.port), functools.partial(Handler, directory=root))
    print("serving %s on http://127.0.0.1:%d/  (installer: /BASEURL=http://127.0.0.1:%d/ /UPSTREAM=0); Ctrl+C stops" % (
        root, a.port, a.port), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
