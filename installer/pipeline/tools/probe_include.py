r"""Compile-probe for generated\catalog.iss, independent of the INNO lane's code: a minimal .iss that declares the
contract's arrays (README_CONTRACT.md section 3.2) itself, includes generated\build_info.iss + generated\catalog.iss and
calls InitCatalog from InitializeSetup. ISCC must compile it (/DCodeCheck-like: no payload).

usage: py -3.11 -X utf8 pipeline\tools\probe_include.py      (writes work\iss_probe\, exit 0 = compiles)
"""
import os
import subprocess
import sys

INST = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ISCC = os.path.join(os.environ.get("LOCALAPPDATA") or os.path.expanduser(r"~\AppData\Local"), "Programs", "Inno Setup 6", "ISCC.exe")
OUT = os.path.join(INST, "work", "iss_probe")

S = "TArrayOfString"
I = "array of Integer"
B = "array of Boolean"
L = "array of Int64"
DECL = [
    ("CompId", S), ("CompSwitch", S), ("CompTitle", S), ("CompDesc", S), ("CompKind", S), ("CompExperimental", B),
    ("CompDefault", I), ("CompStateCount", I), ("CompStateStart", I), ("CompCredit", S), ("CompSourceText", S),
    ("StateCode", S), ("StateTitle", S), ("StateWall", I),
    ("RuleKind", S), ("RuleA", I), ("RuleAMask", I), ("RuleB", I), ("RuleBMask", I), ("RuleText", S),
    ("PathRel", S), ("PathFlags", S), ("PathOwner", I), ("PathAffStart", I), ("PathAffCount", I), ("PathTabStart", I),
    ("AffComp", I), ("PathTab", I),
    ("VarPath", I), ("VarSha", S), ("VarSize", L), ("VarSrc", S), ("VarRef", I),
    ("ArchId", S), ("ArchComp", I), ("ArchTitle", S), ("ArchAuthor", S), ("ArchHint", S), ("ArchNexusUrl", S),
    ("ArchNameHints", S), ("ArchMode", S), ("ArchMustVerify", B), ("ArchGlobs", S), ("ArchPinStart", I), ("ArchPinCount", I),
    ("PinSize", L), ("PinSha", S), ("ArchMemStart", I), ("ArchMemCount", I), ("MemArch", I), ("MemName", S), ("MemTail", S),
    ("MemSha", S), ("MemSize", L),
    ("BlobSha", S), ("BlobSize", L), ("BlobAsset", S), ("BlobTag", S), ("BlobUpstream", S), ("BaseUrls", S),
    ("NatComp", I), ("NatMatch", S), ("NatPath", S), ("NatForeign", S), ("NatLf", B), ("NatLineStart", I), ("NatLineCount", I),
    ("NatLine", S), ("PristineMe3Lines0", S), ("PristineMe3Lines1", S),
    ("DetComp", I), ("DetKind", S), ("DetArg", S), ("DetSha", S), ("DetState", I),
    ("ObsRel", S), ("ObsSha", S), ("ObsNote", S),
    ("FieldComp", I), ("FieldId", S), ("FieldSwitch", S), ("FieldLabel", S), ("FieldRel", S), ("FieldSection", S),
    ("FieldKey", S), ("FieldSecret", B),
    ("CreditComp", I), ("CreditText", S),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    gen = os.path.join(INST, "generated")
    lines = [
        '#include "%s"' % os.path.join(gen, "build_info.iss"),
        "#if CatFormat != 1",
        '  #error CatFormat',
        "#endif",
        "[Setup]",
        "AppName=CXCXM catalog include probe",
        "AppVersion={#CatVersion}",
        "DefaultDirName={tmp}\\probe",
        "OutputBaseFilename=probe",
        "Uninstallable=no",
        "CreateAppDir=no",
        "PrivilegesRequired=lowest",
        "",
        "[Code]",
        "var",
    ] + ["  %s: %s;" % (n, t) for n, t in DECL] + [
        "",
        '#include "%s"' % os.path.join(gen, "catalog.iss"),
        "",
        "function InitializeSetup(): Boolean;",
        "var k: Integer;",
        "begin",
        "  InitCatalog;",
        "  k := CAT_C_ERCAP + WALL_BASE + MAX_REL_LEN + CONV302_FILE_COUNT;",
        "  Log(CAT_SHA256 + ' ' + CAT_SEAMLESS_TESTED_VERSION + ' ' + IntToStr(k));",
        "  Result := (GetArrayLength(PathTab) = CAT_TAB_COUNT) and (GetArrayLength(VarSha) = CAT_VAR_COUNT);",
        "end;",
    ]
    iss = os.path.join(OUT, "probe.iss")
    with open(iss, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    r = subprocess.run([ISCC, "/Qp", "/O" + OUT, iss], capture_output=True, text=True, encoding="utf-8", errors="replace",
                       creationflags=getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0))
    print((r.stdout + r.stderr).strip()[-2500:])
    print("PROBE", "COMPILES" if r.returncode == 0 else "FAILED (exit %d)" % r.returncode)
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
