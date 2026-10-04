{ =============================================================================
  globals.iss - constants, global state and Win32 imports.
  Included first; every other module depends on these declarations.

  The catalog arrays below carry EXACTLY the names and types of the builder
  contract (installer\README_CONTRACT.md section 3.2, CAT_FORMAT 2). The
  pipeline's generated\catalog.iss declares the CAT_* constants and the
  procedure InitCatalog, which fills them. Nothing in this file may use a
  CAT_* constant: catalog.iss is included after it.
  ============================================================================= }

const
  REQUIRED_CONV_VERSION = '3.0.2.0';
  { The Convergence's official site (the Convergence Launcher is downloaded there) }
  CONVERGENCE_SITE_URL  = 'https://www.convergencemod.com/';
  { the process that must not run while files change. The code-check and
    test builds (never shipped) watch a dummy name so they can be tested
    while the game is open. }
#if Defined(CodeCheck) || Defined(TestBuild)
  GAME_EXE_NAME         = 'cxcxm_codecheck_dummy_game.exe';
#else
  GAME_EXE_NAME         = 'eldenring.exe';
#endif
  { a second Setup is refused (and the uninstaller waits for it) }
  SETUP_MUTEX_NAME      = 'CanalpaCXCXMInstaller';

  { files and folders the installer owns inside the Convergence folder }
  MARKER_NAME           = 'CXCXM_INSTALLED.txt';
  MARKER_MAGIC_3        = 'CXCXM-MARKER 3';
  BACKUP_ROOT_NAME      = 'CXCXM_backup';
  UNINSTALL_DIR_NAME    = 'CXCXM_uninstall';
  BACKUP_MANIFEST_NAME  = 'CXCXM_BACKUP_MANIFEST.txt';
  { work folder for the unpacked downloads: <Conv>\CXCXM_work (same drive as
    the target, deleted when Setup ends and by the uninstaller) }
  WORK_DIR_NAME         = 'CXCXM_work';
  { the downloaded (hosted) files: <Setup temp folder>\cxcxm_blobs }
  BLOB_DIR_NAME         = 'cxcxm_blobs';
  { format 1: kinds B N E D. Format 2 adds M (another mod's file that exists
    ONLY in the backup folder); it is written only when the plan has M
    entries, so an older uninstaller (which knows format 1 only) never lists
    such a folder and can neither skip those files nor delete them }
  BACKUP_MANIFEST_MAGIC = 'CXCXM-BACKUP-MANIFEST 1';
  BACKUP_MANIFEST_MAGIC_2 = 'CXCXM-BACKUP-MANIFEST 2';
  { Setup is not long-path aware: every path must stay below MAX_PATH. The
    longest backup file is <Conv>\ + this template + the longest relative
    path (MAX_REL_LEN / MAX_REL_DIR_LEN come from generated\catalog.iss). }
  BACKUP_PATH_TEMPLATE  = 'CXCXM_backup\2026-01-01_00-00-00_99\';
  MAX_FILE_PATH_LEN     = 259;      { MAX_PATH minus the terminating NUL }
  MAX_DIR_PATH_LEN      = 247;      { CreateDirectory limit (MAX_PATH - 12 - 1) }
  ME3_PROFILE_COUNT     = 2;

  { PathTab values below 0 }
  PT_ABSENT             = -1;       { the file must NOT exist }
  PT_LEAVE              = -2;       { the file is left as it is }

  { Elden Ring (check A, code\checks.iss). The exe's FileVersion 2.7.1.0 is
    what players know as Patch 1.17. }
  REQUIRED_GAME_VERSION = '2.7.1.0';
  GAME_PATCH_NAME       = 'Patch 1.17';
  { Patch 1.17 shipped as exe 2.7.0.0 first; 2.7.1.0 is its later update }
  GAME_PATCH_FIRST_EXE  = '2.7.0.0';
  ELDEN_RING_APPID      = '1245620';
  GAME_SUBDIR           = 'steamapps\common\ELDEN RING\Game';
  { Shadow of the Erdtree: DLC.bdt is ~15.7 GB and DLC.bhd ~1.4 MB. Only a
    plausible minimum is required, never an exact size. }
  DLC_BDT_MIN_BYTES     = 1073741824;
  DLC_BHD_MIN_BYTES     = 65536;
  GS_NOTCHECKED = 0;
  GS_OK         = 1;     { 2.7.1.0 with Shadow of the Erdtree }
  GS_NOTFOUND   = 2;     { no eldenring.exe in any Steam library }
  GS_NOVERSION  = 3;     { found, but its version cannot be read }
  GS_WRONG      = 4;     { wrong version and/or no Shadow of the Erdtree }

  { how many foreign files the page and the marker list one by one }
  FOREIGN_LIST_MAX      = 500;
  { what every installer version's "switched off" prefix starts with
    (v6.3 wrote 'v6.3', v6.4 'v6.4'; ours is Me3OffPrefix in me3.iss) }
  ME3_OFF_PREFIX_ANY    = '# switched off by the CXCXM v';

  { Convergence scan limits }
  SCAN_MAX_DEPTH        = 4;        { levels below each drive root / common root }
  SCAN_TIME_BUDGET_MS   = 90000;    { hard stop so a huge disk never hangs Setup }
  { download / extracted-folder search limits }
  ARCH_MAX_DEPTH        = 10;       { a folder the player picked: "any depth" }
  ARCH_MAX_DIRS         = 20000;
  DL_SEARCH_DEPTH       = 4;        { the Downloads folder }
  DL_VORTEX_DEPTH       = 3;        { Vortex's download and mod folders }
  DL_MAX_TRIES          = 6;        { name-hint archives unpacked per download: best name match first, then newest }

  { archive states (ArchState) }
  AS_NOTNEEDED          = 0;        { its component is off, or every file it gives is in place }
  AS_MISSING            = 1;        { needed, nothing found yet }
  AS_ACCEPTED           = 2;        { needed, a download was found and every member checked }
  AS_REJECTED           = 3;        { needed, the last candidate was refused (ArchProblem) }

  { Win32 values (own names so they never clash with Inno's predefined ones) }
  FA_READONLY           = $1;
  FA_HIDDEN             = $2;
  FA_SYSTEM             = $4;
  FA_DIRECTORY          = $10;
  FA_REPARSE_POINT      = $400;
  FA_NORMAL             = $80;
  DRIVE_TYPE_FIXED      = 3;
  MOVE_REPLACE_EXISTING = $1;       { MoveFileEx: MOVEFILE_REPLACE_EXISTING }
  MOVE_WRITE_THROUGH    = $8;       { MoveFileEx: MOVEFILE_WRITE_THROUGH }
  { EVERY file Setup or the uninstaller writes in the Convergence folder (a
    new one too: repair 5, sixth verifier DEFECT 1) is written next to it
    under this suffix first, flushed to the disk, and then moved to its name
    (MoveFileEx): the write never goes through an NTFS hard link into a file
    outside the Convergence folder (code review repair 2, D2), and a Setup
    that is stopped hard (Task Manager, a crash, a power cut) never leaves a
    half-written file under a name the game loads - only "<name>.cxtmp",
    which the next run and the uninstaller delete (DeleteStaleTempFiles) }
  REPLACE_TMP_SUFFIX    = '.cxtmp';
  { the journal of a run that has started to change the Convergence folder:
    written into the run's backup folder right before the first change and
    deleted when the run's post-install step ends (passed, failed, rolled
    back). A backup folder that still holds it belongs to a run that was
    stopped hard; the next run preselects that run's options (repair 5) }
  RUN_JOURNAL_NAME      = 'CXCXM_RUN_UNFINISHED.txt';
  { a backup folder whose run has made its copies but has not changed the
    Convergence folder yet: written before its manifest gets its name and
    deleted right after the run journal is written (its first change). A
    folder that holds it and no run journal belongs to a run stopped before
    any change; every later run and the uninstaller delete such a folder
    instead of applying it (repair 6, code review of repair 5, LOW) }
  BACKUP_ONLY_NAME      = 'CXCXM_BACKUP_ONLY.txt';
  { the backup folders' names: yyyy-mm-dd_hh-nn-ss (NowForFolder), maybe
    with _<n>; a folder of that shape without a manifest is the partial
    backup of a stopped Setup (verifier 3, D4) }
  BACKUP_STAMP_LEN      = 19;

  { custom exit codes (GetCustomSetupExitCode); Inno's own codes are 1..8 }
  EXIT_VERIFY_FAILED_RESTORED = 20;
  EXIT_VERIFY_FAILED_KEPT     = 21;
  EXIT_POSTINSTALL_FAILED     = 22;

  { what a line of a .me3 profile (TOML) is, in its context (code\me3.iss
    Me3Classify; repair 3, verifier 4 D1: a table runs from its header to
    the next header, and a multi-line array, inline table or string may hold
    blank lines, comments and lines that start with "[") }
  ME3_K_BLANK           = 0;        { empty or blanks only }
  ME3_K_COMMENT         = 1;        { a # comment line outside any value }
  ME3_K_HEADER          = 2;        { [table] or [[array of tables]] (a trailing # comment allowed) }
  ME3_K_KEY             = 3;        { key = value, starting outside any value }
  ME3_K_CONT            = 4;        { a line that starts inside an open array, inline table or string }
  ME3_K_BAD             = 5;        { anything else outside a value: not TOML }
  { joins the parts of a TOML key path in code\me3.iss (repair 4; a character
    no profile holds) }
  ME3_PART_SEP          = #1;

  { the unpacked size Setup allows for one archive, as a multiple of the
    archive's own size (plus 256 MB), and the free space it always leaves on
    the drive (repair 3, code review LOW: no cap on the unpacked size) }
  UNPACK_RATIO_MAX      = 8;
  UNPACK_RESERVE_BYTES  = 536870912;

  { CreateFileW / GetFileInformationByHandle (FileLinkCount, util.iss) }
  WIN_OPEN_EXISTING     = 3;
  WIN_FILE_SHARE_ALL    = 7;        { read + write + delete }
  WIN_GENERIC_WRITE     = $40000000;
  WIN_FILE_ATTR_NORMAL  = $80;

var
  { ====================== catalog (contract 3.2; InitCatalog fills them) === }
  { components }
  CompId: TArrayOfString;
  CompSwitch: TArrayOfString;
  CompTitle: TArrayOfString;
  CompDesc: TArrayOfString;
  CompKind: TArrayOfString;            { R required, T toggle, C choice, X disabled placeholder }
  CompExperimental: array of Boolean;
  CompDefault: array of Integer;
  CompStateCount: array of Integer;
  CompStateStart: array of Integer;
  CompCredit: TArrayOfString;
  CompSourceText: TArrayOfString;
  { states }
  StateCode: TArrayOfString;
  StateTitle: TArrayOfString;
  StateWall: array of Integer;
  { the exact animation-wall total of every combination of the animation-touching
    options (WallComboComp = their component indexes; WallComboTotal indexed by
    their states, the first one counting fastest). Empty = the additive model
    WALL_BASE + StateWall (rc8 switch prep: DMN + NRM is not additive). }
  WallComboComp: array of Integer;
  WallComboTotal: array of Integer;
  { rules }
  RuleKind: TArrayOfString;            { Q requires, X conflict, W warning, D (2026-10-03) A and B together
                                         need the DLL component WALL_DLL_COMP: switched on by itself, RuleText
                                         = the reason shown next to its locked check box }
  RuleA: array of Integer;
  RuleAMask: array of Integer;
  RuleB: array of Integer;
  RuleBMask: array of Integer;
  RuleText: TArrayOfString;
  { paths }
  PathRel: TArrayOfString;
  PathFlags: TArrayOfString;           { U = user config, '' = normal }
  PathOwner: array of Integer;
  PathAffStart: array of Integer;
  PathAffCount: array of Integer;
  PathTabStart: array of Integer;
  AffComp: array of Integer;
  PathTab: array of Integer;           { >= 0 variant, PT_ABSENT, PT_LEAVE }
  { variants }
  VarPath: array of Integer;
  VarSha: TArrayOfString;              { '' = dynamic (mode V archive member) }
  VarSize: array of Int64;
  VarSrc: TArrayOfString;              { A archive member, B hosted blob }
  VarRef: array of Integer;
  { archives (the player's downloads), their pins and members }
  ArchId: TArrayOfString;
  ArchComp: array of Integer;
  ArchTitle: TArrayOfString;
  ArchAuthor: TArrayOfString;
  ArchHint: TArrayOfString;
  ArchNexusUrl: TArrayOfString;
  ArchNameHints: TArrayOfString;
  ArchMode: TArrayOfString;            { P pinned members, V any version }
  ArchMustVerify: array of Boolean;
  ArchGlobs: TArrayOfString;
  ArchPinStart: array of Integer;
  ArchPinCount: array of Integer;
  PinSize: array of Int64;
  PinSha: TArrayOfString;
  ArchMemStart: array of Integer;
  ArchMemCount: array of Integer;
  MemArch: array of Integer;
  MemName: TArrayOfString;
  MemTail: TArrayOfString;
  MemSha: TArrayOfString;
  MemSize: array of Int64;
  { hosted blobs }
  BlobSha: TArrayOfString;
  BlobSize: array of Int64;
  BlobAsset: TArrayOfString;
  BlobTag: TArrayOfString;
  BlobUpstream: TArrayOfString;
  { CAT_FORMAT 2 (final pass 2026-10-03): '' = the release mirrors
    (BaseUrls + BlobTag + '/' + BlobAsset); else the root of another
    download site: URL = BlobSite + BlobTag + '/' + BlobAsset. The pipeline
    makes no such blob since 2026-10-03 (always '') }
  BlobSite: TArrayOfString;
  BaseUrls: TArrayOfString;
  BaseUrlsReplaced: Boolean;            { /BASEURL= given: it replaces every download root (tests, mirrors) }
  { me3 natives }
  NatComp: array of Integer;
  NatMatch: TArrayOfString;
  NatPath: TArrayOfString;
  NatForeign: TArrayOfString;          { R re-point one foreign table, S strip, K keep the player's own copy while off }
  NatLf: array of Boolean;
  NatLineStart: array of Integer;
  NatLineCount: array of Integer;
  NatLine: TArrayOfString;
  PristineMe3Lines0: TArrayOfString;   { stock me3\convergence.me3 }
  PristineMe3Lines1: TArrayOfString;   { stock me3\convergence - seamless.me3 }
  { detection (presets) }
  DetComp: array of Integer;
  DetKind: TArrayOfString;             { F file exists, N .me3 line, H sha256 }
  DetArg: TArrayOfString;
  DetSha: TArrayOfString;
  DetState: array of Integer;
  { obsolete files of older releases }
  ObsRel: TArrayOfString;
  ObsSha: TArrayOfString;
  ObsNote: TArrayOfString;
  { fields (values the player types, written into an ini) }
  FieldComp: array of Integer;
  FieldId: TArrayOfString;
  FieldSwitch: TArrayOfString;
  FieldLabel: TArrayOfString;
  FieldRel: TArrayOfString;
  FieldSection: TArrayOfString;
  FieldKey: TArrayOfString;
  FieldSecret: array of Boolean;
  { credits }
  CreditComp: array of Integer;        { -1 = always shown }
  CreditText: TArrayOfString;

  { ================================================ runtime state ======== }
  { the selection (contract section 5.1) }
  ChosenState: array of Integer;
  ChosenExplicit: array of Boolean;    { set by /COMPONENTS (/SELECT) or a per-component switch }
  DetectedState: array of Integer;     { what the detection rules found (-1 = nothing) }
  SelectionPresetFor: String;          { ConvDir the presets were made for }
  InterruptedRunStamp: String;         { the backup folder of a run that was stopped hard before it finished
                                         (its run journal is still there); its options are the presets
                                         ('' = none; repair 5) }
  { per variant }
  VarShaRt: TArrayOfString;            { dynamic variants: the sha256 of the accepted archive member }
  VarSkip: array of Boolean;           { the file already holds this variant: nothing to write }
  VarSrcPath: TArrayOfString;          { where the bytes come from (member or downloaded blob) }
  { per archive member / archive / blob }
  MemPath: TArrayOfString;             { the accepted candidate file }
  ArchState: array of Integer;         { AS_* }
  ArchNeeded: array of Boolean;
  ArchSource: TArrayOfString;          { the accepted (or last rejected) file or folder }
  ArchProblem: TArrayOfString;         { why the last candidate was refused }
  ArchNeedNote: TArrayOfString;        { why it is needed although its files are in place ('' = they are not) }
  ArchWorkDir: TArrayOfString;         { extraction folder of the accepted archive ('' = none) }
  ArchPinned: array of Boolean;        { the accepted archive file is a pinned (known) file }
  ArchTested: array of Boolean;        { mode V: the accepted files are the tested version (pinned file, or every
                                         member equals MemSha); mode P: always True (every member is pinned) }
  ArchSearchedFor: TArrayOfString;     { ConvDir the automatic search ran for }
  DlWanted: array of Boolean;          { the archives the running download search looks for }
  BlobPath: TArrayOfString;            { downloaded and checked copy ('' = not downloaded) }
  BlobNeeded: array of Boolean;
  { per path / obsolete row / field }
  PathDelete: array of Boolean;        { this run removes the file }
  PathKeepForeign: array of Boolean;   { a -1 file kept: another .me3 entry still loads it, or it is another
                                         mod's file kept in place (PathForeignFile) }
  PathForeignFile: array of Boolean;   { a -1 file that holds another mod's content (moved or kept, never
                                         removed as ours; repair 3, verifier 4 D2) }
  ObsDelete: array of Boolean;         { this run removes the obsolete file }
  FieldValue: TArrayOfString;          { what the player typed ('' = leave the ini as it is) }
  FieldGiven: array of Boolean;        { /<FieldSwitch>= was on the command line }
  FieldWrite: array of Boolean;        { this run edits the ini }
  { animation wall }
  WallTotal: Integer;
  WallLimitUsed: Integer;              { the limit that applies to the final selection }
  WallDllText: String;                 { off | on | forced }
  { the DLL component switched on because the selection needs it (2026-10-03, Luka: DMN + Nightreign's
    Wylder need ERCapacityExpansion; a D rule or the animation wall). Invariant: DllAuto -> ChosenState = 1
    and DllOwn = the player's own state (0); not DllAuto -> ChosenState is the player's own state. }
  DllOwn: Integer;                     { the player's own state of WALL_DLL_COMP, whatever the selection needs }
  DllAuto: Boolean;                    { on only because the selection needs it: AUTO_ON in the marker and the
                                         backup manifest; a later run that no longer needs it removes it }
  DllReason: String;                   { why the selection needs it ('' = it does not) }
  { rule notes for the Ready page }
  RuleWarnings: TArrayOfString;
  RuleNotes: TArrayOfString;
  { the folder's marker (format 3) as found before this run }
  PrevVerifiedArchives: String;        { comma list of archive ids }
  PrevMarkerLines: TArrayOfString;
  { file hash cache (path + size + time -> sha256) }
  ShaCacheKey: TStringList;
  ShaCacheVal: TStringList;
  { the .me3 profiles in this run (repair 3, verifier 4 D1) }
  Me3OtherBefore: TArrayOfString;      { per profile: its other tables (Me3OtherTablesText) right before Setup
                                         applied the natives; the verification compares the file with it }
  Me3ChangedNow: array of Boolean;     { per profile: Setup rewrote it in this run (its natives, or another
                                         mod's package table switched off) }
  { archive extraction (repair 3, code review LOWs) }
  UnpackCapBytes: Int64;               { the most bytes the running extraction may unpack (0 = no cap) }
  UnpackCapHit: Boolean;               { the built-in extractor stopped at the cap }
  SearchUnpack: Boolean;               { the automatic download search is running (its candidates get the cap) }
  ForeignNamesCount: Integer;          { other mods' files under names an option uses (Other mods page; repair 3) }
  { download plan }
  FetchFiles: Integer;
  FetchBytes: Int64;
  FetchDone: Boolean;
  FetchProblem: String;
  WorkDirRoot: String;                 { <Conv>\CXCXM_work, or CXCXM_work in Setup's temp folder }
  WorkCounter: Integer;

  Me3Profile: TArrayOfString;          { relative paths of the two me3 profiles }

  { ---- the user's (or the command line's) choices ---- }
  ConvDir: String;                     { validated Convergence folder, '' until chosen }
  ConvVersion: String;
  ForeignMove: Boolean;                { move other mods' files into the backup (default) }

  { ---- command line (read once in InitializeSetup) ---- }
  ParamConvDir: String;
  ParamComponents: String;             { /COMPONENTS= or /SELECT= }
  ParamComp: TArrayOfString;           { per component: /<CompSwitch>= value ('' = not given) }
  ParamArch: TArrayOfString;           { per archive: /ARCHIVE_<ID>= (or /CLEVER=) }
  ParamArchiveDir: String;
  ParamSearchDownloads: String;
  ParamBaseUrl: String;
  ParamUpstream: String;
  ParamForeign: String;                { move | keep ('' = move) }
  ParamGameOk: String;                 { 1 = the user confirms the game Setup could not find }
  UseUpstream: Boolean;

  { ---- check A: Elden Ring ---- }
  GameStatus: Integer;                 { GS_* }
  GameExePath: String;                 { eldenring.exe that was checked ('' when none) }
  GameVersion: String;                 { its FileVersion ('' when unreadable) }
  GameStatusText: String;              { what the Elden Ring page shows }
  GameProblem: String;                 { why Setup refuses (GS_WRONG) }
  GameConfirmed: Boolean;              { the user ticked the box / passed /GAMEOK=1 }
  GameFromBrowse: Boolean;             { the checked exe was picked with Browse }
  GameLibraryCount: Integer;           { Steam libraries looked at }
  GameSteamStatus: Integer;            { GS_* of the copy Steam launches }
  GameSteamExe: String;                { that copy ('' when none) }

  { ---- check B: The Convergence 3.0.2 manifest (extracted to Setup's temp folder) ---- }
  CmFlag: TArrayOfString;              { S size(+md5), C config, T batch file, R runtime,
                                         X not in the official release, O replaced, P .me3 }
  CmSize: array of Int64;
  CmMd5: TArrayOfString;
  CmRel: TArrayOfString;
  CmCount: Integer;
  Me3KeepProfile: TArrayOfString;      { .me3 profile (relative path) ... }
  Me3KeepLine: TArrayOfString;         { ... and a line it must keep (Me3Squeeze form) }
  KnownModFiles: TStringList;          { sorted: every file under mod\ that is not foreign }
  ConvCheckSummary: String;            { result line for the Ready page and the marker }
  BatVarName: TArrayOfString;          { Start_Convergence.bat settings players may change }
  ConvOfficial: String;                { the official release the manifest comes from }

  { ---- check C: files from other mods under <Conv>\mod ---- }
  ForeignRel: TArrayOfString;
  ForeignSize: array of Int64;
  ForeignKind: TArrayOfString;         { M movable, D in mod\dll (kept), L cannot be moved (kept) }
  ForeignNote: TArrayOfString;
  ForeignCount: Integer;
  ForeignScannedFor: String;
  Me3ExtraProfile: TArrayOfString;
  Me3ExtraLine: TArrayOfString;
  Me3ExtraKind: TArrayOfString;        { P [[package]] (switched off), N [[natives]] (kept) }
  Me3ExtraNote: TArrayOfString;
  Me3ExtraNat: array of Integer;       { a K native's own copy (another path): the native's index, else -1 }
  Me3ExtraCount: Integer;

  { ---- run state ---- }
  ActiveProgress: TOutputProgressWizardPage;   { nil when running without UI }
  BackupDir: String;                   { <Conv>\CXCXM_backup\<stamp> of this run }
  BackupMade: Boolean;
  InstallStarted: Boolean;             { ssInstall reached: files may have changed }
  InstallFinished: Boolean;            { post-install finished (pass, or handled failure) }
  PostInstallFailed: Boolean;
  VerifyFailed: Boolean;
  RolledBack: Boolean;
  VerifiedFileCount: Integer;
  FinalReport: String;                 { shown on the Finished page }

  { ---- backup plan (built before the backup) ---- }
  PlanRel: TArrayOfString;
  PlanKind: TArrayOfString;            { B N E M (D is added when the manifest is written) }
  PlanWriteBytes: Int64;
  PlanCount: Integer;
  PlanBackupBytes: Int64;
  PlanMade: Boolean;
  { ---- uninstall (repair 4, code review LOW): files at paths a run created
    that hold another mod's content now, left in place ---- }
  RestoreKeptCount: Integer;
  RestoreKeptText: String;             { "  path" lines for the log and the final message }

  { ---- Convergence detection results ---- }
  FoundDir: TArrayOfString;
  FoundVersion: TArrayOfString;
  FoundProblem: TArrayOfString;
  FoundCount: Integer;
  LauncherConvDir: String;
  ScanDone: Boolean;
  ScanTimedOut: Boolean;
  ScanStartTick: Cardinal;
  ScanDirCount: Integer;
  ScanVisited: TStringList;
  ScanSkipTmp: String;
  ScanSkipTemp: String;

{ ---- Win32 imports (kernel32 is always present; resolved on first call) ---- }
function GetTickCount: Cardinal;
  external 'GetTickCount@kernel32.dll stdcall';
function GetLogicalDrives: Cardinal;
  external 'GetLogicalDrives@kernel32.dll stdcall';
function GetDriveTypeW(lpRootPathName: String): Cardinal;
  external 'GetDriveTypeW@kernel32.dll stdcall';
function SetFileAttributesW(lpFileName: String; dwFileAttributes: Cardinal): Boolean;
  external 'SetFileAttributesW@kernel32.dll stdcall';
function GetFileAttributesW(lpFileName: String): Cardinal;
  external 'GetFileAttributesW@kernel32.dll stdcall';
function MoveFileExW(lpExistingFileName, lpNewFileName: String; dwFlags: Cardinal): Boolean;
  external 'MoveFileExW@kernel32.dll stdcall';
function GetVolumeInformationW(lpRootPathName: String; lpVolumeNameBuffer: String;
  nVolumeNameSize: Cardinal; var lpVolumeSerialNumber: Cardinal;
  var lpMaximumComponentLength: Cardinal; var lpFileSystemFlags: Cardinal;
  lpFileSystemNameBuffer: String; nFileSystemNameSize: Cardinal): Boolean;
  external 'GetVolumeInformationW@kernel32.dll stdcall';

{ the number of names (NTFS hard links) of a file: FileLinkCount in util.iss }
type
  TCxByHandleFileInfo = record
    dwFileAttributes: Cardinal;
    ftCreationTime: TFileTime;
    ftLastAccessTime: TFileTime;
    ftLastWriteTime: TFileTime;
    dwVolumeSerialNumber: Cardinal;
    nFileSizeHigh: Cardinal;
    nFileSizeLow: Cardinal;
    nNumberOfLinks: Cardinal;
    nFileIndexHigh: Cardinal;
    nFileIndexLow: Cardinal;
  end;

function CxCreateFileW(lpFileName: String; dwDesiredAccess, dwShareMode, lpSecurityAttributes,
  dwCreationDisposition, dwFlagsAndAttributes: Cardinal; hTemplateFile: THandle): THandle;
  external 'CreateFileW@kernel32.dll stdcall';
function CxGetFileInformationByHandle(hFile: THandle; var lpFileInformation: TCxByHandleFileInfo): Boolean;
  external 'GetFileInformationByHandle@kernel32.dll stdcall';
function CxCloseHandle(hObject: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
{ FlushFileToDisk (util.iss, repair 5): a temporary file's bytes reach the
  disk before it is moved to its name, so a power cut never leaves a file of
  zeros under a name the game loads }
function CxFlushFileBuffers(hFile: THandle): Boolean;
  external 'FlushFileBuffers@kernel32.dll stdcall';
{ the uninstaller holds Setup's own mutex names while it runs, so a Setup
  started meanwhile waits (Inno's SetupMutex check) instead of deleting the
  uninstaller's temporary files and planning on a half-restored folder
  (repair 6, code review of repair 5, INFO) }
function CxCreateMutexW(lpMutexAttributes: Cardinal; bInitialOwner: Boolean; lpName: String): THandle;
  external 'CreateMutexW@kernel32.dll stdcall';

{ The two Convergence profiles (relative to the Convergence folder). }
procedure InitProfileNames;
begin
  SetArrayLength(Me3Profile, ME3_PROFILE_COUNT);
  Me3Profile[0] := 'me3\convergence.me3';
  Me3Profile[1] := 'me3\convergence - seamless.me3';
end;
