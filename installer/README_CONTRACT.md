# v6.5 Auto Installer ("installer v2") - BUILDER CONTRACT (CAT_FORMAT 2)

Final pass (2026-10-03): CAT_FORMAT 2 = CAT_FORMAT 1 + the per-blob download site `BlobSite` (section 3.2, Blobs) and
`/BASEURL=` replacing every download root (section 5.5). Everything else below still holds; the change log
(section 12) lists the final pass's other changes (McKenyu 1.4 RAR5, DMN enabled, Seamless 2.0.1, repair round 6).
Release prep (2026-10-03): Nightreign Movement 0.2 is the player's own download (archive `nrm_02`, Nexus 11174) like
every other author's mod; the pipeline makes no site blob any more (`BlobSite` is always `''`; the installer keeps
reading the field, so CAT_FORMAT stays 2). rc8 switch prep (2026-10-03): the NRM option ships the NRM layer of the
catalog's `inputs.nrm_tier` (T2W, Wylder on); DMN + NRM may be built on a sibling NRM layer (T2, Wylder off) whose
differing files come before the DMN overlay; Lucy + NRM gets Lucy's icon pair with NRM 0.2's icon change put in
(section 12). DMN + Wylder (2026-10-03, Luka after his field test): DMN + NRM ships NRM 0.2 WITH Wylder (the ERCap-only
layer `dmn_nrmw_<rc>`) and the installer adds ERCapacityExpansion by itself - rule kind `D`, marker / manifest line
`AUTO_ON=`; the sibling arrangement is retired (section 12, CAT_FORMAT 2 unchanged).

Design and reasons: `C:\$MD\EldenRing\merge\v65\INSTALLER_V65_DESIGN.md`. This file is the binding contract between the two
builder lanes. Anything not fixed here is the owning lane's choice. A change to anything in sections 3-9 needs a
`CAT_FORMAT` bump and a line in section 12 (both lanes read it before they start a work block).

Hard rules for both lanes (from the overnight plan; they win over anything below):
- Never write: TESTINSTALL, the live Steam game, the build-PC folders listed in the LOCAL `catalog\*.local.json` files
  (`forbidden_write_roots`), any `v64` or older folder
  (incl. `v64\installer\sb\_golden`, which is a READ-ONLY hard-link source), Luka's Downloads, the Recycle Bin,
  `clever_x_convergence_x_mckenyu_INF_DURATIONS\v64` (build64.py's own run folder is a v64 folder: use the vendored port).
- Code and outputs only under `...\clever_x_convergence_x_mckenyu\v65\` (exception: the Lucy recipe writes exactly
  `<Lucy workspace>\base\merge_v65<rc>[_nrm]` and `<Lucy workspace>\build\lucy_merge_v65<rc>[_nrm]`, as deploy_v65.py
  already does; the workspace folder and the recipe are build-PC settings in the LOCAL file
  `catalog\lucy_build.local.json`, never pushed).
  Docs only in `C:\$MD\EldenRing\merge\v65\`.
- Never kill processes by image name (only PIDs you started). Uninstall every test Apps entry you create.
- No web browsing. `gh`/`git` only for Luka's own repo. NEVER make a repo or release public (only `publish_github.py`
  does that, and only Luka runs it). Never post anywhere, never send email.
- Luka is asleep: never ask; decide by the design doc's assumptions and log every extra decision.

## 1. Lanes and ownership

| path (under `v65\installer\`) | owner | notes |
|---|---|---|
| `README_CONTRACT.md` | architect | this file |
| `catalog\catalog.src.json` | PIPELINE | hand-edited catalog source (architect wrote the v6.5 draft) |
| `catalog\CHANGELOG_v6.5.txt` | PIPELINE (text from the release-kit lane) | the main zip's `CHANGELOG.txt`; a file containing `PLACEHOLDER` is refused by `--final` |
| `release.py`, `publish_github.py`, `pipeline\**` | PIPELINE | Python 3.11 stdlib (+ subprocesses: py -3.14 for InfDur/Lucy, py -3.11 framework) |
| `upstream\convergence_302_manifest_v2.json` | PIPELINE | copied from `v64\installer\upstream\`, sha256 `823e8254...3ab3` |
| `generated\catalog.iss`, `generated\build_info.iss` | PIPELINE writes, INNO reads | never hand-edited |
| `staging\meta\CXCXM_conv302_manifest.txt` | PIPELINE writes, INNO reads | v6.4 format 2, unchanged (section 6) |
| `work\**`, `dist\**` | PIPELINE | scratch / release outputs; `work\products\<rc>\products.json` is a contract file (section 10) |
| `..\release.py` (= `v65\release.py`) | PIPELINE | 5-line forwarder to `installer\release.py` (the overnight plan names that path) |
| `output\`, `test_output\`, `codecheck_output\` | written by `pipeline\iscc.py` only | |
| `CXCXM_v65_Installer.iss`, `code\*.iss` | INNO | copied from `v64\installer\` and generalized (v64 is never edited) |
| `tests\**`, `sb\**` | INNO | harness, oracle, local HTTP server, fixtures, results |

The INNO lane may RUN `release.py` (e.g. `--emit-only`, `--build test`) but never edits pipeline files; the PIPELINE lane
never edits `.iss` files.

## 2. Commands (both lanes use exactly these)

```
cd C:\00000ConvergenceER\ClaudeWorkspace\clever_x_convergence_x_mckenyu\v65\installer
py -3.11 -X utf8 release.py --rc rc7 --all                # THE ONE COMMAND (final pass 2, pipeline\oneshot.py): build (exes reused
                                                          #   when BUILD_INPUTS.json matches) + test gate (only if no passing results
                                                          #   for this catalog + code) + site files + GitHub draft + --final gates +
                                                          #   publish check + release-kit drafts -> READY / NOT READY (exit 0 / 1)
py -3.11 -X utf8 release.py --rc rc7 --all --cold         # the same trusting no cache (re-hash, rebuild, re-test, download back)
py -3.11 -X utf8 release.py --rc rc7 --emit-only          # products (cached) + compose + generated\ + staging\meta + dist catalog; no zip, no ISCC
py -3.11 -X utf8 release.py --rc rc7 --build codecheck    # + ISCC /DCodeCheck  -> codecheck_output\
py -3.11 -X utf8 release.py --rc rc7 --build test         # + main zip + blob staging + ISCC /DTestBuild -> test_output\
py -3.11 -X utf8 release.py --rc rc7 --build release      # + ISCC release -> output\ and dist\v6.5.0\
py -3.11 -X utf8 release.py --rc rc7 --build all          # codecheck + test + release
py -3.11 -X utf8 release.py --rc rc7 --stage-github       # (after a build) repo files (1 commit) + DRAFT release + asset upload
py -3.11 -X utf8 release.py --rc rc7 --build release --final   # refuses TODO/INFERRED URLs, PLACEHOLDER changelog, missing test results, a published tag
py -3.11 -X utf8 publish_github.py --tag v6.5.0 --check            # read-only: all checks + what --publish would change
py -3.11 -X utf8 publish_github.py --tag v6.5.0 --verify-download  # read-only: every asset downloaded (gh login) + sha256
py -3.11 -X utf8 publish_github.py --tag v6.5.0 --verify-public    # read-only: anonymous HEAD of every asset URL + GET of every site file
py -3.11 -X utf8 publish_github.py --tag v6.5.0 --publish --confirm "PUBLISH v6.5.0"   # ONLY after Luka's explicit OK (decision T7)
py -3.11 -X utf8 tests\run_all.py --rc rc7 [--phase P2,...]   # INNO lane test runner (section 10)
```
`--rc` is REQUIRED (repair 1) and takes `rcN` (a folder `v65\opus\build\rcN`) or `auto` (highest N whose GATES.json
`fail == []`, whose `nrm_rcN_T2\NRM_LAYER_REPORT.json` passed and was made from that chain). Every output records the
RC used. `--final` runs its gates BEFORE anything is compiled or copied (a refusal leaves output\ and dist\ as they
were). Only runs that build the release write `dist\<tag>\BUILD_REPORT.json`; every run writes
`work\products\<rc>\BUILD_REPORT_<stamp>.json`.
ISCC: `%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe /Qp /DFromPipeline [/DCodeCheck|/DTestBuild] /O<dir> CXCXM_v65_Installer.iss`
(cwd = installer\, BELOW_NORMAL priority). From Git Bash set `MSYS_NO_PATHCONV=1` or the `/Q...` switches turn into paths.

## 3. generated\catalog.iss (PIPELINE writes; INNO consumes)

Encoding UTF-8 (no BOM), LF. Pascal string literals via `pascal_str` (v64 build.py): single quotes doubled, no CR/LF.
All hashes are lowercase hex SHA-256 (64 chars). Paths are relative to the Convergence folder, backslashes, no leading `\`.

### 3.1 Constants (exact names)
```
const
  CAT_FORMAT        = 1;
  CAT_VERSION       = '6.5.0';
  CAT_VERSION_SHORT = 'v6.5';
  CAT_MOD_TITLE     = 'Convergence X Clever X McKenyu v6.5';
  CAT_RC            = 'rc2';
  CAT_RELEASE_TAG   = 'v6.5.0';
  CAT_BUILD_STAMP   = 'YYYY-MM-DD HH:MM:SS';
  CAT_SHA256        = '<sha256 of dist\<tag>\catalog.json>';
  CAT_CHANGELOG_REL = 'CXCXM_CHANGELOG_v6.5.txt';
  CAT_NEXUS_URL     = 'https://www.nexusmods.com/eldenring/mods/10388';
  CAT_COMP_COUNT, CAT_STATE_COUNT, CAT_RULE_COUNT, CAT_PATH_COUNT, CAT_AFF_COUNT, CAT_TAB_COUNT, CAT_VAR_COUNT,
  CAT_ARCH_COUNT, CAT_PIN_COUNT, CAT_MEM_COUNT, CAT_BLOB_COUNT, CAT_URL_COUNT, CAT_NAT_COUNT, CAT_NATLINE_COUNT,
  CAT_DET_COUNT, CAT_OBS_COUNT, CAT_FIELD_COUNT, CAT_CREDIT_COUNT  = <integers>;
  CAT_C_<ID> = <component index>;   { one per component, ID upper-case: CAT_C_MAIN, CAT_C_CONV, CAT_C_CLEVER, CAT_C_MCK,
                                      CAT_C_LUCY, CAT_C_NRM, CAT_C_INFDUR, CAT_C_ARROWS, CAT_C_SEAMLESS, CAT_C_ERCAP, CAT_C_DMN }
  WALL_BASE         = <clip-list total of MAIN alone>;      { rc2: 31452 }
  WALL_LIMIT_NODLL  = 32768;
  WALL_LIMIT_DLL    = 65000;
  WALL_DLL_COMP     = CAT_C_ERCAP;                           { -1 when the catalog has no such component }
  MAX_REL_LEN       = <longest relative file path any variant/obsolete/field/user path writes>;
  MAX_REL_DIR_LEN   = <longest relative folder of those>;
  CONV_MANIFEST_FILE  = 'CXCXM_conv302_manifest.txt';
  CONV_MANIFEST_MAGIC = 'CXCXM-CONV302-MANIFEST 2';
  CONV302_FILE_COUNT  = <files in the pristine folder>;      { 4265 }
```

### 3.2 Global arrays (INNO declares them in `code\globals.iss` with EXACTLY these names/types; `InitCatalog` fills them)

Components, index `c` (array order = catalog order; required components first is NOT assumed):
| array | type | meaning |
|---|---|---|
| `CompId` | TArrayOfString | lower-case id (`main`, `lucy`, ...) |
| `CompSwitch` | TArrayOfString | command-line switch name (`LUCY`), `''` = none (R components) |
| `CompTitle` / `CompDesc` | TArrayOfString | wizard caption / one-line description |
| `CompKind` | TArrayOfString | `R` required (state always 1), `T` toggle (states 0/1), `C` choice (n states), `X` disabled placeholder (state always 0, shown greyed) |
| `CompExperimental` | array of Boolean | caption gets ` (experimental)`; Ready page warns |
| `CompDefault` | array of Integer | state when detection finds nothing |
| `CompStateCount`, `CompStateStart` | array of Integer | states of c are `CompStateStart[c] .. +CompStateCount[c]-1` in the State* arrays |
| `CompCredit` | TArrayOfString | credit line (`''` none) |
| `CompSourceText` | TArrayOfString | human source: `your download (Nexus)`, `downloaded from GitHub`, `your existing install` |

States, index `CompStateStart[c] + s`:
| `StateCode` | TArrayOfString | switch value, lower-case: toggles `0`/`1`, InfDur `none`,`v1`..`v4` |
| `StateTitle` | TArrayOfString | wizard text |
| `StateWall` | array of Integer | clip-list delta of this state against MAIN alone (rc2: nrm state 1 = +67, all others 0; dmn placeholder 310) |
| `WallComboComp`, `WallComboTotal` | array of Integer | additive extension (rc8 switch prep, CAT_FORMAT 2 unchanged): the component indexes of the animation-touching options and the MEASURED clip-list total of every combination of their states (the first one's state counts fastest); empty = the additive model. catalog.json `wall.combo_comps` / `wall.combo_totals` |

Rules, index `r`:
| `RuleKind` | TArrayOfString | `Q` requires, `X` conflict, `W` warning, `D` (2026-10-03) A and B together need the DLL component `WALL_DLL_COMP` (switched on by itself; `RuleText` = the reason the Options page shows next to its locked check box) |
| `RuleA`, `RuleB` | array of Integer | component indices |
| `RuleAMask`, `RuleBMask` | array of Integer | bit s set = state s of that component is in the set |
| `RuleText` | TArrayOfString | shown to the player and logged |

Paths, index `p`:
| `PathRel` | TArrayOfString | relative path |
| `PathFlags` | TArrayOfString | `U` = user config (written only when missing, never removed when its component turns off, verified by existence only); `''` = normal |
| `PathOwner` | array of Integer | component that owns the path (texts, empty-folder cleanup) |
| `PathAffStart`, `PathAffCount` | array of Integer | the components whose states pick this path's content: `AffComp[PathAffStart[p] .. +PathAffCount[p]-1]` |
| `PathTabStart` | array of Integer | first entry of this path's table in `PathTab` |
| `AffComp` | array of Integer | component indices |
| `PathTab` | array of Integer | `>= 0` variant index; `-1` the file must NOT exist; `-2` leave the file as it is (unmanaged in this state) |

Key rule: `key = sum_i state(AffComp[PathAffStart[p]+i]) * stride_i`, `stride_0 = 1`,
`stride_(i+1) = stride_i * CompStateCount[AffComp[PathAffStart[p]+i]]`; the table has `prod CompStateCount` entries;
`DesiredVariant(p) = PathTab[PathTabStart[p] + key]`. `PathAffCount[p] = 0` means a one-entry table.

Variants, index `k`:
| `VarPath` | array of Integer | its path |
| `VarSha` | TArrayOfString | expected sha256; `''` = dynamic: the expected content is whatever the accepted mode-V archive member holds (set at run time) |
| `VarSize` | array of Int64 | bytes; `-1` for dynamic variants |
| `VarSrc` | TArrayOfString | `A` = archive member `VarRef[k]`; `B` = hosted blob `VarRef[k]` |
| `VarRef` | array of Integer | member or blob index |

Archives (the player's downloads), index `a`; members index `m`; pins index `i`:
| `ArchId` | TArrayOfString | `main_v65`, `clever_262`, `mck_14`, `seamless`, `dmn`, `nrm_02` (the catalog's enabled archives, in order) |
| `ArchComp` | array of Integer | component that needs it when its state >= 1 (R components: always) |
| `ArchTitle`, `ArchAuthor`, `ArchHint` | TArrayOfString | page texts |
| `ArchNexusUrl` | TArrayOfString | `''` = unknown (button hidden; the page shows the title to search for) |
| `ArchNameHints` | TArrayOfString | lower-case substrings joined by `|`, used to pick archive candidates by file name |
| `ArchMode` | TArrayOfString | `P` every member pinned by sha256; `V` any version: members must exist, their bytes become the variants' expected content |
| `ArchMustVerify` | array of Boolean | needed even when all its files are in place, unless the folder's marker lists it under `VERIFIED_ARCHIVES` |
| `ArchGlobs` | TArrayOfString | `|`-joined tar `--include` patterns, already in case-insensitive bracket form (`*[Pp][Aa][Rr][Tt][Ss]*...`) |
| `ArchPinStart`, `ArchPinCount` | array of Integer | whole-archive files known byte for byte (fast detection by size, then sha256) |
| `PinSize` / `PinSha` | array of Int64 / TArrayOfString | |
| `ArchMemStart`, `ArchMemCount` | array of Integer | its members |
| `MemArch` | array of Integer | |
| `MemName` | TArrayOfString | file name; candidates = files with this name (case-insensitive) at any depth below the extraction/folder root |
| `MemTail` | TArrayOfString | reference path inside the pack (display, tie-break only) |
| `MemSha` / `MemSize` | TArrayOfString / array of Int64 | pinned content; mode V: `MemSha` = the TESTED version's sha256 (repair 1; never a requirement, only the "tested version" verdict), `MemSize` `-1` |

A mode P archive may list verify-only members (`archives[].verify_members` in catalog.src.json): members no variant
uses, which must be present (by name + sha256) for the archive to be accepted - files only the author's own pack has
(mck_1313: `Start_McKenyu_Modpack.bat`), so a package that merely carries copies of his files is refused.

Blobs (hosted files), index `b`; download URLs:
| `BlobSha`, `BlobSize` | TArrayOfString / array of Int64 | |
| `BlobAsset` | TArrayOfString | asset file name: `<sha256[0:16]>-<sanitized basename>` |
| `BlobTag` | TArrayOfString | release tag folder (`v6.5.0`; a later version may point at an older tag to reuse an unchanged asset) |
| `BlobUpstream` | TArrayOfString | absolute URL tried FIRST unless `/UPSTREAM=0` (ERCap: the author's release asset), `''` none |
| `BlobSite` | TArrayOfString | CAT_FORMAT 2: `''` = the release mirrors (`BaseUrls`); else the root URL of another download site, ending in `/`; URL = `BlobSite[b] + BlobTag[b] + '/' + BlobAsset[b]`, that site only. Since 2026-10-03 (release prep) the pipeline makes no such blob: always `''` |
| `BaseUrls` | TArrayOfString | mirror roots, each ending in `/`; URL = `BaseUrls[i] + BlobTag[b] + '/' + BlobAsset[b]`; `/BASEURL=` replaces the whole list - and, since CAT_FORMAT 2, every site root too (`BaseUrlsReplaced`: tests serve every site from one local server) |

me3 natives (array order = append order; the last one is appended last):
| `NatComp` | array of Integer | component whose state >= 1 puts this block in BOTH profiles |
| `NatMatch` | TArrayOfString | squeezed substring; every `[[natives]]` table whose path line contains it belongs to this native |
| `NatPath` | TArrayOfString | our exact path line, squeezed (`path='./../mod/dll/capacityexpansion.dll'`) |
| `NatForeign` | TArrayOfString | `R` = v6.3 arrows rule (one foreign table is re-pointed at ours, two or more = refuse); `S` = strip every matching table; `K` (repair 2) = as `S` while the component is on, only our exact table while it is off (the player's own copy at another path stays) |
| `NatLf` | array of Boolean | a profile that carries this block is written LF + final LF (v6.4 NRM rule) |
| `NatLineStart`, `NatLineCount` / `NatLine` | array of Integer / TArrayOfString | the block, line by line; its `#` lines directly above its header are part of it when stripping |
| `PristineMe3Lines0`, `PristineMe3Lines1` | TArrayOfString | stock `me3\convergence.me3` / `me3\convergence - seamless.me3` (CRLF split, no final break) |

Detection (presets; evaluated in array order, the first matching rule of a component sets its state; none -> `CompDefault`):
| `DetComp` | array of Integer | |
| `DetKind` | TArrayOfString | `F` file `DetArg` exists; `N` an active line of either .me3 profile, squeezed, contains `DetArg`; `H` file `DetArg` has sha256 `DetSha` |

Repair 3 (verifier 4 D2): the pipeline makes `F` rules only for names a component declares as its alone
(`components[].detect_files` in catalog.src.json; Lucy: her armor set 3360) and for mode V members (any version of that
author's file); every other own file is detected by `H` (every v6.5 variant and every older release's content of up to
3 of its paths). `H` rules also list every older release's content of any other path only that component writes: the
installer's "own content" of a catalog path = its variants' sha256 + the `H` rules of that path (+ any content for a
path whose variants are dynamic).
| `DetArg`, `DetSha` | TArrayOfString | |
| `DetState` | array of Integer | |

Obsolete files (older releases' files this release does not have):
| `ObsRel`, `ObsSha`, `ObsNote` | TArrayOfString | removed (backed up, kind B) when present and (`ObsSha = ''` or its sha256 matches); several rows per path allowed |

Fields (values the player types; written into an ini after the files):
| `FieldComp` | array of Integer | |
| `FieldId`, `FieldSwitch`, `FieldLabel`, `FieldRel`, `FieldSection`, `FieldKey` | TArrayOfString | |
| `FieldSecret` | array of Boolean | value never logged, never written to the marker |

Credits: `CreditComp: array of Integer` (`-1` = always shown) and `CreditText: TArrayOfString`.

### 3.3 Procedures (generated)
`procedure InitCatalog;` (fills every array above with `SetArrayLength` then assignments; may be split into
`InitCatalog1..n` called by `InitCatalog` if one routine gets too long). `procedure InitConvManifestNames;` is NOT
generated (the conv manifest stays a data file, section 6).

### 3.4 Example (shape only; values illustrative)
```
const
  CAT_FORMAT = 1;
  CAT_COMP_COUNT = 2;
  CAT_C_MAIN = 0;
  CAT_C_ARROWS = 1;
  ...
procedure InitCatalog;
begin
  SetArrayLength(CompId, 2); SetArrayLength(CompKind, 2); { ... every array ... }
  CompId[0] := 'main'; CompSwitch[0] := ''; CompKind[0] := 'R'; CompDefault[0] := 1; CompStateCount[0] := 2; CompStateStart[0] := 0;
  CompId[1] := 'arrows'; CompSwitch[1] := 'ARROWS'; CompKind[1] := 'T'; CompDefault[1] := 0; CompStateCount[1] := 2; CompStateStart[1] := 2;
  StateCode[0] := '0'; StateCode[1] := '1'; StateCode[2] := '0'; StateCode[3] := '1';
  PathRel[0] := 'mod\regulation.bin'; PathFlags[0] := ''; PathOwner[0] := 0; PathAffStart[0] := 0; PathAffCount[0] := 0; PathTabStart[0] := 0;
  PathTab[0] := 0;
  PathRel[1] := 'mod\dll\infinite_arrows.dll'; PathFlags[1] := ''; PathOwner[1] := 1; PathAffStart[1] := 0; PathAffCount[1] := 1; PathTabStart[1] := 1;
  AffComp[0] := 1;
  PathTab[1] := -1; PathTab[2] := 1;
  VarPath[0] := 0; VarSha[0] := '<64 hex>'; VarSize[0] := 3049536; VarSrc[0] := 'A'; VarRef[0] := 0;
  VarPath[1] := 1; VarSha[1] := '<64 hex>'; VarSize[1] := 167424; VarSrc[1] := 'B'; VarRef[1] := 0;
  BlobSha[0] := '<64 hex>'; BlobSize[0] := 167424; BlobAsset[0] := '0123456789abcdef-infinite_arrows.dll'; BlobTag[0] := 'v6.5.0'; BlobUpstream[0] := '';
  BaseUrls[0] := 'https://github.com/LukaTheHero/Convergence-X-Clever-X-McKenyu/releases/download/';
end;
```

## 4. generated\build_info.iss
```
#define CatFormat 1
#define CatVersion "6.5.0"
#define CatRc "rc2"
#define CatSha256 "<sha256 of catalog.json>"
#define BuildStamp "YYYY-MM-DD HH:MM:SS"
#define InstallerBaseName "Convergence X Clever X McKenyu V6.5 - Auto Installer"
#define VersionInfo "6.5.0.0"
```
`CXCXM_v65_Installer.iss` must `#error` unless `FromPipeline` is defined and `CatFormat == 1`.

## 5. Runtime semantics the INNO code must implement (the pipeline relies on them)

1. Selection: `ChosenState[c]`. R -> 1, X -> 0 always. Sources in order: detection presets (section 3.2 Detection),
   then `/COMPONENTS=` (alias `/SELECT=`), then per-component switches (`/<CompSwitch>=<StateCode>`; toggles also accept
   0/1/yes/no/true/false/on/off), then the wizard. `/COMPONENTS=` lists `id` (state 1) or `id:code`; every optional
   component not listed is set to 0; `none` = all optional off. A switch for an X component with a non-zero state is refused.
2. Normalize (wizard Next on Options, and silent start): rules `Q` (auto-set B to the lowest state in RuleBMask, with a
   note; refused in silent mode when B was given explicitly), `X` (refuse), `W` (warn on Ready + log). Wall:
   `WallTotal = WallComboTotal[index of the animation options' states] + sum StateWall[state] of the other options` (WallComboTotal empty: `WALL_BASE + sum StateWall[state]`); above `WALL_LIMIT_NODLL` (test builds: `/TESTWALLLIMIT=n` replaces it)
   the DLL component is forced to 1 (refused if it was explicitly 0); above `WALL_LIMIT_DLL` refuse.
   `D` rules (2026-10-03), before the wall: A and B both in their masks -> the DLL component is switched on (refused in
   silent mode when it was given explicitly, e.g. `/ERCAP=0` or `ercap:0` in `/COMPONENTS`; not listed in `/COMPONENTS`
   is not explicit), log `CXCXM RULE D <text> (<dll id> switched on)`, a Ready-page note. A DLL switched on ONLY because
   the selection needs it (a D rule or the wall; the player's own state was off) is `DllAuto`: Ready page / marker
   "yes (added automatically: <reason>)", `WALL ... dll=forced`, log `CXCXM AUTO_ON <id> (<reason>)`, `AUTO_ON=<id>` in
   the marker and the backup manifest. Presets: when the last finished run's marker (or, after a hard stop, the resumed
   backup's manifest) lists the DLL under `AUTO_ON` and the detection found it on, its preset is OFF (the player never
   ticked it): a selection that still needs it switches it on again, one that dropped DMN or NRM removes it. Every
   normalisation starts from the player's own state (`DllOwn`), so a second check never takes the switch-on for his
   choice. Wizard (pages.iss `UpdateDllLock`): while the ticked options need the DLL (`DllNeededReason`: the first D
   rule that holds, else the wall), its list line is ticked, greyed and captioned `<short title> - <reason>`
   (`ERCapacityExpansion - needed so DMN and Nightreign's Wylder fit together`); unticking A or B releases it to the
   player's own tick (log `CXCXM OPTIONS <id> locked on: ... / released: ...`).
3. Archive needed = its component's state >= 1 AND (some variant `k` with `VarSrc='A'`, member in this archive, is wanted
   and not in place, OR (`ArchMustVerify` and the marker does not list it)). In place = file exists, size and sha256 equal
   (dynamic variants: file exists; `U` paths: file exists).
4. Accepting an archive (file or folder): extract (archive) with `{sys}\tar.exe` fed on stdin with `ArchGlobs`, falling back
   to `ExtractArchive` (ArchiveExtraction=full), into `<Conv>\CXCXM_work\a<index>\` (fallback `{tmp}`); folders are used in
   place; Convergence folders below the root are never entered. Every member resolves to a candidate with the same name
   whose sha256 = `MemSha` (mode P) or that exists (mode V; then `VarShaRt[k]` := its sha256 for every variant sourced
   from it). All members found -> accepted. Pinned whole-archive files (`PinSize`/`PinSha`) are detected by size, then sha256.
   A download-search candidate that is not pinned may unpack to at most 8x its size + 256 MB (repair 3): tar's `-t -v`
   listing first, each entry counted as the LARGEST number of its line (owner/group names may hold blanks; repair 4); a
   listing that fails means tar is not used for that candidate (the built-in extractor stops at the cap; repair 4).
5. Fetch (wizard: Install click on Ready, inside the download page; silent: PrepareToInstall), BEFORE the backup: every
   wanted, not-in-place `B` variant is downloaded once per blob into `{tmp}\cxcxm_blobs\` with Inno's SHA-256 check;
   URLs tried: `BlobUpstream` (if any and `/UPSTREAM` is not 0), then each `BaseUrls` entry. Any failure = nothing changed.
6. Plan / backup / restore = v6.4 model (kinds B N E D M, SEQ order, manifest magic 1/2) extended with: obsolete files (B),
   field ini edits (B when the ini existed), user-config paths (N only when this run creates them), all catalog natives in
   the E logic (an entry "of ours" = any native table of the catalog). Repair 4 (code review, D2 at the uninstall): the
   uninstall (a full restore) deletes an `N` file at a catalog path that an option writes only while it is on (no user
   config) only while it holds one of the catalog's own contents for that path (a variant, an `H` rule of it, any
   content for a path of a mode V archive); any other content (a body or face mod the player put over one of Lucy's
   files) stays, listed in the uninstall log and its final message. Every other `N` file (the merge's own paths, which
   every selection writes - an older release's content there included -, user configs, the marker) is deleted as
   before, and a rollback of the running Setup deletes every `N` file it created.
   Repair 5 (sixth verifier DEFECT 1, crash safety): EVERY file Setup or the uninstaller writes in the Convergence
   folder (new ones too: catalog files, backup copies, restored files, profiles, ini fields, the marker) goes to
   `<name>.cxtmp` first, is flushed to the disk (FlushFileBuffers) and then moved to its name (MoveFileEx), so a Setup
   or uninstall stopped hard (TerminateProcess = Task Manager, a crash, a power cut) leaves each file either as it
   was or complete; the backup manifest is flushed before its rename. Stale `<path>.cxtmp` files next to any path a
   run writes (catalog paths, obsolete files, field inis, both profiles, the marker, every path of every backup
   manifest - the manifests are the journal of what a run writes) are deleted by Setup right after the Install click
   (before its plan) and by the uninstaller before it restores; the foreign-file scan never lists them. Other mods'
   files (`M`) are moved at the start of the post-install step, after Inno registered the uninstaller, so a Setup
   stopped after its first change can always be uninstalled. Each run writes a journal `CXCXM_RUN_UNFINISHED.txt`
   into its backup folder right before its first change and deletes it when its post-install step ends; when the
   NEWEST backup folder still holds one, that run was stopped and its `SELECTION` is the preset (before the command
   line; log `CXCXM RESUME <stamp> <selection>`, a Ready-page note). A restored backup folder loses its manifest first
   (a stop while it is deleted leaves a folder without a manifest = a partial one, deleted by every later run); a
   restored folder whose manifest cannot be deleted stops the walk. Setup deletes the `cxcxm_blobs` downloads of
   stopped Setups in the other `%TEMP%\is-*.tmp` folders (one Setup at a time: SetupMutex). The longest backup path
   check counts the `.cxtmp` suffix.
7. Install (ssPostInstall, in order): write every wanted not-in-place variant (copy from its source), delete `-1` paths
   that hold one of the catalog's own contents for that path (repair 3; another content is another mod's file: an `M`
   entry with `/FOREIGN=move` - not for mod\dll, paths too long for the backup or unsafe names -, else kept; listed on
   the Ready page, in the log and the marker; backed up) + obsolete files, remove empty folders they leave (never `mod\` itself), me3 profiles,
   fields, marker, verification of every path/native/field, rollback offer on failure (v6.4 texts and exit codes).
8. me3 (repair 3, verifier 4 D1: lines are read in their TOML context - a table runs from its header, which may carry a
   trailing `# comment`, to the next header; multi-line arrays with blank lines and comments belong to their key; taking
   a table out removes its header down to its last key/continuation line, keeps the comments and blank lines after that
   and every comment above it that is not a line of our block; a profile that is not readable TOML, an edit that would
   not be, or an edit that would change any table that is not a catalog native's is refused before anything changes;
   after writing, a rewritten profile must still be readable, keep every other table as it was, and pass me3's own
   `me3\Windows\me3.exe profile show` (a copy in {tmp}, md5-checked against the 3.0.2 manifest, never in an elevated
   Setup); the kind E uninstall puts the saved copy back whole when taking our entries out would leave an unreadable
   profile). Repair 4 (fifth verifier, code review D1 residual): an ENTRY is a `[[natives]]` (or `[[package]]`) table
   plus every sub-table TOML puts inside it - a header with two or more key parts whose first part names a list of
   tables declared above it (`[natives.initializer]`, `[[natives.load_after]]`, `[package.x]`); taking an entry out (or
   switching another mod's package off) takes all of it, and "every other table unchanged" compares entries with
   their sub-tables; headers and keys are read as TOML keys (quoted parts `[["natives"]]`, `"path" = ...`); readable
   also means no table defined twice, no name both a table and a list of tables, no key repeated (dotted keys
   included), no sub-table header naming a key its entry already has, and not both names of one of me3's aliases
   (`natives`/`native`, `packages`/`package`: me3 0.13.0 refuses such a profile, "duplicate field"; a profile written
   with `[[native]]` is therefore never edited to add `[[natives]]` entries):
   Repair 5 (sixth verifier DEFECT 2): a profile Setup cannot read is refused also when nothing of ours would change in
   it; a multi-line string closes with a run of 3-5 quotes (6+ = refused); an escape in a quoted key or header, and a
   path line whose basic string has a `\u`/`\U` escape or whose multi-line string runs over several lines, are refused; natives headers
   are compared case-sensitively (`[[Natives]]` is no natives table: me3 0.13.0 ignores it) and `[[native]]` (me3's
   alias) is read as natives (taking our entries out works; adding is still refused, both names); and wherever
   me3.exe may run (not elevated, not the uninstaller), me3's own `profile show` must list the same natives as Setup
   reads (each one = the catalog native its path names, or "other"; sorted) - checked BEFORE Setup acts on a profile
   (refusal, exit 1 in a silent run, log `CXCXM ME3READ differs ...`) and after it wrote one (verification).
   strip every catalog native's tables (per `NatMatch`/`NatForeign`; `K` while off: only our exact table), then append the blocks of every native whose
   component is on, in array order, after one blank line; inline `natives = [` list + any of ours on = refuse. Canonical
   writing as v6.4 (stock lines -> stock bytes; a profile with a `NatLf` block -> LF + final LF; else UTF-8 CRLF).
9. Fields: only when the component is on and a non-empty value was given: in `[FieldSection]` replace the value of the
   first `FieldKey =` line (keep `key = ` spacing, keep every other byte), append the line to the section if missing.

## 6. staging\meta\CXCXM_conv302_manifest.txt
Exactly v6.4's format 2 (`CXCXM-CONV302-MANIFEST 2`, `F|flag|size|md5|path`, `K|`, `V|` lines; v64 build.py
`conv_manifest()`/`write_conv_manifest()`), regenerated: flag `O` = every path any v6.5 variant, obsolete row, user
config or field writes. Stays MD5 (check B is proven code; do not migrate it). Embedded `[Files] ... Flags: dontcopy`.

## 7. Command line, exit codes, log lines

Switches (ours; Inno's own `/SILENT /VERYSILENT /SUPPRESSMSGBOXES /LOG= ...` as usual). Parse with `ParamStr` (not
`{param:}`) so values may contain any character:
`/CONVDIR=` `/COMPONENTS=` (`/SELECT=`) `/<CompSwitch>=` (LUCY NRM INFDUR ARROWS SEAMLESS ERCAP DMN; final pass: DMN enabled)
`/ARCHIVEDIR=` `/ARCHIVE_<ARCHID upper>=` (`/CLEVER=` = `/ARCHIVE_CLEVER_262=`) `/SEARCHDOWNLOADS=0|1` (silent default 0)
`/BASEURL=` `/UPSTREAM=0|1` `/<FieldSwitch>=` (`/COOPPASSWORD=`) `/FOREIGN=move|keep` `/GAMEOK=1`.
Repair 1 runtime rules: (a) every extraction gets a work folder name never used before in the run, and the hash
cache forgets every file below a folder that is made or deleted; (b) mode V members come from ONE package folder
(the folder holding the most members, by the longest shared path end with the reference path); (c) the download
SEARCH takes a mode V archive by itself only when it is the tested version (pinned file, or every non-user-config
member equals `MemSha`); any other version must be chosen explicitly (wizard: Select archive/folder; silent:
`/ARCHIVE_<ID>=`); search candidates are ranked newest first, folders and archives together; (d) archives found by
name are tried best hint score first (summed length of the matching hints), then newest, at most 6; (e) a field whose
ini Setup never edits (not UTF-8, unreadable) is refused before anything changes (silent: exit 1, log
`CXCXM FIELD <id> refused <reason>`); (f) every catalog path is checked with IsSafeRelPath at start-up (exit 1).
Test builds only: `/TESTGAMEONLY /TESTGAMEBROWSE= /TESTDLSEARCH /TESTCHECKSONLY /TESTLAYOUT /TESTDOWNLOADS=<dir>
/TESTWALLLIMIT=<n> /TESTFETCHONLY=1 /TESTASADMIN=1` (repair 3: the elevated paths without a UAC prompt)
`/TESTME3EXE=<me3.exe>` (repair 5: the me3 reader cross-check in /TESTUNIT runs, which have no Convergence folder), `/TESTNOTAR=1` (repair 6: the built-in extractor only). A switch that is not ours but shares its first three letters with one of ours (and
is not an Inno switch) is refused, as is one of ours without a value (v6.4 rule). Measured 2026-10-01: Inno ignores
`/COMPONENTS=` when the script has no `[Components]` section and the value reaches the code.

Exit codes: 0 ok; 1 validation failed before anything changed (InitializeSetup; incl. missing/wrong archives in silent
mode); 7 refused at Preparing (incl. any download/fetch failure; nothing changed); 20 verification failed, rolled back;
21 failed, kept; 22 post-install step failed. Uninstaller as v6.4.

Log lines (exact prefixes, one line each; tests grep them):
```
CXCXM SELECTION <id>=<code> <id>=<code> ...            (after normalization, all components, catalog order)
CXCXM WALL total=<n> limit=<n> dll=<off|on|forced>
CXCXM RULE <W|Q|X|D> <text>                             (D: '... (<dll id> switched on)' / '(refused: ...)')
CXCXM AUTO_ON <dll id> (<reason>)                       (2026-10-03: the DLL is on only because the selection needs it)
CXCXM OPTIONS <dll id> locked on: <reason> (your own choice: yes|no)   |   ... released: back to your own choice (..)
CXCXM ARCHIVE <archid> <accepted|in-place|not-needed|missing|rejected> <path or reason>
CXCXM FETCH <asset> <ok|fail> <url> [reason]
CXCXM FETCH DONE files=<n> bytes=<n>   |   CXCXM FETCH FAILED <reason>
CXCXM PLAN entries=<n> backup=<bytes> write=<bytes>
CXCXM VERIFY PASSED checks=<n>   |   CXCXM VERIFY FAILED problems=<n>
CXCXM STALETEMP deleted=<n>                              (repair 5: Setup before its plan, the uninstaller before it restores)
CXCXM RESUME <backup stamp> <id>:<code>,...              (repair 5: the newest backup's run was stopped; its options preset)
CXCXM ME3READ differs <profile>: me3 [..] Setup [..]     (repair 5: me3's own reader lists other natives than Setup reads)
```

## 8. Marker `CXCXM_INSTALLED.txt` (format 3) and backup manifest
Marker: first lines machine-readable, then a blank line, then the v6.4-style human text (+ credits of every installed
component):
```
CXCXM-MARKER 3
VERSION=6.5.0
RC=rc2
CATALOG_SHA256=<CAT_SHA256>
SELECTION=main:1,conv:1,clever:1,mck:1,lucy:0,nrm:1,infdur:v2,arrows:1,seamless:0,ercap:0,dmn:0
AUTO_ON=<dll id | empty>      (2026-10-03: the ids this run switched on only because the selection needs them)
VERIFIED_ARCHIVES=clever_262,mck_14,nrm_02
SEAMLESS_VERSION=<tested 1.9.9 | not a tested version (ersc.dll sha256 ...)>     (only when seamless is on)
RESULT=PASSED|FAILED
```
Backup manifest: v6.4 format (magic 1, or 2 with M entries), header keys `SEQ CREATED CONVERGENCE_DIR CONVERGENCE_VERSION
INSTALLER=6.5.0 SELECTION=... AUTO_ON=... FOREIGN=` (AUTO_ON since 2026-10-03; readers skip unknown header keys). AppId formula unchanged (`CanalpaCXCXM_` + md5(lower(ConvDir))[0:16]), so v6.5
takes over v6.3/v6.4 Apps entries and its uninstaller walks all their backups newest first.

## 9. Hosting layout
- Release staging: `dist\<tag>\github\<tag>\<BlobAsset>` (exactly the assets of the catalog, nothing else).
- Local test server (tests\httpserve.py): root = `dist\<tag>\github`, so `/BASEURL=http://127.0.0.1:<port>/` + `<tag>/<asset>`
  resolves. Fault switches: `--missing <asset>`, `--corrupt <asset>`, `--slow`.
- `dist\<tag>\`: `<main zip>`, `catalog.json`, `BUILD_REPORT.json`, `repo\` (README.md, CREDITS.md, LICENSE-NOTES.md,
  .gitignore, LICENSES\ERCapacityExpansion-MIT.txt, releases\<tag>\ASSETS.md), the installer exe(s) copied from
  output\ (release) for Luka.
- GitHub repo tree (one commit per change, `pipeline\ghstage.py`): `dist\<tag>\repo\*` + `releases/<tag>/catalog.json` +
  `releases/<tag>/SOURCE.json` + `installer/` (the .iss, code\*.iss, release.py, publish_github.py, this contract,
  pipeline\, catalog.src.json + the changelog source). Text files only, content-scanned (no user path, user name,
  token, key, LAN address or e-mail); tests\, logs, builds and game files never go into git.
- Other download sites: none since 2026-10-03 (release prep). The second site (Nightreign Movement beta.16's own files
  on canalpa.com, only for this installer) was retired when NRM 0.2 became the player's own Nexus download: the
  pipeline's site step and `catalog.src.json` `sites` / `hosted` are gone (the loader refuses them), every blob is a
  GitHub release asset, `BlobSite` stays `''` (the installer still reads the field).
- GitHub: repo `LukaTheHero/Convergence-X-Clever-X-McKenyu`, PRIVATE until publish; release `v6.5.0` DRAFT until publish.
  Assets = the blobs only (never the main zip, never the exe, never any Clever/McKenyu/DMN/NRM/Seamless author file).
  The exe downloads `base_urls[0] + <tag> + "/" + <asset>` = `https://github.com/LukaTheHero/Convergence-X-Clever-X-McKenyu/
  releases/download/v6.5.0/<asset>`; these URLs answer only after `publish_github.py --publish` (a draft's assets are
  private: anonymous requests get 404, measured by tests\release_exe_default_url.py).

## 10. Tests (INNO lane) - result file
`tests\results\<tag>_<rc>_<build>.json` = `{"exe": path, "exe_sha256", "catalog_sha256", "rc", "started", "finished",
"phases": {"P2": {"pass": n, "fail": n, "cases": [{"name", "ok", "details"}]}, ...}, "golden_ok": true|false}`.
`release.py --final` requires a results file for the current `catalog_sha256` with every phase fail = 0 and golden_ok.
Repair 1: the file also carries `code_fingerprint` (pipeline\codefp.py: sha256 over CXCXM_v65_Installer.iss,
code\*.iss, generated\*.iss without their stamp lines, staging\meta manifest), `exe_code_fingerprint` (read from the
tested exe) and `complete`; `--final` and `publish_github.py` accept only a complete P0-P9 result whose
`code_fingerprint` is the one the release exe was compiled from. ISCC gets `/DCodeFp=<fingerprint>`; every exe
carries `<version> cat <16 hex of the catalog sha256> code <16 hex of the code fingerprint>` as its ProductVersion
string (Inno keeps 50 characters), and the release build writes `dist\<tag>\RELEASE_EXE.json` (exe sha256, catalog
sha256, code fingerprint). `publish_github.py --check-only` checks the exe itself, the sidecar, the draft assets and
the --final gates.
The oracle (`tests\oracle.py`) must not read `generated\` or reuse `pipeline\compose.py`; it rebuilds expected folder states
from the raw inputs (pristine Convergence, RC build chain, NRM layer, Lucy builds, `work\products\<rc>\` InfDur
outputs, Clever/McKenyu reference folders, the authors' zips, the Seamless/NRM zips). It may read `catalog.json` only for
component ids, kinds, state codes, fields, native blocks and archive ids, and (repair 3) `catalog.src.json` only for the
raw declarations: `components[].files` (dest, the author's zip, the member), `user_config`, `archives` and a mode V
archive's `members`. A component that is on and none of these describe makes the oracle fail.
Repair 3: the results file also carries `coverage` = {`verified_uninstalled`: every "id:code" pair of a passing
install whose sandbox was then uninstalled to its expected folder, `required`, `missing`, `passing_installs`};
`--final` and publish_github.py need every non-X pair (`checks.required_pairs`).

`work\products\<rc>\products.json` (PIPELINE writes; the oracle reads it to LOCATE built inputs, never composed results):
```
{"rc": "rc2", "chain": [<build dirs, newest first>], "base": "<v65\\opus\\build\\base>",
 "nrm_layer": "<dir>", "nrm_ini": "<file>", "nrm_block": "<natives_block_nrm.toml>",
 "lucy": {"plain": "<...\\lucy_merge_v65rc2\\mod>", "nrm": "<...\\lucy_merge_v65rc2_nrm\\mod>", "regulation_canonical": "<file>"},
 "infdur": {"plain": {"v1": "<regulation.bin>", ...}, "lucy": {"v1": ..., ...}},
 "arrows_dll": "<file>", "ercap": {"dll": "<file>", "license": "<file>"},
 "convergence_pristine": "<dir>", "references": {"clever_262": "<dir>", "mck_1313": "<dir>", "nrm_b16": "<zip>", "seamless": "<zip>"},
 "main_zip": "<dist\\v6.5.0\\...Main Files.zip>", "wall": {"main": 31452, "main+nrm": 31519}}
```

## 11. Measured reference numbers (architect, rc2, 2026-10-01; scripts in the architect's scratchpad, see the design doc)
MAIN = 133 paths (1016.7 MB). Sources: McKenyu archive 83 paths (80 same path + 3 from `mod\parts\wp_a_5071.partsbnd.dcx`,
446.7 MB), Clever archive 1 non-part (`mod\chr\c0000_a00_hi.anibnd.dcx`, 11.7 MB) + his 50 parts, main zip 49 paths
(558.3 MB). NRM layer 45 files: 22 identical to NRM zip members (1.3 MB), 23 merged (hosted). Hot paths 200; affects:
none 96, lucy 57, nrm 31, lucy+nrm 15 (menu_dlc02), lucy+infdur 1 (regulation, 10 variants). About 282 variants for the
hot components; hosted distinct blobs ~81 / ~512 MB (Lucy ~375 MB, NRM merged ~92 MB, Convergence originals 45 MB,
InfDur ~24 MB). Wall: MAIN 31,452, MAIN+NRM 31,519 (under 32,768: ERCap is never forced by v6.5's own options).

## 12. Contract change log
- DMN + Wylder, ERCapacityExpansion added automatically (2026-10-03 evening, Luka's decision after his field test of
  RC8 + NRM 0.2 WITH Wylder + DMN + ERCap: "everything positive"; CAT_FORMAT 2 unchanged, no new array - a new
  `RuleKind` value and a new marker / manifest line, both additive):
  - **Pipeline:** DMN + NRM = the NRM layer + `dmn_nrmw_<rc>` (DMN made on the Wylder NRM layer itself; catalog
    `inputs.dmn_nrm_layer_pattern` = `dmn_nrmw_{rc}`, alternates `dmn_nrm_{rc}` for the rc3-rc7 test builds; the first
    made from exactly the NRM layer + the chain). Its report fails exactly G-WALL + G-VOL-REC by design: accepted ONLY
    as an ERCap state where `inputs.dmn_ercap_only_layers` allows it (`rcinputs.dmn_layer_problems`, the checks of
    deploy_v65.py `--dmn-nrmw` ported: DMN_ERCAP_STATE.json accepted, same roots, same manifest, M2 last index in
    32,668..65,433, every shipped file unchanged, no regulation). The rc8 switch prep's sibling arrangement
    (`nrm_<rc>_T2` + `dmn_nrm_<rc>`, `inputs.dmn_nrm_sibling_*`) is retired (the loader refuses those keys; a DMN + NRM
    layer made on another NRM layer is refused). `wall.check_forced`: every combination that uses an ERCap-only layer
    measures over `limit_without_dll` and has a D rule; a D rule holds only on combinations over that limit and names
    two animation options. rc8 measured: main 31,514, + DMN 31,824, + NRM 32,621, + DMN + NRM 32,931 (= additive
    again) -> the DLL is forced for DMN + NRM (+ any other option). products.json `dmn_ercap_only` replaces
    `nrm_sibling` / `nrm_dmn_base`.
  - **Catalog:** rule `D` dmn:1 + nrm:1 "needed so DMN and Nightreign's Wylder fit together" (replaces the W rule
    "installed without Wylder's skills"); a W rule for the DMN moveset toggle (R1+R2+Y) that shares buttons with
    Onslaught Stake; NRM / ERCap descriptions say ERCap is added for DMN + NRM.
  - **Inno code:** section 5.2 (D rules, `DllOwn` / `DllAuto` / `DllReason`, presets from `AUTO_ON`), the Options
    page lock (`UpdateDllLock`; `ReadOptionsList` skips the locked line), section 7 (log lines), section 8 (`AUTO_ON=`).
    `CompShortTitle` moved from backup.iss to catalogrt.iss.
  - **Tests:** `tests\oracle.py` switches the DLL on from the DMN layer's own DMN_ERCAP_STATE.json (or a raw D rule)
    (`effective`, `dll_auto`); run_all P2 checks `AUTO_ON`; P1 dry runs `dmn_nrm_forced`, `dmn_nrm_ercap0`,
    `layout_dmn_nrm`; P10 `tests\ercap_forced_regress.py` ('ef ...': silent + WIZARD, the field-tested bat's 111 files,
    changes that drop DMN / NRM, the explicit-off refusal); smoke_integrate expects `dll=forced`.
- NRM-era fix (2026-10-03, after the rc8 one-command run's P4 / P10 DT failures; CAT_FORMAT 2 unchanged, no new array):
  the pipeline's H rules (section 3.2 Detection) now also hold (a) every older content of a path an option writes only
  while it is on but whose content another option also picks (rc8: `mod\action\script\nrm-extension.hks`, affects
  nrm + dmn; `legacy.presence_paths`) - v6.4's / the rc1-rc7 test builds' merged beta.16 file `8e7b453a...` was taken
  for another mod's file (moved by the install, kept by the uninstall); (b) the contents of `catalog.src.json`
  `legacy.packages`: other authors' packages (zip pinned by sha256, member prefixes mapped under `mod\`, the package's
  own `install-files.json` with every earlier version's sha256 in `originalSHA256`), used only at the paths their
  `component` writes alone (the build stops when a package file meets another option's path), never obsolete rows.
  Now: Nightreign Movement 1.0.0-beta.16 (`v60\sources`) and 0.2 (`v65\sources`): 18 new NRM H rules (9 at
  nrm-extension.hks, 9 earlier DLL versions). The Inno code is unchanged (it already reads every H rule as own content).
  Tests: run_all P4 also fails when an upgrade log names an older release's file as another mod's.
- rc8 switch prep (2026-10-03, after the release-prep reviews; rc7 test build; CAT_FORMAT 2 unchanged):
  - **NRM tiers:** `inputs.nrm_tier` (T2W) = the tier the NRM option ships; `nrm_layer_pattern` = `nrm_<rc>`,
    alternates `nrm_<rc>_T2W`, `nrm_<rc>_T2`; `rcinputs.nrm_dir` takes the first with that tier and
    `nrm_package_problems` refuses another tier (so `--final` / `--all` never ship a Wylder-off layer).
    `inputs.dmn_nrm_sibling_tier` + `dmn_nrm_sibling_files`: a DMN + NRM layer made on a SIBLING NRM layer (RC8:
    `dmn_nrm_<rc>` on `nrm_<rc>_T2`, because DMN + Wylder is over the animation wall) is accepted when the sibling has
    the same chain, package, files and `_me3` / `_installer` files and differs only in those files; DMN + NRM = the NRM
    layer + the sibling's differing files + the DMN overlay (`compose.combo_tree`, `tests\oracle.py`, as deploy_v65.py).
  - **Lucy + NRM 0.2:** Lucy's `_nrm` base = deploy_v65.py's (01_common from the chain; item_dlc02 where the NRM layer
    ships it; menu_dlc02 from the NRM layer), so the pipeline reuses the Lucy builds the RC lane made; the Lucy + NRM
    selection's `menu\hi\01_common` pair = Lucy's pair + NRM's changed layout / texture (`inputs.nrm_menu_composer`;
    the field-tested pair `inputs.nrm_menu_tested_pattern` is adopted when its sources match, and must be identical
    when both exist; `products.ensure_nrm_menu`, products.json `nrm_menu`). The icon re-pack of the release prep is gone.
  - **Lucy's own build checks** (`products.lucy_build_checks`): every check the LOCAL `lucy_build.local.json`
    `build_checks` names runs on both Lucy builds of the RC and must exit 0 (none configured = refused; cached per
    input md5s).
  - **Rules:** a W rule for NRM + DMN ("... installed without Wylder's skills ..."; catalog data only).
  - **Credits / licences:** `components[].licenses` (name, from, expect_sha256, what) -> `LICENSES/<name>` + a
    LICENSE-NOTES line (fromsoftware-rs in infinite_arrows.dll); arrows `credits_extra` (vswarte, the original
    9032); `credits_always`: AronTheBaron and The Convergence Team; windshadowruins (the original merge) and Kinder.
  - **Animation wall per combination:** rc8's DMN + NRM uses the Wylder-off sibling layer, so its total is not
    base + the two deltas (MEASURED rc8: main 31,514, + DMN 31,824, + NRM 32,621, + DMN + NRM 31,891; additive would be
    32,931 and force ERCapacityExpansion for nothing). `wall.measure` no longer refuses a non-additive RC: it emits the
    exact table (`WallComboComp` / `WallComboTotal`, catalog.json `wall.combo_comps` / `combo_totals`, always when an
    option touches the animation binders) and `catalogrt.iss CurrentWallTotal` uses it (empty table = additive, so the
    stub and older catalogs read as before). `tests\smoke_integrate.py` computes the expected WALL line the same way.
  - **Installer code (3 small changes; the wall table above is the third):** a download with the exact size of a pinned archive but other content is now
    REJECTED with a "damaged, incomplete or another version" problem (was: silently skipped, then "missing";
    `archives.iss TryFoundDownloads`); `mod\dll\*.skills.ini` (Nightreign Movement 0.2's run-time skill settings) is
    a runtime file like logs and saves (`checks.iss IsRuntimeFile`: never listed, never moved, never reported as foreign).
  - **Repo scan:** also every Caesar shift, base32, look-alike letters, leetspeak, decoded escapes, chr()/#NN codes,
    string literals joined, and lines squeezed together; short forms count only at a word start (ordinary words pass);
    one prefix-tree regex per kind (the tree scan takes ~5 s). The history check also reads the repo's Activity log:
    a commit id there that the branch no longer holds is refused (`ghstage.activity_problems`).
- Release prep (2026-10-03, rc7 test build; CAT_FORMAT 2 unchanged): Nightreign Movement 0.2 "Wylder" is the player's
  own download from its Nexus page (component `nrm` source `nexus`, archive `nrm_02`, mode P, must_verify,
  verify member `install-files.json`, whole zip pinned 23facf3f...); the files the NRM layer ships unchanged come from
  it, the merged NRM files from the release. New `archives[].package_version`: the RC's NRM layer must report that
  package version (+ the zip's sha256 when its report records it) - `rcinputs.nrm_package_problems`, enforced by the
  build and by `checks.final_gates`; `release.py --allow-other-nrm-package` makes a TEST build of an older layer that
  `--final`, `--stage-github`, `--all` and `publish_github.py` refuse. `sites` / `hosted` / source `hosted` retired
  (the loader refuses them), `pipeline\sitesync.py` and `tests\site_fetch_real.py` retired, the `--all` site step and
  the publish check's site files gone. New `components[].credits_extra` (one extra credit row each while the option is
  on; the third-party authors whose work an option's own files are built from). Build-PC forbidden write roots moved
  to the LOCAL `catalog\*.local.json` files.
- Release prep, repo scan (2026-10-03): texts that must never be public are configured only in the LOCAL
  `catalog\*.local.json` files and read at run time (`cfg.private_markers`); the scan also catches their reversed /
  rot13 / squeezed / hex / decimal / base64 forms and repo paths, and refuses everything when none is configured.
- Final repair (2026-10-03, after the release-kit review; rc7; no .iss code change, the generated arrays changed):
  catalog - Lucy's credit is "Lucy Character and Chevaleresse Armor by Canalpa (Luka) - nexusmods.com/eldenring/mods/11128",
  her `desc` gives the creator steps and the armor seller, Seamless Co-op and ERCapacityExpansion are no longer
  `experimental` (only DMN is; the design doc kept them experimental until Luka's Seamless tests passed, which they
  did on 2026-10-02), ERCap's credit names the author's version label. Lucy's workspace folder and build recipe moved
  to the LOCAL file `catalog\lucy_build.local.json` (never pushed; `cfg.LUCY_ROOT` / `cfg.LUCY_RECIPE`). The repo
  content scan (`ghstage._leak_patterns`) also runs over the history. catalog.json writes archive reference paths with workspace tokens (`cfg.public_path`) and refuses any local drive
  path (`emit_json.catalog_json_text`). The draft release notes named the canalpa.com exception (Nightreign Movement)
  until the release prep retired that site.
  Tests: publish_github_selftest S1, S2.
- Final pass part 2 (2026-10-03, Luka asleep; rc7, catalog 2130f1ec and code f983c700 unchanged - no .iss and no
  generated-array change): **`release.py --rc <rc> --all`** (pipeline\oneshot.py, the one command; `--cold`,
  `--retest`, `--verify-download`, `--no-upload`); every ISCC run writes `<out dir>\BUILD_INPUTS.json` (kind, exe
  sha256, catalog sha256, code fingerprint, ISCC.exe sha256, defines) and `--all` reuses an exe whose record matches
  (its md5 stays stable for the Nexus upload); the kinds still to compile run in parallel; `publish_release_exe` keeps
  dist's exe + sidecar when they are already this build. `pipeline\sitesync.py` (site files: anonymous check +
  upload), `pipeline\drafts.py` (v65\dist\_drafts: RELEASE_FILES_<ver>.txt + the [AUTO:RELEASE-FILES] blocks + a
  lint), `ghstage`: an asset is re-uploaded when GitHub's sha256 digest differs (not only the size), uploads and
  verify-download run 3 gh processes at once, the history scan caches per git blob/tree (work\gh_history_scan_cache.json),
  the user-path scan no longer flags the placeholder `C:\Users\...` (a comment in code\me3.iss). `publish_github.py`
  `--check` / `--publish` / `--verify-public` also check every site file anonymously; `--publish` runs only after
  Luka's OK (decision T7). New test tool `tests\site_fetch_real.py` (the TEST exe's own downloader fetches the real
  site files through a local pass-through; MEASURED: Inno 6.7.3 sends no Accept-Encoding, the site answers identity).
- CAT_FORMAT 2, final pass part 1 + repair round 6 (2026-10-03, Luka asleep; release base rc7):
  - **Format:** one new generated array `BlobSite` (section 3.2) and the flag `BaseUrlsReplaced` (code only);
    `CXCXM_v65_Installer.iss`, `emit_iss.py`, the stub (`tests\stub\make_stub.py`) and `catalog.json` ("format": 2;
    blobs carry "site", "site_id", "hosted"; a top-level "hosted" list) moved to 2. `legacy.py` reads earlier catalogs
    of format 1 or 2.
  - **catalog.src.json:** `inputs.dmn_layer_pattern` / `dmn_nrm_layer_pattern` (the DMN layers of the RC, checked like
    the NRM layer: fail [], made from the chain), `inputs.infdur_ack` (DMN's 240 SpEffect ids, merged with
    `--infdur-ack`), component source `hosted` + `components[].hosted`, top-level `sites` and `hosted` (a package WE
    host on another site, only for the installer: its files become blobs of that site, never GitHub release assets;
    the never-host check enforces both directions), archive reference kind `rar` (unpacked once into
    `work\refcache\<sha16>`) and `reference.expect_sha256` (the pinned file). McKenyu's archive is `mck_14` (1.4,
    RAR5, page CONFIRMED), `nrm_b16` is no archive any more (then a hosted package on canalpa.com; since the release
    prep the archive is `nrm_02`, the player's own NRM 0.2 download), DMN is a T component
    (experimental, hot, archive `dmn` = Rei Jr.'s zip), Seamless' reference is 2.0.1, the Seamless+ERCap warning rule
    is gone.
  - **Pipeline:** DMN is a hot product (compose: its layer after NRM's, the nrm variant when NRM is on); detection gets
    H rules for a hot option with no native/own file (its "on" contents at up to 3 shared paths); the hosting trees
    are `dist\<tag>\github\<tag>\` (release) and `dist\<tag>\sites\<site>\<folder>\` (other sites); ghstage /
    publish_github / selftest / hosted_checks treat only the release blobs as GitHub assets.
  - **Inno code (repair round 6):** `.me3` path lines are read as me3 resolves them (`Me3PathLineValue`,
    `Me3ResolveConvRel`: quotes, `'''`/`"""`, escapes, `/` and `\`, `.`/`..`/`//`, an absolute path into the
    Convergence folder): an entry that loads an option's own file at its own path is that option's entry, whatever its
    spelling (findings A and C); the kind E uninstall puts the saved copy back whole when a path line cannot be read;
    `CleanStaleUninstallers` deletes a dead `unins###` (empty log / no AppId, or an .exe without its .dat; finding B);
    the run journal is joined by a "backup only" marker (`CXCXM_BACKUP_ONLY.txt`, written before the manifest's
    rename, deleted after the journal is written): a backup folder with the marker and no journal = a run stopped
    before its first change, deleted by every later run and the uninstaller instead of applied; the manifest's flush
    is no longer fatal; `ReplaceFileWithTemp` retries sharing/access errors for about 3 s; the uninstaller holds the
    installer's mutex names; `ListWriteTargets` (moved to checks.iss) takes only B/N/E/M manifest lines and the
    foreign-file scan hides every `.cxtmp` of those targets; test builds take `/TESTNOTAR=1` (the built-in extractor).
  - **Tests:** `tests\repair6_regress.py` (run_all P10 `r6 ...`: findings A and C on re-spelled and the player's
    own entries, B on a dead uninstaller, K1/K2 on a stop between the backup and the first change),
    `tests\unit_me3.py` repair-6 cases; `tests\verify_independent.py` picks the NRM hks asset by the NRM
    layer's own sha256 (three c0000.hks assets since DMN).
- CAT_FORMAT 1 (2026-10-01, architect): first version.
- CAT_FORMAT 1, repair round 1 (2026-10-01 ~09:00, INTEGRATE lane, both lanes' files): no array was added or
  renamed, so old and new code read the same shape. Changed meaning: mode V `MemSha` = tested version's sha256
  (was ''). New catalog.src.json keys: `archives[].verify_members`, `components[].files[].dest` must be unique per
  component; `user_config.from` names a mode V member by its full reference path. New runtime array (code only):
  `ArchTested`. Sections 2, 3.2, 7 and 10 above carry the details.
- CAT_FORMAT 1, repair round 2 (2026-10-01 ~13:00, INTEGRATE lane): no array added or renamed. New `NatForeign`
  value `K` (ERCapacityExpansion: a player's own entry at another path is kept while the option is off; verifier 3 D1).
  Runtime rules: (g) archive names and name hints are compared as words (every non-letter/digit = a blank) and a
  number hint matches only a whole word; the pipeline adds the Nexus mod id of `nexus_url` to `name_hints` (D2);
  (h) the download search tries every complete mode V package folder below an extracted folder on its own, and a picked
  folder with several packages takes the tested one (D3); (i) a backup folder (stamp name) without a manifest is the
  partial backup of a stopped Setup and is deleted by the next install and by the uninstaller; the manifest is written
  under `.tmp` and renamed when complete (D4); (j) Setup never writes an existing file in place: it writes
  `<file>.cxtmp` and moves it over the file (MoveFileEx), so a hard-linked file outside the Convergence folder never
  changes (review D2); (k) a path that goes through a junction Windows' RedirectionGuard blocks is reported as such,
  with the real folder (review D1); (l) the free-space check counts the hosted downloads when Setup's temp folder is on
  the Convergence drive, and checks the temp drive otherwise (review D5); (m) an invalid `/BASEURL=` is never applied
  (review D8); the Downloads page opens only `https://` addresses and catalog_src.py refuses any other URL (review D9).
  `release.py --final` runs its gates before anything is written into dist\, generated\, staging\meta or the hosting
  trees (the main zip is built in `work\mainzip\<tag>\` and linked into dist\ afterwards; review D4).
- CAT_FORMAT 1, repair round 3 (2026-10-01 ~18:00-, INTEGRATE lane): no generated array added or renamed. Inno code:
  .me3 profiles read in context (section 5.8; verifier 4 D1); Lucy detection + `-1` deletions by content (sections 3.2,
  5.7; D2); after an install in a moved Convergence folder the earlier Apps entry and `unins000.*` are removed when that
  entry's folder is gone, and the marker names the real uninstaller (D3); the in-place write fallback refuses a file
  with more than one name (the step fails -> rollback); an elevated Setup never starts tar (ExtractArchive instead) and
  never advises /NOREDIRECTIONGUARD; the download search's candidates (not pinned) may unpack to at most 8x their size +
  256 MB (tar: its `-t -v` listing first; the built-in extractor stops at the cap or at the drive's free space - 512 MB);
  a secret field given on the command line gets a log note (Inno's own "Setup command line:" line cannot be masked);
  IsInnoSwitchName adds REDIRECTIONGUARD/NOREDIRECTIONGUARD. New catalog.src.json key `components[].detect_files`.
  Pipeline: `catalog_src.py` reads Inno's and the installer's switch names from code\catalogrt.iss (one list);
  `checks.final_gates` requires `coverage.verified_uninstalled` of the results file to hold every non-X (component,
  state) pair (`checks.required_pairs`) and refuses a published tag itself (`check_published`, False only for
  publish_github.py, which reads the release). Section 10: the results file carries `coverage`
  (`verified_uninstalled`, `required`, `missing`, `passing_installs`); the oracle may read catalog.src.json's raw
  declarations (files[], user_config[], archives / mode V members) - never anything the pipeline made; tests\run_all.py
  derives P2/P3 from catalog.json. NRM's page = https://boosty.to/neirox (INFERRED).
- CAT_FORMAT 1, repair round 4 (2026-10-01 ~23:15-, Luka asleep): no generated array added or renamed, catalog
  unchanged (fa6ec0e22f06c3eb). Inno code: .me3 entries with their TOML sub-tables (section 5.8: `[natives.x]`,
  `[[natives.x]]`, `[package.x]` belong to the `[[natives]]`/`[[package]]` table above them; quoted headers and keys;
  tables/keys defined twice refused; both names of a me3 alias (`[[native]]` next to `[[natives]]`) refused, from the
  fifth verifier's u1 probe) - fifth verifier DEFECT 1/2 + code review MEDIUM; the uninstall keeps another
  mod's file at a path of an option that a run created (section 5.6; code review LOW); an Apps entry of another AppId whose folder exists
  but whose uninstaller is gone counts as stale (fifth verifier, D3 variant); the tar listing cap fails closed and reads
  sizes position-free (section 5.4; code review LOW). Pipeline: catalog.src.json `legacy.catalogs` (earlier releases'
  dist\<tag>\catalog.json: their contents become H contents, their dropped paths obsolete rows, their changelog an old
  changelog, their regulations InfDur states); `checks.final_gates` refuses a build when an earlier
  dist\<tag>\catalog.json exists that legacy.catalogs does not list (code review LOW). Tests: tests\repair4_regress.py
  (P10 'r4 ...'), tests\unit_me3.py repair-4 cases.
- CAT_FORMAT 1, repair round 5 (2026-10-02 06:35-, Luka asleep): no generated array added or renamed, catalog
  unchanged (fa6ec0e22f06c3eb), code 76b7bd5782be6927. Inno code: crash safety (sixth verifier DEFECT 1, section
  5.6): every write through `<name>.cxtmp` + flush + rename (new files too), stale `.cxtmp` deleted before the plan and
  before an uninstall (never listed as another mod's), other mods' files moved after Inno registered the uninstaller,
  a run journal `CXCXM_RUN_UNFINISHED.txt` in each backup folder (the newest one's = the presets after a stop), a
  restored backup folder loses its manifest first, stopped Setups' `cxcxm_blobs` in `%TEMP%` deleted, the long-path
  check counts the suffix. .me3 (DEFECT 2, section 5.8): 3-5 closing quotes, escaped keys / `\u` paths / paths over
  several lines refused, case-sensitive natives headers, `[[native]]` read as natives, unreadable profiles refused even with nothing
  to change, me3's own reader must list the same natives (before and after an edit; `/TESTME3EXE=` in test builds).
  New log lines `CXCXM STALETEMP`, `CXCXM RESUME`, `CXCXM ME3READ` (section 7). Tests: tests\repair5_regress.py (P10
  'r5 ...'), tests\unit_me3.py repair-5 cases (run with /TESTME3EXE=), sb_verify\_v6r5\_tools\k5_sweep.py (the kill
  sweep).
- GitHub stage lane (2026-10-01 ~17:00): no catalog or Inno change (catalog 5760156231215e95 and code 1ae176a4 kept).
  `--stage-github` now commits the repo tree above in ONE Git-data-API commit (no-op when nothing changed), keeps the
  draft's title/notes publish-ready, refuses when the release is already published, and leaves the files of a PUBLIC
  repo alone (drafts are still staged, so v6.6 can be staged next to a published v6.5.0). `publish_github.py` gained
  `--check` (lists what would change), `--publish` (files -> PUBLIC -> published -> anonymous HEAD of every asset URL),
  `--verify-public`, `--verify-download` and a BASEURL check (first mirror == this repo's releases/download/, every
  blob tag == the release tag). `checks.final_gates` also refuses an archive page marked INFERRED; `--final` refuses a
  tag whose GitHub release is already published. cfg.py takes the user-profile folders from the environment.
  Tests: tests\publish_github_selftest.py, tests\release_exe_default_url.py.
