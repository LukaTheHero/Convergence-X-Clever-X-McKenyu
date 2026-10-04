{ =============================================================================
  checks.iss - "the correct version of everything", checked before anything
  is written.

  A  Elden Ring. Steam's folder comes from the registry (HKCU SteamPath,
     HKLM InstallPath); every library listed in its libraryfolders.vdf is
     searched for steamapps\common\ELDEN RING\Game\eldenring.exe (the
     library with appmanifest_1245620.acf wins). Required: FileVersion
     2.7.1.0 (= Patch 1.17) and Shadow of the Erdtree (Game\DLC.bdt and
     Game\DLC.bhd present with a plausible size, never an exact one).
     A wrong version or a missing DLC always stops Setup. When the game
     cannot be found (or its version cannot be read) the player must
     confirm it: a tick box on the Elden Ring page, /GAMEOK=1 when silent.
     In the game folder Setup only reads the exe's version resource and the
     directory entries of the two DLC files. It never writes there.

  B  The Convergence 3.0.2 integrity. build.py lists every file of the
     official 3.0.2 release (the Convergence Launcher's own download list,
     pinned at the 3.0.2.0 commit) in staging\meta\CXCXM_conv302_manifest.txt,
     extracted to Setup's temp folder at start-up. Each file must exist with
     its exact size (read from the directory entry with FindFirst: no
     hashing of 10 GB); the files that matter most (me3, mod\dll\*.dll) are
     MD5-checked too. Start_Convergence.bat is compared without its
     ':: Variables' settings lines (players may raise ER_Launch_Timeout).
     Configs (*.ini, *.toml) only need to exist, logs are ignored, and the
     files this release writes in any combination (every path of the
     catalog: the merge, its options, the files taken from the players'
     downloads) are checked after install instead. The two .me3 profiles
     get [[natives]] entries for some options, so they are checked by
     content: every Convergence line (except savefile) must still be there. Files that were in Luka's reference
     folder but are not in the official release (X: old download pieces,
     tool backups) are known but never required.

  C  Foreign files: every file under <Convergence>\mod that is neither part
     of The Convergence 3.0.2, nor a path of the catalog (any combination),
     nor a file of an older release (obsolete rows), nor a log or other
     runtime file. By default they are moved into this run's
     backup when the installation starts (uninstall moves them back). Files
     under mod\dll are listed but always kept: me3 only loads a DLL that a
     .me3 profile lists.
     Other mods loaded by the .me3 profiles: every table, package or
     natives, whose path The Convergence 3.0.2 does not have (the natives
     of the catalog aside: the installer's own options manage them). Another mod's package table (a folder of game
     files that can override the merge) is switched off by default: its
     lines become comments, and the profile is backed up whole so uninstall
     puts it back. Natives tables (DLLs) are listed and kept, like the DLLs
     in mod\dll.
  ============================================================================= }

{ ---------------------------------------------------------------- helpers --- }

{ The size in a TFindRec as one number. }
function FindRecSize(var FR: TFindRec): Int64;
var
  Low: Int64;
begin
  Result := FR.SizeHigh;
  Result := Result * 65536;
  Result := Result * 65536;
  Low := FR.SizeLow;
  Result := Result + Low;
end;

{ Size of a file from its directory entry (no need to open it); -1 when it
  does not exist or is a folder. }
function DirEntrySize(const FileName: String): Int64;
var
  FR: TFindRec;
begin
  Result := -1;
  if FindFirst(FileName, FR) then begin
    try
      if (FR.Attributes and FA_DIRECTORY) = 0 then
        Result := FindRecSize(FR);
    finally
      FindClose(FR);
    end;
  end;
end;

function SizeText(const Bytes: Int64): String;
begin
  if Bytes >= 1073741824 then
    Result := Format('%.1f GB', [Bytes / 1073741824.0])
  else if Bytes >= 1048576 then
    Result := Format('%.1f MB', [Bytes / 1048576.0])
  else if Bytes >= 1024 then
    Result := Format('%.1f KB', [Bytes / 1024.0])
  else
    Result := Format('%d bytes', [Bytes]);
end;

{ Lines of L as "- line", at most MaxItems, then "- and N more". }
function BulletList(L: TStringList; const MaxItems: Integer): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to L.Count - 1 do begin
    if I >= MaxItems then begin
      Result := Result + Format('- and %d more', [L.Count - MaxItems]) + #13#10;
      Break;
    end;
    Result := Result + '- ' + L[I] + #13#10;
  end;
  Result := TrimRight(Result);
end;

{ ====================================================== A: Elden Ring === }

procedure AddUniqueDir(L: TStringList; const DirIn: String);
var
  Dir: String;
  I: Integer;
begin
  Dir := NormalizeDir(DirIn);
  if Dir = '' then
    Exit;
  for I := 0 to L.Count - 1 do
    if PathSame(L[I], Dir) then
      Exit;
  L.Add(Dir);
end;

{ One '"key"   "value"' line of Steam's VDF text format (\\ = one backslash). }
function ParseVdfPair(const Line: String; var Key, Value: String): Boolean;
var
  S: String;
  P: Integer;
begin
  Result := False;
  S := Trim(Line);
  if (Length(S) < 2) or (S[1] <> '"') then
    Exit;
  S := Copy(S, 2, Length(S));
  P := Pos('"', S);
  if P = 0 then
    Exit;
  Key := Copy(S, 1, P - 1);
  S := Copy(S, P + 1, Length(S));      { never Trim(Copy(..)): see SubStr in util.iss }
  S := Trim(S);
  if (Length(S) < 2) or (S[1] <> '"') then
    Exit;
  S := Copy(S, 2, Length(S));
  P := Pos('"', S);
  if P = 0 then
    Exit;
  Value := Copy(S, 1, P - 1);
  StringChangeEx(Value, '\\', '\', True);
  Result := True;
end;

{ Adds every library folder listed in a libraryfolders.vdf: "path" entries
  (current Steam) and "1", "2"... entries whose value is a path (old Steam). }
procedure ReadSteamLibraryFile(const Vdf: String; Libs: TStringList);
var
  Lines: TArrayOfString;
  I: Integer;
  Key, Value: String;
begin
  if not LoadStringsFromFile(Vdf, Lines) then
    Exit;
  Log('Reading ' + Vdf);
  for I := 0 to GetArrayLength(Lines) - 1 do
    if ParseVdfPair(Lines[I], Key, Value) then
      if (CompareText(Key, 'path') = 0) or
        ((StrToIntDef(Key, -1) >= 0) and (Pos(':\', Value) > 0)) then
        AddUniqueDir(Libs, Value);
end;

{ Steam's own folder(s): registry first, then the default location. }
procedure GetSteamRoots(Roots: TStringList);
var
  S: String;
begin
#if Defined(CodeCheck) || Defined(TestBuild)
  { test builds only: /TESTSTEAM="folder" is the only Steam folder looked at }
  S := ExpandConstant('{param:TESTSTEAM|}');
  if S <> '' then begin
    Log('TESTSTEAM: ' + S + ' replaces the Steam folder from the registry');
    if DirExists(S) then
      AddUniqueDir(Roots, S);
    Exit;
  end;
#endif
  { HKLM first: its InstallPath keeps the real letter case (SteamPath in
    HKCU is all lowercase with / separators); duplicates are dropped }
  if RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath', S) and DirExists(NormalizeDir(S)) then
    AddUniqueDir(Roots, S);
  if RegQueryStringValue(HKLM32, 'SOFTWARE\Valve\Steam', 'InstallPath', S) and DirExists(NormalizeDir(S)) then
    AddUniqueDir(Roots, S);
  if RegQueryStringValue(HKCU, 'Software\Valve\Steam', 'SteamPath', S) and DirExists(NormalizeDir(S)) then
    AddUniqueDir(Roots, S);
  S := ExpandConstant('{commonpf32}\Steam');
  if DirExists(S) then
    AddUniqueDir(Roots, S);
end;

{ eldenring.exe in the Steam libraries ('' when there is none). The library
  that holds Elden Ring's app manifest wins over a leftover copy elsewhere. }
function FindEldenRingInSteam: String;
var
  Roots, Libs: TStringList;
  I: Integer;
  Exe, First: String;
begin
  Result := '';
  First := '';
  Roots := TStringList.Create;
  Libs := TStringList.Create;
  try
    GetSteamRoots(Roots);
    for I := 0 to Roots.Count - 1 do begin
      Log('Steam folder: ' + Roots[I]);
      AddUniqueDir(Libs, Roots[I]);
      ReadSteamLibraryFile(AddBackslash(Roots[I]) + 'steamapps\libraryfolders.vdf', Libs);
      ReadSteamLibraryFile(AddBackslash(Roots[I]) + 'config\libraryfolders.vdf', Libs);
    end;
    GameLibraryCount := Libs.Count;
    for I := 0 to Libs.Count - 1 do begin
      Exe := AddBackslash(Libs[I]) + GAME_SUBDIR + '\eldenring.exe';
      if not FileExists(Exe) then begin
        Log('Steam library ' + Libs[I] + ': no Elden Ring');
        Continue;
      end;
      Log('Steam library ' + Libs[I] + ': found ' + Exe);
      if (Result = '') and
        FileExists(AddBackslash(Libs[I]) + 'steamapps\appmanifest_' + ELDEN_RING_APPID + '.acf') then
        Result := Exe;
      if First = '' then
        First := Exe;
    end;
    if Result = '' then
      Result := First;
  finally
    Roots.Free;
    Libs.Free;
  end;
end;

{ Checks one eldenring.exe ('' = not found) and fills the Game* globals. }
procedure EvaluateGameExe(const Exe: String);
var
  Have, Want: Int64;
  GameDir, VerMsg, DlcMsg, Missing: String;
  Bdt, Bhd: Int64;
  Cmp: Integer;
begin
  GameExePath := Exe;
  GameVersion := '';
  GameProblem := '';
  if Exe = '' then begin
    GameStatus := GS_NOTFOUND;
    GameStatusText := Format('Setup could not find Elden Ring in your Steam libraries (%d looked at).', [GameLibraryCount]) + #13#10 +
      'Click Browse and select your ELDEN RING folder, or tick the box below if you are sure you have ' +
      'Elden Ring ' + GAME_PATCH_NAME + ' with Shadow of the Erdtree.';
    Log('Elden Ring check: not found');
    Exit;
  end;

  GameDir := ExtractFileDir(Exe);
  if not (GetVersionNumbersString(Exe, GameVersion) and GetPackedVersion(Exe, Have)) then begin
    GameVersion := '';
    GameStatus := GS_NOVERSION;
    GameStatusText := 'Elden Ring found:' + #13#10 + Exe + #13#10 +
      'but Setup cannot read its version. Tick the box below if you are sure it is ' +
      GAME_PATCH_NAME + ' with Shadow of the Erdtree.';
    Log('Elden Ring check: version of ' + Exe + ' unreadable');
    Exit;
  end;

  VerMsg := '';
  if StrToVersion(REQUIRED_GAME_VERSION, Want) then begin
    Cmp := ComparePackedVersion(Have, Want);
    if Cmp < 0 then begin
      VerMsg := 'This Elden Ring is older than the latest ' + GAME_PATCH_NAME + ' update: The Convergence ' +
        '3.0.2 and ' + CAT_VERSION_SHORT + ' need exe version ' + REQUIRED_GAME_VERSION + ', yours is ' +
        GameVersion + '.';
      if GameVersion = GAME_PATCH_FIRST_EXE then
        VerMsg := VerMsg + ' (' + GAME_PATCH_FIRST_EXE + ' is the first release of ' + GAME_PATCH_NAME +
          '; ' + REQUIRED_GAME_VERSION + ' is its later update.)';
      VerMsg := VerMsg + ' Let Steam finish updating ELDEN RING: in Steam, open Library > ELDEN RING > ' +
        'Properties > Updates, set "Automatic updates" to "Always keep this game updated" (not "Only ' +
        'update this game when I launch it"), wait until the update is done, then run this installer again.';
    end else if Cmp > 0 then
      VerMsg := 'This Elden Ring is version ' + GameVersion + ', newer than ' + GAME_PATCH_NAME +
        ' (version ' + REQUIRED_GAME_VERSION + '). The Convergence 3.0.2 and ' + CAT_VERSION_SHORT +
        ' are made for ' +
        GAME_PATCH_NAME + ' and do not support a newer patch. Wait for updates of The Convergence and ' +
        'of this merge.';
  end;

  Bdt := DirEntrySize(GameDir + '\DLC.bdt');
  Bhd := DirEntrySize(GameDir + '\DLC.bhd');
  DlcMsg := '';
  Missing := '';
  if Bdt < 0 then
    Missing := 'Game\DLC.bdt';
  if Bhd < 0 then begin
    if Missing <> '' then
      Missing := Missing + ' and ';
    Missing := Missing + 'Game\DLC.bhd';
  end;
  if Missing <> '' then
    DlcMsg := 'Shadow of the Erdtree is not installed (' + Missing + ' missing). The Convergence and this ' +
      'merge need Shadow of the Erdtree. Install the DLC through Steam, then run this installer again.'
  else if (Bdt < DLC_BDT_MIN_BYTES) or (Bhd < DLC_BHD_MIN_BYTES) then
    DlcMsg := 'Shadow of the Erdtree looks incomplete (DLC.bdt is ' + SizeText(Bdt) + ', DLC.bhd is ' +
      SizeText(Bhd) + '). Let Steam finish the download, or let Steam verify the game files ' +
      '(Library > ELDEN RING > Properties > Installed Files), then run this installer again.';

  if (VerMsg = '') and (DlcMsg = '') then begin
    GameStatus := GS_OK;
    GameStatusText := 'OK: Elden Ring ' + GAME_PATCH_NAME + ' (version ' + GameVersion +
      ') with Shadow of the Erdtree.' + #13#10 + Exe;
  end else begin
    GameStatus := GS_WRONG;
    GameProblem := 'Elden Ring: ' + Exe + #13#10 + 'Version: ' + GameVersion + ' (' + GAME_PATCH_NAME +
      ' is ' + REQUIRED_GAME_VERSION + ')';
    if VerMsg <> '' then
      GameProblem := GameProblem + #13#10#13#10 + VerMsg;
    if DlcMsg <> '' then
      GameProblem := GameProblem + #13#10#13#10 + DlcMsg;
    GameStatusText := GameProblem;
  end;
  Log(Format('Elden Ring check: %s, version %s, DLC.bdt %s, DLC.bhd %s, status %d', [Exe, GameVersion, SizeText(Bdt), SizeText(Bhd), GameStatus]));
end;

{ Looks for the game in the Steam libraries and checks it. }
procedure RunGameCheck;
begin
  GameFromBrowse := False;
  GameLibraryCount := 0;
  EvaluateGameExe(FindEldenRingInSteam);
  GameSteamStatus := GameStatus;
  GameSteamExe := GameExePath;
end;

{ Browse is only for a game Setup cannot check itself. When Steam's copy was
  found and read, that copy is what Start_Convergence.bat launches
  (me3 launch --auto-detect), so its verdict stands: picking another folder
  must never turn a refusal into a pass. }
function GameBrowseAllowed: Boolean;
begin
  Result := (GameSteamStatus = GS_NOTFOUND) or (GameSteamStatus = GS_NOVERSION);
end;

{ eldenring.exe inside a folder the player picked: the ELDEN RING folder,
  its Game folder, or the Steam library that holds it. '' when none. }
function GameExeInFolder(const Dir: String): String;
begin
  Result := '';
  if FileExists(AddBackslash(Dir) + 'eldenring.exe') then
    Result := AddBackslash(Dir) + 'eldenring.exe'
  else if FileExists(AddBackslash(Dir) + 'Game\eldenring.exe') then
    Result := AddBackslash(Dir) + 'Game\eldenring.exe'
  else if FileExists(AddBackslash(Dir) + GAME_SUBDIR + '\eldenring.exe') then
    Result := AddBackslash(Dir) + GAME_SUBDIR + '\eldenring.exe';
end;

{ The player picked a folder with Browse. '' when it was checked (the Game*
  globals now describe it), otherwise why nothing was checked. }
function ApplyGameBrowse(const Dir: String): String;
var
  Exe: String;
begin
  Result := '';
  if not GameBrowseAllowed then begin
    Result := 'Steam launches the Elden Ring in' + #13#10 + GameSteamExe + #13#10 +
      'Setup checks that copy; another folder cannot replace it.';
    Log('Browse refused: Steam''s copy was found and read (' + GameSteamExe + ')');
    Exit;
  end;
  Exe := GameExeInFolder(Dir);
  if Exe = '' then begin
    Result := 'There is no eldenring.exe in' + #13#10 + Dir + #13#10#13#10 +
      'Select the ELDEN RING folder (it contains Game\eldenring.exe).';
    Exit;
  end;
  EvaluateGameExe(Exe);
  GameFromBrowse := True;
  Log('Elden Ring selected with Browse: ' + Exe);
end;

{ The game check again, right before files change (Steam may have updated the
  game while the wizard was open). A folder picked with Browse is checked
  again only while Steam still cannot check its own copy. }
procedure RecheckGame;
var
  WasBrowse: Boolean;
  Browsed: String;
begin
  WasBrowse := GameFromBrowse;
  Browsed := GameExePath;
  RunGameCheck;
  if WasBrowse and (Browsed <> '') and GameBrowseAllowed then begin
    EvaluateGameExe(Browsed);
    GameFromBrowse := True;
  end;
end;

{ True when Setup may continue as far as the game is concerned. }
function GameCheckPassed: Boolean;
begin
  Result := (GameStatus = GS_OK) or
    (((GameStatus = GS_NOTFOUND) or (GameStatus = GS_NOVERSION)) and GameConfirmed);
end;

{ For the Ready page and the marker. }
function GameSummaryText: String;
begin
  if GameStatus = GS_OK then begin
    Result := GameExePath + ' - version ' + GameVersion + ' (' + GAME_PATCH_NAME +
      '), Shadow of the Erdtree installed';
    if GameFromBrowse then
      Result := Result + ' (selected with Browse: Steam could not check its own copy)';
  end else if GameStatus = GS_NOTFOUND then
    Result := 'not found in the Steam libraries; the player confirmed ' + GAME_PATCH_NAME +
      ' with Shadow of the Erdtree'
  else if GameStatus = GS_NOVERSION then
    Result := GameExePath + ' (version unreadable); the player confirmed ' + GAME_PATCH_NAME +
      ' with Shadow of the Erdtree'
  else
    Result := '(not checked)';
end;

{ ==================================== B: The Convergence 3.0.2 integrity === }

{ Extracts and reads the manifest; builds KnownModFiles. False = the
  installer itself is damaged (Problem says so). }
function LoadConvManifest(var Problem: String): Boolean;
var
  Lines: TArrayOfString;
  I, N, K, P, Idx: Integer;
  S, FileName: String;
begin
  Result := False;
  Problem := '';
  FileName := ExpandConstant('{tmp}\') + CONV_MANIFEST_FILE;
  try
    ExtractTemporaryFile(CONV_MANIFEST_FILE);
  except
    Problem := 'Setup could not unpack its list of The Convergence 3.0.2 files (' + GetExceptionMessage +
      '). The installer file is damaged: download it again.';
    Exit;
  end;
  if not LoadStringsFromFile(FileName, Lines) or (GetArrayLength(Lines) = 0) or
    (Trim(Lines[0]) <> CONV_MANIFEST_MAGIC) then
  begin
    Problem := 'Setup''s list of The Convergence 3.0.2 files is unreadable. The installer file is damaged: ' +
      'download it again.';
    Exit;
  end;

  N := GetArrayLength(Lines);
  SetArrayLength(CmFlag, N);
  SetArrayLength(CmSize, N);
  SetArrayLength(CmMd5, N);
  SetArrayLength(CmRel, N);
  SetArrayLength(Me3KeepProfile, 0);
  SetArrayLength(Me3KeepLine, 0);
  SetArrayLength(BatVarName, 0);
  ConvOfficial := '';
  K := 0;
  for I := 1 to N - 1 do begin
    S := Lines[I];
    if Copy(S, 1, 9) = 'OFFICIAL=' then
      ConvOfficial := Copy(S, 10, Length(S))
    else if Copy(S, 1, 2) = 'V|' then begin
      { a Start_Convergence.bat setting players may change }
      Idx := GetArrayLength(BatVarName);
      SetArrayLength(BatVarName, Idx + 1);
      BatVarName[Idx] := Lowercase(Copy(S, 3, Length(S)));
    end else if Copy(S, 1, 2) = 'F|' then begin
      { F|flag|size|md5|relative path }
      CmFlag[K] := Copy(S, 3, 1);
      S := Copy(S, 5, Length(S));
      P := Pos('|', S);
      CmSize[K] := StrToInt64Def(Copy(S, 1, P - 1), -1);
      S := Copy(S, P + 1, Length(S));
      P := Pos('|', S);
      CmMd5[K] := Copy(S, 1, P - 1);
      CmRel[K] := Copy(S, P + 1, Length(S));
      if (CmRel[K] = '') or (Length(CmFlag[K]) <> 1) or (Pos(CmFlag[K], 'SCTRXOP') = 0) or
        ((CmFlag[K] = 'S') and (CmSize[K] < 0)) or ((CmFlag[K] = 'T') and (Length(CmMd5[K]) <> 32)) then
      begin
        Problem := 'Setup''s list of The Convergence 3.0.2 files is damaged (line ' + IntToStr(I + 1) +
          '). Download the installer again.';
        Exit;
      end;
      K := K + 1;
    end else if Copy(S, 1, 2) = 'K|' then begin
      { K|profile|line }
      S := Copy(S, 3, Length(S));
      P := Pos('|', S);
      Idx := GetArrayLength(Me3KeepLine);
      SetArrayLength(Me3KeepProfile, Idx + 1);
      SetArrayLength(Me3KeepLine, Idx + 1);
      Me3KeepProfile[Idx] := Copy(S, 1, P - 1);
      Me3KeepLine[Idx] := Copy(S, P + 1, Length(S));
    end;
  end;
  CmCount := K;
  SetArrayLength(CmFlag, K);
  SetArrayLength(CmSize, K);
  SetArrayLength(CmMd5, K);
  SetArrayLength(CmRel, K);
  if (CmCount <> CONV302_FILE_COUNT) or (GetArrayLength(Me3KeepLine) = 0) or
    (GetArrayLength(BatVarName) = 0) or (ConvOfficial = '') then
  begin
    Problem := Format('Setup''s list of The Convergence 3.0.2 files is incomplete (%d of %d files). ' +
      'Download the installer again.', [CmCount, CONV302_FILE_COUNT]);
    Exit;
  end;

  { every file under mod\ that belongs there: The Convergence 3.0.2, every
    path of the catalog (this release in every combination, the files taken
    from the players' downloads, user config files) and the files of older
    releases (obsolete rows, removed by this installer when they match) }
  KnownModFiles := TStringList.Create;
  KnownModFiles.Sorted := True;
  KnownModFiles.Duplicates := dupIgnore;
  for I := 0 to CmCount - 1 do
    KnownModFiles.Add(CmRel[I]);
  for I := 0 to GetArrayLength(PathRel) - 1 do
    KnownModFiles.Add(PathRel[I]);
  for I := 0 to GetArrayLength(ObsRel) - 1 do
    KnownModFiles.Add(ObsRel[I]);
  Log(Format('Convergence 3.0.2 manifest (official release %s): %d files, %d .me3 lines to keep, ' +
    '%d batch settings, %d known file names', [ConvOfficial, CmCount, GetArrayLength(Me3KeepLine),
    GetArrayLength(BatVarName), KnownModFiles.Count]));
  Result := True;
end;

{ Lowercase, no spaces, tabs or double quotes (build.py: bat_squeeze). }
function BatSqueeze(const Line: String): String;
begin
  Result := Lowercase(Trim(Line));
  StringChangeEx(Result, ' ', '', True);
  StringChangeEx(Result, #9, '', True);
  StringChangeEx(Result, '"', '', True);
end;

{ True for a "set NAME=value" line of a setting players may change. }
function IsBatSettingLine(const Line: String): Boolean;
var
  S: String;
  I: Integer;
begin
  Result := False;
  S := BatSqueeze(Line);
  for I := 0 to GetArrayLength(BatVarName) - 1 do
    if StartsWithStr(S, 'set' + BatVarName[I] + '=') then begin
      Result := True;
      Exit;
    end;
end;

{ md5 of Start_Convergence.bat without its settings lines, exactly as
  build.py computes it (bat_normalized_md5): the other lines joined with LF,
  trailing empty lines dropped, hashed as UTF-16LE. '' when unreadable. }
function BatNormalizedMd5(const FileName: String): String;
var
  Lines: TArrayOfString;
  Kept: TStringList;
  I: Integer;
  Text: String;
begin
  Result := '';
  if not LoadStringsFromFile(FileName, Lines) then
    Exit;
  Kept := TStringList.Create;
  try
    for I := 0 to GetArrayLength(Lines) - 1 do
      if not IsBatSettingLine(Lines[I]) then
        Kept.Add(Lines[I]);
    while (Kept.Count > 0) and (Trim(Kept[Kept.Count - 1]) = '') do
      Kept.Delete(Kept.Count - 1);
    Text := '';
    for I := 0 to Kept.Count - 1 do begin
      if I > 0 then
        Text := Text + #10;
      Text := Text + Kept[I];
    end;
  finally
    Kept.Free;
  end;
  Result := Lowercase(GetMD5OfUnicodeString(Text));
end;

{ A .me3 profile must keep every Convergence line (build.py lists them). }
procedure CheckMe3Keeps(const Full, Rel: String; Bad: TStringList);
var
  Lines: TArrayOfString;
  Have: TStringList;
  I, Idx: Integer;
begin
  if not LoadStringsFromFile(Full, Lines) then begin
    Bad.Add(Rel + ' (cannot be read)');
    Exit;
  end;
  Have := TStringList.Create;
  try
    Have.Sorted := True;
    Have.Duplicates := dupIgnore;
    for I := 0 to GetArrayLength(Lines) - 1 do
      if Me3IsActiveLine(Lines[I]) then
        Have.Add(Me3Squeeze(Lines[I]));
    for I := 0 to GetArrayLength(Me3KeepLine) - 1 do
      if (CompareText(Me3KeepProfile[I], Rel) = 0) and not Have.Find(Me3KeepLine[I], Idx) then
        Bad.Add(Rel + ' (the line ' + Me3KeepLine[I] + ' is missing)');
  finally
    Have.Free;
  end;
end;

{ Checks Dir against the pristine Convergence 3.0.2. True when intact.
  Problem: message for the player (count + the first 10 paths + what to do).
  Summary: one line for the Ready page and the marker. }
function CheckConvergenceIntegrity(const Dir: String; var Problem, Summary: String): Boolean;
var
  Bad: TStringList;
  I, Checked, Hashed, Replaced, Configs, Ignored, NotOfficial: Integer;
  Full: String;
  Size: Int64;
  T0: Cardinal;
  BatChanged: Boolean;
begin
  Result := False;
  Problem := '';
  Summary := '';
  T0 := GetTickCount;
  BatChanged := False;
  Bad := TStringList.Create;
  try
    Checked := 0;
    Hashed := 0;
    Replaced := 0;
    Configs := 0;
    Ignored := 0;
    NotOfficial := 0;
    for I := 0 to CmCount - 1 do begin
      if (I mod 100) = 0 then begin
        ProgressText(Format('Checking the files of The Convergence 3.0.2 (%d of %d)...', [I + 1, CmCount]), CmRel[I]);
        ProgressPos(I, CmCount);
      end;
      if CmFlag[I] = 'R' then begin
        Ignored := Ignored + 1;
        Continue;
      end;
      { not part of the official release (old download pieces, tool
        backups in Luka's reference folder): never required }
      if CmFlag[I] = 'X' then begin
        NotOfficial := NotOfficial + 1;
        Continue;
      end;
      if CmFlag[I] = 'O' then begin
        Replaced := Replaced + 1;
        Continue;
      end;
      Full := AddBackslash(Dir) + CmRel[I];
      Size := DirEntrySize(Full);
      Checked := Checked + 1;
      if Size < 0 then begin
        Bad.Add(CmRel[I] + ' (missing)');
        Continue;
      end;
      if CmFlag[I] = 'C' then
        Configs := Configs + 1
      else if CmFlag[I] = 'P' then
        CheckMe3Keeps(Full, CmRel[I], Bad)
      else if CmFlag[I] = 'T' then begin
        { the batch file: any size, its text apart from the settings lines }
        Hashed := Hashed + 1;
        if CompareText(BatNormalizedMd5(Full), CmMd5[I]) <> 0 then begin
          Bad.Add(CmRel[I] + ' (changed in more than its '':: Variables'' settings)');
          BatChanged := True;
        end;
      end else if Size <> CmSize[I] then
        Bad.Add(CmRel[I] + Format(' (wrong size: %d bytes instead of %d)', [Size, CmSize[I]]))
      else if CmMd5[I] <> '' then begin
        Hashed := Hashed + 1;
        ProgressText('Checking the files of The Convergence 3.0.2 (MD5)...', CmRel[I]);
        if CompareText(SafeMD5(Full), CmMd5[I]) <> 0 then
          Bad.Add(CmRel[I] + ' (same size, different content)');
      end;
    end;
    ProgressPos(CmCount, CmCount);
    Log(Format('Convergence 3.0.2 check of %s against the official release %s: %d files checked ' +
      '(%d by MD5, %d configs by existence), %d written by this release, %d logs ignored, ' +
      '%d not in the official release (not required), %d problem(s), %d ms', [Dir, ConvOfficial, Checked,
      Hashed, Configs, Replaced, Ignored, NotOfficial, Bad.Count, GetTickCount - T0]));
    for I := 0 to Bad.Count - 1 do
      if I < 200 then
        Log('  Convergence 3.0.2 problem: ' + Bad[I]);

    if Bad.Count = 0 then begin
      Summary := Format('PASSED - %d files of the official Convergence 3.0.2 release are there with the ' +
        'right size (%d also checked by MD5 or content, the .me3 profiles by content); %d files that ' +
        'this release writes are checked after install', [Checked, Hashed,
        Replaced]);
      Result := True;
      Exit;
    end;
    Problem := Format('The Convergence 3.0.2 in this folder is incomplete or was changed: %d file(s) ' +
      'are missing or differ from the official 3.0.2 release.', [Bad.Count]) + #13#10 + Dir + #13#10#13#10 +
      BulletList(Bad, 10) + #13#10#13#10 +
      CAT_VERSION_SHORT + ' needs an unchanged The Convergence 3.0.2. Open the Convergence Launcher and ' +
      'let it verify ' +
      '(repair) The Convergence 3.0.2, or reinstall it, launch it once, then run this installer again.';
    if BatChanged then
      Problem := Problem + #13#10#13#10 + 'Start_Convergence.bat: you may change the "set" lines under ' +
        '":: Variables" at its top (for example ER_Launch_Timeout), but nothing else. Undo your other ' +
        'edits, or let the Launcher verify (repair) the files.';
  finally
    Bad.Free;
  end;
end;

{ ============================================ C: files from other mods === }

{ Runtime output that belongs to no mod: logs, crash dumps, saves, and the
  files Windows Explorer drops into folders. Never listed, never moved.
  Also the skill settings a DLL writes next to itself (mod\dll\*.skills.ini:
  Nightreign Movement 0.2 writes one at run time; rc8 switch prep, review
  MINOR): the player's data, like a save. }
function IsRuntimeFile(const Rel: String): Boolean;
var
  L, Name, Ext: String;
begin
  L := Lowercase(Rel);
  Name := ExtractFileName(L);
  Ext := ExtractFileExt(L);
  Result := (Ext = '.log') or (Pos('.log.', Name) > 0) or (Ext = '.dmp') or
    (Ext = '.sl2') or (Ext = '.co2') or (Copy(Name, 1, 7) = 'er0000.') or
    (Name = 'desktop.ini') or (Name = 'thumbs.db') or
    (Copy(L, 1, 13) = 'mod\dll\logs\') or
    ((Copy(L, 1, 8) = 'mod\dll\') and (Length(Name) > 11) and
     (Copy(Name, Length(Name) - 10, 11) = '.skills.ini'));
end;

{ ------------------------------------------- backup folders, write targets --- }

function BackupRoot(const Conv: String): String;
begin
  Result := AddBackslash(Conv) + BACKUP_ROOT_NAME;
end;

function ReadBackupManifest(const BDir: String; var Lines: TArrayOfString): Boolean;
begin
  Result := LoadStringsFromFile(AddBackslash(BDir) + BACKUP_MANIFEST_NAME, Lines) and
    (GetArrayLength(Lines) > 0) and
    ((Trim(Lines[0]) = BACKUP_MANIFEST_MAGIC) or (Trim(Lines[0]) = BACKUP_MANIFEST_MAGIC_2));
end;

function ManifestValue(const Lines: TArrayOfString; const Key: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(Lines) - 1 do
    if CompareText(Copy(Lines[I], 1, Length(Key) + 1), Key + '=') = 0 then begin
      Result := Copy(Lines[I], Length(Key) + 2, Length(Lines[I]));
      Exit;
    end;
end;

{ All backup folders of Conv that hold a manifest, oldest first: ordered by
  the manifest's SEQ number (a manifest without one counts as 0), then by
  folder name. The order never depends on the clock (DST, clock changes). }
procedure ListBackupDirs(const Conv: String; Dirs: TStringList);
var
  FindRec: TFindRec;
  Lines: TArrayOfString;
  Root: String;
  I: Integer;
begin
  Dirs.Clear;
  Root := BackupRoot(Conv);
  if FindFirst(AddBackslash(Root) + '*', FindRec) then begin
    try
      repeat
        if ((FindRec.Attributes and FA_DIRECTORY) <> 0) and (FindRec.Name <> '.') and (FindRec.Name <> '..') then
          if ReadBackupManifest(AddBackslash(Root) + FindRec.Name, Lines) then
            Dirs.Add(Format('%.9d|%s', [StrToIntDef(ManifestValue(Lines, 'SEQ'), 0),
              AddBackslash(Root) + FindRec.Name]));
      until not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;
  Dirs.Sort;
  for I := 0 to Dirs.Count - 1 do
    Dirs[I] := Copy(Dirs[I], 11, Length(Dirs[I]));
end;

{ Adds Rel to L (sorted, no duplicates, case-insensitive) when it is a safe
  relative path. }
procedure AddWriteTarget(L: TStringList; const Rel: String);
begin
  if (Rel <> '') and IsSafeRelPath(Rel) then
    L.Add(Rel);
end;

{ Every path inside Conv that a run of this installer or its uninstaller
  writes: the catalog's paths, the obsolete files, the fields' ini files,
  the two .me3 profiles, the marker, and every path a backup manifest of
  Conv lists (the uninstall copies those back). Each of them is written
  through "<path>.cxtmp" (util.iss CommitTempFile), so these temporary names
  are this installer's own and nothing else's: the backup manifests are the
  journal of what a stopped run may have left (repair 5). }
procedure ListWriteTargets(const Conv: String; L: TStringList);
var
  Dirs: TStringList;
  Lines: TArrayOfString;
  I, J: Integer;
  Rel: String;
begin
  L.Sorted := True;
  L.Duplicates := dupIgnore;
  for I := 0 to GetArrayLength(PathRel) - 1 do
    AddWriteTarget(L, PathRel[I]);
  for I := 0 to GetArrayLength(ObsRel) - 1 do
    AddWriteTarget(L, ObsRel[I]);
  for I := 0 to GetArrayLength(FieldRel) - 1 do
    AddWriteTarget(L, FieldRel[I]);
  for I := 0 to GetArrayLength(Me3Profile) - 1 do
    AddWriteTarget(L, Me3Profile[I]);
  AddWriteTarget(L, MARKER_NAME);
  Dirs := TStringList.Create;
  try
    ListBackupDirs(Conv, Dirs);
    for I := 0 to Dirs.Count - 1 do
      if ReadBackupManifest(Dirs[I], Lines) then
        for J := 0 to GetArrayLength(Lines) - 1 do
          { files only: B N E M (a D line names a folder, never written through
            "<name>.cxtmp"; repair 6, code review of repair 5, INFO) }
          if (Length(Lines[J]) > 2) and (Copy(Lines[J], 2, 1) = '|') and
            (Pos(Copy(Lines[J], 1, 1), 'BNEM') > 0) then
          begin
            Rel := Copy(Lines[J], 3, Length(Lines[J]));
            AddWriteTarget(L, Rel);
          end;
  finally
    Dirs.Free;
  end;
end;

{ "<file>.cxtmp" next to a file under mod\ that belongs there (KnownModFiles):
  the temporary copy of a Setup or uninstall that was stopped hard (every
  file is written under that name first; util.iss CommitTempFile). It is
  this installer's own, never another mod's: never listed or moved, and
  deleted when the installation starts (backup.iss DeleteStaleTempFiles;
  repair 5, sixth verifier DEFECT 1 LOW). }
function IsOwnTempFile(const Rel: String; WriteTargets: TStringList): Boolean;
var
  L, Base: String;
  Idx: Integer;
begin
  Result := False;
  L := Lowercase(Rel);
  if (Length(L) <= Length(REPLACE_TMP_SUFFIX)) or
    (Copy(L, Length(L) - Length(REPLACE_TMP_SUFFIX) + 1, Length(REPLACE_TMP_SUFFIX)) <> REPLACE_TMP_SUFFIX) then
    Exit;
  Base := Copy(Rel, 1, Length(Rel) - Length(REPLACE_TMP_SUFFIX));
  { repair 6 (code review of repair 5, INFO): the same list the clean-up
    deletes from (ListWriteTargets: catalog paths, obsolete files, field
    inis, profiles, marker, every file a backup manifest names - a stopped
    uninstall's restore copy of another mod's file too) }
  Result := ((KnownModFiles <> nil) and KnownModFiles.Find(Base, Idx)) or
    ((WriteTargets <> nil) and WriteTargets.Find(Base, Idx));
end;

procedure ForeignClear;
begin
  ForeignCount := 0;
  SetArrayLength(ForeignRel, 0);
  SetArrayLength(ForeignSize, 0);
  SetArrayLength(ForeignKind, 0);
  SetArrayLength(ForeignNote, 0);
end;

{ The arrays grow in chunks (another overhaul unpacked into mod\ can mean
  thousands of files); ForeignCount is the number of entries in use. }
procedure ForeignAdd(const Rel: String; const Size: Int64; const Kind, Note: String);
var
  Cap: Integer;
begin
  if ForeignCount >= GetArrayLength(ForeignRel) then begin
    Cap := GetArrayLength(ForeignRel) * 2 + 64;
    SetArrayLength(ForeignRel, Cap);
    SetArrayLength(ForeignSize, Cap);
    SetArrayLength(ForeignKind, Cap);
    SetArrayLength(ForeignNote, Cap);
  end;
  ForeignRel[ForeignCount] := Rel;
  ForeignSize[ForeignCount] := Size;
  ForeignKind[ForeignCount] := Kind;
  ForeignNote[ForeignCount] := Note;
  ForeignCount := ForeignCount + 1;
end;

function ForeignCountOf(const Kinds: String): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to ForeignCount - 1 do
    if Pos(ForeignKind[I], Kinds) > 0 then
      Result := Result + 1;
end;

{ The active lines of both .me3 profiles, lowercase, / instead of \. }
function Me3ProfilesText(const Dir: String): String;
var
  Lines: TArrayOfString;
  I, J: Integer;
begin
  Result := '';
  for I := 0 to ME3_PROFILE_COUNT - 1 do
    if LoadStringsFromFile(AddBackslash(Dir) + Me3Profile[I], Lines) then
      for J := 0 to GetArrayLength(Lines) - 1 do
        if Me3IsActiveLine(Lines[J]) then
          Result := Result + Lowercase(Lines[J]) + #10;
  StringChangeEx(Result, '\', '/', True);
end;

{ ------------------------------------ C: other mods in the .me3 profiles --- }

procedure Me3ExtraClear;
begin
  Me3ExtraCount := 0;
  SetArrayLength(Me3ExtraProfile, 0);
  SetArrayLength(Me3ExtraLine, 0);
  SetArrayLength(Me3ExtraKind, 0);
  SetArrayLength(Me3ExtraNote, 0);
  SetArrayLength(Me3ExtraNat, 0);
end;

procedure Me3ExtraAdd(const Profile, Line, Kind, Note: String; const Nat: Integer);
begin
  SetArrayLength(Me3ExtraProfile, Me3ExtraCount + 1);
  SetArrayLength(Me3ExtraLine, Me3ExtraCount + 1);
  SetArrayLength(Me3ExtraKind, Me3ExtraCount + 1);
  SetArrayLength(Me3ExtraNote, Me3ExtraCount + 1);
  SetArrayLength(Me3ExtraNat, Me3ExtraCount + 1);
  Me3ExtraProfile[Me3ExtraCount] := Profile;
  Me3ExtraLine[Me3ExtraCount] := Line;
  Me3ExtraKind[Me3ExtraCount] := Kind;
  Me3ExtraNote[Me3ExtraCount] := Note;
  Me3ExtraNat[Me3ExtraCount] := Nat;
  Me3ExtraCount := Me3ExtraCount + 1;
end;

{ The [[natives]] entries of other mods that stay: every 'N' entry except a
  K native's own copy while that option is on (it is replaced by ours). }
function Me3ExtraNativesKept: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Me3ExtraCount - 1 do
    if (Me3ExtraKind[I] = 'N') and ((Me3ExtraNat[I] < 0) or not NativeOn(Me3ExtraNat[I])) then
      Result := Result + 1;
end;

{ The player's own copies of a K native that this run replaces by ours. }
function Me3ExtraNativesReplaced: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Me3ExtraCount - 1 do
    if (Me3ExtraKind[I] = 'N') and (Me3ExtraNat[I] >= 0) and NativeOn(Me3ExtraNat[I]) then
      Result := Result + 1;
end;

function Me3ExtraCountOf(const Kinds: String): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Me3ExtraCount - 1 do
    if Pos(Me3ExtraKind[I], Kinds) > 0 then
      Result := Result + 1;
end;

function Me3ExtraCountIn(const Profile, Kinds: String): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Me3ExtraCount - 1 do
    if (Pos(Me3ExtraKind[I], Kinds) > 0) and (CompareText(Me3ExtraProfile[I], Profile) = 0) then
      Result := Result + 1;
end;

{ True when Squeezed is a line The Convergence 3.0.2 has in this profile. }
function Me3KeepHas(const Profile, Squeezed: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to GetArrayLength(Me3KeepLine) - 1 do
    if (Me3KeepLine[I] = Squeezed) and (CompareText(Me3KeepProfile[I], Profile) = 0) then begin
      Result := True;
      Exit;
    end;
end;

{ 'P' when line I is the path line of another mod's [[package]] table, 'N'
  for another mod's [[natives]] table, '' otherwise (not a path line, a line
  of The Convergence 3.0.2, or a native of the catalog, which the
  installer's options handle). Kinds = Me3Classify(Lines): a path line is a
  key line of its table (repair 3: a line inside a multi-line list is not). }
function Me3OtherModKindK(const Lines: TArrayOfString; const Kinds: TArrayOfInteger; const I: Integer;
  const Profile: String): String;
var
  S, H: String;
  Owner: Integer;
begin
  Result := '';
  if Kinds[I] <> ME3_K_KEY then
    Exit;
  S := Me3Squeeze(Lines[I]);
  if not StartsWithStr(S, 'path=') then
    Exit;
  { every catalog native's entry (Infinite Arrows, Nightreign Movement,
    ERCapacityExpansion, ...) belongs to the installer's own options, which
    add and remove them }
  if Me3KeepHas(Profile, S) then
    Exit;
  { the player's own copy of a K native (ERCapacityExpansion at another path)
    is another mod's native: kept while the option is off }
  if Me3OwnKNative(Lines[I]) >= 0 then begin
    Owner := Me3OwnerHeaderK(Kinds, I);
    if (Owner >= 0) and IsNativesHeaderLine(Lines[Owner]) then
      Result := 'N';
    Exit;
  end;
  if Me3LineIsCatalogNative(Lines[I]) then
    Exit;
  Owner := Me3OwnerHeaderK(Kinds, I);
  if Owner < 0 then
    Exit;
  H := Me3Squeeze(Lines[Owner]);
  if (H = '[[package]]') or (H = '[[packages]]') then
    Result := 'P'
  else if (H = '[[natives]]') or (H = '[[native]]') then
    Result := 'N';
end;

function Me3OtherModKind(const Lines: TArrayOfString; const I: Integer; const Profile: String): String;
var
  Kinds: TArrayOfInteger;
begin
  Me3Classify(Lines, Kinds);
  Result := Me3OtherModKindK(Lines, Kinds, I, Profile);
end;

{ Lists the other mods both .me3 profiles of Dir load (Me3Extra*). }
procedure ScanMe3Extras(const Dir: String);
var
  Lines: TArrayOfString;
  Kinds: TArrayOfInteger;
  P, I, Nat: Integer;
  Kind, Note, T: String;
begin
  Me3ExtraClear;
  for P := 0 to ME3_PROFILE_COUNT - 1 do
    if LoadStringsFromFile(AddBackslash(Dir) + Me3Profile[P], Lines) then begin
      Me3Classify(Lines, Kinds);
      for I := 0 to GetArrayLength(Lines) - 1 do begin
        Kind := Me3OtherModKindK(Lines, Kinds, I, Me3Profile[P]);
        if Kind = '' then
          Continue;
        Note := '';
        Nat := Me3OwnKNative(Lines[I]);
        if (Kind = 'N') and (Nat >= 0) then begin
          { the component's short name: its title up to " - " }
          T := CompTitle[NatComp[Nat]];
          if Pos(' - ', T) > 0 then
            T := Copy(T, 1, Pos(' - ', T) - 1);
          if NativeOn(Nat) then
            Note := 'replaced: your own ' + T + ' entry; the installer''s own copy of it is loaded instead ' +
              '(switch the option off to keep yours)'
          else
            Note := 'kept: your own ' + T + ' entry (the installer''s option for it is off)';
        end else if Kind = 'N' then begin
          { repair 6: the file the line loads as me3 resolves it }
          if StartsWithStr(Me3PathLineRel(Lines[I]), 'mod\dll\') then
            Note := 'kept: a DLL in mod\dll, kept like the DLL files there'
          else
            Note := 'kept: a DLL from outside mod\dll; if it belongs to another overhaul, remove this ' +
              'entry yourself';
        end;
        Me3ExtraAdd(Me3Profile[P], Trim(Lines[I]), Kind, Note, Nat);
      end;
    end;
  Log(Format('.me3 profiles of %s: %d entr(ies) of other mods (%d [[package]], %d [[natives]])', [Dir,
    Me3ExtraCount, Me3ExtraCountOf('P'), Me3ExtraCountOf('N')]));
  for I := 0 to Me3ExtraCount - 1 do
    Log('  .me3 ' + Me3ExtraKind[I] + ': ' + Me3ExtraProfile[I] + ': ' + Me3ExtraLine[I] + ' ' + Me3ExtraNote[I]);
end;

{ Switches off every other mod's [[package]] entry in a profile: its header
  and every line up to the next header that is a key or the start of a
  value's line become comments that start with ME3_OFF_PREFIX (a value that
  spans several lines: each of its lines; repair 3), and so does every
  sub-table of the entry ([package.x], [[package.load_after]]: TOML puts
  them inside that [[package]] table; left active, they would join the
  table [[package]] above it - repair 4, code review). Count = entries
  switched off. True when the file is fine afterwards. The profile was
  backed up whole (kind B) before. }
procedure Me3SwitchOffTable(const Lines: TArrayOfString; const Kinds: TArrayOfInteger; const H: Integer;
  var Off: TArrayOfBoolean);
var
  J, N: Integer;
begin
  N := GetArrayLength(Lines);
  Off[H] := True;
  J := H + 1;
  while (J < N) and (Kinds[J] <> ME3_K_HEADER) do begin
    if Me3IsContentKind(Kinds[J]) and Me3IsActiveLine(Lines[J]) then
      Off[J] := True;
    J := J + 1;
  end;
end;

function Me3SwitchOffPackages(const FileName, Profile: String; var Count: Integer): Boolean;
var
  Lines: TArrayOfString;
  Kinds, Roots: TArrayOfInteger;
  Off: TArrayOfBoolean;
  I, J, S, N: Integer;
begin
  Count := 0;
  Result := True;
  if not FileExists(FileName) then
    Exit;
  if not LoadStringsFromFile(FileName, Lines) then begin
    Log('Cannot read ' + FileName);
    Result := False;
    Exit;
  end;
  N := GetArrayLength(Lines);
  Me3Classify(Lines, Kinds);
  Me3HeaderRoots(Lines, Kinds, Roots);
  SetArrayLength(Off, N);
  for I := 0 to N - 1 do
    Off[I] := False;
  for I := 0 to N - 1 do
    if Me3OtherModKindK(Lines, Kinds, I, Profile) = 'P' then begin
      J := Me3OwnerHeaderK(Kinds, I);
      Count := Count + 1;
      Me3SwitchOffTable(Lines, Kinds, J, Off);
      for S := J + 1 to N - 1 do
        if (Kinds[S] = ME3_K_HEADER) and (Roots[S] = J) then
          Me3SwitchOffTable(Lines, Kinds, S, Off);
    end;
  if Count = 0 then
    Exit;
  for I := 0 to N - 1 do
    if Off[I] then
      Lines[I] := Me3OffPrefix + Lines[I];
  Result := SaveMe3Lines(FileName, Lines);
  if Result then
    Log(Format('Switched off %d [[package]] table(s) of other mods in %s', [Count, FileName]));
end;

{ Other mods' [[package]] tables still active in a profile (0 when unreadable). }
function Me3ActiveOtherPackages(const FileName, Profile: String): Integer;
var
  Lines: TArrayOfString;
  Kinds: TArrayOfInteger;
  I: Integer;
begin
  Result := 0;
  if LoadStringsFromFile(FileName, Lines) then begin
    Me3Classify(Lines, Kinds);
    for I := 0 to GetArrayLength(Lines) - 1 do
      if Me3OtherModKindK(Lines, Kinds, I, Profile) = 'P' then
        Result := Result + 1;
  end;
end;

{ One line per .me3 entry of the given kinds. }
function Me3ExtraLines(const Kinds: String; const WithNotes: Boolean): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Me3ExtraCount - 1 do
    if Pos(Me3ExtraKind[I], Kinds) > 0 then begin
      Result := Result + '  ' + Me3ExtraProfile[I] + ': ' + Me3ExtraLine[I];
      if WithNotes and (Me3ExtraNote[I] <> '') then
        Result := Result + ' - ' + Me3ExtraNote[I];
      Result := Result + #13#10;
    end;
end;

{ Path lines of [[package]] tables that a run of this installer switched off
  (still off now), as "profile: line". }
procedure Me3SwitchedOffEntries(const Dir: String; L: TStringList);
var
  Lines: TArrayOfString;
  P, I: Integer;
  Rest: String;
begin
  for P := 0 to ME3_PROFILE_COUNT - 1 do
    if LoadStringsFromFile(AddBackslash(Dir) + Me3Profile[P], Lines) then
      for I := 0 to GetArrayLength(Lines) - 1 do
        if StartsWithStr(Lines[I], ME3_OFF_PREFIX_ANY) and (Pos(' installer: ', Lines[I]) > 0) then begin
          Rest := Copy(Lines[I], Pos(' installer: ', Lines[I]) + Length(' installer: '), Length(Lines[I]));
          if StartsWithStr(Me3Squeeze(Rest), 'path=') then
            L.Add(Me3Profile[P] + ': ' + Trim(Rest));
        end;
end;

{ True when a file cannot be moved into a backup folder of Dir without
  exceeding MAX_PATH (Setup is not long-path aware). }
function BackupPathTooLong(const Dir, Rel: String): Boolean;
var
  Base: Integer;
begin
  Base := Length(AddBackslash(Dir)) + Length(BACKUP_PATH_TEMPLATE);
  { a copy goes to <name>.cxtmp first (repair 5) }
  Result := (Base + Length(Rel) + Length(REPLACE_TMP_SUFFIX) > MAX_FILE_PATH_LEN) or
    (Base + Length(ExtractFileDir(Rel)) > MAX_DIR_PATH_LEN);
end;

{ Lists every foreign file under <Dir>\mod into the Foreign* arrays. }
procedure ScanForeignFiles(const Dir: String);
var
  Queue, Targets: TStringList;
  Head, Idx: Integer;
  Sub, Rel, LRel, Profiles, Note: String;
  FR: TFindRec;
  Size: Int64;
  T0: Cardinal;
begin
  T0 := GetTickCount;
  ForeignClear;
  ForeignScannedFor := Dir;
  Profiles := Me3ProfilesText(Dir);
  Queue := TStringList.Create;
  Targets := TStringList.Create;
  try
    ListWriteTargets(Dir, Targets);
    Queue.Add('mod');
    Head := 0;
    while Head < Queue.Count do begin
      Sub := Queue[Head];
      Head := Head + 1;
      if (Head mod 20) = 1 then
        ProgressText('Looking for files from other mods...', Sub);
      if FindFirst(AddBackslash(Dir) + Sub + '\*', FR) then begin
        try
          repeat
            if (FR.Name = '.') or (FR.Name = '..') then
              Continue;
            Rel := Sub + '\' + FR.Name;
            LRel := Lowercase(Rel);
            if (FR.Attributes and FA_DIRECTORY) <> 0 then begin
              if (FR.Attributes and FA_REPARSE_POINT) <> 0 then
                ForeignAdd(Rel + '\', 0, 'L', 'kept: a link to another folder (Setup does not move links); ' +
                  'remove it yourself if it belongs to another mod')
              else
                Queue.Add(Rel);
            end else if not KnownModFiles.Find(Rel, Idx) and not IsRuntimeFile(Rel) and
              not IsOwnTempFile(Rel, Targets) then
            begin
              Size := FindRecSize(FR);
              if StartsWithStr(LRel, 'mod\dll\') then begin
                if ExtractFileExt(LRel) <> '.dll' then
                  Note := 'kept: files in mod\dll only matter to a DLL that a .me3 profile loads'
                else if Pos('/' + Lowercase(FR.Name), Profiles) > 0 then
                  Note := 'kept: a .me3 profile loads it'
                else
                  Note := 'kept: not loaded unless a .me3 profile lists it';
                ForeignAdd(Rel, Size, 'D', Note);
              end else if BackupPathTooLong(Dir, Rel) then
                ForeignAdd(Rel, Size, 'L', 'kept: its path is too long to move into the backup; ' +
                  'remove it yourself')
              else if not IsSafeRelPath(Rel) then
                { the backup manifest could not record it safely (restore
                  refuses such paths), so it is never moved }
                ForeignAdd(Rel, Size, 'L', 'kept: its name cannot be recorded safely in the backup; ' +
                  'remove it yourself')
              else
                ForeignAdd(Rel, Size, 'M', '');
            end;
          until not FindNext(FR);
        finally
          FindClose(FR);
        end;
      end;
    end;
  finally
    Queue.Free;
    Targets.Free;
  end;
  Log(Format('Foreign-file scan of %s\mod: %d folders, %d foreign file(s) (%d movable, %d kept), %d ms', [Dir, Head, ForeignCount, ForeignCountOf('M'), ForeignCount - ForeignCountOf('M'), GetTickCount - T0]));
  for Idx := 0 to ForeignCount - 1 do
    if Idx < FOREIGN_LIST_MAX then
      Log('  foreign ' + ForeignKind[Idx] + ': ' + ForeignRel[Idx] + ' (' + SizeText(ForeignSize[Idx]) + ') ' +
        ForeignNote[Idx]);
  ScanMe3Extras(Dir);
end;

{ True when the scan found anything from other mods (files or .me3 entries). }
function OtherModsFound: Boolean;
begin
  Result := (ForeignCount > 0) or (Me3ExtraCount > 0);
end;

{ Something the "move / switch off" box acts on. }
function OtherModsMovable: Boolean;
begin
  Result := (ForeignCountOf('M') > 0) or (Me3ExtraCountOf('P') > 0);
end;

{ One line per foreign file of the given kinds, at most FOREIGN_LIST_MAX. }
function ForeignLines(const Kinds: String; const WithNotes: Boolean): String;
var
  I, N, Total: Integer;
begin
  Result := '';
  N := 0;
  Total := ForeignCountOf(Kinds);
  for I := 0 to ForeignCount - 1 do
    if Pos(ForeignKind[I], Kinds) > 0 then begin
      N := N + 1;
      if N > FOREIGN_LIST_MAX then begin
        Result := Result + Format('  ... and %d more', [Total - FOREIGN_LIST_MAX]) + #13#10;
        Break;
      end;
      Result := Result + '  ' + ForeignRel[I];
      if Copy(ForeignRel[I], Length(ForeignRel[I]), 1) <> '\' then
        Result := Result + '  (' + SizeText(ForeignSize[I]) + ')';
      if WithNotes and (ForeignNote[I] <> '') then
        Result := Result + ' - ' + ForeignNote[I];
      Result := Result + #13#10;
    end;
end;
