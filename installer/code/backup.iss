{ =============================================================================
  backup.iss - backup before install, restore on uninstall or failure
  (the v6.4 model, contract 5.6 and 8).

  Before any file is written, every target that will change is classified:
    B  the file exists and will be replaced, edited or deleted
       -> copied to <Conv>\CXCXM_backup\<yyyy-mm-dd_hh-nn-ss>\<same path>
          and copied back on restore (skipped when already identical)
    N  the file does not exist yet -> deleted again on restore; at an
       uninstall, a file at a catalog path an option writes only while it
       is on (not a user config) is deleted only while it holds one of the
       catalog's own contents for its path (a variant or an H rule, any
       content for a path of a mode V archive); a file the player put there
       since (another mod's body or face file over one of Lucy's) stays and
       is listed (repair 4, code review LOW)
    E  a .me3 profile that only gets entries of ours appended (catalog
       natives) -> copied to the backup too; on restore exactly the entries
       of ours that the saved copy lacks are removed (the saved copy is put
       back byte for byte when nothing else changed), so later edits by the
       user survive
    D  a folder that does not exist yet (the install creates it)
       -> removed on restore once it is empty
    M  a file from another mod under mod\ (code\checks.iss, check C) that
       the player chose to move out of the way
       -> moved into the backup folder at the start of the post-install
          step, after Inno registered the uninstaller (not before: a
          cancelled or refused run leaves it where it was, and a Setup
          stopped hard after it can be uninstalled; repair 5) and moved
          back on restore
  What is planned, per catalog path p (DesiredVariant, contract 5.7):
    a variant      the file already holds it: nothing (VarSkip); else B or N
    a user config  (flag U) N when this run creates it; never touched when
                   it exists (the player's settings)
    PT_ABSENT      B when the file exists (removed after the copy step);
                   kept when another .me3 entry still loads it (the v6.3
                   arrows rule)
    PT_LEAVE       nothing
  plus: obsolete files of older releases (B, removed), ini files a field is
  written into (B when the ini existed), the .me3 profiles (B or E), other
  mods' files (M) and the marker.
  A .me3 profile in which another mod's [[package]] entry is switched off
  (check C) is a B entry: the whole profile is put back on restore.
  The manifest's first line is CXCXM-BACKUP-MANIFEST 2 when the plan has M
  entries (1 otherwise): an older uninstaller only knows format 1, so it
  never touches a backup that holds other mods' files it cannot put back.
  Any kind this code does not know makes the restore of that folder fail
  (the folder is kept), never skipped.

  Crash safety (repair 5, sixth verifier DEFECT 1): every file Setup and the
  uninstaller write in the Convergence folder goes to "<name>.cxtmp" first,
  is flushed to the disk and then moved to its name (util.iss
  CommitTempFile), so a Setup or uninstall stopped hard at any moment leaves
  each file either as it was or complete - never half written under a name
  the game loads. The leftover "<name>.cxtmp" files are deleted by the next
  run and by the uninstaller (DeleteStaleTempFiles; the names come from the
  catalog and the backup manifests, the journal of what a run writes). A
  run's backup folder also holds its journal (RUN_JOURNAL_NAME) from its
  first change until its post-install step ends: the next run preselects
  the options of a run that was stopped. A restored backup folder loses its
  manifest first (DeleteBackupFolder), so a stop while it is deleted leaves
  a folder without a manifest, which every later run deletes.

  The plan is written to CXCXM_BACKUP_MANIFEST.txt inside the backup folder,
  with SEQ = a sequence number (1 for the first backup in this folder, then
  +1). Restoring walks all backup folders from the highest SEQ to the lowest
  (newest to oldest, whatever the clock did), which returns the Convergence
  folder to its state before the FIRST install, even after several
  re-installs (v6.3 and v6.4 backups included: same format). Each backup
  folder is deleted once it is fully restored; the walk stops at the first
  folder that cannot be fully restored, so a retry continues in the right
  order.
  ============================================================================= }

procedure PlanClear;
begin
  PlanCount := 0;
  SetArrayLength(PlanRel, 0);
  SetArrayLength(PlanKind, 0);
  PlanBackupBytes := 0;
  PlanWriteBytes := 0;
  PlanMade := False;
end;

{ Grows the arrays in chunks (other mods' files can add thousands of M
  entries); PlanCount is the number of entries in use. }
procedure PlanAdd(const Rel, Kind: String);
var
  Cap: Integer;
begin
  if PlanCount >= GetArrayLength(PlanRel) then begin
    Cap := GetArrayLength(PlanRel) * 2 + 256;
    SetArrayLength(PlanRel, Cap);
    SetArrayLength(PlanKind, Cap);
  end;
  PlanRel[PlanCount] := Rel;
  PlanKind[PlanCount] := Kind;
  PlanCount := PlanCount + 1;
end;

function PlanHas(const Rel: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to PlanCount - 1 do
    if CompareText(PlanRel[I], Rel) = 0 then begin
      Result := True;
      Exit;
    end;
end;

{ The marker and other files that are simply (re)written: B or N. }
procedure PlanRewrite(const Rel: String);
begin
  if PlanHas(Rel) then
    Exit;
  if FileExists(ConvPath(Rel)) then
    PlanAdd(Rel, 'B')
  else
    PlanAdd(Rel, 'N');
end;

{ '' when the natives of the chosen options can be set up in both .me3
  profiles, otherwise the reason (shown at the Options page and the gate). }
function Me3ProfilesProblem: String;
var
  I: Integer;
  P: String;
begin
  Result := '';
  for I := 0 to ME3_PROFILE_COUNT - 1 do begin
    P := Me3ProfileProblem(ConvPath(Me3Profile[I]), Me3Profile[I]);
    { me3's own reader must list the same natives as Setup reads in the
      profile, before Setup acts on it (repair 5, sixth verifier DEFECT 2:
      a layout Setup's line reader takes differently is refused, never
      mis-edited; skipped where me3.exe is not started, see Me3ExeRun) }
    if P = '' then begin
      P := Me3ExeProblem(ConvPath(Me3Profile[I]));
      if P <> '' then
        P := Me3Profile[I] + ': ' + P + ', so Setup does not edit it. Restore the profile with the Convergence ' +
          'Launcher (repair), or correct it.';
    end;
    if P <> '' then begin
      if Result <> '' then
        Result := Result + #13#10#13#10;
      Result := Result + P;
    end;
  end;
  if Result <> '' then
    Result := 'The chosen options cannot be set up in your .me3 profiles automatically:' + #13#10#13#10 +
      Result + #13#10#13#10 + 'Or switch those options off on the Options page. Nothing was changed.';
end;

{ True when a file the selection must NOT have is a DLL that an R native
  (Infinite Arrows) loads, the native is off, and a .me3 entry this
  installer did not add still loads it: the file then stays (v6.3 rule). }
function NativeKeepsDll(const P: Integer): Boolean;
var
  N, I: Integer;
begin
  Result := False;
  for N := 0 to NatCount - 1 do begin
    if NativeOn(N) or (CompareText(NativeDllRel(N), PathRel[P]) <> 0) then
      Continue;
    if NatForeign[N] = 'R' then begin
      for I := 0 to ME3_PROFILE_COUNT - 1 do
        if Me3FileHasOtherMention(ConvPath(Me3Profile[I]), N) then begin
          Result := True;
          Exit;
        end;
    end else if NatForeign[N] = 'K' then begin
      { K: the player's own entry (kept while the option is off) loads this
        very file. Repair 6: an entry that loads it at its own path is ours
        whatever its spelling (seventh verifier, finding C: '../mod/dll/
        CapacityExpansion.dll' kept its entry while the DLL went); it is
        taken out with the DLL, so this only answers for a layout Setup
        does not take out }
      for I := 0 to ME3_PROFILE_COUNT - 1 do
        if Me3FileForeignLoadsOurDll(ConvPath(Me3Profile[I]), N) then begin
          Result := True;
          Exit;
        end;
    end;
  end;
end;

{ True when the file at catalog path P holds one of the catalog's own
  contents for it: a variant of P, or a content that a detection rule (H)
  names for P (an older release's file of that component). A path whose
  variants come from a mode V archive (any version of that author's file)
  counts every content as the component's own. A file that cannot be read
  counts as own (it is then handled as before: backed up and removed).
  (Repair 3, verifier 4 D2: a body or face replacer shares the names of
  Lucy's parts; it is another mod's file, never removed as Lucy's.) }
function PathHoldsOwnContentIn(const Dir: String; const P: Integer): Boolean;
var
  K, D: Integer;
  Sha: String;
begin
  Result := True;
  for K := 0 to VarCount - 1 do
    if (VarPath[K] = P) and (VarSha[K] = '') then
      Exit;
  Sha := FileSha256(AddBackslash(Dir) + PathRel[P]);
  if Sha = '' then begin
    Log('Cannot read ' + PathRel[P] + ' to tell whose file it is; it is treated as this release''s');
    Exit;
  end;
  for K := 0 to VarCount - 1 do
    if (VarPath[K] = P) and (CompareText(VarSha[K], Sha) = 0) then
      Exit;
  for D := 0 to GetArrayLength(DetKind) - 1 do
    if (DetKind[D] = 'H') and (CompareText(DetArg[D], PathRel[P]) = 0) and (CompareText(DetSha[D], Sha) = 0) then
      Exit;
  Result := False;
end;

function PathHoldsOwnContent(const P: Integer): Boolean;
begin
  Result := PathHoldsOwnContentIn(ConvDir, P);
end;

{ The number of entries of path P's table (the product of its components'
  state counts). }
function PathTableSize(const P: Integer): Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 0 to PathAffCount[P] - 1 do
    Result := Result * CompStateCount[AffComp[PathAffStart[P] + I]];
end;

{ True when some selection must not have path P (an option writes it only
  while it is on). }
function PathCanBeAbsent(const P: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to PathTableSize(P) - 1 do
    if PathTab[PathTabStart[P] + I] = PT_ABSENT then begin
      Result := True;
      Exit;
    end;
end;

{ CompShortTitle (a component's title up to " - ") moved to catalogrt.iss on 2026-10-03 (the D rule texts use it). }

{ For the Other mods page (any selection): files in Dir at paths that an
  option writes only while it is on, holding another mod's content, as
  "path - note" (repair 3, verifier 4 D2). }
procedure ForeignUnderOptionNames(const Dir: String; L: TStringList);
var
  P: Integer;
begin
  if Dir = '' then
    Exit;
  for P := 0 to PathCount - 1 do
    if not PathIsUserConfig(P) and PathCanBeAbsent(P) and FileExists(AddBackslash(Dir) + PathRel[P]) and
      not PathHoldsOwnContentIn(Dir, P) then
      L.Add(PathRel[P] + ' - its name is also one of ' + CompShortTitle(PathOwner[P]) + '''s files');
end;

{ A file at catalog path P that the selection must not have (PT_ABSENT),
  that holds another mod's content (PathHoldsOwnContent) and that no .me3
  entry of another mod still needs (NativeKeepsDll handles those). }
function PathHoldsForeignToRemove(const P: Integer): Boolean;
begin
  Result := (DesiredVariant(P) = PT_ABSENT) and not PathIsUserConfig(P) and
    FileExists(ConvPath(PathRel[P])) and not NativeKeepsDll(P) and not PathHoldsOwnContent(P);
end;

{ True when such a file can be moved into the backup (as the foreign-file
  scan decides for files elsewhere in mod\: mod\dll files, paths too long
  for the backup and names the manifest cannot record stay). }
function ForeignPathMovable(const P: Integer): Boolean;
var
  Rel: String;
begin
  Rel := PathRel[P];
  Result := not StartsWithStr(Lowercase(Rel), 'mod\dll\') and IsSafeRelPath(Rel) and
    not BackupPathTooLong(ConvDir, Rel);
end;

{ Other mods' files at the paths of this release's options that the
  selection must not have: Moved (they go into the backup when the player
  chose so) and Kept (with the reason), as "path - note". For the Ready page
  and the log (repair 3, verifier 4 D2). }
procedure ForeignAtCatalogPaths(Moved, Kept: TStringList);
var
  P: Integer;
  T: String;
begin
  for P := 0 to PathCount - 1 do
    if PathHoldsForeignToRemove(P) then begin
      T := CompTitle[PathOwner[P]];
      if Pos(' - ', T) > 0 then
        T := Copy(T, 1, Pos(' - ', T) - 1);
      if ForeignMove and ForeignPathMovable(P) then
        Moved.Add(PathRel[P] + ' - another mod''s file under a name ' + T + ' also uses')
      else if not ForeignPathMovable(P) then
        Kept.Add(PathRel[P] + ' - kept: another mod''s file under a name ' + T + ' also uses (Setup does ' +
          'not move it)')
      else
        Kept.Add(PathRel[P] + ' - kept: another mod''s file under a name ' + T + ' also uses (you chose to ' +
          'keep other mods'' files)');
    end;
end;

{ The bytes variant K will write (dynamic variants: the member's size). }
function VariantWriteSize(const K: Integer): Int64;
begin
  Result := VarSize[K];
  if (Result < 0) and (VarSrc[K] = 'A') and (MemPath[VarRef[K]] <> '') then
    Result := GetFileSizeSafe(MemPath[VarRef[K]]);
  if Result < 0 then
    Result := 0;
end;

{ ------------------------------------------------------------------ fields --- }

{ An ini file as lines plus their line ends, byte for byte (UTF-8). False
  when it cannot be read or is not valid UTF-8 (it is then never edited). }
function IniLoad(const FileName: String; var Lines, Ends: TArrayOfString): Boolean;
var
  Raw: AnsiString;
  Text, Cur: String;
  I, N, L: Integer;
begin
  Result := False;
  SetArrayLength(Lines, 0);
  SetArrayLength(Ends, 0);
  if not LoadStringFromFile(FileName, Raw) then
    Exit;
  Text := UTF8Decode(Raw);
  if UTF8Encode(Text) <> Raw then begin
    Log(FileName + ' is not UTF-8 text; it is not edited');
    Exit;
  end;
  N := 0;
  Cur := '';
  L := Length(Text);
  I := 1;
  while I <= L do begin
    if Text[I] = #10 then begin
      SetArrayLength(Lines, N + 1);
      SetArrayLength(Ends, N + 1);
      if (Length(Cur) > 0) and (Cur[Length(Cur)] = #13) then begin
        Lines[N] := Copy(Cur, 1, Length(Cur) - 1);
        Ends[N] := #13#10;
      end else begin
        Lines[N] := Cur;
        Ends[N] := #10;
      end;
      N := N + 1;
      Cur := '';
    end else
      Cur := Cur + Text[I];
    I := I + 1;
  end;
  if Cur <> '' then begin
    SetArrayLength(Lines, N + 1);
    SetArrayLength(Ends, N + 1);
    Lines[N] := Cur;
    Ends[N] := '';
  end;
  Result := True;
end;

function IniSave(const FileName: String; const Lines, Ends: TArrayOfString): Boolean;
var
  I: Integer;
  Text: String;
begin
  Text := '';
  for I := 0 to GetArrayLength(Lines) - 1 do
    Text := Text + Lines[I] + Ends[I];
  { through a temporary file that replaces the ini (never in place: no write
    through a hard link; code review repair 2, D2) }
  Result := SaveBytesReplacing(FileName, UTF8Encode(Text));
end;

{ The section name of a "[name]" line ('' when the line is no header). }
function IniSectionOf(const Line: String): String;
var
  S: String;
begin
  Result := '';
  S := Trim(Line);
  if (Length(S) >= 2) and (S[1] = '[') and (S[Length(S)] = ']') then begin
    Result := Copy(S, 2, Length(S) - 2);
    Result := Trim(Result);
  end;
end;

{ The key of a "key = value" line ('' for comments and lines without "="). }
function IniKeyOf(const Line: String): String;
var
  S: String;
  P: Integer;
begin
  Result := '';
  S := Trim(Line);
  if (S = '') or (S[1] = ';') or (S[1] = '#') or (S[1] = '[') then
    Exit;
  P := Pos('=', S);
  if P > 0 then begin
    Result := Copy(S, 1, P - 1);
    Result := Trim(Result);
  end;
end;

{ Finds the first "Key =" line of [Section]: KeyLine (or -1); SecLine = the
  header line (-1 when the section is missing); LastLine = the last
  non-blank line of the section. }
procedure IniFind(const Lines: TArrayOfString; const Section, Key: String; var SecLine, KeyLine,
  LastLine: Integer);
var
  I: Integer;
  InSec: Boolean;
  Sec: String;
begin
  SecLine := -1;
  KeyLine := -1;
  LastLine := -1;
  InSec := False;
  for I := 0 to GetArrayLength(Lines) - 1 do begin
    Sec := IniSectionOf(Lines[I]);
    if Sec <> '' then begin
      if InSec then
        Exit;
      if CompareText(Sec, Section) = 0 then begin
        InSec := True;
        SecLine := I;
        LastLine := I;
      end;
      Continue;
    end;
    if not InSec then
      Continue;
    if Trim(Lines[I]) <> '' then
      LastLine := I;
    if (KeyLine < 0) and (CompareText(IniKeyOf(Lines[I]), Key) = 0) then
      KeyLine := I;
  end;
end;

{ The value of Key in [Section] of FileName (Found = the line exists). }
function IniGetValue(const FileName, Section, Key: String; var Found: Boolean): String;
var
  Lines, Ends: TArrayOfString;
  SecLine, KeyLine, LastLine, P: Integer;
begin
  Result := '';
  Found := False;
  if not IniLoad(FileName, Lines, Ends) then
    Exit;
  IniFind(Lines, Section, Key, SecLine, KeyLine, LastLine);
  if KeyLine < 0 then
    Exit;
  Found := True;
  P := Pos('=', Lines[KeyLine]);
  Result := Copy(Lines[KeyLine], P + 1, Length(Lines[KeyLine]));
  Result := Trim(Result);
end;

{ Contract 5.9: in [Section] the value of the first "Key =" line is
  replaced (everything up to "=" and the blanks after it stays, so
  "key = " keeps its spacing; every other byte of the file stays); a missing
  line is added at the end of the section, a missing section at the end of
  the file. A missing file is created. }
function IniSetValue(const FileName, Section, Key, Value: String): Boolean;
var
  Lines, Ends: TArrayOfString;
  SecLine, KeyLine, LastLine, P, J, N, I: Integer;
  Eol, Prefix, Line: String;
begin
  Result := False;
  if FileExists(FileName) then begin
    if not IniLoad(FileName, Lines, Ends) then
      Exit;
  end else begin
    SetArrayLength(Lines, 0);
    SetArrayLength(Ends, 0);
    ForceDirectories(ExtractFileDir(FileName));
  end;
  Eol := #13#10;
  for I := 0 to GetArrayLength(Ends) - 1 do
    if Ends[I] <> '' then begin
      Eol := Ends[I];
      Break;
    end;
  IniFind(Lines, Section, Key, SecLine, KeyLine, LastLine);
  if KeyLine >= 0 then begin
    Line := Lines[KeyLine];
    P := Pos('=', Line);
    J := P + 1;
    while (J <= Length(Line)) and ((Line[J] = ' ') or (Line[J] = #9)) do
      J := J + 1;
    Prefix := Copy(Line, 1, J - 1);
    Lines[KeyLine] := Prefix + Value;
  end else if SecLine >= 0 then begin
    { insert "Key = Value" after the last non-blank line of the section }
    N := GetArrayLength(Lines);
    SetArrayLength(Lines, N + 1);
    SetArrayLength(Ends, N + 1);
    for I := N downto LastLine + 2 do begin
      Lines[I] := Lines[I - 1];
      Ends[I] := Ends[I - 1];
    end;
    Lines[LastLine + 1] := Key + ' = ' + Value;
    Ends[LastLine + 1] := Eol;
    if Ends[LastLine] = '' then
      Ends[LastLine] := Eol;
  end else begin
    N := GetArrayLength(Lines);
    if (N > 0) and (Ends[N - 1] = '') then
      Ends[N - 1] := Eol;
    SetArrayLength(Lines, N + 2);
    SetArrayLength(Ends, N + 2);
    Lines[N] := '[' + Section + ']';
    Ends[N] := Eol;
    Lines[N + 1] := Key + ' = ' + Value;
    Ends[N + 1] := Eol;
  end;
  Result := IniSave(FileName, Lines, Ends);
end;

{ The file field I's ini will be when the value is written: the ini in the
  Convergence folder when it stays (a user config file is never replaced,
  or it already holds the wanted content), else the file this run copies
  there (an archive member or a downloaded blob; '' while not known yet);
  '' = the ini is created new. }
function FieldIniSource(const I: Integer): String;
var
  P, K: Integer;
  Rel: String;
  Keep: Boolean;
begin
  Result := '';
  Rel := FieldRel[I];
  P := PathIndexOf(Rel);
  K := -1;
  if P >= 0 then
    K := DesiredVariant(P);
  if FileExists(ConvPath(Rel)) then begin
    Keep := K < 0;
    if not Keep then
      Keep := PathIsUserConfig(P);
    if not Keep then
      Keep := VariantInPlace(K);
    if Keep then begin
      Result := ConvPath(Rel);
      Exit;
    end;
  end;
  if K >= 0 then begin
    if VarSrc[K] = 'A' then
      Result := MemPath[VarRef[K]]
    else
      Result := BlobPath[VarRef[K]];
  end;
end;

{ '' when field I can be written (or nothing is to be written), else why
  not: an ini that is not UTF-8 text (or cannot be read) is never edited, so
  a typed value would make the install fail at its very end. Setup refuses
  before anything changes instead (verifier 1, defect D6). }
function FieldIniProblem(const I: Integer): String;
var
  Src: String;
  Lines, Ends: TArrayOfString;
begin
  Result := '';
  if not CompOn(FieldComp[I]) or (FieldValue[I] = '') then
    Exit;
  Src := FieldIniSource(I);
  if (Src = '') or not FileExists(Src) then
    Exit;
  if not IniLoad(Src, Lines, Ends) then
    Result := Src + ' is not UTF-8 text (or cannot be read), and Setup never edits such a file. Save it as UTF-8 ' +
      '(Notepad: File > Save As, Encoding UTF-8), or leave the ' + FieldKey[I] + ' empty (unattended: leave out /' +
      FieldSwitch[I] + '=)';
end;

{ The first field problem as a full message ('' = none). }
function FieldsProblemText: String;
var
  I: Integer;
  P: String;
begin
  Result := '';
  for I := 0 to FieldCount - 1 do begin
    P := FieldIniProblem(I);
    if P <> '' then begin
      Log('CXCXM FIELD ' + FieldId[I] + ' refused: ' + P);
      Result := 'Setup cannot write the ' + FieldKey[I] + ' you gave: ' + P + '.' + #13#10#13#10 + 'Nothing was changed.';
      Exit;
    end;
  end;
end;

{ ------------------------------------------------------------------- plan --- }

{ Builds the plan for the current selection and checks the free disk space.
  The Convergence 3.0.2 check (B) runs again first, and the foreign-file
  scan (C) is refreshed: the folder may have changed while the wizard was
  open. Sets VarSkip, PathDelete, PathKeepForeign, ObsDelete, FieldWrite. }
function BuildBackupPlan(var Problem: String): Boolean;
var
  I, K, P, Total: Integer;
  Rel, Kind, Cur, TmpDir: String;
  FreeBytes, TotalBytes, Need, Size: Int64;
  Found, SameDrive: Boolean;
begin
  Result := False;
  Problem := '';
  PlanClear;
  if not CheckConvergenceIntegrity(ConvDir, Problem, ConvCheckSummary) then
    Exit;
  ScanForeignFiles(ConvDir);
  Problem := Me3ProfilesProblem;
  if Problem <> '' then
    Exit;

  { every catalog path }
  for K := 0 to VarCount - 1 do
    VarSkip[K] := False;
  Total := PathCount;
  for P := 0 to Total - 1 do begin
    PathDelete[P] := False;
    PathKeepForeign[P] := False;
    PathForeignFile[P] := False;
    Rel := PathRel[P];
    ProgressText(Format('Comparing your files with %s (%d of %d)...', [CAT_VERSION_SHORT, P + 1, Total]), Rel);
    ProgressPos(P, Total);
    K := DesiredVariant(P);
    if K >= 0 then begin
      if PathIsUserConfig(P) then begin
        if FileExists(ConvPath(Rel)) then
          VarSkip[K] := True
        else begin
          PlanAdd(Rel, 'N');
          PlanWriteBytes := PlanWriteBytes + VariantWriteSize(K);
        end;
      end else if VariantInPlace(K) then begin
        VarSkip[K] := True;
      end else begin
        if FileExists(ConvPath(Rel)) then
          PlanAdd(Rel, 'B')
        else
          PlanAdd(Rel, 'N');
        PlanWriteBytes := PlanWriteBytes + VariantWriteSize(K);
      end;
    end else if (K = PT_ABSENT) and FileExists(ConvPath(Rel)) then begin
      if NativeKeepsDll(P) then begin
        PathKeepForeign[P] := True;
        Log('Kept (another .me3 entry still loads it): ' + Rel);
      end else if not PathIsUserConfig(P) and not PathHoldsOwnContent(P) then begin
        { another mod's file under a name of ours: other mods' rule, never
          removed as ours (repair 3, verifier 4 D2) }
        PathForeignFile[P] := True;
        if ForeignMove and ForeignPathMovable(P) then begin
          PlanAdd(Rel, 'M');
          Log('Another mod''s file at a path of this release (not one of its contents), moved into the backup: ' +
            Rel);
        end else begin
          PathKeepForeign[P] := True;
          Log('Another mod''s file at a path of this release (not one of its contents), kept: ' + Rel);
        end;
      end else begin
        PlanAdd(Rel, 'B');
        PathDelete[P] := True;
      end;
    end;
  end;
  ProgressPos(Total, Total);

  { files of older releases that this release does not have }
  for I := 0 to GetArrayLength(ObsRel) - 1 do begin
    ObsDelete[I] := False;
    Rel := ObsRel[I];
    if (PathIndexOf(Rel) >= 0) or not FileExists(ConvPath(Rel)) then
      Continue;
    if PlanHas(Rel) then begin
      { another row of the same path already planned the removal }
      ObsDelete[I] := True;
      Continue;
    end;
    if (ObsSha[I] = '') or (CompareText(FileSha256(ConvPath(Rel)), ObsSha[I]) = 0) then begin
      PlanAdd(Rel, 'B');
      ObsDelete[I] := True;
      Log('Obsolete file (' + ObsNote[I] + '): ' + Rel);
    end;
  end;

  { fields: the ini gets the typed value (refused before anything changes
    when the ini is one Setup never edits) }
  Problem := FieldsProblemText;
  if Problem <> '' then
    Exit;
  for I := 0 to FieldCount - 1 do begin
    FieldWrite[I] := False;
    if not CompOn(FieldComp[I]) or (FieldValue[I] = '') then
      Continue;
    Rel := FieldRel[I];
    if PlanHas(Rel) then
      FieldWrite[I] := True
    else if FileExists(ConvPath(Rel)) then begin
      Cur := IniGetValue(ConvPath(Rel), FieldSection[I], FieldKey[I], Found);
      if not (Found and (Cur = FieldValue[I])) then begin
        PlanAdd(Rel, 'B');
        FieldWrite[I] := True;
      end;
    end else begin
      PlanAdd(Rel, 'N');
      FieldWrite[I] := True;
    end;
  end;

  { the .me3 profiles, one entry each at most: B (uninstall puts the whole
    profile back) when another mod's [[package]] entry is switched off or the
    change is more than appending entries of ours; E when only entries of ours
    are appended }
  for I := 0 to ME3_PROFILE_COUNT - 1 do begin
    if ForeignMove and (Me3ExtraCountIn(Me3Profile[I], 'P') > 0) then
      Kind := 'B'
    else
      Kind := Me3PlanKind(ConvPath(Me3Profile[I]), Me3Profile[I]);
    if Kind <> '' then
      PlanAdd(Me3Profile[I], Kind);
  end;

  { files from other mods: moved into the backup (renamed, so they need no
    extra disk space) when the player chose so; mod\dll and paths that are
    too long stay (see ScanForeignFiles) }
  if ForeignMove then
    for I := 0 to ForeignCount - 1 do
      if ForeignKind[I] = 'M' then
        PlanAdd(ForeignRel[I], 'M');

  { the marker is always rewritten }
  PlanRewrite(MARKER_NAME);

  for I := 0 to PlanCount - 1 do
    if (PlanKind[I] <> 'N') and (PlanKind[I] <> 'M') then begin
      Size := GetFileSizeSafe(ConvPath(PlanRel[I]));
      if Size > 0 then
        PlanBackupBytes := PlanBackupBytes + Size;
    end;
  Log(Format('CXCXM PLAN entries=%d backup=%d write=%d', [PlanCount, PlanBackupBytes, PlanWriteBytes]));
  Log(Format('Backup plan: %d entries, %s to back up, %s to write', [PlanCount, BytesToMB(PlanBackupBytes),
    BytesToMB(PlanWriteBytes)]));

  { room for the backup plus everything that will be written, with a margin;
    the hosted files are downloaded into Setup's temp folder first and stay
    there until Setup ends, so they count too when that folder is on the
    same drive (code review repair 2, D5) }
  ComputeNeededBlobs;
  TmpDir := ExpandConstant('{tmp}');
  SameDrive := CompareText(ExtractFileDrive(TmpDir), ExtractFileDrive(ConvDir)) = 0;
  Need := PlanBackupBytes + PlanWriteBytes + 268435456;
  if SameDrive then
    Need := Need + FetchBytes;
  if GetSpaceOnDisk64(ConvDir, FreeBytes, TotalBytes) then begin
    if FreeBytes < Need then begin
      Problem := 'Not enough free disk space on the drive of ' + ConvDir + '.' + #13#10 +
        'Needed: about ' + BytesToMB(Need) + ' (backup ' + BytesToMB(PlanBackupBytes) + ' + new files';
      if SameDrive and (FetchBytes > 0) then
        Problem := Problem + ' + ' + BytesToMB(FetchBytes) + ' downloaded first';
      Problem := Problem + '). Free: ' + BytesToMB(FreeBytes) + '.' + #13#10#13#10 + 'Nothing was changed.';
      Exit;
    end;
  end else
    Log('Could not read the free disk space; continuing');
  if not SameDrive and (FetchBytes > 0) then begin
    Need := FetchBytes + 67108864;
    if GetSpaceOnDisk64(TmpDir, FreeBytes, TotalBytes) and (FreeBytes < Need) then begin
      Problem := 'Not enough free disk space for the downloads in Setup''s temp folder (' + TmpDir + ').' + #13#10 +
        'Needed: about ' + BytesToMB(Need) + '. Free: ' + BytesToMB(FreeBytes) + '.' + #13#10#13#10 +
        'Nothing was changed. Free some space on that drive, then try again.';
      Exit;
    end;
  end;
  PlanMade := True;
  Result := True;
end;

{ BackupRoot, ReadBackupManifest, ManifestValue, ListBackupDirs and ListWriteTargets live in checks.iss
  (repair 6: the foreign-file scan uses the same list of write targets). }

{ True when Path is a plain file (not a folder, not a link). }
function IsPlainFile(const Path: String): Boolean;
var
  FR: TFindRec;
begin
  Result := False;
  if not FindFirst(Path, FR) then
    Exit;
  try
    Result := (FR.Attributes and (FA_DIRECTORY or FA_REPARSE_POINT)) = 0;
  finally
    FindClose(FR);
  end;
end;

{ Deletes every "<path>.cxtmp" next to a path a run of this installer or its
  uninstaller writes (ListWriteTargets): the temporary copy a Setup or an
  uninstall that was stopped hard (Task Manager, a crash, a power cut) left
  behind. Every file is written under that name first and only then moved
  to its own name, so such a file is never a complete file of anyone; left
  alone, the foreign-file scan would move it into the backup as another
  mod's file and the uninstall would put it back (repair 5, sixth verifier
  DEFECT 1). Called by Setup before its plan (after the Install click) and
  by the uninstaller before it restores. }
procedure DeleteStaleTempFiles(const Conv: String);
var
  L: TStringList;
  I, N: Integer;
  T: String;
begin
  if Conv = '' then
    Exit;
  L := TStringList.Create;
  N := 0;
  try
    ListWriteTargets(Conv, L);
    for I := 0 to L.Count - 1 do begin
      T := AddBackslash(Conv) + L[I] + REPLACE_TMP_SUFFIX;
      if not IsPlainFile(T) then
        Continue;
      if DeleteFileForced(T) then begin
        N := N + 1;
        Log('Deleted the temporary file of a stopped Setup or uninstall: ' + T);
      end else
        Log('Could not delete the temporary file ' + T);
    end;
  finally
    L.Free;
  end;
  Log(Format('CXCXM STALETEMP deleted=%d', [N]));
end;

{ The journal of a run (RUN_JOURNAL_NAME in its backup folder): written
  right before the run's first change to the Convergence folder, deleted
  when the run's post-install step ends. Flushed to the disk, so it is there
  after a power cut as well (repair 5). }
function WriteRunJournal: Boolean;
var
  F: String;
begin
  Result := False;
  if BackupDir = '' then
    Exit;
  F := AddBackslash(BackupDir) + RUN_JOURNAL_NAME;
  if SaveStringToFile(F, 'CXCXM run journal: this run started to change the Convergence folder at ' + NowForDisplay +
    ' and has not finished yet.' + #13#10 + 'SELECTION=' + SelectionText(',', ':') + #13#10, False) then
  begin
    FlushFileToDisk(F);
    Log('Run journal written: ' + F);
    Result := True;
  end else
    Log('Could not write the run journal ' + F);
end;

{ The "backup made, nothing changed yet" marker of this run's backup folder
  (BACKUP_ONLY_NAME; repair 6). Written (flushed) before the manifest gets
  its name, so every complete backup folder of a run that has not reached
  its first change carries it. }
function WriteBackupOnlyMarker: Boolean;
var
  F: String;
begin
  Result := False;
  if BackupDir = '' then
    Exit;
  F := AddBackslash(BackupDir) + BACKUP_ONLY_NAME;
  Result := SaveStringToFile(F, 'CXCXM: this backup was made at ' + NowForDisplay + '; its run has not changed ' +
    'the Convergence folder yet.' + #13#10, False);
  if Result then
    FlushFileToDisk(F)
  else
    Log('Could not write ' + F);
end;

{ Right before the run's first change: the run journal is written, then the
  "backup only" marker goes. A folder with both (a stop between the two)
  counts as changed: the journal wins (BackupFolderUnstarted). False only
  when neither could be done - the folder would then look unchanged after a
  stop although the run went on, so the run must not change anything. }
function StartChangingBackupRun: Boolean;
var
  F: String;
begin
  Result := True;
  if BackupDir = '' then
    Exit;
  F := AddBackslash(BackupDir) + BACKUP_ONLY_NAME;
  if WriteRunJournal then begin
    if FileExists(F) and not DeleteFile(F) then
      Log('Could not delete ' + F + ' (the run journal next to it counts)');
    Exit;
  end;
  if FileExists(F) and not DeleteFileForced(F) then begin
    Log('Neither the run journal could be written nor ' + F + ' deleted: no change is made');
    Result := False;
  end;
end;

{ True when backup folder D belongs to a run that made its copies and then
  stopped before its first change: it holds the "backup only" marker and no
  run journal (repair 6). }
function BackupFolderUnstarted(const D: String): Boolean;
begin
  Result := FileExists(AddBackslash(D) + BACKUP_ONLY_NAME) and not FileExists(AddBackslash(D) + RUN_JOURNAL_NAME);
end;

procedure DeleteRunJournal;
var
  F: String;
begin
  if BackupDir = '' then
    Exit;
  F := AddBackslash(BackupDir) + RUN_JOURNAL_NAME;
  if FileExists(F) then begin
    if DeleteFile(F) then
      Log('Run journal closed (the run finished): ' + F)
    else
      Log('Could not delete the run journal ' + F);
  end;
end;

{ Deletes a backup folder: its manifest FIRST, then the rest. A folder
  without a manifest is a partial one that every later run and the
  uninstaller delete (DeleteOrphanBackups), so a stop in the middle of the
  deletion never leaves a folder whose manifest lists copies that are gone
  (which an uninstall could never restore; repair 5). False when the
  manifest cannot be deleted (the folder is then left whole). }
function DeleteBackupFolder(const Dir: String): Boolean;
var
  M: String;
begin
  Result := True;
  if (Dir = '') or not DirExists(Dir) then
    Exit;
  M := AddBackslash(Dir) + BACKUP_MANIFEST_NAME;
  if FileExists(M) then begin
    MakeFileWritable(M);
    if not DeleteFile(M) then begin
      Log('Could not delete ' + M + '; the backup folder is kept');
      Result := False;
      Exit;
    end;
  end;
  ShaCacheForgetUnder(Dir);
  if not DelTree(Dir, True, True, True) then
    Log('Could not delete ' + Dir + ' completely (a later run deletes the rest: it has no manifest now)');
end;

{ True for a backup folder name: yyyy-mm-dd_hh-nn-ss (NowForFolder), maybe
  followed by _<n>. }
function IsBackupStampName(const Name: String): Boolean;
var
  I: Integer;
  C: Char;
begin
  Result := False;
  if Length(Name) < BACKUP_STAMP_LEN then
    Exit;
  for I := 1 to Length(Name) do begin
    C := Name[I];
    if (I = 5) or (I = 8) or (I = 14) or (I = 17) then begin
      if C <> '-' then
        Exit;
    end else if (I = 11) or (I = BACKUP_STAMP_LEN + 1) then begin
      if C <> '_' then
        Exit;
    end else if (C < '0') or (C > '9') then
      Exit;
  end;
  Result := Length(Name) <> BACKUP_STAMP_LEN + 1;
end;

{ Deletes every backup folder of Conv that has no manifest: the partial
  copies of a Setup that was stopped (crash, power loss, killed) while it
  made its backup. Nothing in the Convergence folder changes before the
  manifest exists (the manifest is written last, under a temporary name that
  is renamed when complete; other mods' files are moved only after it), so
  such a folder holds nothing but copies. Without this they stayed for ever:
  no run and no uninstall lists a folder without a manifest (verifier 3,
  defect D4). Skip = this run's own folder. }
procedure DeleteOrphanBackups(const Conv, Skip: String);
var
  FindRec: TFindRec;
  Root, D: String;
  Orphans: TStringList;
  I: Integer;
begin
  Root := BackupRoot(Conv);
  if not DirExists(Root) then
    Exit;
  Orphans := TStringList.Create;
  try
    if FindFirst(AddBackslash(Root) + '*', FindRec) then begin
      try
        repeat
          if ((FindRec.Attributes and FA_DIRECTORY) <> 0) and ((FindRec.Attributes and FA_REPARSE_POINT) = 0) and
            IsBackupStampName(FindRec.Name) then
          begin
            D := AddBackslash(Root) + FindRec.Name;
            if not FileExists(AddBackslash(D) + BACKUP_MANIFEST_NAME) and not ((Skip <> '') and PathSame(D, Skip)) then
              Orphans.Add(D);
          end;
        until not FindNext(FindRec);
      finally
        FindClose(FindRec);
      end;
    end;
    for I := 0 to Orphans.Count - 1 do begin
      Log('Deleting a backup folder without a manifest (a stopped Setup''s partial backup): ' + Orphans[I]);
      ShaCacheForgetUnder(Orphans[I]);
      if not DelTree(Orphans[I], True, True, True) then
        Log('Could not delete ' + Orphans[I] + ' completely');
    end;
  finally
    Orphans.Free;
  end;
  RemoveDir(Root);
end;

{ Deletes every backup folder of Conv (but Skip) whose run stopped before
  its first change (BackupFolderUnstarted): it changed nothing, so there is
  nothing to put back, and applied by a later uninstall it would treat files
  that came after it (the player's own, at a path it planned to create) as
  ones it created (repair 6, code review of repair 5, LOW: a stop between
  the backup and Inno's "Installation process succeeded"). }
procedure DeleteUnstartedBackups(const Conv, Skip: String);
var
  Dirs: TStringList;
  I: Integer;
begin
  Dirs := TStringList.Create;
  try
    ListBackupDirs(Conv, Dirs);
    for I := Dirs.Count - 1 downto 0 do
      if not ((Skip <> '') and PathSame(Dirs[I], Skip)) and BackupFolderUnstarted(Dirs[I]) then begin
        Log('Deleting a backup whose run stopped before it changed anything: ' + Dirs[I]);
        DeleteBackupFolder(Dirs[I]);
      end;
  finally
    Dirs.Free;
  end;
  RemoveDir(BackupRoot(Conv));
end;

{ The SEQ number for a new backup: 1 + the highest one in this folder. }
function NextBackupSeq(const Conv: String): Integer;
var
  Dirs: TStringList;
  Lines: TArrayOfString;
  I, S: Integer;
begin
  Result := 1;
  Dirs := TStringList.Create;
  try
    ListBackupDirs(Conv, Dirs);
    for I := 0 to Dirs.Count - 1 do
      if ReadBackupManifest(Dirs[I], Lines) then begin
        S := StrToIntDef(ManifestValue(Lines, 'SEQ'), 0);
        if S + 1 > Result then
          Result := S + 1;
      end;
  finally
    Dirs.Free;
  end;
end;

{ Removes a failed or unused backup folder of this run (its manifest first:
  DeleteBackupFolder). }
procedure DropThisRunsBackup;
begin
  DeleteBackupFolder(BackupDir);
  RemoveDir(BackupRoot(ConvDir));
  BackupDir := '';
end;

{ Copies every B and E file into a new timestamped backup folder and writes
  the manifest. On any failure the partial backup is removed and nothing has
  been changed in the Convergence folder yet. }
function RunBackup(var Problem: String): Boolean;
var
  Stamp, D: String;
  Lines: TArrayOfString;
  L, NewDirs: TStringList;
  I, N, Done, Seq: Integer;
  HasMoved: Boolean;
begin
  Result := False;
  Problem := '';
  if not PlanMade then begin
    Problem := 'Internal check failed: there is no backup plan. Nothing was changed.';
    Exit;
  end;
  DeleteOrphanBackups(ConvDir, '');
  DeleteUnstartedBackups(ConvDir, '');
  Seq := NextBackupSeq(ConvDir);
  Stamp := NowForFolder;
  BackupDir := AddBackslash(BackupRoot(ConvDir)) + Stamp;
  N := 1;
  while DirExists(BackupDir) do begin
    BackupDir := AddBackslash(BackupRoot(ConvDir)) + Stamp + '_' + IntToStr(N);
    N := N + 1;
  end;
  if not ForceDirectories(BackupDir) then begin
    Problem := 'Could not create the backup folder:' + #13#10 + BackupDir + #13#10#13#10 +
      'Nothing was changed. Check that the drive has free space and that no other program ' +
      'is using the Convergence folder, then try again.';
    BackupDir := '';
    Exit;
  end;

  Done := 0;
  for I := 0 to PlanCount - 1 do begin
    { N: nothing to save; M: moved later, when the installation starts }
    if (PlanKind[I] = 'N') or (PlanKind[I] = 'M') then
      Continue;
    Done := Done + 1;
    ProgressText('Backing up the files that will be replaced...', PlanRel[I]);
    ProgressPos(I, PlanCount);
    if not CopyFileChecked(ConvPath(PlanRel[I]), AddBackslash(BackupDir) + PlanRel[I]) then begin
      Problem := 'Could not back up this file:' + #13#10 + ConvPath(PlanRel[I]) + #13#10#13#10 +
        'Nothing was changed. Check that the file is not open in another program and that ' +
        'the drive has free space, then try again.';
      DropThisRunsBackup;
      Exit;
    end;
  end;
  ProgressPos(PlanCount, PlanCount);

  HasMoved := False;
  for I := 0 to PlanCount - 1 do
    if PlanKind[I] = 'M' then
      HasMoved := True;
  L := TStringList.Create;
  NewDirs := TStringList.Create;
  try
    { folders the install will create (for N files), shallowest first; the
      restore walks the manifest bottom-up, so it handles the files first and
      then removes the deepest folders first }
    NewDirs.Sorted := True;
    NewDirs.Duplicates := dupIgnore;
    for I := 0 to PlanCount - 1 do
      if PlanKind[I] = 'N' then begin
        D := ExtractFileDir(PlanRel[I]);
        while (D <> '') and not DirExists(ConvPath(D)) do begin
          NewDirs.Add(D);
          D := ExtractFileDir(D);
        end;
      end;
    if HasMoved then
      L.Add(BACKUP_MANIFEST_MAGIC_2)
    else
      L.Add(BACKUP_MANIFEST_MAGIC);
    L.Add('# ' + CAT_MOD_TITLE + ' installer backup. Do not edit or move this folder.');
    L.Add('SEQ=' + IntToStr(Seq));
    L.Add('CREATED=' + NowForDisplay);
    L.Add('CONVERGENCE_DIR=' + ConvDir);
    L.Add('CONVERGENCE_VERSION=' + ConvVersion);
    L.Add('INSTALLER=' + CAT_VERSION);
    L.Add('SELECTION=' + SelectionText(',', ':'));
    L.Add('AUTO_ON=' + AutoOnText);      { 2026-10-03: read back by InterruptedRunSelection after a hard stop }
    if ForeignMove then
      L.Add('FOREIGN=move')
    else
      L.Add('FOREIGN=keep');
    L.Add('# B|path = the file existed; its original is in this folder and is put back on uninstall');
    L.Add('# N|path = the file did not exist; it is deleted on uninstall');
    L.Add('# E|path = [[natives]] entries of ours were appended; uninstall removes exactly those entries');
    L.Add('# D|path = the folder did not exist; it is removed on uninstall when empty');
    L.Add('# M|path = a file from another mod, moved into this folder; uninstall moves it back');
    L.Add('# (uninstall reads this list from the bottom up)');
    for I := 0 to NewDirs.Count - 1 do
      L.Add('D|' + NewDirs[I]);
    for I := 0 to PlanCount - 1 do
      L.Add(PlanKind[I] + '|' + PlanRel[I]);
    SetArrayLength(Lines, L.Count);
    for I := 0 to L.Count - 1 do
      Lines[I] := L[I];
  finally
    L.Free;
    NewDirs.Free;
  end;
  { written under a temporary name, flushed to the disk (with every copy
    before it: CopyFileChecked flushes each one; repair 5) and renamed when
    complete: a folder whose manifest exists is always a complete backup
    (DeleteOrphanBackups). The "backup only" marker comes first (repair 6),
    and a flush the drive refuses is logged, not fatal, as everywhere else
    (repair 6, code review of repair 5, LOW/INFO) }
  if not (WriteBackupOnlyMarker and
    SaveStringsToUTF8FileWithoutBOM(AddBackslash(BackupDir) + BACKUP_MANIFEST_NAME + '.tmp', Lines, False)) then
  begin
    Problem := 'Could not write the backup manifest in' + #13#10 + BackupDir;
    DropThisRunsBackup;
    Exit;
  end;
  FlushFileToDisk(AddBackslash(BackupDir) + BACKUP_MANIFEST_NAME + '.tmp');
  if not RenameFile(AddBackslash(BackupDir) + BACKUP_MANIFEST_NAME + '.tmp', AddBackslash(BackupDir) +
    BACKUP_MANIFEST_NAME) then
  begin
    Problem := 'Could not write the backup manifest in' + #13#10 + BackupDir;
    DropThisRunsBackup;
    Exit;
  end;
  BackupMade := True;
  Log(Format('Backup complete (SEQ %d): %d files copied to %s', [Seq, Done, BackupDir]));
  Result := True;
end;

{ Removes this run's backup when nothing was installed after all. }
procedure DiscardBackup;
begin
  if (BackupDir <> '') and DirExists(BackupDir) then begin
    Log('Discarding unused backup ' + BackupDir);
    DeleteBackupFolder(BackupDir);
    RemoveDir(BackupRoot(ConvDir));
  end;
  BackupDir := '';
  BackupMade := False;
end;

{ Called at the start of the post-install step (RunPostInstall; it was
  ssInstall before repair 5, when Inno had not registered the uninstaller
  yet): moves every M file of the plan into this run's backup folder, same
  relative path. A rename on the same drive; a copy + delete otherwise. A
  file that cannot be moved stays where it is; the verification after
  install reports it. Then switches off other mods' [[package]] entries in
  the .me3 profiles (backed up whole). }
procedure MoveForeignFilesToBackup;
var
  I, Moved, Failed, Count: Integer;
  Src, Dst: String;
begin
  Moved := 0;
  Failed := 0;
  if ForeignMove then
    for I := 0 to ME3_PROFILE_COUNT - 1 do
      if Me3ExtraCountIn(Me3Profile[I], 'P') > 0 then begin
        if not Me3SwitchOffPackages(ConvPath(Me3Profile[I]), Me3Profile[I], Count) then
          Log('Could not switch off the other mods'' [[package]] entries in ' + ConvPath(Me3Profile[I]));
        if Count > 0 then
          Me3ChangedNow[I] := True;
      end;
  for I := 0 to PlanCount - 1 do begin
    if PlanKind[I] <> 'M' then
      Continue;
    Src := ConvPath(PlanRel[I]);
    Dst := AddBackslash(BackupDir) + PlanRel[I];
    if not FileExists(Src) then begin
      Log('Already gone (nothing to move): ' + PlanRel[I]);
      Continue;
    end;
    if ForceDirectories(ExtractFileDir(Dst)) and RenameFile(Src, Dst) then begin
      Moved := Moved + 1;
      Log('Moved into the backup: ' + PlanRel[I]);
    end else if CopyFileChecked(Src, Dst) and DeleteFileForced(Src) then begin
      Moved := Moved + 1;
      Log('Copied into the backup and deleted: ' + PlanRel[I]);
    end else begin
      Failed := Failed + 1;
      Log('Could not move into the backup: ' + Src);
    end;
  end;
  if Moved + Failed > 0 then
    Log(Format('Files from other mods: %d moved into %s, %d could not be moved', [Moved, BackupDir, Failed]));
end;

{ ------------------------------------------------------------------ restore --- }

procedure RestoreStatus(const Text: String);
begin
  Log(Text);
  if IsUninstaller then begin
    UninstallProgressForm.StatusLabel.Caption := Text;
    UninstallProgressForm.StatusLabel.Repaint;
  end else
    ProgressText(Text, '');
end;

{ True when Target already holds exactly the bytes of Saved. }
function SameFileContent(const Target, Saved: String): Boolean;
var
  M: String;
begin
  Result := False;
  if not FileExists(Target) or (GetFileSizeSafe(Target) <> GetFileSizeSafe(Saved)) then
    Exit;
  M := SafeMD5(Target);
  Result := (M <> '') and (M = SafeMD5(Saved));
end;

{ True when the N entry Rel must stay at an uninstall: a catalog path that
  an option writes only while it is on (PathCanBeAbsent; not a user config)
  whose file now holds no content of the catalog for it - the player (or
  another mod) put that file there after the run that created the path (a
  body or face mod over one of Lucy's files); it is not this release's
  file, so it is never deleted as ours (repair 4, code review LOW: the D2
  rule of repair 3 at the uninstall, with the same scope). A path every
  selection writes (the merge's own files) is always ours: an older
  release's content there (v6.4's mckenyuBankai.lua) is deleted as before. }
function KeepNewFileAtUninstall(const Conv, Rel: String): Boolean;
var
  P: Integer;
begin
  Result := False;
  P := PathIndexOf(Rel);
  if (P < 0) or PathIsUserConfig(P) or not PathCanBeAbsent(P) or not FileExists(AddBackslash(Conv) + Rel) then
    Exit;
  Result := not PathHoldsOwnContentIn(Conv, P);
end;

{ Applies one backup folder to Conv. Failed paths are added to Failures.
  KeepOthers (a full restore = the uninstall): an N entry whose file holds
  another mod's content now is left in place (KeepNewFileAtUninstall); a
  rollback of the running Setup deletes what it created. }
function RestoreOneBackup(const Conv, BDir: String; Failures: TStringList; const KeepOthers: Boolean): Boolean;
var
  Lines: TArrayOfString;
  I, Before: Integer;
  Line, Kind, Rel, Target, Saved: String;
begin
  Before := Failures.Count;
  if not ReadBackupManifest(BDir, Lines) then begin
    Failures.Add('unreadable backup manifest in ' + BDir);
    Result := False;
    Exit;
  end;
  RestoreStatus('Restoring the files backed up on ' + ManifestValue(Lines, 'CREATED') + '...');
  for I := GetArrayLength(Lines) - 1 downto 0 do begin
    Line := Lines[I];
    if (Length(Line) < 3) or (Copy(Line, 2, 1) <> '|') then
      Continue;
    Kind := Copy(Line, 1, 1);
    Rel := Copy(Line, 3, Length(Line));
    { a manifest path must stay inside the Convergence folder (util.iss) }
    if not IsSafeRelPath(Rel) then begin
      Failures.Add('unsafe path in manifest: ' + Rel);
      Continue;
    end;
    Target := AddBackslash(Conv) + Rel;
    Saved := AddBackslash(BDir) + Rel;
    if Kind = 'B' then begin
      { a file that already holds the saved bytes needs no copy (it may even
        be locked by another program, which is then no failure) }
      if SameFileContent(Target, Saved) then
        Continue;
      if not CopyFileChecked(Saved, Target) then
        Failures.Add(Rel);
    end else if Kind = 'N' then begin
      if KeepOthers and KeepNewFileAtUninstall(Conv, Rel) then begin
        Log('Kept ' + Rel + ': it holds another mod''s file now (not one of this release''s contents), so the ' +
          'uninstall leaves it');
        RestoreKeptCount := RestoreKeptCount + 1;
        if RestoreKeptCount <= 20 then
          RestoreKeptText := RestoreKeptText + '  ' + Rel + #13#10;
        Continue;
      end;
      if not DeleteFileForced(Target) then
        Failures.Add(Rel);
    end else if Kind = 'E' then begin
      if not Me3RemoveAddedEntries(Target, Saved) then
        Failures.Add(Rel);
    end else if Kind = 'M' then begin
      { another mod's file: move it back. Not in the backup = it was never
        moved (the install stopped first, or it could not be moved). }
      if not FileExists(Saved) then begin
        if not FileExists(Target) then
          Log('Moved file is neither in the backup nor in the folder: ' + Rel);
        Continue;
      end;
      if SameFileContent(Target, Saved) then
        Continue;
      if not FileExists(Target) and ForceDirectories(ExtractFileDir(Target)) and RenameFile(Saved, Target) then
        Continue;
      if not CopyFileChecked(Saved, Target) then
        Failures.Add(Rel);
    end else if Kind = 'D' then begin
      { only an empty folder is removed; one that still holds files stays }
      if DirExists(Target) and not RemoveDir(Target) then
        Log('Folder kept (not empty): ' + Target);
    end else
      { a kind from a newer installer: never skip it (the folder would be
        deleted with whatever it holds) }
      Failures.Add('unknown entry ' + Kind + '|' + Rel + ' (a newer installer made this backup: run its uninstaller)');
  end;
  Result := Failures.Count = Before;
end;

{ Restores OnlyDir (when given) or every backup of Conv, newest first.
  Fully restored backup folders are deleted. The walk stops at the first
  folder that cannot be fully restored: that folder and the older ones are
  kept, so running the uninstaller again continues in the right order.
  Report receives a readable summary of any failures. }
function RestoreBackups(const Conv, OnlyDir: String; var Report: String): Boolean;
var
  Dirs, Failures: TStringList;
  I, Pending: Integer;
begin
  Report := '';
  Pending := 0;
  Dirs := TStringList.Create;
  Failures := TStringList.Create;
  try
    if OnlyDir <> '' then begin
      if DirExists(OnlyDir) then
        Dirs.Add(OnlyDir);
    end else
      ListBackupDirs(Conv, Dirs);
    Log(Format('Restoring %d backup folder(s) into %s', [Dirs.Count, Conv]));
    for I := Dirs.Count - 1 downto 0 do begin
      if (OnlyDir = '') and BackupFolderUnstarted(Dirs[I]) then begin
        { its run changed nothing (repair 6): nothing to put back }
        Log('Backup of a run that stopped before any change, deleted without applying it: ' + Dirs[I]);
        if not DeleteBackupFolder(Dirs[I]) then begin
          Failures.Add('the backup folder ' + Dirs[I] + ' cannot be deleted');
          Pending := I;
          Break;
        end;
        Continue;
      end;
      if RestoreOneBackup(Conv, Dirs[I], Failures, OnlyDir = '') then begin
        { the manifest goes first (DeleteBackupFolder): a restored folder that
          kept its manifest would be applied again after an OLDER one by a
          later uninstall, so the walk stops when it cannot be deleted
          (repair 5) }
        if not DeleteBackupFolder(Dirs[I]) then begin
          Failures.Add('the restored backup folder ' + Dirs[I] + ' cannot be deleted');
          Pending := I;
          Break;
        end;
      end else begin
        Log('Backup folder kept because some files could not be restored: ' + Dirs[I]);
        Pending := I;
        Break;
      end;
    end;
    RemoveDir(BackupRoot(Conv));
    Result := Failures.Count = 0;
    if not Result then begin
      Report := Format('%d item(s) could not be restored: ', [Failures.Count]) +
        JoinLimited(Failures, 8) + #13#10 + 'The backup is kept in ' + BackupRoot(Conv) + '.';
      if Pending > 0 then
        Report := Report + Format(' %d older backup folder(s) were not applied yet.', [Pending]);
    end;
  finally
    Dirs.Free;
    Failures.Free;
  end;
end;
