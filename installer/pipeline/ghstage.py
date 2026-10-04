"""P10: GitHub staging - the repo's files + a DRAFT release. Never changes visibility, never publishes a release
(publish_github.py does that, only after Luka's OK).

What release.py --stage-github writes:
  1. The repo's text files, as ONE commit made through the Git data API (no local checkout, no credentials beyond gh):
       README.md, CREDITS.md, LICENSE-NOTES.md, LICENSES/..., .gitignore, releases/<tag>/ASSETS.md
                                         (made by pipeline\\emit_json.py into dist\\<tag>\\repo\\)
       releases/<tag>/catalog.json       (dist\\<tag>\\catalog.json, byte for byte)
       releases/<tag>/SOURCE.json        (which installer code + catalog + release exe the source snapshot belongs to)
       installer/...                     the installer source (source_files(): .iss, code\\*.iss, release.py,
                                         publish_github.py, pipeline\\, the catalog source + changelog)
     scan_repo_files() refuses the whole commit when any file is not text with an allowed extension, is over 4 MB, or
     holds a local user path, the Windows user name, a token, a private key or a private LAN address: no game file and
     no machine detail can land in git. Files under installer/ that are no longer part of the source are deleted in
     the same commit; nothing else is ever deleted. A restage with nothing changed makes no commit.
  2. The DRAFT release <tag> and its assets (resumable: only missing or wrong-size assets are uploaded; assets the
     catalog no longer lists are removed from the draft).

Guards (checked again right before every write):
  - repo files are written only while the repo is PRIVATE (publish_github.py --publish passes allow_public=True after
    Luka's confirmation; once the repo is public, --stage-github skips the repo files and says so);
  - release writes only ever touch a DRAFT release (a draft is never visible to the public, also in a public repo, so
    v6.6 can be staged as a draft next to the published v6.5.0).
"""
from __future__ import annotations

import ast
import base64
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time
import unicodedata
from pathlib import Path

from . import cfg
from .util import BuildError, log, require

GH = "gh"
UPLOAD_WORKERS = 3              # gh release upload processes at once (final pass 2: different assets of one draft)
MAX_REPO_FILE = 4 * 1024 * 1024
TEXT_EXTS = {".md", ".txt", ".py", ".iss", ".json"}
TEXT_NAMES = {".gitignore"}
DELETE_STALE_PREFIXES = ("installer/",)


def gh(args, check=True, input_text=None, timeout=1800) -> subprocess.CompletedProcess:
    r = subprocess.run([GH] + [str(a) for a in args], capture_output=True, text=True, encoding="utf-8", errors="replace",
                       input=input_text, timeout=timeout)
    if check and r.returncode != 0:
        raise BuildError("gh %s failed (exit %d): %s" % (" ".join(str(a) for a in args[:4]), r.returncode,
                                                          (r.stderr or r.stdout)[-800:]))
    return r


def gh_json(args, body: dict | None = None, check=True):
    """gh api ... -> parsed JSON; body is sent as the request's JSON (through a temp file, so size is no problem)"""
    tmp = None
    try:
        if body is not None:
            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
                json.dump(body, f)
                tmp = f.name
            args = list(args) + ["--input", tmp]
        r = gh(args, check=check)
        if r.returncode != 0:
            return None
        return json.loads(r.stdout) if r.stdout.strip() else {}
    finally:
        if tmp:
            os.unlink(tmp)


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


# ------------------------------------------------------------------ what goes into git
def source_files(src: dict) -> dict[str, Path]:
    """repo path -> local file: the installer source as it is now (the code the release exe is compiled from, the
    pipeline that builds it, the catalog source). Tests, logs, sandboxes, builds and game files are never included."""
    inst = cfg.INST
    picks = [cfg.ISS, inst / "release.py", inst / "publish_github.py", inst / "README_CONTRACT.md", cfg.CATALOG_SRC]
    cl = Path(cfg.expand(src["release"]["changelog_source"]))
    if cl.is_file() and cl.parent == cfg.CATALOG_DIR:
        picks.append(cl)
    picks += sorted(cfg.CODE_DIR.glob("*.iss"))
    picks += sorted(p for p in cfg.PIPE.rglob("*") if p.is_file() and "__pycache__" not in p.parts
                    and p.suffix.lower() in (".py", ".json", ".txt"))
    out = {}
    for p in picks:
        if p.is_file():
            out["installer/" + p.relative_to(inst).as_posix()] = p
    return out


def _shift(s: str, k: int) -> str:
    """Caesar shift of the ASCII letters by k (k = 13: rot13)"""
    lo, up = "abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    return s.translate(str.maketrans(lo + up, lo[k:] + lo[:k] + up[k:] + up[:k]))


def _rot13(s: str) -> str:
    return _shift(s, 13)


def _b64_cores(b: bytes) -> set[str]:
    """the base64 characters that only these bytes decide, at each of the three alignments (+ the URL-safe alphabet)"""
    out = set()
    for k in range(3):
        enc = base64.b64encode(b"\0" * k + b).decode("ascii")
        core = enc[-(-8 * k // 6):(8 * (k + len(b))) // 6]
        if len(core) >= 6:
            out |= {core, core.replace("+", "-").replace("/", "_")}
    return out


def _b32_cores(b: bytes) -> set[str]:
    """the base32 characters that only these bytes decide, at each of the five alignments (upper and lower case)"""
    out = set()
    for k in range(5):
        enc = base64.b32encode(b"\0" * k + b).decode("ascii").rstrip("=")
        core = enc[-(-8 * k // 5):(8 * (k + len(b))) // 5]
        if len(core) >= 6:
            out |= {core, core.lower()}
    return out


# letters of other scripts that look like Latin ones (Cyrillic, Greek, a few IPA / letterlike forms); NFKD folds the
# full-width, accented and ligature forms on top of this
_CONFUSABLE = str.maketrans({
    "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
    "і": "i", "ј": "j", "ѕ": "s", "ԁ": "d", "ӏ": "l", "ɡ": "g", "ı": "i",
    "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O",
    "Р": "P", "С": "C", "Т": "T", "Х": "X", "І": "I", "Ј": "J", "Ѕ": "S",
    "α": "a", "ε": "e", "ι": "i", "κ": "k", "ν": "v", "ο": "o", "ρ": "p",
    "τ": "t", "υ": "u", "χ": "x", "Α": "A", "Β": "B", "Ε": "E", "Ζ": "Z",
    "Η": "H", "Ι": "I", "Κ": "K", "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P",
    "Τ": "T", "Υ": "Y", "Χ": "X", "ℓ": "l", "ⅰ": "i", "ⅼ": "l", "ⅽ": "c",
    "ⅾ": "d", "ⅿ": "m"})
_LEET = str.maketrans("4@3!10$57896", "aaeiiosstbgg")
_ESCAPE = re.compile(r"\\x([0-9A-Fa-f]{2})|\\u([0-9A-Fa-f]{4})|\\U([0-9A-Fa-f]{8})|\\([0-7]{1,3})|%([0-9A-Fa-f]{2})|"
                     r"&#[xX]([0-9A-Fa-f]{1,6});?|&#(\d{1,7});?|#(\d{1,7})|\\[nrt]")
_CHR_CALL = re.compile(r"(?i)\b(?:chr|chrw|unichr|char)\s*\(\s*(0x[0-9a-f]+|\d+)\s*\)")
_CHAR_CODES = re.compile(r"(?i)fromCharCode\s*\(([^)]*)\)")
_QUOTED = re.compile(r"'((?:[^'\\\n]|\\.|'')*)'|\"((?:[^\"\\\n]|\\.)*)\"")


def _fold(text: str) -> str:
    t = unicodedata.normalize("NFKD", text)
    return "".join(ch for ch in t if not unicodedata.combining(ch)).translate(_CONFUSABLE)


def _unescape(text: str) -> str:
    def one(m):
        for g, base in ((1, 16), (2, 16), (3, 16), (4, 8), (5, 16), (6, 16), (7, 10), (8, 10)):
            if m.group(g):
                try:
                    return chr(int(m.group(g), base))
                except (ValueError, OverflowError):
                    return " "
        return " "
    return _ESCAPE.sub(one, text)


def _alt_views(path: str, text: str) -> list[tuple[str, str]]:
    """whole-file forms a name can hide in besides its plain lines (rc8 switch prep, review LOW): look-alike letters
    folded, leetspeak digits as letters, escape sequences decoded (\\x.. \\u.... \\NNN %.. &#..; #NN), chr()/Chr()/
    fromCharCode() calls spelled out, and the string literals joined in source order (Python: every constant; JSON:
    every value; .iss: the quoted texts) - each view is then scanned line by line AND across its lines"""
    views = [("look-alike letters folded", _fold(text))]
    views.append(("leetspeak digits as letters", views[0][1].translate(_LEET)))
    views.append(("escape sequences decoded", _unescape(text)))
    codes = []
    for m in _CHR_CALL.finditer(text):
        codes.append(int(m.group(1), 0))
    for m in _CHAR_CODES.finditer(text):
        codes += [int(x, 0) for x in re.findall(r"0x[0-9A-Fa-f]+|\d+", m.group(1))]
    if codes:
        views.append(("character-code calls spelled out", "".join(chr(c) for c in codes if 0 < c < 0x110000)))
    ext = os.path.splitext(path)[1].lower()
    joined = None
    if ext == ".py":
        try:
            tree = ast.parse(text)
            consts = sorted(((n.lineno, n.col_offset, n.value) for n in ast.walk(tree)
                             if isinstance(n, ast.Constant) and isinstance(n.value, (str, bytes))), key=lambda x: x[:2])
            joined = "".join(v if isinstance(v, str) else v.decode("latin-1") for _, _, v in consts)
        except (SyntaxError, ValueError):
            joined = None
    elif ext == ".json":
        try:
            parts = []

            def walk(o):
                if isinstance(o, str):
                    parts.append(o)
                elif isinstance(o, dict):
                    for v in o.values():
                        walk(v)
                elif isinstance(o, list):
                    for v in o:
                        walk(v)
            walk(json.loads(text))
            joined = "".join(parts)
        except ValueError:
            joined = None
    if joined is None and ext in (".py", ".iss", ".json"):
        joined = "".join((m.group(1) or "").replace("''", "'") + (m.group(2) or "") for m in _QUOTED.finditer(text))
    if joined:
        views.append(("string literals joined", joined))
    return views


def _squeeze(s: str) -> tuple[str, list[int]]:
    """(the letters and digits of s, lower case, nothing else; the index in s of each of them)"""
    keep = [i for i, ch in enumerate(s) if ch.isascii() and ch.isalnum()]
    return "".join(s[i] for i in keep).lower(), keep


def _inside_word(s: str, i: int) -> bool:
    """s[i] continues a word (a letter of the same case right before it): 'summaries', 'primaries', 'Rosemarie' hold a
    short marker that is only part of an ordinary word. A capital after a small letter starts a new CamelCase word."""
    return 0 < i < len(s) and s[i - 1].isalpha() and s[i].isalpha() and s[i - 1].islower() == s[i].islower()


# a marker form this short (letters and digits) can sit inside an ordinary word: its hit counts only at a word start
_WORDLIKE_MAX = 6


def _marker_forms(markers: list[str]) -> tuple[set, set, set, list]:
    """-> (forms matched in any case, forms matched as written, squeezed forms, encoded-form regexes). Every marker,
    reversed, and every Caesar shift of both (rot13 included); markers of 5+ letters/digits in any case and squeezed
    (separators removed: 'p l a i n', 'pl' + 'ain'); shorter ones in any case where they start with a separator or a
    capital (exact case for the others). Encoded forms of the 5+ ones: hex (\\x, 0x, %, &#x), decimal lists, base64
    (3 alignments, URL-safe too) and base32 (5 alignments)."""
    ci, cs, squeezed, enc = set(), set(), set(), []
    enc_hex, enc_dec, enc_lit = set(), set(), set()
    for m in markers:
        alnum = re.sub(r"[^0-9A-Za-z]", "", m)
        long_ = len(alnum) >= 5
        for k in range(26) if long_ else (0, 13):
            for form in (_shift(m, k), _shift(m, k)[::-1]):
                if long_:
                    ci.add(form)
                    squeezed.add(re.sub(r"[^0-9A-Za-z]", "", form).lower())
                else:
                    cs.add(form)
                    if not form[:1].isalpha() or form[:1].isupper():
                        ci.add(form)
        if not long_:
            continue
        for v in {m, m.lower(), m.upper(), m[:1].upper() + m[1:].lower()}:
            b = v.encode("utf-8")
            sep = r"(?:\\x|\\u00|0x|%|&#x|&#)?"
            enc_hex.add(r"[\s,;:'\"+-]{0,3}".join(sep + "%02x;?" % c for c in b))
            enc_dec.add(r"\D{1,4}".join(str(c) for c in b))
            enc_lit.update(_b64_cores(b) | _b32_cores(b))
    if enc_hex:                 # one regex per kind (a line is searched for all of them at once)
        enc = [re.compile("(?i)(?:%s)" % "|".join(sorted(enc_hex))),
               re.compile(r"(?<!\d)(?:%s)(?!\d)" % "|".join(sorted(enc_dec))),
               re.compile("|".join(re.escape(x) for x in sorted(enc_lit, key=len, reverse=True)))]
    return ci, cs, squeezed, enc


def _trie_regex(words) -> str:
    """one regex for many literal words, factored by common prefixes (the longest word wins at a position): Python's
    re tries a flat alternation branch by branch at every position, a prefix tree only along the letters that fit"""
    root: dict = {}
    for w in words:
        d = root
        for ch in w:
            d = d.setdefault(ch, {})
        d[""] = {}

    def emit(d: dict) -> str:
        alts = [re.escape(ch) + emit(sub) for ch, sub in sorted(d.items()) if ch != ""]
        if not alts:
            return ""
        body = alts[0] if len(alts) == 1 else "(?:%s)" % "|".join(alts)
        return "(?:%s)?" % body if "" in d else body
    return emit(root)


class _MarkerScan:
    """one pattern-like object for the content scan: .search(line) over the line (any case / as written / encoded,
    word-start rule for short forms) and over its squeezed form; .search_squeezed(text) over a whole text whose lines
    are squeezed together (a name split across lines)"""

    def __init__(self, markers: list[str]):
        self.markers = markers
        ci, cs, sq, self.enc = _marker_forms(markers)
        self.ci = re.compile("(?i)" + _trie_regex({x.lower() for x in ci})) if ci else None
        self.cs = re.compile(_trie_regex(cs)) if cs else None
        self.sq = re.compile(_trie_regex(sq)) if sq else None
        self.pattern = hashlib.sha256(json.dumps(
            ["v2", _WORDLIKE_MAX, self.ci.pattern if self.ci else "", self.cs.pattern if self.cs else "",
             self.sq.pattern if self.sq else "", [r.pattern for r in self.enc]]).encode()).hexdigest()

    @staticmethod
    def _hit(rx, s: str, orig: str | None = None, idx: list | None = None) -> bool:
        """a match of rx in s that is not a short form inside an ordinary word (s squeezed: orig + idx map back)"""
        for m in rx.finditer(s):
            n_alnum = sum(ch.isalnum() for ch in m.group(0))
            if n_alnum > _WORDLIKE_MAX:
                return True
            if orig is None:
                first = m.start() + next((j for j, ch in enumerate(m.group(0)) if ch.isalnum()), 0)
                if not _inside_word(s, first):
                    return True
            else:
                o = idx[m.start()]
                if not (m.start() > 0 and idx[m.start() - 1] == o - 1 and _inside_word(orig, o)):
                    return True
        return False

    def search(self, line: str, encoded: bool = True):
        if not self.markers:
            return True                     # not configured: nothing can pass (fail closed)
        if self.ci and self._hit(self.ci, line):
            return True
        if self.cs and self.cs.search(line):
            return True
        if self.sq:
            sq, idx = _squeeze(line)
            if self._hit(self.sq, sq, line, idx):
                return True
        return True if encoded and any(r.search(line) for r in self.enc) else None

    def search_squeezed(self, text: str):
        if not self.markers:
            return True
        if not self.sq:
            return None
        sq, idx = _squeeze(text)
        return True if self._hit(self.sq, sq, text, idx) else None


def _leak_patterns() -> list[tuple[str, re.Pattern]]:
    pats = [
        # a real profile folder name; "C:\Users\..." (only dots: a placeholder in a code comment, code\me3.iss since
        # repair 5) is not one (final pass 2: that comment refused the first restage after repair 5)
        ("a user-profile path", re.compile(r"(?i)\b[a-z]:[\\/]+users[\\/]+(?!\.+(?:[\\/\s\"'`<>|)\]]|$))"
                                           r"[^\\/\s\"'`<>|]+")),
        ("a GitHub token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})")),
        ("a private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
        ("a private LAN address", re.compile(r"(?<![\d.])(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|"
                                             r"172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(?![\d.])")),
        ("an e-mail address", re.compile(r"\b[\w.+-]+@[\w-]+\.(?:com|net|org|io|me|de|tr|edu|co)\b")),
        ("a private marker (or its reversed / encoded form), or the markers are not configured on this PC "
         "(catalog\\*.local.json)", _MarkerScan(cfg.private_markers())),
    ]
    user = os.environ.get("USERNAME", "")
    if len(user) >= 4:
        pats.append(("the Windows user name", re.compile(r"(?i)(?<![A-Za-z0-9])" + re.escape(user) + r"(?![A-Za-z0-9])")))
    prof = os.environ.get("USERPROFILE", "")
    if len(prof) > 3:
        pats.append(("the user-profile folder", re.compile(re.escape(prof), re.I)))
    return pats


def scan_repo_files(files: dict[str, bytes]) -> list[str]:
    """-> problems (empty = OK): text files only, allowed extensions, size cap, no machine details"""
    problems = []
    pats = _leak_patterns()
    for path, data in sorted(files.items()):
        name = path.rsplit("/", 1)[-1]
        ext = os.path.splitext(name)[1].lower()
        if not (ext in TEXT_EXTS or name in TEXT_NAMES):
            problems.append("%s: not a text file type the repo may hold (%s)" % (path, ext or name))
            continue
        if len(data) > MAX_REPO_FILE:
            problems.append("%s: %d bytes is over the %d byte cap" % (path, len(data), MAX_REPO_FILE))
            continue
        if b"\0" in data:
            problems.append("%s: binary content" % path)
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            problems.append("%s: not UTF-8 text" % path)
            continue
        if any(seg in ("..", "") for seg in path.split("/")) or path.startswith("/") or "\\" in path:
            problems.append("%s: unsafe repo path" % path)
        for what, rx in pats:
            if rx.search(path):
                problems.append("%s: its path holds %s" % (path, what))
                break
        for n, line in enumerate(text.splitlines(), 1):
            for what, rx in pats:
                if rx.search(line):
                    problems.append("%s:%d holds %s" % (path, n, what))
                    break
        # the private markers also in the file's other forms: split across lines, look-alike letters, leetspeak,
        # escapes, character-code calls, its string literals joined (rc8 switch prep, review LOW)
        mk = [rx for what, rx in pats if isinstance(rx, _MarkerScan)]
        if mk and mk[0].markers and not any(p_.startswith(path + ":") for p_ in problems):
            ms = mk[0]
            hit = "its lines squeezed together" if ms.search_squeezed(text) else None
            if not hit:
                for vname, vtext in _alt_views(path, text):
                    if ms.search_squeezed(vtext) or any(ms.search(ln, False) for ln in vtext.splitlines()):
                        hit = vname
                        break
            if hit:
                problems.append("%s: holds a private marker (found with %s)" % (path, hit))
    return problems


HISTORY_CACHE = cfg.WORK / "gh_history_scan_cache.json"


def _scan_version() -> str:
    """the content scan's identity: a cached verdict counts only for the same scan rules (patterns + limits)"""
    pats = [(w, rx.pattern) for w, rx in _leak_patterns()]
    return hashlib.sha256(json.dumps([pats, sorted(TEXT_EXTS), sorted(TEXT_NAMES), MAX_REPO_FILE]).encode()).hexdigest()


def activity_problems(full: str, reachable: set) -> list[str]:
    """read-only (rc8 switch prep, review MEDIUM): GitHub's Activity view keeps every push - force pushes too - with
    the commit ids before and after it, and shows it once the repo is public; such a commit also stays readable by its
    id. A commit id there that the branch no longer holds is a replaced history that would become public: refused
    (a force-pushed orphan commit does not hide the old one; the zero-trace way is a fresh repo, INSTALLER_V65.md
    section 2 step 2b). Unreadable log = refused (fail closed)."""
    r = gh(["api", "--paginate", "repos/%s/activity?per_page=100" % full, "--jq",
            '.[] | .activity_type + " " + (.before // "-") + " " + (.after // "-")'], check=False)
    if r.returncode != 0:
        return ["could not read the repo's Activity log (gh: %s)" % (r.stderr or r.stdout or "").strip()[-200:]]
    gone = set()
    for ln in r.stdout.splitlines():
        parts = ln.split()
        for sha in parts[1:3]:
            known = any(x.startswith(sha) or sha.startswith(x) for x in reachable)
            if re.fullmatch(r"[0-9a-f]{7,40}", sha) and set(sha) != {"0"} and not known:
                gone.add("%s %s" % (parts[0], sha[:12]))
    if not gone:
        return []
    return ["the repo's Activity log lists %d commit id(s) the branch no longer holds (%s): a replaced history stays "
            "visible there and readable by its id once the repo is public - publish from a fresh repo instead "
            "(INSTALLER_V65.md section 2 step 2b)" % (len(gone), ", ".join(sorted(gone)[:5]))]


def history_problems(full: str) -> tuple[list[str], dict]:
    """read-only: the content scan over EVERY file version in the repo's history (publishing makes the history public
    too), and the Activity log check (activity_problems). -> (problems, counts). A git blob never changes under its sha, so a blob's verdict is cached
    (work/gh_history_scan_cache.json, per scan version + path): a re-check only downloads the new file versions."""
    try:
        cache = json.loads(HISTORY_CACHE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        cache = {}
    ver = _scan_version()
    if cache.get("scan_version") != ver:
        cache = {"scan_version": ver, "blobs": {}, "trees": {}}
    r = gh(["api", "--paginate", "repos/%s/commits?per_page=100" % full, "--jq", '.[] | .sha + " " + .commit.tree.sha'],
           check=False)
    if r.returncode != 0:
        err = (r.stderr or r.stdout or "").strip()
        if "empty" in err.lower():
            return [], {"commits": 0, "blobs": 0}
        return ["could not list the repo history (gh: %s)" % err[-200:]], {}
    pairs = [ln.split() for ln in r.stdout.splitlines() if len(ln.split()) == 2]
    trees = [p[1] for p in pairs]
    act = activity_problems(full, {p[0] for p in pairs})
    blobs: dict[str, str] = {}
    tcache = cache.setdefault("trees", {})
    n_trees_cached = len(tcache)
    for t in trees:
        if t not in tcache:            # a tree never changes under its sha either
            tr = gh(["api", "repos/%s/git/trees/%s?recursive=1" % (full, t), "--jq",
                     '.tree[] | select(.type=="blob") | .sha + " " + .path'])
            tcache[t] = [line.partition(" ")[::2] for line in tr.stdout.splitlines() if line.strip()]
        for sha, path in tcache[t]:
            if sha and sha not in blobs:
                blobs[sha] = path
    problems = list(act)
    fetched = 0
    for sha, path in sorted(blobs.items(), key=lambda kv: kv[1]):
        key = sha + " " + path
        if key in cache["blobs"]:
            found = cache["blobs"][key]
        else:
            b = gh(["api", "repos/%s/git/blobs/%s" % (full, sha), "--jq", ".content"])
            data = base64.b64decode("".join(b.stdout.split()))
            require(git_blob_sha(data) == sha, "history blob %s: content does not hash to its sha" % sha[:8])
            found = scan_repo_files({path: data})
            cache["blobs"][key] = found
            fetched += 1
        problems += ["history (blob %s) %s" % (sha[:8], p) for p in found]
    if fetched or len(tcache) != n_trees_cached:
        try:
            HISTORY_CACHE.parent.mkdir(parents=True, exist_ok=True)
            tmp = HISTORY_CACHE.with_suffix(".tmp")
            tmp.write_text(json.dumps(cache, indent=0), encoding="utf-8")
            os.replace(tmp, HISTORY_CACHE)
        except OSError:
            pass
    return problems, {"commits": len(trees), "blobs": len(blobs), "blobs_downloaded": fetched}


def code_ids() -> dict:
    """the installer code fingerprint of the current source (pipeline/codefp.py)"""
    from .codefp import code_fingerprint
    return {"code_fingerprint": code_fingerprint()}


def repo_tree(model: dict, src: dict, tag: str) -> dict[str, bytes]:
    """every file the repo should hold for this release (repo path -> bytes)"""
    from .iscc import SIDECAR
    files: dict[str, bytes] = {}
    root = cfg.DIST / tag / "repo"
    for p in sorted(root.rglob("*")):
        if p.is_file() and not p.name.endswith(".tmp"):
            files[p.relative_to(root).as_posix()] = p.read_bytes()
    cat_p = cfg.DIST / tag / "catalog.json"
    files["releases/%s/catalog.json" % tag] = cat_p.read_bytes()
    srcs = source_files(src)
    for rp, p in srcs.items():
        files[rp] = p.read_bytes()
    side_p = cfg.DIST / tag / SIDECAR
    side = json.loads(side_p.read_text(encoding="utf-8")) if side_p.is_file() else {}
    fp = code_ids()["code_fingerprint"]
    cat_sha = hashlib.sha256(files["releases/%s/catalog.json" % tag]).hexdigest()
    meta = {
        "tag": tag, "rc": model.get("rc"), "catalog_sha256": cat_sha,
        "installer_code_fingerprint": fp,
        "release_exe": {k: side.get(k) for k in ("exe", "sha256", "size", "catalog_sha256", "code_fingerprint")}
        if side else None,
        "source_is_release_exe_code": bool(side) and side.get("code_fingerprint") == fp and
        side.get("catalog_sha256") == cat_sha,
        "_doc": "installer/ in this commit is the source the release exe was compiled from when source_is_release_exe_"
                "code is true (installer_code_fingerprint = pipeline/codefp.py over the .iss files + generated includes).",
        "files": {rp: hashlib.sha256(files[rp]).hexdigest() for rp in sorted(srcs)},
    }
    files["releases/%s/SOURCE.json" % tag] = (json.dumps(meta, indent=1) + "\n").encode("utf-8")
    return files


# ------------------------------------------------------------------ the repo + the draft release
class Repo:
    def __init__(self, owner: str, name: str, tag: str):
        self.owner, self.name = owner, name
        self.full = "%s/%s" % (owner, name)
        self.tag = tag

    # ------------------------------------------------------------------ guards
    def view(self):
        r = gh(["repo", "view", self.full, "--json", "visibility,isPrivate,defaultBranchRef,name,url"], check=False)
        if r.returncode != 0:
            return None
        return json.loads(r.stdout)

    def assert_private(self):
        v = self.view()
        require(v is not None, "repo %s does not exist" % self.full)
        require(v.get("visibility") == "PRIVATE" and v.get("isPrivate") is True,
                "REFUSED: repo %s is %s, not PRIVATE - nothing written" % (self.full, v.get("visibility")))
        return v

    def assert_files_writable(self, allow_public: bool):
        v = self.view()
        require(v is not None, "repo %s does not exist" % self.full)
        if not allow_public:
            require(v.get("visibility") == "PRIVATE" and v.get("isPrivate") is True,
                    "REFUSED: repo %s is %s, not PRIVATE - no repo file written (publish_github.py --publish updates "
                    "the files of a public repo, only after Luka's OK)" % (self.full, v.get("visibility")))
        return v

    def release(self):
        r = gh(["release", "view", self.tag, "--repo", self.full, "--json", "isDraft,tagName,assets,name,url,body"],
               check=False)
        if r.returncode != 0:
            return None
        return json.loads(r.stdout)

    def assert_draft(self):
        v = self.view()
        require(v is not None, "repo %s does not exist" % self.full)
        rel = self.release()
        require(rel is not None, "release %s missing" % self.tag)
        require(rel.get("isDraft") is True, "REFUSED: release %s is not a draft - nothing written" % self.tag)
        return rel

    # ------------------------------------------------------------------ writes
    def ensure_repo(self, description: str):
        v = self.view()
        if v is None:
            log("GitHub: creating PRIVATE repo %s" % self.full)
            gh(["repo", "create", self.full, "--private", "--description", description, "--disable-wiki"])
            for _ in range(10):
                if self.view():
                    break
                time.sleep(2)
            v = self.assert_private()
        log("GitHub: repo %s is %s (%s)" % (self.full, v.get("visibility"), v.get("url")))
        return v

    def put_file(self, path: str, data: bytes, message: str, allow_public: bool = False) -> str:
        """one file through the contents API (used to make the first commit of an empty repo)"""
        self.assert_files_writable(allow_public)
        r = gh(["api", "repos/%s/contents/%s" % (self.full, path)], check=False)
        old_sha = None
        if r.returncode == 0:
            cur = json.loads(r.stdout)
            old_sha = cur.get("sha")
            if old_sha == git_blob_sha(data):
                return "unchanged"
        body = {"message": message, "content": base64.b64encode(data).decode("ascii")}
        if old_sha:
            body["sha"] = old_sha
        self.assert_files_writable(allow_public)
        gh_json(["api", "-X", "PUT", "repos/%s/contents/%s" % (self.full, path)], body)
        return "updated" if old_sha else "created"

    def remote_tree(self, branch: str):
        """-> (head commit sha, its tree sha, {path: blob sha}) or None for an empty repo"""
        ref = gh_json(["api", "repos/%s/git/ref/heads/%s" % (self.full, branch)], check=False)
        if not ref or "object" not in ref:
            return None
        head = ref["object"]["sha"]
        commit = gh_json(["api", "repos/%s/git/commits/%s" % (self.full, head)])
        tree_sha = commit["tree"]["sha"]
        tree = gh_json(["api", "repos/%s/git/trees/%s?recursive=1" % (self.full, tree_sha)])
        require(not tree.get("truncated"), "the repo tree listing is truncated: cannot compare safely")
        return head, tree_sha, {e["path"]: e["sha"] for e in tree.get("tree", []) if e.get("type") == "blob"}

    def plan_tree(self, files: dict[str, bytes], branch: str) -> dict:
        """read-only: what push_tree would change"""
        rt = self.remote_tree(branch)
        remote = rt[2] if rt else {}
        create = sorted(p for p in files if p not in remote)
        update = sorted(p for p in files if p in remote and remote[p] != git_blob_sha(files[p]))
        delete = sorted(p for p in remote if p not in files and p.startswith(DELETE_STALE_PREFIXES))
        return {"branch": branch, "head": rt[0] if rt else None, "create": create, "update": update, "delete": delete,
                "unchanged": len(files) - len(create) - len(update)}

    def push_tree(self, files: dict[str, bytes], message: str, branch: str, allow_public: bool = False) -> dict:
        """ONE commit that makes the repo hold `files` (and drops stale installer/ files); no commit when nothing
        changed. Refuses before any write when scan_repo_files() finds a problem."""
        problems = scan_repo_files(files)
        require(not problems, "REFUSED: repo files failed the content scan, nothing written:\n  " + "\n  ".join(
            problems[:40]))
        self.assert_files_writable(allow_public)
        rt = self.remote_tree(branch)
        if rt is None:          # empty repo: the contents API makes the first commit (and the branch)
            first = "README.md" if "README.md" in files else sorted(files)[0]
            self.put_file(first, files[first], message, allow_public)
            rt = self.remote_tree(branch)
            require(rt is not None, "could not create branch %s in %s" % (branch, self.full))
        head, base_tree, remote = rt
        entries, created, updated, deleted = [], [], [], []
        for path, data in sorted(files.items()):
            bsha = git_blob_sha(data)
            if remote.get(path) == bsha:
                continue
            self.assert_files_writable(allow_public)
            b = gh_json(["api", "-X", "POST", "repos/%s/git/blobs" % self.full],
                        {"content": base64.b64encode(data).decode("ascii"), "encoding": "base64"})
            require(b.get("sha") == bsha, "GitHub stored %s as blob %s, expected %s" % (path, b.get("sha"), bsha))
            entries.append({"path": path, "mode": "100644", "type": "blob", "sha": bsha})
            (updated if path in remote else created).append(path)
        for path in sorted(remote):
            if path not in files and path.startswith(DELETE_STALE_PREFIXES):
                entries.append({"path": path, "mode": "100644", "type": "blob", "sha": None})
                deleted.append(path)
        res = {"branch": branch, "created": created, "updated": updated, "deleted": deleted,
               "unchanged": len(files) - len(created) - len(updated), "commit": None}
        if not entries:
            return res
        tree = gh_json(["api", "-X", "POST", "repos/%s/git/trees" % self.full], {"base_tree": base_tree, "tree": entries})
        commit = gh_json(["api", "-X", "POST", "repos/%s/git/commits" % self.full],
                         {"message": message, "tree": tree["sha"], "parents": [head]})
        self.assert_files_writable(allow_public)
        gh_json(["api", "-X", "PATCH", "repos/%s/git/refs/heads/%s" % (self.full, branch)],
                {"sha": commit["sha"], "force": False})
        after = self.remote_tree(branch)
        require(after and after[0] == commit["sha"], "branch %s did not move to the new commit" % branch)
        bad = [p for p, d in files.items() if after[2].get(p) != git_blob_sha(d)]
        require(not bad, "after the commit these repo files differ from the local ones: %s" % bad[:5])
        res["commit"] = commit["sha"]
        return res

    def ensure_draft(self, title: str, notes: str, target: str):
        rel = self.release()
        if rel is None:
            require(self.view() is not None, "repo %s does not exist" % self.full)
            log("GitHub: creating DRAFT release %s" % self.tag)
            with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
                f.write(notes)
                tmp = f.name
            try:
                gh(["release", "create", self.tag, "--repo", self.full, "--draft", "--title", title, "--notes-file", tmp,
                    "--target", target])
            finally:
                os.unlink(tmp)
        return self.assert_draft()

    def assets(self) -> dict:
        rel = self.assert_draft()
        return {a["name"]: a for a in rel.get("assets", [])}


def release_title(src: dict, tag: str) -> str:
    return "%s - Auto Installer files (%s)" % (src["release"]["mod_title"], tag)


def release_notes(model: dict, src: dict, tag: str) -> str:
    """the release text; it reads right both as a draft and once published"""
    rel = src["release"]
    blob = "https://github.com/%s/%s/blob/HEAD/" % (rel["github"]["owner"], rel["github"]["repo"])
    return "\n".join([
        "The files that the **%s Auto Installer** downloads (release candidate %s)." % (rel["mod_title"], model.get("rc")),
        "",
        "They are not a mod on their own. Get the merge (Main Files + Auto Installer) from its Nexus page,",
        "%s, and run the installer: it downloads only what your options need from here and checks" % rel["nexus_url"],
        "every file by SHA-256 before anything in your game folder changes. Every other author's mod is downloaded",
        "from the author's own page.",
        "",
        "What each asset is: [ASSETS.md](%sreleases/%s/ASSETS.md). Credits: [README.md](%sREADME.md), "
        "[CREDITS.md](%sCREDITS.md). Licences: [LICENSE-NOTES.md](%sLICENSE-NOTES.md)." % (blob, tag, blob, blob, blob),
        "",
    ])


def published_problems(src: dict, tag: str) -> list[str]:
    """--final: refuse a tag whose GitHub release is already published (its assets can no longer change, so an exe
    built for a changed catalog would fail every download). No repo or no release yet = fine."""
    g = src["release"]["github"]
    full = "%s/%s" % (g["owner"], g["repo"])
    r = gh(["release", "view", tag, "--repo", full, "--json", "isDraft"], check=False)
    if r.returncode != 0:
        err = (r.stderr or r.stdout or "").strip()
        if "release not found" in err.lower() or "could not resolve to a repository" in err.lower():
            return []
        return ["could not read the GitHub release %s of %s (gh: %s)" % (tag, full, err[-200:])]
    if not json.loads(r.stdout).get("isDraft"):
        return ["the GitHub release %s of %s is already PUBLISHED: its assets can no longer change - give this build a "
                "new version (release.version + release.tag in catalog\\catalog.src.json)" % (tag, full)]
    return []


def default_branch(v: dict) -> str:
    return ((v or {}).get("defaultBranchRef") or {}).get("name") or "main"


def commit_message(model: dict, tag: str) -> str:
    return "%s (RC %s): installer source, catalog and docs" % (tag, model.get("rc"))


def stage(model: dict, src: dict, tag: str, upload=True) -> dict:
    gcfg = src["release"]["github"]
    repo = Repo(gcfg["owner"], gcfg["repo"], tag)
    t0 = time.time()
    v = repo.ensure_repo("Source and downloads of the %s Auto Installer (not a standalone mod)."
                         % src["release"]["mod_title"])
    branch = default_branch(v)
    rel_state = repo.release()
    require(rel_state is None or rel_state.get("isDraft") is True,
            "REFUSED: release %s of %s is already published - nothing written (a published release never changes; "
            "give this build a new version)" % (tag, repo.full))
    files = repo_tree(model, src, tag)
    if v.get("visibility") == "PRIVATE":
        res_files = repo.push_tree(files, commit_message(model, tag), branch)
        log("GitHub: repo files: %d created, %d updated, %d deleted, %d unchanged%s" % (
            len(res_files["created"]), len(res_files["updated"]), len(res_files["deleted"]), res_files["unchanged"],
            " -> commit %s" % res_files["commit"][:12] if res_files["commit"] else " (no commit)"))
    else:
        problems = scan_repo_files(files)
        res_files = {"skipped": "repo is %s: its files are updated by publish_github.py --publish (only after Luka's OK)"
                                % v.get("visibility"), "scan_problems": problems,
                     "plan": repo.plan_tree(files, branch)}
        log("GitHub: repo %s is %s - repo files NOT updated (publish_github.py --publish does it); the draft release "
            "is staged" % (repo.full, v.get("visibility")))
    title, notes = release_title(src, tag), release_notes(model, src, tag)
    rel0 = repo.ensure_draft(title, notes, branch)
    if rel0.get("name") != title or (rel0.get("body") or "").replace("\r\n", "\n").strip() != notes.strip():
        # the notes are written to read right once Luka publishes (no "draft" wording); kept current on every stage
        repo.assert_draft()
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
            f.write(notes)
            tmp = f.name
        try:
            gh(["release", "edit", tag, "--repo", repo.full, "--draft", "--title", title, "--notes-file", tmp])
        finally:
            os.unlink(tmp)
        log("GitHub: draft release %s title/notes updated" % tag)
    want = {b["asset"]: b for b in model["blobs"] if not b.get("site")}   # CAT_FORMAT 2: site blobs are not release assets
    have = repo.assets()
    stale = [n for n in have if n not in want]
    if stale:
        from concurrent.futures import ThreadPoolExecutor

        def _del(n):
            repo.assert_draft()
            gh(["release", "delete-asset", tag, n, "--repo", repo.full, "-y"])
            log("GitHub: deleted stale draft asset %s" % n)
        with ThreadPoolExecutor(max_workers=UPLOAD_WORKERS) as ex:      # final pass 2: 3 at a time (~1.5 s each)
            list(ex.map(_del, stale))
    # an asset already on the draft is skipped when its name, size AND GitHub's own sha256 digest (computed by GitHub
    # from the stored bytes) equal the catalog's; a wrong size or digest is uploaded again (--clobber). Final pass 2:
    # the digest was only checked AFTER the upload before, so a same-size wrong file failed the stage instead of
    # being replaced.
    def _digest_bad(a: dict, b: dict) -> bool:
        d = a.get("digest") or ""
        return d.startswith("sha256:") and d[7:] != b["sha256"]
    wrong = [n for n, a in have.items() if n in want and (a.get("size") != want[n]["size"] or _digest_bad(a, want[n]))]
    missing = [n for n in want if n not in have or n in wrong]
    skipped = len(want) - len(missing)
    up_root = cfg.DIST / tag / "github" / tag
    uploaded = []
    if upload and missing:
        from concurrent.futures import ThreadPoolExecutor
        log("GitHub: %d asset(s) already on the draft with the catalog's size + sha256 digest (skipped); uploading %d "
            "asset(s), %.1f MB, %d at a time" % (skipped, len(missing), sum(want[n]["size"] for n in missing) / 1048576,
                                                 UPLOAD_WORKERS))
        # batches of up to 8 files, balanced by size, UPLOAD_WORKERS gh processes at once (different assets of one draft)
        order = sorted(missing, key=lambda n: -want[n]["size"])
        nb = max(1, min(len(order), max(UPLOAD_WORKERS, (len(order) + 7) // 8)))
        batches = [[] for _ in range(nb)]
        sizes = [0] * nb
        for n in order:
            i = min(range(nb), key=lambda k: (sizes[k], len(batches[k])) if len(batches[k]) < 8 else (1 << 62, 0))
            batches[i].append(n)
            sizes[i] += want[n]["size"]
        lock = __import__("threading").Lock()

        def _up(batch):
            for attempt in range(3):
                repo.assert_draft()
                r = gh(["release", "upload", tag, "--repo", repo.full, "--clobber"] + [up_root / x for x in batch],
                       check=False, timeout=7200)
                if r.returncode == 0:
                    break
                log("GitHub: upload attempt %d failed: %s" % (attempt + 1, (r.stderr or r.stdout)[-300:]))
                time.sleep(10)
            else:
                raise BuildError("GitHub upload failed for %s" % batch)
            with lock:
                uploaded.extend(batch)
                log("GitHub: uploaded %d/%d" % (len(uploaded), len(missing)))
        with ThreadPoolExecutor(max_workers=UPLOAD_WORKERS) as ex:
            list(ex.map(_up, [b for b in batches if b]))
    elif not missing:
        log("GitHub: all %d assets already on the draft with the catalog's size + sha256 digest - nothing uploaded"
            % len(want))
    have = repo.assets()
    names_ok = set(have) == set(want)
    sizes_ok = all(have[n].get("size") == want[n]["size"] for n in want if n in have)
    digest_checked = 0
    digest_bad = []
    for n, a in have.items():
        d = a.get("digest") or ""
        if n in want and d.startswith("sha256:"):
            digest_checked += 1
            if d[7:] != want[n]["sha256"]:
                digest_bad.append(n)
    require(not digest_bad, "GitHub asset digest != catalog sha256: %s" % digest_bad)
    rel = repo.assert_draft()
    vis = repo.view() or {}
    ok = names_ok and sizes_ok
    # the draft now matches dist\<tag>\catalog.json; say so loudly when the release exe in dist\<tag>\ was compiled
    # from another catalog (publish_github.py refuses that combination)
    from .iscc import exe_catalog_sha, same_id
    from .util import hash_file
    exe = cfg.DIST / tag / (src["release"]["installer_base_name"] + ".exe")
    cat_sha = hash_file(cfg.DIST / tag / "catalog.json")["sha256"]
    exe_cat = exe_catalog_sha(exe) if exe.is_file() else ""
    if not same_id(cat_sha, exe_cat):
        log("GitHub: NOTE the release exe in dist\\%s was compiled with catalog %s, the draft now holds catalog %s's "
            "assets: build the release exe for this catalog before publishing (publish_github.py refuses otherwise)" % (
                tag, exe_cat[:16] or "(no exe)", cat_sha[:16]))
    log("GitHub: repo %s %s, release %s draft=%s, %d assets on GitHub, names %s, sizes %s, sha256 digests checked %d; %.0f s" % (
        repo.full, vis.get("visibility"), tag, rel.get("isDraft"), len(have), "OK" if names_ok else "DIFFER",
        "OK" if sizes_ok else "DIFFER", digest_checked, time.time() - t0))
    if upload:
        require(ok, "GitHub draft assets != catalog (missing %s, extra %s)" % (sorted(set(want) - set(have))[:5],
                                                                            sorted(set(have) - set(want))[:5]))
    return {"repo": repo.full, "url": vis.get("url"), "visibility": vis.get("visibility"), "release": tag,
            "release_url": rel.get("url"), "is_draft": rel.get("isDraft"), "assets_remote": len(have),
            "assets_catalog": len(want), "uploaded": len(uploaded), "skipped_same_sha256": skipped,
            "uploaded_mb": round(sum(want[n]["size"] for n in uploaded) / 1048576, 1),
            "deleted_stale": stale, "names_ok": names_ok,
            "sizes_ok": sizes_ok, "digests_checked": digest_checked, "repo_files": res_files,
            "secs": round(time.time() - t0, 1)}


# ------------------------------------------------------------------ read-only verification
def verify_by_download(model: dict, src: dict, tag: str, keep_dir: Path | None = None) -> dict:
    """downloads every asset of the release WITH gh's auth (works for a draft) into a temp folder and checks each one's
    size and sha256 against the catalog; read-only on GitHub. The temp folder is removed afterwards."""
    import shutil
    gcfg = src["release"]["github"]
    repo = Repo(gcfg["owner"], gcfg["repo"], tag)
    rel = repo.release()
    require(rel is not None, "release %s missing in %s" % (tag, repo.full))
    want = {b["asset"]: b for b in model["blobs"] if not b.get("site")}   # CAT_FORMAT 2: site blobs are not release assets
    have = {a["name"]: a for a in rel.get("assets", [])}
    d = Path(tempfile.mkdtemp(prefix="cxcxm_ghverify_"))
    t0 = time.time()
    bad, ok, missing = [], [], sorted(set(want) - set(have))
    try:
        from concurrent.futures import ThreadPoolExecutor
        names = sorted(n for n in want if n in have)

        def _dl(part):
            args = ["release", "download", tag, "--repo", repo.full, "--dir", d, "--clobber"]
            for n in part:
                args += ["--pattern", n]
            gh(args, timeout=3600)
        # final pass 2: UPLOAD_WORKERS gh processes at once, each with its own files (12 per call)
        with ThreadPoolExecutor(max_workers=UPLOAD_WORKERS) as ex:
            list(ex.map(_dl, [names[i:i + 12] for i in range(0, len(names), 12)]))
        for n in names:
            p = d / n
            if not p.is_file():
                bad.append("%s: not downloaded" % n)
                continue
            h = hashlib.sha256()
            with open(p, "rb") as f:
                for chunk in iter(lambda: f.read(8 << 20), b""):
                    h.update(chunk)
            size = p.stat().st_size
            if size != want[n]["size"] or h.hexdigest() != want[n]["sha256"]:
                bad.append("%s: size %d sha256 %s, catalog %d %s" % (n, size, h.hexdigest()[:16], want[n]["size"],
                                                                    want[n]["sha256"][:16]))
            else:
                ok.append(n)
    finally:
        if keep_dir is None:
            shutil.rmtree(d, ignore_errors=True)
    return {"repo": repo.full, "tag": tag, "is_draft": rel.get("isDraft"), "checked": len(ok) + len(bad),
            "ok": len(ok), "bad": bad, "missing": missing, "extra": sorted(set(have) - set(want)),
            "bytes": sum(want[n]["size"] for n in ok), "secs": round(time.time() - t0, 1)}
