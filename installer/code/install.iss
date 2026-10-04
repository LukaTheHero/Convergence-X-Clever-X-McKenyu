{ =============================================================================
  install.iss - the installation itself, after the backup (contract 5.7):
  RunPostInstall (called at ssPostInstall) writes every wanted, not-in-place
  variant from its source (an archive member or a downloaded blob), removes
  what the selection must not have and the obsolete files of older releases,
  brings the .me3 profiles to the chosen natives, writes the fields into
  their ini files, writes the marker (format 3, contract 8), verifies every
  path, native, field and moved file, and on a failure offers the rollback.
  The files are written by Pascal code, not by [Files]: the payload is not
  inside the exe, a content may go to several paths, and every write is
  backed up and verified like v6.4.
  ============================================================================= }

{ ------------------------------------------------------------------ write --- }

function WriteVariants(var Problem: String): Boolean;
var
  P, K, Total, N: Integer;
  Dest: String;
begin
  Result := True;
  Total := PathCount;
  N := 0;
  for P := 0 to Total - 1 do begin
    K := DesiredVariant(P);
    if (K < 0) or VarSkip[K] then
      Continue;
    Dest := ConvPath(PathRel[P]);
    if PathIsUserConfig(P) and FileExists(Dest) then
      Continue;
    ProgressText(Format('Copying the files of %s (%d of %d)...', [CAT_VERSION_SHORT, P + 1, Total]), PathRel[P]);
    ProgressPos(P, Total);
    if (VarSrcPath[K] = '') or not CopyFileChecked(VarSrcPath[K], Dest) then begin
      Problem := 'Could not copy' + #13#10 + VarSrcPath[K] + #13#10 + 'to' + #13#10 + Dest;
      Result := False;
      Exit;
    end;
    N := N + 1;
  end;
  ProgressPos(Total, Total);
  Log(Format('Wrote %d file(s)', [N]));
end;

{ Removes Rel's folder and its parents up to (not including) a top-level
  folder (mod\ itself is never removed) while they are empty: folders a
  switched-off option leaves behind. A folder that holds anything stays. }
procedure RemoveEmptyParents(const Rel: String);
var
  D: String;
begin
  D := ExtractFileDir(Rel);
  while (D <> '') and (CompareText(D, 'mod') <> 0) and (Pos('\', D) > 0) do begin
    if not DirExists(ConvPath(D)) then
      Break;
    if not RemoveDir(ConvPath(D)) then
      Break;
    Log('Removed the empty folder ' + ConvPath(D));
    D := ExtractFileDir(D);
  end;
end;

function DeletePlanned(const Rel: String; var Problem: String): Boolean;
begin
  Result := DeleteFileForced(ConvPath(Rel));
  if Result then begin
    Log('Removed ' + Rel);
    RemoveEmptyParents(Rel);
  end else
    Problem := 'Could not delete ' + ConvPath(Rel);
end;

{ Removes what the selection must not have and the obsolete files (all
  backed up as B entries in BuildBackupPlan). User config files stay. }
function RemoveUnwantedFiles(var Problem: String): Boolean;
var
  I, N: Integer;
begin
  Result := True;
  N := 0;
  for I := 0 to PathCount - 1 do
    if PathDelete[I] and FileExists(ConvPath(PathRel[I])) then begin
      ProgressText('Removing the files of the options you switched off...', PathRel[I]);
      if not DeletePlanned(PathRel[I], Problem) then begin
        Result := False;
        Exit;
      end;
      N := N + 1;
    end;
  for I := 0 to GetArrayLength(ObsRel) - 1 do
    if ObsDelete[I] and FileExists(ConvPath(ObsRel[I])) then begin
      ProgressText('Removing files of older releases...', ObsRel[I]);
      if not DeletePlanned(ObsRel[I], Problem) then begin
        Result := False;
        Exit;
      end;
      N := N + 1;
    end;
  if N > 0 then
    Log(Format('Removed %d file(s) the selection does not have (they are in the backup)', [N]));
end;

{ Brings both .me3 profiles to the chosen natives (code\me3.iss). }
function UpdateMe3Profiles(var Problem: String): Boolean;
var
  I: Integer;
  Changed: Boolean;
  Lines: TArrayOfString;
begin
  Result := True;
  for I := 0 to ME3_PROFILE_COUNT - 1 do begin
    ProgressText('Updating the me3 profiles...', Me3Profile[I]);
    { every other table as it is right before the edit: the verification
      compares the written profile with it (repair 3, verifier 4 D1) }
    if LoadStringsFromFile(ConvPath(Me3Profile[I]), Lines) then
      Me3OtherBefore[I] := Me3OtherTablesText(Lines)
    else
      Me3OtherBefore[I] := '';
    if not Me3ApplyTarget(ConvPath(Me3Profile[I]), Me3Profile[I], Changed) then begin
      Problem := 'Could not update ' + ConvPath(Me3Profile[I]);
      Result := False;
      Exit;
    end;
    if Changed then
      Me3ChangedNow[I] := True;
  end;
end;

{ The values the player typed (contract 5.9). }
function WriteFields(var Problem: String): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to FieldCount - 1 do
    if FieldWrite[I] then begin
      if not IniSetValue(ConvPath(FieldRel[I]), FieldSection[I], FieldKey[I], FieldValue[I]) then begin
        Problem := 'Could not write ' + FieldLabel[I] + ' into ' + ConvPath(FieldRel[I]);
        Result := False;
        Exit;
      end;
      if FieldSecret[I] then
        Log('Wrote ' + FieldId[I] + ' (value not logged) into ' + FieldRel[I])
      else
        Log('Wrote ' + FieldId[I] + ' = ' + FieldValue[I] + ' into ' + FieldRel[I]);
    end;
end;

{ ---------------------------------------------------------------- outcome --- }

{ Other mods' files of this run: moved (M entries of the plan that are gone
  from the folder), not moved (M entries still there), kept (everything the
  scan listed that was not to be moved). Each list holds relative paths. }
procedure GetForeignOutcome(Moved, NotMoved, Kept: TStringList);
var
  I: Integer;
begin
  for I := 0 to PlanCount - 1 do
    if PlanKind[I] = 'M' then begin
      if FileExists(ConvPath(PlanRel[I])) then
        NotMoved.Add(PlanRel[I])
      else
        Moved.Add(PlanRel[I]);
    end;
  for I := 0 to ForeignCount - 1 do
    if (ForeignKind[I] <> 'M') or not ForeignMove then begin
      if ForeignNote[I] <> '' then
        Kept.Add(ForeignRel[I] + ' - ' + ForeignNote[I])
      else
        Kept.Add(ForeignRel[I] + ' - kept: the player chose to keep it');
    end;
  { other mods' files under a name of this release's options (repair 3) }
  for I := 0 to PathCount - 1 do
    if PathForeignFile[I] and PathKeepForeign[I] then
      Kept.Add(PathRel[I] + ' - kept: another mod''s file under a name one of the options also uses');
end;

{ Other mods' files that EARLIER runs of this installer moved into their
  backups (still there: uninstall moves them back), as "file (in backup)". }
procedure GetEarlierMoved(Earlier: TStringList);
var
  Dirs: TStringList;
  Lines: TArrayOfString;
  I, J: Integer;
  Rel: String;
begin
  Dirs := TStringList.Create;
  try
    ListBackupDirs(ConvDir, Dirs);
    for I := 0 to Dirs.Count - 1 do
      if not PathSame(Dirs[I], BackupDir) and ReadBackupManifest(Dirs[I], Lines) then
        for J := 0 to GetArrayLength(Lines) - 1 do
          if StartsWithStr(Lines[J], 'M|') then begin
            { assigned first: a Copy() inside the concatenation would lose
              non-ANSI characters (see SubStr in util.iss) }
            Rel := Copy(Lines[J], 3, Length(Lines[J]));
            if FileExists(AddBackslash(Dirs[I]) + Rel) then
              Earlier.Add(Rel + '  (in ' + BACKUP_ROOT_NAME + '\' + ExtractFileName(Dirs[I]) + ')');
          end;
  finally
    Dirs.Free;
  end;
end;

{ Other mods' .me3 entries of this run: switched off ([[package]] entries
  that are no longer active), still on (to be switched off, but active),
  kept (everything else the scan listed), and those an earlier run switched
  off. Each list holds "profile: line (- note)". }
procedure GetMe3Outcome(SwitchedOff, StillOn, Kept, Earlier: TStringList);
var
  I: Integer;
  OffNow: TStringList;
begin
  OffNow := TStringList.Create;
  try
    Me3SwitchedOffEntries(ConvDir, OffNow);
    for I := 0 to Me3ExtraCount - 1 do begin
      if (Me3ExtraKind[I] = 'P') and ForeignMove then begin
        if OffNow.IndexOf(Me3ExtraProfile[I] + ': ' + Me3ExtraLine[I]) >= 0 then
          SwitchedOff.Add(Me3ExtraProfile[I] + ': ' + Me3ExtraLine[I])
        else
          StillOn.Add(Me3ExtraProfile[I] + ': ' + Me3ExtraLine[I]);
      end else if Me3ExtraKind[I] = 'P' then
        Kept.Add(Me3ExtraProfile[I] + ': ' + Me3ExtraLine[I] + ' - kept: the player chose to keep it')
      else
        Kept.Add(Me3ExtraProfile[I] + ': ' + Me3ExtraLine[I] + ' - ' + Me3ExtraNote[I]);
    end;
    for I := 0 to OffNow.Count - 1 do
      if SwitchedOff.IndexOf(OffNow[I]) < 0 then
        Earlier.Add(OffNow[I]);
  finally
    OffNow.Free;
  end;
end;

function Me3OutcomeText(SwitchedOff, StillOn, Kept, Earlier: TStringList): String;
begin
  Result := '';
  if SwitchedOff.Count > 0 then
    Result := Format('%d [[package]] entr(ies) switched off (uninstall switches them back on)', [SwitchedOff.Count]);
  if StillOn.Count > 0 then begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Format('%d could NOT be switched off', [StillOn.Count]);
  end;
  if Kept.Count > 0 then begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Format('%d kept', [Kept.Count]);
  end;
  if Earlier.Count > 0 then begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + Format('%d switched off by an earlier run', [Earlier.Count]);
  end;
  if Result = '' then
    Result := 'none (the profiles load only The Convergence 3.0.2 and this installer''s options)';
end;

function ForeignOutcomeText(Moved, NotMoved, Kept: TStringList): String;
begin
  Result := '';
  if Moved.Count > 0 then
    Result := Format('%d moved into the backup (uninstall puts them back)', [Moved.Count]);
  if NotMoved.Count > 0 then begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Format('%d could NOT be moved', [NotMoved.Count]);
  end;
  if Kept.Count > 0 then begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Format('%d kept in place', [Kept.Count]);
  end;
  if Result = '' then
    Result := 'none found in mod\';
end;

procedure AddLines(L: TStringList; const Heading: String; Items: TStringList);
var
  I: Integer;
begin
  if Items.Count = 0 then
    Exit;
  L.Add('');
  L.Add(Heading);
  for I := 0 to Items.Count - 1 do begin
    if I >= FOREIGN_LIST_MAX then begin
      L.Add(Format('  ... and %d more', [Items.Count - FOREIGN_LIST_MAX]));
      Exit;
    end;
    L.Add('  ' + Items[I]);
  end;
end;

{ Every credit line of the selection: CreditText rows whose component is on
  (CreditComp -1 = always) and the components' own credits, each once. }
procedure GetCredits(L: TStringList);
var
  I, C: Integer;
begin
  for I := 0 to GetArrayLength(CreditText) - 1 do begin
    C := CreditComp[I];
    if ((C < 0) or ((C < CompCount) and CompOn(C))) and (CreditText[I] <> '') and (L.IndexOf(CreditText[I]) < 0) then
      L.Add(CreditText[I]);
  end;
  for C := 0 to CompCount - 1 do
    if CompOn(C) and (CompCredit[C] <> '') and (L.IndexOf(CompCredit[C]) < 0) then
      L.Add(CompCredit[C]);
end;

{ VERIFIED_ARCHIVES: the earlier marker's list plus the archives accepted in
  this run, for the components that are on now. }
function VerifiedArchivesText: String;
var
  A: Integer;
begin
  Result := '';
  for A := 0 to ArchCount - 1 do
    if ArchCompOn(A) and ((ArchState[A] = AS_ACCEPTED) or CommaListHas(PrevVerifiedArchives, ArchId[A])) then begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + ArchId[A];
    end;
end;

{ One line per component for the marker and the Finished page. }
function CompOutcomeText(const C: Integer): String;
var
  A: Integer;
begin
  Result := CompChoiceText(C);
  if CompKind[C] = 'R' then
    Result := 'yes (always installed)';
  if CompOn(C) then begin
    for A := 0 to ArchCount - 1 do
      if ArchComp[A] = C then begin
        if (ArchState[A] = AS_ACCEPTED) and not ArchTested[A] then
          Result := Result + ' - copied as it is from ' + ArchSource[A] + ' (not the tested version)'
        else if ArchState[A] = AS_ACCEPTED then
          Result := Result + ' - checked from ' + ArchSource[A]
        else if ArchNeeded[A] then
          Result := Result + ' - its download was NOT provided'
        else
          Result := Result + ' - its files were already in place';
      end;
  end else if (CompKind[C] <> 'X') and (DetectedState[C] >= 1) then
    Result := Result + ' (removed from this folder)';
end;

{ The file name of this run's uninstaller (unins000.exe, or unins001.exe in a
  folder that still holds the uninstaller of an earlier install under
  another Apps entry: a moved Convergence folder; repair 3, verifier 4 D3). }
function OwnUninstallerName: String;
begin
  Result := '';
  try
    Result := ExtractFileName(ExpandConstant('{uninstallexe}'));
  except
    Result := '';
  end;
  if Result = '' then
    Result := 'unins000.exe';
end;

{ <Conv>\CXCXM_INSTALLED.txt, format 3 (contract 8): machine lines, a blank
  line, then what is installed, from where, what was checked, how to undo,
  the credits. }
procedure WriteMarker(const Passed: Boolean; const VerificationText: String);
var
  Lines: TArrayOfString;
  L, Moved, NotMoved, Kept, Earlier, MeOff, MeOn, MeKept, MeEarlier, Credits: TStringList;
  Backup, Foreign, S: String;
  I, A: Integer;
begin
  if BackupDir <> '' then
    Backup := BACKUP_ROOT_NAME + '\' + ExtractFileName(BackupDir)
  else
    Backup := '(none)';
  L := TStringList.Create;
  Moved := TStringList.Create;
  NotMoved := TStringList.Create;
  Kept := TStringList.Create;
  Earlier := TStringList.Create;
  MeOff := TStringList.Create;
  MeOn := TStringList.Create;
  MeKept := TStringList.Create;
  MeEarlier := TStringList.Create;
  Credits := TStringList.Create;
  try
    GetForeignOutcome(Moved, NotMoved, Kept);
    GetEarlierMoved(Earlier);
    GetMe3Outcome(MeOff, MeOn, MeKept, MeEarlier);
    GetCredits(Credits);
    Foreign := ForeignOutcomeText(Moved, NotMoved, Kept);
    if Earlier.Count > 0 then
      Foreign := Foreign + Format('; %d moved by an earlier run (listed below)', [Earlier.Count]);
    L.Add(MARKER_MAGIC_3);
    L.Add('VERSION=' + CAT_VERSION);
    L.Add('RC=' + CAT_RC);
    L.Add('CATALOG_SHA256=' + CAT_SHA256);
    L.Add('SELECTION=' + SelectionText(',', ':'));
    { 2026-10-03: the ids this run switched on only because the selection needs them (ERCapacityExpansion for
      DMN + Nightreign's Wylder); the next run presets them off, so dropping DMN or NRM removes it again }
    L.Add('AUTO_ON=' + AutoOnText);
    L.Add('VERIFIED_ARCHIVES=' + VerifiedArchivesText);
    for A := 0 to ArchCount - 1 do
      if ArchIsModeV(A) and ArchCompOn(A) then
        L.Add(Uppercase(ArchId[A]) + '_VERSION=' + ModeVVersionText(A));
    if Passed then
      L.Add('RESULT=PASSED')
    else
      L.Add('RESULT=FAILED');
    L.Add('');
    L.Add(CAT_MOD_TITLE + ' (Auto Installer, release ' + CAT_RELEASE_TAG + ', ' + CAT_RC + ')');
    L.Add('');
    L.Add('Installed:            ' + NowForDisplay);
    L.Add('Convergence folder:   ' + ConvDir);
    L.Add('Convergence version:  ' + ConvVersion);
    L.Add('Elden Ring:           ' + GameSummaryText);
    L.Add('Convergence check:    ' + ConvCheckSummary);
    L.Add('Checked against:      the official release ' + ConvOfficial + ' (the Convergence Launcher''s download list)');
    L.Add('Other mods'' files:    ' + Foreign);
    L.Add('Other mods in .me3:   ' + Me3OutcomeText(MeOff, MeOn, MeKept, MeEarlier));
    L.Add('Backup of replaced:   ' + Backup);
    L.Add('Verification:         ' + VerificationText);
    L.Add('Changelog:            ' + CAT_CHANGELOG_REL);
    L.Add('Animation slots:      ' + FormatThousands(WallTotal) + ' of ' + FormatThousands(WallLimitUsed));
    if FetchFiles > 0 then
      L.Add(Format('Downloaded:           %d file(s), %s, SHA-256 checked', [FetchFiles, BytesToMB(FetchBytes)]));
    L.Add('');
    L.Add('Components:');
    for I := 0 to CompCount - 1 do
      if CompKind[I] <> 'X' then
        L.Add('  ' + CompCaption(I) + ': ' + CompOutcomeText(I));
    for I := 0 to FieldCount - 1 do
      if CompOn(FieldComp[I]) then begin
        if FieldValue[I] = '' then
          S := 'not set by this installer'
        else if FieldSecret[I] then
          S := 'set (not shown here)'
        else
          S := FieldValue[I];
        L.Add('  ' + FieldLabel[I] + ' ' + S);
      end;
    for I := 0 to GetArrayLength(RuleWarnings) - 1 do
      L.Add('  Warning: ' + RuleWarnings[I]);
    L.Add('');
    L.Add('To change the options, run the installer again and pick them on the Options page. What is');
    L.Add('installed now is preselected.');
    L.Add('To uninstall: Windows Settings > Apps > Installed apps > "' + CAT_MOD_TITLE + ' (...)" > Uninstall,');
    L.Add('or run ' + UNINSTALL_DIR_NAME + '\' + OwnUninstallerName + ' in this folder (not in a copy of it). It puts the backed-up');
    L.Add('Convergence files back and removes the files and folders this installer added.');
    L.Add('Launch the game with Start_Convergence.bat or the Convergence Launcher. Play offline.');
    if Credits.Count > 0 then begin
      L.Add('');
      L.Add('Credits (thank you):');
      for I := 0 to Credits.Count - 1 do
        L.Add('  ' + Credits[I]);
    end;
    AddLines(L, 'Files from other mods moved into ' + Backup + ' (uninstall moves them back):', Moved);
    AddLines(L, 'Files from other mods that could NOT be moved (they are still in mod\):', NotMoved);
    AddLines(L, 'Files from other mods kept in place:', Kept);
    AddLines(L, 'Files from other mods moved by an earlier run of this installer (uninstall moves them back):', Earlier);
    AddLines(L, 'Other mods'' [[package]] entries switched off in the .me3 profiles (uninstall switches them back on):', MeOff);
    AddLines(L, 'Other mods'' [[package]] entries that could NOT be switched off:', MeOn);
    AddLines(L, 'Other mods loaded by your .me3 profiles, kept:', MeKept);
    AddLines(L, 'Other mods'' [[package]] entries switched off by an earlier run of this installer:', MeEarlier);
    SetArrayLength(Lines, L.Count);
    for I := 0 to L.Count - 1 do
      Lines[I] := L[I];
  finally
    L.Free;
    Moved.Free;
    NotMoved.Free;
    Kept.Free;
    Earlier.Free;
    MeOff.Free;
    MeOn.Free;
    MeKept.Free;
    MeEarlier.Free;
    Credits.Free;
  end;
  if not SaveLinesUTF8Replacing(ConvPath(MARKER_NAME), Lines) then
    Log('Could not write ' + ConvPath(MARKER_NAME));
end;

{ ------------------------------------------------------------ verification --- }

{ Checks every path of the catalog against the selection (the right variant
  by sha256, a user config file or a dynamic variant without a known hash by
  existence, or not there), the obsolete files that were removed, the
  fields, the natives of both profiles, and the files and entries of other
  mods that were to be moved / switched off. Returns the number of checks;
  failures are listed in Failures. }
function VerifyInstallation(Failures: TStringList): Integer;
var
  I, K, Total, Step: Integer;
  Full, Sha, Problem, Cur: String;
  Found: Boolean;
begin
  Result := 0;
  Total := PathCount + 4;
  Step := 0;

  for I := 0 to PathCount - 1 do begin
    Step := Step + 1;
    ProgressText(Format('Checking the installed files (%d of %d)...', [Step, Total]), PathRel[I]);
    ProgressPos(Step, Total);
    Full := ConvPath(PathRel[I]);
    K := DesiredVariant(I);
    if K >= 0 then begin
      Sha := VariantSha(K);
      if PathIsUserConfig(I) or (Sha = '') then begin
        if not FileExists(Full) then
          Failures.Add(PathRel[I] + ' (missing)');
      end else if not FileHasSHA256(Full, Sha, VarSize[K]) then
        Failures.Add(PathRel[I]);
      Result := Result + 1;
    end else if K = PT_ABSENT then begin
      if FileExists(Full) and not PathKeepForeign[I] then
        Failures.Add(PathRel[I] + ' (must not be there with the chosen options)');
      Result := Result + 1;
    end;
  end;

  for I := 0 to GetArrayLength(ObsRel) - 1 do
    if ObsDelete[I] then begin
      if FileExists(ConvPath(ObsRel[I])) then
        Failures.Add(ObsRel[I] + ' (a file of an older release is still there)');
      Result := Result + 1;
    end;

  for I := 0 to FieldCount - 1 do
    if FieldWrite[I] then begin
      Cur := IniGetValue(ConvPath(FieldRel[I]), FieldSection[I], FieldKey[I], Found);
      if not Found or (Cur <> FieldValue[I]) then
        Failures.Add(FieldRel[I] + ' (' + FieldKey[I] + ' in [' + FieldSection[I] + '] was not written)');
      Result := Result + 1;
    end;

  ProgressText('Checking the me3 profiles...', '');
  for I := 0 to ME3_PROFILE_COUNT - 1 do begin
    Problem := Me3VerifyProfile(ConvPath(Me3Profile[I]));
    { a profile Setup rewrote: readable, every other table as before the
      edit, and me3's own reader takes it (repair 3, verifier 4 D1) }
    if (Problem = '') and Me3ChangedNow[I] then
      Problem := Me3VerifyProfileEdit(ConvPath(Me3Profile[I]), Me3OtherBefore[I]);
    if Problem <> '' then
      Failures.Add(Me3Profile[I] + ' (' + Problem + ')');
    Result := Result + 1;
  end;

  { files from other mods that were to be moved into the backup }
  for I := 0 to PlanCount - 1 do
    if (PlanKind[I] = 'M') and FileExists(ConvPath(PlanRel[I])) then
      Failures.Add(PlanRel[I] + ' (a file from another mod that could not be moved into the backup)');

  { other mods' [[package]] entries that were to be switched off }
  if ForeignMove then
    for I := 0 to ME3_PROFILE_COUNT - 1 do
      if (Me3ExtraCountIn(Me3Profile[I], 'P') > 0) and (Me3ActiveOtherPackages(ConvPath(Me3Profile[I]),
        Me3Profile[I]) > 0) then
        Failures.Add(Me3Profile[I] + ' (still loads another mod''s [[package]])');
  ProgressPos(Total, Total);
  Log(Format('Verification: %d checks, %d problem(s)', [Result, Failures.Count]));
end;

function FinishedSuccessText: String;
var
  Foreign, S: String;
  Moved, NotMoved, Kept, MeOff, MeOn, MeKept, MeEarlier: TStringList;
  C: Integer;
begin
  Moved := TStringList.Create;
  NotMoved := TStringList.Create;
  Kept := TStringList.Create;
  MeOff := TStringList.Create;
  MeOn := TStringList.Create;
  MeKept := TStringList.Create;
  MeEarlier := TStringList.Create;
  try
    GetForeignOutcome(Moved, NotMoved, Kept);
    GetMe3Outcome(MeOff, MeOn, MeKept, MeEarlier);
    Foreign := 'Files from other mods in mod\: ' + ForeignOutcomeText(Moved, NotMoved, Kept);
    if Moved.Count + Kept.Count > 0 then
      Foreign := Foreign + ' (listed in ' + MARKER_NAME + ')';
    if MeOff.Count + MeKept.Count > 0 then
      Foreign := Foreign + #13#10 + 'Other mods in the .me3 profiles: ' +
        Me3OutcomeText(MeOff, MeOn, MeKept, MeEarlier);
  finally
    Moved.Free;
    NotMoved.Free;
    Kept.Free;
    MeOff.Free;
    MeOn.Free;
    MeKept.Free;
    MeEarlier.Free;
  end;
  S := '';
  for C := 0 to CompCount - 1 do
    if CompIsOptional(C) then
      S := S + CompTitle[C] + ': ' + CompChoiceText(C) + #13#10;
  Result := CAT_MOD_TITLE + ' is installed in:' + #13#10 + ConvDir + #13#10#13#10 + S + Foreign + #13#10 +
    Format('All %d checks passed: every file matches this release.', [VerifiedFileCount]) + #13#10#13#10 +
    'Launch the game with Start_Convergence.bat in that folder (or the Convergence Launcher). ' +
    'Play offline. Run this installer again to change the options.' + #13#10#13#10 +
    'Replaced files were backed up to ' + BACKUP_ROOT_NAME + '. Uninstalling (Windows ' +
    'Settings > Apps) puts them back.';
end;

{ Called from CurStepChanged(ssPostInstall). Never raises; failures are
  reported, offered a rollback, and turned into a non-zero exit code. }
procedure RunPostInstall;
var
  Problem, Report, Msg, Detail: String;
  Failures, Dirs: TStringList;
  StepsOk: Boolean;
begin
  Problem := '';
  Failures := TStringList.Create;
  try
    { the run's journal right before its first change; then other mods'
      files go into the backup (Inno has registered the uninstaller by now,
      so a Setup stopped hard from here on can be uninstalled; repair 5) }
    { repair 6: the "backup only" marker goes once the journal is there }
    StepsOk := StartChangingBackupRun;
    if not StepsOk then
      Problem := 'Setup could not record in its backup folder that it starts to change your Convergence ' +
        'folder, so nothing was changed.'
    else begin
      MoveForeignFilesToBackup;
      StepsOk := WriteVariants(Problem);
    end;
    if StepsOk then
      StepsOk := RemoveUnwantedFiles(Problem);
    if StepsOk then
      StepsOk := UpdateMe3Profiles(Problem);
    if StepsOk then
      StepsOk := WriteFields(Problem);
    if StepsOk then
      WriteMarker(False, 'in progress');

    VerifiedFileCount := VerifyInstallation(Failures);

    if StepsOk and (Failures.Count = 0) then begin
      WriteMarker(True, Format('PASSED - all %d checks match this release (SHA-256)', [VerifiedFileCount]));
      FinalReport := FinishedSuccessText;
      Log(Format('CXCXM VERIFY PASSED checks=%d', [VerifiedFileCount]));
      Log('Post-install: PASSED');
    end else begin
      PostInstallFailed := not StepsOk;
      VerifyFailed := True;
      if StepsOk then
        Log(Format('CXCXM VERIFY FAILED problems=%d', [Failures.Count]))
      else
        Log(Format('CXCXM VERIFY FAILED problems=%d', [Failures.Count + 1]));
      Detail := '';
      if Problem <> '' then
        Detail := Problem + #13#10#13#10;
      if Failures.Count > 0 then
        Detail := Detail + Format('%d file(s) do not match this release: ', [Failures.Count]) +
          JoinLimited(Failures, 8) + #13#10#13#10;
      Msg := 'The installation did not complete correctly.' + #13#10#13#10 + Detail +
        'Setup can put your Convergence folder back exactly as it was before this ' +
        'installer ran (recommended). Restore it now?';
      if AskYesNo(Msg, IDYES) then begin
        ProgressText('Restoring your Convergence folder...', '');
        RolledBack := RestoreBackups(ConvDir, BackupDir, Report);
        if RolledBack then begin
          FinalReport := 'The installation failed, so Setup put your Convergence files back as they ' +
            'were before this run.';
          Dirs := TStringList.Create;
          try
            ListBackupDirs(ConvDir, Dirs);
            if Dirs.Count > 0 then
              FinalReport := FinalReport + ' Your earlier installation of the mod in this folder ' +
                'is unchanged and can still be uninstalled from Windows Settings > Apps.';
          finally
            Dirs.Free;
          end;
          FinalReport := FinalReport + #13#10#13#10 + 'Problem: ' + Trim(Detail);
        end else
          FinalReport := 'The installation failed and the folder could not be fully restored.' + #13#10 +
            Report + #13#10#13#10 + 'Run this installer again, or uninstall the mod (Windows Settings > ' +
            'Apps) to restore the rest.' + #13#10#13#10 + 'Problem: ' + Trim(Detail);
        ShowError(FinalReport);
      end else begin
        WriteMarker(False, Format('FAILED - %d problem(s); see the Setup log', [Failures.Count]));
        FinalReport := 'The installation finished WITH ERRORS. Run this installer again, or uninstall ' +
          'it (Windows Settings > Apps) to restore the backup.' + #13#10#13#10 + Trim(Detail);
      end;
    end;
  finally
    Failures.Free;
    { the run ended (passed, failed and kept, or rolled back) }
    DeleteRunJournal;
  end;
end;
