{ =============================================================================
  convergence.iss - finding and validating The Convergence 3.0.2 install.

  A Convergence folder contains Start_Convergence.bat, me3\convergence.me3,
  me3\convergence - seamless.me3, mod\ and version.txt ("3.0.2.0").
  Detection sources, in order:
    1. the official launcher: %APPDATA%\ConvergenceLauncher\settings.json,
       key "InstallationPath" (the folder itself or its ConvergenceER child)
    2. common roots: Desktop, Documents, Downloads, %USERPROFILE%\Games
    3. every fixed drive, depth <= SCAN_MAX_DEPTH below the root
  The scan only reads directory listings; it never writes anything.
  ============================================================================= }

function LooksLikeConvergence(const Dir: String): Boolean;
begin
  Result := (Dir <> '') and
    FileExists(AddBackslash(Dir) + 'Start_Convergence.bat') and
    FileExists(AddBackslash(Dir) + 'me3\convergence.me3');
end;

{ Accepts what a user (or the launcher) points at and returns the actual
  Convergence folder: the folder itself, its ConvergenceER child (launcher
  InstallationPath), or its parent when me3\ or mod\ was picked. }
function ResolveConvergenceDir(const Picked: String): String;
var
  D: String;
begin
  D := NormalizeDir(Picked);
  Result := D;
  if D = '' then
    Exit;
  if LooksLikeConvergence(D) then
    Exit;
  if LooksLikeConvergence(AddBackslash(D) + 'ConvergenceER') then begin
    Result := AddBackslash(D) + 'ConvergenceER';
    Exit;
  end;
  if LooksLikeConvergence(ExtractFileDir(D)) then
    Result := ExtractFileDir(D);
end;

function ReadConvergenceVersion(const Dir: String): String;
begin
  Result := ReadFirstLine(AddBackslash(Dir) + 'version.txt');
end;

function IsInsideEldenRingGameFolder(const Dir: String): Boolean;
begin
  Result := (Pos('\elden ring\game\', Lowercase(AddBackslash(Dir))) > 0) or
    FileExists(AddBackslash(Dir) + 'eldenring.exe');
end;

{ Cloud-sync detection. Returns the service name ('' when not synced):
  OneDrive (path, or below a folder OneDrive publishes through its environment
  variables), Google Drive (its "My Drive" folder, or a drive whose volume
  label is "Google Drive"), Dropbox and iCloud Drive (by folder name). These
  services lock files or turn them into online-only placeholders, which
  breaks the game and makes the MD5 checks download every file. }
function CloudSyncService(const Dir: String): String;
var
  I: Integer;
  Root, L: String;
  Vars: TArrayOfString;
begin
  Result := '';
  L := AddBackslash(Lowercase(Dir));
  if Pos('onedrive', L) > 0 then begin
    Result := 'OneDrive';
    Exit;
  end;
  SetArrayLength(Vars, 3);
  Vars[0] := 'OneDrive';
  Vars[1] := 'OneDriveConsumer';
  Vars[2] := 'OneDriveCommercial';
  for I := 0 to 2 do begin
    Root := GetEnv(Vars[I]);
    if (Root <> '') and PathIsWithin(Dir, Root) then begin
      Result := 'OneDrive';
      Exit;
    end;
  end;
  if (Pos('\google drive\', L) > 0) or (Pos('\my drive\', L) > 0) or
    (CompareText(GetVolumeLabelOf(Dir), 'Google Drive') = 0) then
    Result := 'Google Drive'
  else if Pos('\dropbox\', L) > 0 then
    Result := 'Dropbox'
  else if Pos('\iclouddrive\', L) > 0 then
    Result := 'iCloud Drive';
end;

{ Returns '' when Dir is a valid target, otherwise a message for the user.
  WriteTest additionally creates and deletes a probe file in Dir and Dir\mod
  (only done for the folder the user actually chose). }
function DescribeConvergenceProblem(const Dir: String; const WriteTest: Boolean): String;
var
  Missing: TStringList;
  Version, D, Cloud: String;
begin
  Result := '';
  D := AddBackslash(Dir);
  if (Dir = '') or not DirExists(Dir) then begin
    Result := 'This folder does not exist:' + #13#10 + Dir;
    { a folder behind a junction a normal user made looks missing to Setup
      (Windows' RedirectionGuard): say so instead (code review repair 2, D1) }
    if Dir <> '' then begin
      Cloud := LinkBlockedNote(Dir);
      if Cloud <> '' then
        Result := 'Setup cannot open this folder:' + #13#10 + Dir + #13#10#13#10 + Cloud;
    end;
    Exit;
  end;

  { Setup is not long-path aware; the deepest backup path must fit MAX_PATH,
    with the temporary name every copy is written under first (repair 5).
    Checked first: with a very long path Windows file tools cannot even see
    the files inside, and "files are missing" would be the wrong advice. }
  if (Length(D) + Length(BACKUP_PATH_TEMPLATE) + MAX_REL_LEN + Length(REPLACE_TMP_SUFFIX) > MAX_FILE_PATH_LEN) or
    (Length(D) + Length(BACKUP_PATH_TEMPLATE) + MAX_REL_DIR_LEN > MAX_DIR_PATH_LEN) then
  begin
    Result := 'The path of this folder is too long (' + IntToStr(Length(Dir)) +
      ' characters) for Windows file tools:' + #13#10 + Dir + #13#10#13#10 +
      'Move The Convergence to a shorter path such as C:\Games\ConvergenceER with the ' +
      'Convergence Launcher, then run this installer again.';
    Exit;
  end;

  Missing := TStringList.Create;
  try
    if not FileExists(D + 'Start_Convergence.bat') then Missing.Add('Start_Convergence.bat');
    if not FileExists(D + 'me3\convergence.me3') then Missing.Add('me3\convergence.me3');
    if not FileExists(D + 'me3\convergence - seamless.me3') then Missing.Add('me3\convergence - seamless.me3');
    if not DirExists(D + 'mod') then Missing.Add('mod\');
    if not FileExists(D + 'version.txt') then Missing.Add('version.txt');
    if Missing.Count > 0 then begin
      Result := 'This is not a complete Convergence folder:' + #13#10 + Dir + #13#10#13#10 +
        'Missing: ' + JoinLimited(Missing, 10) + #13#10#13#10 +
        'Pick the folder that contains Start_Convergence.bat, me3 and mod. ' +
        'If files are missing, repair The Convergence with the Convergence Launcher.';
      Exit;
    end;
  finally
    Missing.Free;
  end;

  Version := ReadConvergenceVersion(Dir);
  if Version <> REQUIRED_CONV_VERSION then begin
    if Version = '' then
      Version := '(unknown)';
    Result := 'This Convergence is version ' + Version + '.' + #13#10 +
      CAT_VERSION_SHORT + ' needs The Convergence 3.0.2 (version.txt = ' + REQUIRED_CONV_VERSION +
      ').' + #13#10#13#10 + 'Update The Convergence with the Convergence Launcher, launch it once, then run this installer again.';
    Exit;
  end;

  if IsInsideEldenRingGameFolder(Dir) then begin
    Result := 'This Convergence folder is inside the Elden Ring game folder (ELDEN RING\Game).' + #13#10#13#10 +
      'The Convergence must live in its own folder, outside the game folder. ' +
      'Reinstall it with the Convergence Launcher to a normal folder such as C:\Games, then run this installer again.';
    Exit;
  end;

  Cloud := CloudSyncService(Dir);
  if Cloud <> '' then begin
    Result := 'This folder is synced by ' + Cloud + ':' + #13#10 + Dir + #13#10#13#10 +
      Cloud + ' breaks Elden Ring mods (it locks files or replaces them with online-only ' +
      'copies). Move The Convergence to a folder outside ' + Cloud + ' (for example ' +
      'C:\Games) with the Convergence Launcher, then run this installer again.';
    Exit;
  end;


  if WriteTest then begin
    if not (CanWriteToDir(Dir) and CanWriteToDir(D + 'mod')) then begin
      Result := 'Setup cannot write to this folder:' + #13#10 + Dir + #13#10#13#10 +
        'This usually means it is under Program Files or another protected location. ' +
        'Close Setup, right-click the installer and choose "Run as administrator", ' +
        'or move The Convergence to a normal folder such as C:\Games.';
      Exit;
    end;
  end;
end;

{ ------------------------------------------------------ detection results --- }

function FindFoundIndex(const Dir: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FoundCount - 1 do
    if PathSame(FoundDir[I], Dir) then begin
      Result := I;
      Exit;
    end;
end;

{ Re-reads the version and problem of an entry (the folder may have been
  updated, repaired or removed since it was listed). }
procedure RefreshFoundEntry(const Index: Integer);
begin
  FoundVersion[Index] := ReadConvergenceVersion(FoundDir[Index]);
  FoundProblem[Index] := DescribeConvergenceProblem(FoundDir[Index], False);
end;

{ Adds a detected (or browsed) folder to the list, or refreshes it when it is
  already listed; returns its index. }
function AddFoundDir(const Picked: String): Integer;
var
  Dir: String;
begin
  Dir := ResolveConvergenceDir(Picked);
  Result := -1;
  if Dir = '' then
    Exit;
  Result := FindFoundIndex(Dir);
  if Result >= 0 then begin
    RefreshFoundEntry(Result);
    Exit;
  end;
  Result := FoundCount;
  FoundCount := FoundCount + 1;
  SetArrayLength(FoundDir, FoundCount);
  SetArrayLength(FoundVersion, FoundCount);
  SetArrayLength(FoundProblem, FoundCount);
  FoundDir[Result] := Dir;
  FoundVersion[Result] := ReadConvergenceVersion(Dir);
  FoundProblem[Result] := DescribeConvergenceProblem(Dir, False);
  Log(Format('Convergence candidate: %s (version %s) %s', [Dir, FoundVersion[Result], FoundProblem[Result]]));
end;

function CountValidFound: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FoundCount - 1 do
    if FoundProblem[I] = '' then
      Result := Result + 1;
end;

{ -------------------------------------------------------- launcher settings --- }

{ Reads "InstallationPath" from the launcher's settings.json (a tiny JSON
  string parser: handles \\, \/, \" and \uXXXX escapes). '' if unavailable. }
function ReadLauncherInstallPath: String;
var
  Lines: TArrayOfString;
  S, Hex: String;
  P, I: Integer;
  C: Char;
begin
  Result := '';
  if not LoadStringsFromFile(ExpandConstant('{userappdata}\ConvergenceLauncher\settings.json'), Lines) then
    Exit;
  S := '';
  for I := 0 to GetArrayLength(Lines) - 1 do
    S := S + Lines[I] + ' ';
  P := Pos('"installationpath"', Lowercase(S));
  if P = 0 then
    Exit;
  S := Copy(S, P + Length('"InstallationPath"'), Length(S));
  P := Pos(':', S);
  if P = 0 then
    Exit;
  S := Copy(S, P + 1, Length(S));      { assigned first: see SubStr in util.iss }
  S := TrimLeft(S);
  if (S = '') or (S[1] <> '"') then
    Exit;
  I := 2;
  while I <= Length(S) do begin
    C := S[I];
    if C = '"' then
      Break;
    if (C = '\') and (I < Length(S)) then begin
      I := I + 1;
      C := S[I];
      if C = 'u' then begin
        Hex := Copy(S, I + 1, 4);
        Result := Result + Chr(StrToIntDef('$' + Hex, 63));
        I := I + 4;
      end else if C = 'n' then
        Result := Result + ' '
      else if C = 't' then
        Result := Result + ' '
      else
        Result := Result + C;       { \\ \/ \" }
    end else
      Result := Result + C;
    I := I + 1;
  end;
  Result := Trim(Result);
  Log('Convergence Launcher InstallationPath: ' + Result);
end;

{ ------------------------------------------------------------- drive scan --- }

function ScanOutOfTime: Boolean;
begin
  if not ScanTimedOut then
    ScanTimedOut := (GetTickCount - ScanStartTick) > SCAN_TIME_BUDGET_MS;
  Result := ScanTimedOut;
end;

function ScanShouldSkip(const Name, FullPath: String; const Attr: Cardinal): Boolean;
var
  N: String;
begin
  N := Lowercase(Name);
  Result :=
    ((Attr and FA_REPARSE_POINT) <> 0) or                         { junctions/symlinks: loops }
    (((Attr and FA_HIDDEN) <> 0) and ((Attr and FA_SYSTEM) <> 0)) or
    (N = 'windows') or (N = 'windows.old') or (N = 'windowsapps') or
    (N = 'programdata') or (N = '$recycle.bin') or (N = 'system volume information') or
    (N = 'appdata') or (N = 'node_modules') or (N = '.git') or
    (N = '$winreagent') or (N = 'recovery') or (N = 'config.msi') or (N = '$windows.~bt') or
    (N = '$windows.~ws') or (N = '$sysreset') or (N = 'msocache') or
    PathEndsWith(FullPath, '\ELDEN RING\Game', True) or
    StartsWithStr(AddBackslash(Lowercase(FullPath)), ScanSkipTmp) or
    StartsWithStr(AddBackslash(Lowercase(FullPath)), ScanSkipTemp);
end;

{ Breadth-first walk of Root down to MaxDepth levels. A folder that contains
  Start_Convergence.bat plus me3\convergence.me3 is recorded. Folders already
  listed (ScanVisited) are not listed again; common roots are scanned before
  drive roots so this never cuts a search short. }
procedure ScanTree(const Root: String; const MaxDepth: Integer);
var
  Queue: TStringList;
  Head, Depth, Bar, Idx: Integer;
  Entry, Dir, Child: String;
  FindRec: TFindRec;
begin
  if (Root = '') or not DirExists(Root) then
    Exit;
  Queue := TStringList.Create;
  try
    Queue.Add('0|' + Root);
    Head := 0;
    while (Head < Queue.Count) and not ScanOutOfTime do begin
      Entry := Queue[Head];
      Head := Head + 1;
      Bar := Pos('|', Entry);
      Depth := StrToIntDef(Copy(Entry, 1, Bar - 1), 0);
      Dir := Copy(Entry, Bar + 1, Length(Entry));
      if ScanVisited.Find(Lowercase(Dir), Idx) then
        Continue;
      ScanVisited.Add(Lowercase(Dir));
      ScanDirCount := ScanDirCount + 1;
      if (ScanDirCount mod 40) = 0 then
        ProgressText('Searching this PC for The Convergence...', Dir);

      if FindFirst(AddBackslash(Dir) + '*', FindRec) then begin
        try
          repeat
            if (FindRec.Name = '.') or (FindRec.Name = '..') then
              Continue;
            Child := AddBackslash(Dir) + FindRec.Name;
            if (FindRec.Attributes and FA_DIRECTORY) <> 0 then begin
              if (Depth < MaxDepth) and not ScanShouldSkip(FindRec.Name, Child, FindRec.Attributes) then
                Queue.Add(IntToStr(Depth + 1) + '|' + Child);
            end else if CompareText(FindRec.Name, 'Start_Convergence.bat') = 0 then begin
              if FileExists(AddBackslash(Dir) + 'me3\convergence.me3') then
                AddFoundDir(Dir);
            end;
          until not FindNext(FindRec);
        finally
          FindClose(FindRec);
        end;
      end;
    end;
  finally
    Queue.Free;
  end;
end;

{ Full detection. Safe to call again ("Search again"): results are merged. }
procedure ScanForConvergence;
var
  Roots: TStringList;
  Drives: Cardinal;
  I: Integer;
  Launcher, Root: String;
begin
  ScanTimedOut := False;
  ScanStartTick := GetTickCount;
  ScanSkipTmp := AddBackslash(Lowercase(ExpandConstant('{tmp}')));
  ScanSkipTemp := AddBackslash(Lowercase(RemoveBackslashUnlessRoot(GetTempDir)));
  ScanDirCount := 0;
  ScanVisited := TStringList.Create;
  Roots := TStringList.Create;
  try
    ScanVisited.Sorted := True;
    ScanVisited.Duplicates := dupIgnore;

    { "Search again": entries found earlier are re-checked, not kept stale }
    for I := 0 to FoundCount - 1 do
      RefreshFoundEntry(I);

    { 1. the launcher knows where it installed The Convergence }
    LauncherConvDir := '';
    Launcher := ReadLauncherInstallPath;
    if Launcher <> '' then begin
      if LooksLikeConvergence(ResolveConvergenceDir(Launcher)) then begin
        LauncherConvDir := ResolveConvergenceDir(Launcher);
        AddFoundDir(Launcher);
      end;
      Roots.Add(NormalizeDir(Launcher));
    end;

    { 2. common roots (deeper than the drive scan reaches) }
    Roots.Add(ExpandConstant('{userdesktop}'));
    Roots.Add(ExpandConstant('{userdocs}'));
    Roots.Add(GetDownloadsDir);
    Roots.Add(AddBackslash(GetEnv('USERPROFILE')) + 'Games');

    { 3. every fixed drive (Google Drive for Desktop mounts a "fixed" drive:
         it is skipped, a Convergence there would be refused anyway) }
    Drives := GetLogicalDrives;
    for I := 0 to 25 do begin
      if (Drives and (1 shl I)) <> 0 then begin
        Root := Chr(Ord('A') + I) + ':\';
        if GetDriveTypeW(Root) = DRIVE_TYPE_FIXED then begin
          if CompareText(GetVolumeLabelOf(Root), 'Google Drive') = 0 then
            Log('Skipping ' + Root + ' (Google Drive)')
          else
            Roots.Add(Root);
        end;
      end;
    end;

    for I := 0 to Roots.Count - 1 do begin
      if ScanOutOfTime then
        Break;
      ProgressText('Searching this PC for The Convergence...', Roots[I]);
      ProgressPos(I, Roots.Count);
      Log('Scanning ' + Roots[I]);
      ScanTree(NormalizeDir(Roots[I]), SCAN_MAX_DEPTH);
    end;
    ProgressPos(Roots.Count, Roots.Count);
  finally
    Roots.Free;
    ScanVisited.Free;
    ScanVisited := nil;
  end;
  ScanDone := True;
  Log(Format('Scan finished: %d folders listed, %d Convergence folders found (%d valid)', [ScanDirCount, FoundCount, CountValidFound]));
  if ScanTimedOut then
    Log('Scan stopped early (time budget reached)');
end;
