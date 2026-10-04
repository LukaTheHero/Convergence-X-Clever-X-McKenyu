{ =============================================================================
  events.iss - Inno Setup event functions, [Setup] callbacks and the
  unattended (/SILENT, /VERYSILENT) path (contract sections 5 and 7).

  Command line (all optional in the wizard, where they only preselect):
    /CONVDIR="path"          Convergence folder (the folder itself, or the
                             launcher's install folder that holds ConvergenceER)
    /COMPONENTS=list         (alias /SELECT=) the whole selection: "id" (on)
                             or "id:code", comma separated, e.g.
                             /COMPONENTS=lucy,nrm,infdur:v2 ; every optional
                             component not listed is off; "none" = all off
    /LUCY= /NRM= /INFDUR= /ARROWS= /SEAMLESS= /ERCAP= /DMN=   one component
                             each (0/1, or the state code: /INFDUR=none|v1..v4);
                             they win over /COMPONENTS. Not given: what the
                             folder has now (detection), else off.
    /ARCHIVE_<ID>="path"     a download: the archive or the folder it was
                             extracted to (/ARCHIVE_MCK_14=, /ARCHIVE_DMN=,
                             /ARCHIVE_NRM_02=, /ARCHIVE_SEAMLESS=,
                             /ARCHIVE_MAIN_V65=, and /ARCHIVE_CLEVER_262= =
                             /CLEVER=)
    /ARCHIVEDIR="folder"     a folder with the downloads (searched like the
                             Downloads folder)
    /SEARCHDOWNLOADS=0|1     silent runs search the Downloads folder (default 0)
    /BASEURL=url             replaces the download mirrors (tests: the local
                             server); several: separate them with |
    /UPSTREAM=0|1            try the authors' own release first (default 1)
    /COOPPASSWORD=text       Seamless Co-op session password (when Seamless is on)
    /FOREIGN=move|keep       other mods' files under mod\ and their [[package]]
                             entries: moved / switched off (default) or kept
    /GAMEOK=1                the player confirms Elden Ring Patch 1.17 with
                             Shadow of the Erdtree when Setup cannot find the
                             game (or read its version)
  A switch that looks like ours but is not (same first three letters, not
  one of Inno's own), or one of ours without a value, is refused.

  Silent runs validate in this order: options, Elden Ring (A), Convergence
  folder, selection (presets + switches, rules, animation wall, .me3),
  downloads, The Convergence 3.0.2 files (B), other mods' files (C); then
  PrepareToInstall downloads the hosted files and makes the backup.
  Exit codes: 0 ok; 1 validation failed before anything was changed
  (InitializeSetup, incl. missing or wrong downloads); 7 refused at
  Preparing (game running, a download failed, the Convergence check failed
  on its second run, backup failed; nothing changed); 20 install failed
  verification and was rolled back; 21 failed and kept; 22 a post-install
  step failed. Uninstaller: 0 ok; non-zero = refused or restore failed.
  ============================================================================= }

{ ------------------------------------------------ [Setup] code: callbacks --- }

{ One AppId per Convergence folder: each folder gets its own uninstall entry
  and uninstall log (the v6.3/v6.4 formula: v6.5 takes their entry over). }
function GetAppId(Param: String): String;
begin
  if ConvDir = '' then
    Result := ''
  else
    Result := 'CanalpaCXCXM_' + Copy(GetMD5OfUnicodeString(Lowercase(ConvDir)), 1, 16);
end;

function GetUninstallDisplayName(Param: String): String;
begin
  Result := CAT_MOD_TITLE;
  if ConvDir <> '' then
    Result := Result + ' (' + ConvDir + ')';
end;

{ ----------------------------------------------------------- the folder --- }

{ A (new) Convergence folder was chosen: forget what belonged to the old
  one, read this one's marker, make the presets. Problem: an invalid
  command line value (silent runs stop on it). }
function SelectConvergenceFolder(const Dir: String; var Problem: String): Boolean;
begin
  Problem := '';
  if (SelectionPresetFor = '') or not PathSame(Dir, SelectionPresetFor) then begin
    if SelectionPresetFor <> '' then
      Log('Convergence folder changed: ' + SelectionPresetFor + ' -> ' + Dir);
    ReleaseAllArchives;
    ConvDir := Dir;
    ConvVersion := ReadConvergenceVersion(Dir);
    DeleteStaleWorkDir(Dir);
    ReadPreviousMarker(Dir);
    Result := ApplySelectionPresets(Problem);
  end else
    Result := True;
end;

{ Rules, wall and the .me3 check for the selection. '' when it can be
  installed. }
function CheckSelection(const Silent: Boolean): String;
begin
  Result := '';
  if not NormalizeSelection(Silent, Result) then
    Exit;
  Result := Me3ProfilesProblem;
end;

#if Defined(CodeCheck) || Defined(TestBuild)
{ test builds only: /TESTUNIT=<folder> runs the .me3 and ini code on test
  files, for the selection of /COMPONENTS and the per-component switches
  on the catalog defaults (no folder, no detection), and stops (exit 1).
  Every case is a subfolder <folder>\<case>:
    in\me3\<profile>        -> out\me3\<profile> (Me3ComputeTarget + the
                               canonical writing) and out\me3\<profile>.kind
                               (Me3PlanKind: E, B or "-" for no change), or
                               out\me3\<profile>.refused (the problem text)
    restore\me3\<profile> + saved\me3\<profile>
                            -> out\restored\me3\<profile> (the uninstall of
                               a kind E entry: Me3RemoveAddedEntries)
    ini\in.ini + ini\args.txt (section, key, value: one per line)
                            -> out\ini.ini (IniSetValue) and out\ini.value
                               (IniGetValue afterwards) }
procedure TestUnitCase(const D: String);
var
  I: Integer;
  InF, OutF, Problem, Kind, Section, Key, Value, Got, Other: String;
  Lines, Target, Args: TArrayOfString;
  Found, Changed: Boolean;
begin
  for I := 0 to ME3_PROFILE_COUNT - 1 do begin
    InF := AddBackslash(D) + 'in\' + Me3Profile[I];
    OutF := AddBackslash(D) + 'out\' + Me3Profile[I];
    if FileExists(InF) and LoadStringsFromFile(InF, Lines) then begin
      ForceDirectories(ExtractFileDir(OutF));
      Problem := '';
      { as Me3ProfilesProblem: me3's own reading of the natives must be
        Setup's (repair 5; runs only with /TESTME3EXE=, there is no
        Convergence folder here) }
      if Me3ComputeTarget(Lines, Me3Profile[I], Target, Problem) then
        Problem := Me3ExeProblem(InF);
      if Problem <> '' then
        SaveStringToFile(OutF + '.refused', Problem, False)
      else begin
        { the target is written like Me3ApplyTarget does: unchanged lines keep the file }
        if SameLines(Lines, Target) then
          CopyFile(InF, OutF, False)
        else
          SaveMe3Lines(OutF, Target);
        Kind := Me3PlanKind(InF, Me3Profile[I]);
        if Kind = '' then
          Kind := '-';
        SaveStringToFile(OutF + '.kind', Kind, False);
      end;
    end;
    InF := AddBackslash(D) + 'restore\' + Me3Profile[I];
    OutF := AddBackslash(D) + 'out\restored\' + Me3Profile[I];
    if FileExists(InF) then begin
      ForceDirectories(ExtractFileDir(OutF));
      CopyFile(InF, OutF, False);
      if not Me3RemoveAddedEntries(OutF, AddBackslash(D) + 'saved\' + Me3Profile[I]) then
        SaveStringToFile(OutF + '.failed', 'Me3RemoveAddedEntries failed', False);
    end;
    InF := AddBackslash(D) + 'apply\' + Me3Profile[I];
    OutF := AddBackslash(D) + 'out\applied\' + Me3Profile[I];
    if FileExists(InF) then begin
      ForceDirectories(ExtractFileDir(OutF));
      CopyFile(InF, OutF, False);
      { as UpdateMe3Profiles + VerifyInstallation (repair 3: the edit check) }
      Other := '';
      if LoadStringsFromFile(OutF, Lines) then
        Other := Me3OtherTablesText(Lines);
      Problem := Me3ExeProblem(OutF);
      if Problem <> '' then
        SaveStringToFile(OutF + '.failed', 'refused (me3 reader check): ' + Problem, False)
      else if not Me3ApplyTarget(OutF, Me3Profile[I], Changed) then
        SaveStringToFile(OutF + '.failed', 'Me3ApplyTarget failed', False)
      else begin
        Problem := Me3VerifyProfile(OutF);
        if (Problem = '') and Changed then
          Problem := Me3VerifyProfileEdit(OutF, Other);
        if Problem = '' then
          Problem := 'OK';
        SaveStringToFile(OutF + '.verify', Problem, False);
      end;
    end;
  end;
  InF := AddBackslash(D) + 'ini\in.ini';
  if FileExists(AddBackslash(D) + 'ini\args.txt') and LoadStringsFromFile(AddBackslash(D) + 'ini\args.txt', Args) and
    (GetArrayLength(Args) >= 3) then
  begin
    Section := Args[0];
    Key := Args[1];
    Value := Args[2];
    OutF := AddBackslash(D) + 'out\ini.ini';
    ForceDirectories(ExtractFileDir(OutF));
    if FileExists(InF) then
      CopyFile(InF, OutF, False)
    else
      DeleteFile(OutF);
    if not IniSetValue(OutF, Section, Key, Value) then
      SaveStringToFile(OutF + '.failed', 'IniSetValue failed', False);
    Got := IniGetValue(OutF, Section, Key, Found);
    if not Found then
      Got := '<not found>';
    SaveStringToFile(AddBackslash(D) + 'out\ini.value', UTF8Encode(Got), False);
  end;
end;

function TestUnit(const Dir: String): String;
var
  FR: TFindRec;
  N: Integer;
  Problem: String;
begin
  ResetSelection;
  if not ApplyComponentsParam(Problem) or not ApplyComponentSwitches(Problem) then begin
    Result := 'TESTUNIT: ' + Problem;
    Exit;
  end;
  N := 0;
  if FindFirst(AddBackslash(Dir) + '*', FR) then begin
    try
      repeat
        if ((FR.Attributes and FA_DIRECTORY) <> 0) and (FR.Name <> '.') and (FR.Name <> '..') then begin
          TestUnitCase(AddBackslash(Dir) + FR.Name);
          N := N + 1;
        end;
      until not FindNext(FR);
    finally
      FindClose(FR);
    end;
  end;
  Result := Format('TESTUNIT: %d case(s) done for %s', [N, SelectionText(' ', '=')]);
end;

{ test builds only (see /TESTDLSEARCH in PrepareSilentRun): every enabled
  archive is "needed"; the download search runs and its result is logged. }
function TestDownloadSearch: String;
var
  A: Integer;
begin
  Result := 'TESTDLSEARCH:';
  for A := 0 to ArchCount - 1 do begin
    ArchNeeded[A] := True;
    ArchState[A] := AS_MISSING;
  end;
  AutoFindArchives(True, -1, True);
  for A := 0 to ArchCount - 1 do
    if ArchState[A] = AS_ACCEPTED then
      Result := Result + #13#10 + ArchId[A] + ' accepted ' + ArchSource[A]
    else if ArchState[A] = AS_REJECTED then
      Result := Result + #13#10 + ArchId[A] + ' rejected ' + ArchSource[A] + ': ' + ArchProblem[A]
    else
      Result := Result + #13#10 + ArchId[A] + ' missing';
end;
#endif

{ Everything a silent run needs, validated up front. Returns '' when ready,
  otherwise the reason (Setup then exits with code 1, nothing changed). }
function PrepareSilentRun: String;
var
  Dir, Problem: String;
  I, Valid: Integer;
begin
  Result := '';
  Log('Unattended install: ' + MaskedCmdTail);
  if SecretSwitchNote <> '' then
    Log(SecretSwitchNote);
#if Defined(CodeCheck) || Defined(TestBuild)
  { test builds only: /TESTGAMEONLY=1 runs check A, logs it and stops.
    /TESTGAMEBROWSE="folder" then does what the page's Browse button does
    (refused unless Steam's own copy could not be checked) and runs the
    check that PrepareToInstall repeats (RecheckGame). }
  if CmdParam('TESTGAMEONLY') = '1' then begin
    RunGameCheck;
    Result := Format('TESTGAMEONLY: status %d, passed %s, exe "%s", version "%s", browse allowed %s', [GameStatus,
      BoolText(GameCheckPassed), GameExePath, GameVersion, BoolText(GameBrowseAllowed)]) + #13#10 + GameStatusText;
    if CmdParam('TESTGAMEBROWSE') <> '' then begin
      Problem := ApplyGameBrowse(CmdParam('TESTGAMEBROWSE'));
      if Problem <> '' then
        Result := Result + #13#10 + 'TESTGAMEBROWSE refused: ' + Problem
      else begin
        RecheckGame;
        Result := Result + #13#10 + Format('TESTGAMEBROWSE: status %d, passed %s, exe "%s", version "%s"', [GameStatus, BoolText(GameCheckPassed), GameExePath, GameVersion]) + #13#10 + 'summary: ' +
          GameSummaryText;
      end;
    end;
    Exit;
  end;
  if CmdParam('TESTUNIT') <> '' then begin
    Result := TestUnit(CmdParam('TESTUNIT'));
    Exit;
  end;
  { test builds only: /TESTDLSEARCH=1 runs the wizard's Downloads search for
    every archive, logs what it accepts, and stops (exit code 1) }
  if CmdParam('TESTDLSEARCH') = '1' then begin
    Result := TestDownloadSearch;
    Exit;
  end;
#endif
#ifdef CodeCheck
  { code-check build only: /SCANONLY=1 runs the detection, logs it and stops }
  if CmdParam('SCANONLY') = '1' then begin
    ScanForConvergence;
    Result := Format('SCANONLY: %d found, %d usable, %d folders listed in %d ms', [FoundCount,
      CountValidFound, ScanDirCount, GetTickCount - ScanStartTick]);
    Exit;
  end;
#endif

  { A: Elden Ring. A wrong version or a missing DLC always stops here; a game
    Setup cannot find (or read) needs /GAMEOK=1. }
  RunGameCheck;
  if GameStatus = GS_WRONG then begin
    Result := GameProblem;
    Exit;
  end;
  if GameStatus <> GS_OK then begin
    if not GameConfirmed then begin
      Result := GameStatusText + #13#10#13#10 + 'Unattended: if you are sure you have Elden Ring ' +
        GAME_PATCH_NAME + ' with Shadow of the Erdtree, confirm it with /GAMEOK=1.';
      Exit;
    end;
    Log('Elden Ring could not be checked; the player confirmed it with /GAMEOK=1');
  end;

  { Convergence folder: /CONVDIR, or exactly one usable detected install }
  if ParamConvDir <> '' then
    Dir := ResolveConvergenceDir(ParamConvDir)
  else begin
    ScanForConvergence;
    Valid := CountValidFound;
    if Valid <> 1 then begin
      Result := Format('No /CONVDIR was given and %d usable Convergence folder(s) were found ' +
        '(%d in total). Pass /CONVDIR="path to your Convergence folder".', [Valid, FoundCount]);
      Exit;
    end;
    for I := 0 to FoundCount - 1 do
      if FoundProblem[I] = '' then
        Dir := FoundDir[I];
  end;
  Problem := DescribeConvergenceProblem(Dir, True);
  if Problem <> '' then begin
    Result := 'Convergence folder: ' + Problem;
    Exit;
  end;
#if Defined(CodeCheck) || Defined(TestBuild)
  { test builds only: /TESTCHECKSONLY=1 runs checks B and C on the folder,
    logs them and stops (exit code 1, nothing changed) }
  if CmdParam('TESTCHECKSONLY') = '1' then begin
    ConvDir := Dir;
    if CheckConvergenceIntegrity(ConvDir, Problem, ConvCheckSummary) then begin
      ScanForeignFiles(ConvDir);
      Result := 'TESTCHECKSONLY: ' + ConvCheckSummary + #13#10 +
        Format('foreign files: %d (%d movable)', [ForeignCount, ForeignCountOf('M')]) + #13#10 +
        ForeignLines('MDL', True) +
        Format('me3 entries: %d (%d package)', [Me3ExtraCount, Me3ExtraCountOf('P')]) + #13#10 +
        Me3ExtraLines('PN', True);
    end else
      Result := 'TESTCHECKSONLY: ' + Problem;
    Exit;
  end;
#endif

  { the selection: what the folder has now, then the switches; then rules,
    the animation wall and the .me3 check }
  if not SelectConvergenceFolder(Dir, Problem) then begin
    Result := Problem;
    Exit;
  end;
  Result := CheckSelection(True);
  if Result <> '' then
    Exit;

  { the downloads: /ARCHIVE_<ID>, /ARCHIVEDIR, Downloads (/SEARCHDOWNLOADS=1) }
  ComputeArchivesNeeded;
  if ArchivesNeededCount > 0 then begin
    AutoFindArchives(SilentSearchDownloads, -1, True);
    if ArchivesMissingCount > 0 then begin
      LogMissingArchives;
      Result := Format('%d download(s) that the chosen options need were not provided (or did not ' +
        'match):', [ArchivesMissingCount]) + #13#10 + MissingArchivesText;
      ReleaseWorkRoot;
      Exit;
    end;
  end;

  { the typed values (/COOPPASSWORD=): an ini Setup never edits (not UTF-8)
    is refused now, not after every file was copied }
  Result := FieldsProblemText;
  if Result <> '' then begin
    ReleaseWorkRoot;
    Exit;
  end;

  { B: every file of The Convergence 3.0.2; C: files from other mods
    (moved into the backup unless /FOREIGN=keep). Both run again right
    before the backup (BuildBackupPlan). }
  if not CheckConvergenceIntegrity(ConvDir, Problem, ConvCheckSummary) then begin
    Result := Problem;
    ReleaseWorkRoot;
    Exit;
  end;
  ScanForeignFiles(ConvDir);
  if OtherModsFound then begin
    if ForeignMove then
      Log(Format('Unattended: %d file(s) from other mods will be moved into the backup and %d [[package]] ' +
        'entr(ies) switched off (/FOREIGN=move); %d file(s) and %d [[natives]] entr(ies) kept', [ForeignCountOf('M'), Me3ExtraCountOf('P'), ForeignCount - ForeignCountOf('M'), Me3ExtraCountOf('N')]))
    else
      Log(Format('Unattended: %d file(s) and %d .me3 entr(ies) of other mods are kept (/FOREIGN=keep)', [ForeignCount, Me3ExtraCount]));
  end;
end;

{ ----------------------------------------------------------- setup events --- }

function InitializeSetup: Boolean;
var
  Problem: String;
begin
  Result := True;
  InitProfileNames;
  InitCatalog;
  CheckCatalogFormat;
  InitRuntimeArrays;
  ShaCacheReset;
  ResetSelection;
  ActiveProgress := nil;
  Problem := CatalogPathsProblem;
  if Problem <> '' then begin
    ShowError('Setup cannot continue. Nothing was changed.' + #13#10#13#10 + 'The installer''s catalog holds a path ' +
      'that would leave the Convergence folder: ' + Problem + #13#10 + 'Download the installer again.');
    Result := False;
    Exit;
  end;
  ForeignMove := True;
  ForeignNamesCount := 0;
  UseUpstream := True;
  GameStatus := GS_NOTCHECKED;
  GameConfirmed := False;
  WorkDirRoot := '';
  WorkCounter := 0;
  ConvDir := '';
  SelectionPresetFor := '';
  Log(Format('%s installer (catalog format %d, %s, release %s, %s, catalog sha256 %s, built %s): %d components, ' +
    '%d paths, %d variants, %d downloads, %d hosted files', [CAT_MOD_TITLE, CAT_FORMAT, CAT_VERSION, CAT_RELEASE_TAG,
    CAT_RC, CAT_SHA256, CAT_BUILD_STAMP, CompCount, PathCount, VarCount, ArchCount, BlobCount]));

  { the Convergence 3.0.2 file list (checks B and C); without it Setup
    cannot check anything, so it stops }
  if not LoadConvManifest(Problem) then begin
    ShowError('Setup cannot continue. Nothing was changed.' + #13#10#13#10 + Problem);
    Result := False;
    Exit;
  end;

  ReadCommandLine;
  ApplyBaseUrlParam;
  Problem := ValidateCommandLine;

  if WizardSilent then begin
    if Problem = '' then
      Problem := PrepareSilentRun;
    if Problem <> '' then begin
      ReleaseWorkRoot;
      ShowError('Setup cannot continue. Nothing was changed.' + #13#10#13#10 + Problem);
      Result := False;
    end;
  end else if Problem <> '' then begin
    { the wizard: a bad switch is reported and the selection switches are
      ignored (the Options page is used instead) }
    MsgBox(Problem + #13#10 + 'The option is ignored; pick it in the wizard instead.', mbInformation, MB_OK);
    ClearSelectionParams;
    if not ParseForeign(ParamForeign, ForeignMove) then begin
      ParamForeign := '';
      ForeignMove := True;
    end;
    if not ParseBoolSwitch(ParamGameOk, False, GameConfirmed) then begin
      ParamGameOk := '';
      GameConfirmed := False;
    end;
    if not ParseBoolSwitch(ParamUpstream, True, UseUpstream) then begin
      ParamUpstream := '';
      UseUpstream := True;
    end;
  end;
  { the wizard's tick box starts ticked for /GAMEOK=1 }
  if GameConfirmed then
    ParamGameOk := '1';
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := WizardSilent and
    ((PageID = GamePage.ID) or (PageID = ConvPage.ID) or (PageID = ForeignPage.ID) or
     (PageID = OptionsPage.ID) or (PageID = DlPage.ID) or (PageID = CreditsPage.ID));
  { the other mods page only when the scan found some }
  if (PageID = ForeignPage.ID) and not OtherModsFound and (ForeignNamesCount = 0) then
    Result := True;
  { the downloads page only when the selection needs downloads }
  if (PageID = DlPage.ID) and (ArchivesNeededCount = 0) then
    Result := True;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if WizardSilent then
    Exit;
  if CurPageID = GamePage.ID then begin
    if GameStatus = GS_NOTCHECKED then
      RunGameCheck;
    UpdateGamePage;
  end else if CurPageID = OptionsPage.ID then
    UpdateOptionsPage
  else if CurPageID = DlPage.ID then
    RefreshDownloadsPage(DlSelectedArch)
  else if CurPageID = CreditsPage.ID then
    UpdateCreditsPage
  else if CurPageID = wpFinished then begin
    if RolledBack or (VerifyFailed and PostInstallFailed) then
      WizardForm.FinishedHeadingLabel.Caption := 'Installation failed'
    else if VerifyFailed then
      WizardForm.FinishedHeadingLabel.Caption := 'Installation finished with errors';
    if FinalReport <> '' then begin
      WizardForm.FinishedLabel.Caption := FinalReport;
      WizardForm.AdjustLabelHeight(WizardForm.FinishedLabel);
    end;
  end;
end;

{ Next on the Options page: the list -> the selection, rules (a Q rule or
  the animation wall may switch a component on: the page then shows it and
  stays), the .me3 check, then which downloads are needed and the automatic
  search for them. }
function OptionsPageNext: Boolean;
var
  Problem, Before, Notes: String;
  I: Integer;
begin
  Result := False;
  ReadOptionsList;
  Before := SelectionText(' ', '=');
  if not NormalizeSelection(False, Problem) then begin
    MsgBox(Problem, mbError, MB_OK);
    Exit;
  end;
  if SelectionText(' ', '=') <> Before then begin
    Notes := '';
    for I := 0 to GetArrayLength(RuleNotes) - 1 do
      Notes := Notes + '- ' + RuleNotes[I] + #13#10;
    SyncOptionsList;
    UpdateOptionsExtras;
    MsgBox('Setup changed your choice:' + #13#10#13#10 + Notes + #13#10 + 'Check the list, then click Next again.',
      mbInformation, MB_OK);
    Exit;
  end;
  Problem := Me3ProfilesProblem;
  if Problem <> '' then begin
    MsgBox(Problem, mbError, MB_OK);
    Exit;
  end;
  BeginWork('Checking your downloads', 'Checking which downloads are needed...');
  try
    ComputeArchivesNeeded;
    if ArchivesMissingCount > 0 then
      AutoFindArchives(True, -1, False);
    LogMissingArchives;
  finally
    EndWork;
  end;
  Result := True;
end;

{ Interactive: right after "Install" is clicked, with progress shown: the
  game check again, the plan, the downloads, the backup. False = stay on
  the Ready page; nothing was changed. }
function InstallFromReadyPage: Boolean;
var
  Problem: String;
begin
  Result := False;
  if not WaitForEldenRingClosed then
    Exit;
  { A again before anything is copied (PrepareToInstall repeats it) }
  RecheckGame;
  if not GameCheckPassed then begin
    if GameStatus = GS_WRONG then
      MsgBox(GameProblem, mbError, MB_OK)
    else
      MsgBox('Setup cannot check your Elden Ring any more:' + #13#10 + GameStatusText + #13#10#13#10 +
        'Go Back to the Elden Ring page.', mbError, MB_OK);
    Exit;
  end;
  if BackupMade then
    DiscardBackup;          { the user went back and changed something }
  BeginWork('Preparing', 'Comparing your files with ' + CAT_VERSION_SHORT + '...');
  try
    { the temporary files a stopped earlier run left (repair 5) }
    DeleteStaleTempFiles(ConvDir);
    Result := BuildBackupPlan(Problem);
  finally
    EndWork;
  end;
  if Result then
    Result := FetchBlobs(Problem);
  if Result then
    Result := ResolveVarSrcPaths(Problem);
  if Result then begin
    { the fields' ini files again, now that every source is known }
    Problem := FieldsProblemText;
    Result := Problem = '';
  end;
  if Result then begin
    BeginWork('Backing up your Convergence files', 'Backing up the files that will be replaced...');
    try
      Result := RunBackup(Problem);
    finally
      EndWork;
    end;
  end;
  if not Result then
    MsgBox(Problem, mbError, MB_OK);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Problem: String;
begin
  Result := True;
  if WizardSilent then
    Exit;
  if CurPageID = GamePage.ID then begin
    if not GameCheckPassed then begin
      if GameStatus = GS_WRONG then
        MsgBox(GameProblem, mbError, MB_OK)
      else
        MsgBox('Setup could not check your Elden Ring. Click Browse and select your ELDEN RING folder, ' +
          'or tick "I have Elden Ring ' + GAME_PATCH_NAME + ' with Shadow of the Erdtree" if you are sure.',
          mbError, MB_OK);
      Result := False;
      Exit;
    end;
    if not ScanDone then begin
      RunConvergenceScan;
      RefreshConvList(DefaultConvSelection);
    end;
  end else if CurPageID = ConvPage.ID then begin
    Result := ConvPageNext;
    if Result then begin
      if not SelectConvergenceFolder(ConvDir, Problem) then begin
        MsgBox(Problem + #13#10 + 'That command line option is ignored; pick the options on the Options page.',
          mbInformation, MB_OK);
        ClearSelectionParams;
        ApplySelectionPresets(Problem);
      end;
      UpdateOptionsPage;
    end;
  end else if CurPageID = ForeignPage.ID then begin
    ForeignMove := ForeignMoveCheck.Checked;
    Log(Format('Other mods: %d file(s) and %d .me3 entr(ies) listed, move / switch off: %s', [ForeignCount,
      Me3ExtraCount, BoolText(ForeignMove)]));
  end else if CurPageID = OptionsPage.ID then
    Result := OptionsPageNext
  else if CurPageID = DlPage.ID then begin
    Result := ArchivesMissingCount = 0;
    if not Result then
      MsgBox('Some downloads are still missing or do not match. Select each line marked "missing" or ' +
        '"wrong files" to see what to do.', mbError, MB_OK);
  end else if CurPageID = CreditsPage.ID then begin
    { for the Ready page: what will be downloaded }
    BeginWork('Preparing the summary', 'Checking which files must be downloaded...');
    try
      ComputeFetchPreview;
    finally
      EndWork;
    end;
  end else if CurPageID = wpReady then
    Result := InstallFromReadyPage;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  S, AtText: String;
  Movable, Kept, C, A, I, AtMovedCount: Integer;
  AtMoved, AtKept: TStringList;
begin
  S := 'Elden Ring:' + NewLine + Space + GameSummaryText + NewLine + NewLine;

  S := S + 'Convergence folder:' + NewLine + Space + ConvDir + NewLine +
    Space + 'The Convergence ' + ConvVersion + NewLine +
    Space + 'Check: every file of the official Convergence 3.0.2 release is there and unchanged' + NewLine +
    Space + '(checked again right before the backup)' + NewLine + NewLine;

  Movable := ForeignCountOf('M');
  Kept := ForeignCount - Movable;
  { other mods' files under names the options use too (repair 3, verifier 4 D2) }
  AtMoved := TStringList.Create;
  AtKept := TStringList.Create;
  try
    ForeignAtCatalogPaths(AtMoved, AtKept);
    AtMovedCount := AtMoved.Count;
    AtText := '';
    for I := 0 to AtMoved.Count - 1 do
      AtText := AtText + Space + '    ' + AtMoved[I] + ' (moved into the backup)' + NewLine;
    for I := 0 to AtKept.Count - 1 do
      AtText := AtText + Space + '    ' + AtKept[I] + NewLine;
  finally
    AtMoved.Free;
    AtKept.Free;
  end;
  S := S + 'Files from other mods in mod\:' + NewLine + Space;
  if (ForeignCount = 0) and (AtText = '') then
    S := S + 'none'
  else if ForeignCount = 0 then
    S := S + 'under names this release''s options use too (never removed as this release''s files):' + NewLine +
      AtText
  else begin
    if Movable > 0 then begin
      if ForeignMove then
        S := S + Format('%d will be moved into the backup (uninstall puts them back)', [Movable])
      else
        S := S + Format('%d stay in place (you chose to keep them)', [Movable]);
      if Kept > 0 then
        S := S + NewLine + Space;
    end;
    if Kept > 0 then
      S := S + Format('%d kept in place (mod\dll files, links or paths too long to move)', [Kept]);
    if AtText <> '' then
      S := S + NewLine + Space + 'under names this release''s options use too (never removed as this release''s ' +
        'files):' + NewLine + AtText;
  end;
  S := S + NewLine + NewLine;

  S := S + 'Other mods loaded by the .me3 profiles:' + NewLine + Space;
  if Me3ExtraCount = 0 then
    S := S + 'none'
  else begin
    if Me3ExtraCountOf('P') > 0 then begin
      if ForeignMove then
        S := S + Format('%d [[package]] entr(ies) will be switched off (uninstall switches them back on)', [Me3ExtraCountOf('P')])
      else
        S := S + Format('%d [[package]] entr(ies) stay on (you chose to keep them)', [Me3ExtraCountOf('P')]);
      if Me3ExtraCountOf('N') > 0 then
        S := S + NewLine + Space;
    end;
    if Me3ExtraNativesKept > 0 then begin
      S := S + Format('%d [[natives]] DLL entr(ies) kept', [Me3ExtraNativesKept]);
      if Me3ExtraNativesReplaced > 0 then
        S := S + NewLine + Space;
    end;
    if Me3ExtraNativesReplaced > 0 then
      S := S + Format('%d entr(ies) of your own that load an option you ticked: replaced by the installer''s own ' +
        'entry (uninstall puts yours back)', [Me3ExtraNativesReplaced]);
  end;
  S := S + NewLine + NewLine;

  S := S + 'Components:' + NewLine;
  for C := 0 to CompCount - 1 do begin
    if CompKind[C] = 'X' then
      Continue;
    S := S + Space + CompCaption(C) + ': ' + CompChoiceText(C);
    if CompKind[C] = 'R' then
      S := S + ' (always installed)'
    else if not CompOn(C) and (DetectedState[C] >= 1) then
      S := S + ' - it is in this folder now and will be REMOVED (its files go into the backup)';
    if CompOn(C) and (CompSourceText[C] <> '') then
      S := S + NewLine + Space + '    source: ' + CompSourceText[C];
    S := S + NewLine;
  end;
  for I := 0 to FieldCount - 1 do
    if CompOn(FieldComp[I]) then begin
      S := S + Space + FieldLabel[I] + ' ';
      if FieldValue[I] = '' then
        S := S + '(left as it is)'
      else if FieldIniProblem(I) <> '' then
        S := S + '(CANNOT be set: ' + FieldIniProblem(I) + ')'
      else if FieldSecret[I] then
        S := S + '(set)'
      else
        S := S + FieldValue[I];
      S := S + NewLine;
    end;
  S := S + Space + 'Animation slots: ' + FormatThousands(WallTotal) + ' of ' + FormatThousands(WallLimitUsed);
  if (WallDllText = 'forced') and (WALL_DLL_COMP >= 0) then
    S := S + ' (' + CompShortTitle(WALL_DLL_COMP) + ' was switched on automatically: ' + DllReason + ')';
  S := S + NewLine + NewLine;

  if GetArrayLength(RuleWarnings) > 0 then begin
    S := S + 'Warnings:' + NewLine;
    for I := 0 to GetArrayLength(RuleWarnings) - 1 do
      S := S + Space + RuleWarnings[I] + NewLine;
    S := S + NewLine;
  end;
  A := 0;
  for C := 0 to CompCount - 1 do
    if CompOn(C) and CompExperimental[C] then begin
      S := S + 'Experimental: ' + CompTitle[C] + ' was not tested as much as the rest.' + NewLine;
      A := A + 1;
    end;
  for I := 0 to GetArrayLength(RuleNotes) - 1 do begin
    S := S + 'Note: ' + RuleNotes[I] + NewLine;
    A := A + 1;
  end;
  { repair 5: the last run here was stopped hard before it finished }
  if InterruptedRunStamp <> '' then begin
    S := S + 'Note: the last installation in this folder (backup ' + InterruptedRunStamp + ') was stopped before it ' +
      'finished. Its options are preselected; installing now completes the folder.' + NewLine;
    A := A + 1;
  end;
  if A > 0 then
    S := S + NewLine;

  S := S + 'Your downloads:' + NewLine;
  I := 0;
  for A := 0 to ArchCount - 1 do
    if ArchState[A] = AS_ACCEPTED then begin
      S := S + Space + ArchTitle[A] + ': ' + ArchSource[A] + NewLine;
      if not ArchIsModeV(A) then
        S := S + Space + '    every file Setup takes from it checked (SHA-256)' + NewLine
      else if ArchTested[A] then
        S := S + Space + '    the tested version ' + ModeVTestedVersion(A) + ': every file checked (SHA-256)' + NewLine
      else
        S := S + Space + '    NOT the tested version ' + ModeVTestedVersion(A) + ' (you chose it): Setup copies its ' +
          'files as they are and cannot check them' + NewLine;
      I := I + 1;
    end;
  if I = 0 then
    S := S + Space + 'none needed (their files are already in this folder)' + NewLine;

  S := S + NewLine + 'Downloaded when you click Install:' + NewLine + Space;
  if FetchFiles = 0 then
    S := S + 'nothing'
  else begin
    S := S + Format('%d file(s), about %s, from %s', [FetchFiles, BytesToMB(FetchBytes), MirrorHostText]);
    S := S + NewLine + Space + '(each one checked by SHA-256 before anything in your folder changes)';
  end;
  S := S + NewLine + NewLine;

  S := S + 'What Setup will do:' + NewLine +
    Space + '1. Download the files above and check them' + NewLine +
    Space + '2. Back up every file it replaces or edits to' + NewLine +
    Space + '    ' + AddBackslash(ConvDir) + BACKUP_ROOT_NAME + '\<date and time>' + NewLine;
  if ForeignMove and (Movable + AtMovedCount > 0) then
    S := S + Space + '    and move the files from other mods there' + NewLine;
  if ForeignMove and (Me3ExtraCountOf('P') > 0) then
    S := S + Space + '    and switch off the other mods'' [[package]] entries' + NewLine;
  S := S + Space + '3. Copy ' + CAT_VERSION_SHORT + ' and the chosen options into your Convergence folder' + NewLine +
    Space + '    and remove the files of options you switched off' + NewLine +
    Space + '4. Check every installed file (SHA-256) against this release' + NewLine +
    NewLine + 'Uninstalling (Windows Settings > Apps) puts the backed-up files back.';
  Result := S;
end;

procedure InitializeWizard;
begin
  CreateWizardPages;
  if WizardSilent then
    WizardForm.DirEdit.Text := ConvDir;
#if Defined(CodeCheck) || Defined(TestBuild)
  { test builds only: /TESTLAYOUT=1 logs whether the new pages' texts fit
    and runs every page's fill code once (the Options list, the Downloads
    page, the Credits page, the Ready memo) on the state of this silent
    run; PrepareToInstall then stops the run }
  if CmdParam('TESTLAYOUT') = '1' then begin
    LogLayoutFit;
    UpdateOptionsPage;
    Log('LAYOUT Options installed-now: ' + InstalledNowLabel.Caption);
    Log('LAYOUT Options animation slots: ' + WallLabel.Caption);
    RefreshDownloadsPage(-1);
    Log(Format('LAYOUT Downloads page: %d line(s), next allowed %s; status: %s', [DlList.Items.Count,
      BoolText(ArchivesMissingCount = 0), DlStatusLabel.Caption]));
    UpdateCreditsPage;
    Log(Format('LAYOUT Credits page: %d line(s)', [CreditsMemo.Lines.Count]));
    ComputeFetchPreview;
    Log('LAYOUT Ready memo:' + #13#10 + UpdateReadyMemo('    ', #13#10, '', '', '', '', '', ''));
  end;
#endif
end;

{ Last gate before files change. Silent runs download and make their
  backup here. }
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Problem: String;
begin
  Result := '';
#if Defined(CodeCheck) || Defined(TestBuild)
  if CmdParam('TESTLAYOUT') = '1' then begin
    Result := 'TESTLAYOUT: layout logged. Nothing was changed.';
    Exit;
  end;
#endif
  if (ConvDir = '') or not PathSame(NormalizeDir(WizardDirValue), ConvDir) then begin
    Result := 'Internal check failed: the install folder (' + WizardDirValue + ') is not the ' +
      'validated Convergence folder (' + ConvDir + '). Nothing was changed.';
    Exit;
  end;
  if ArchivesMissingCount > 0 then begin
    Result := 'Some downloads were not provided:' + #13#10 + MissingArchivesText + #13#10 + 'Nothing was changed.';
    if BackupMade then
      DiscardBackup;
    Exit;
  end;
  { A again: Steam may have updated (or removed) the game while the wizard
    was open. Browse can never replace the copy Steam launches. }
  RecheckGame;
  if not GameCheckPassed then begin
    if GameStatus = GS_WRONG then
      Result := GameProblem + #13#10#13#10 + 'Nothing was changed.'
    else
      Result := 'Elden Ring ' + GAME_PATCH_NAME + ' with Shadow of the Erdtree was not confirmed:' + #13#10 +
        GameStatusText + #13#10#13#10 + 'Nothing was changed.';
    if BackupMade then
      DiscardBackup;
    Exit;
  end;
  if not WaitForEldenRingClosed then begin
    Result := 'Elden Ring (eldenring.exe) is running. Close the game and run the installer again. ' +
      'Nothing was changed.';
    if BackupMade then
      DiscardBackup;
    Exit;
  end;
  Problem := DescribeConvergenceProblem(ConvDir, True);
  if Problem <> '' then begin
    Result := Problem + #13#10#13#10 + 'Nothing was changed.';
    if BackupMade then
      DiscardBackup;
    Exit;
  end;
  if not BackupMade then begin
    { the temporary files a stopped earlier run left (repair 5) }
    DeleteStaleTempFiles(ConvDir);
    if not BuildBackupPlan(Problem) then begin
      Result := Problem;
      Exit;
    end;
    if not FetchBlobs(Problem) then begin
      Result := Problem;
      Exit;
    end;
#if Defined(CodeCheck) || Defined(TestBuild)
    if CmdParam('TESTFETCHONLY') = '1' then begin
      Result := Format('TESTFETCHONLY: %d file(s) downloaded and checked. Nothing was changed.', [FetchFiles]);
      Exit;
    end;
#endif
    if not ResolveVarSrcPaths(Problem) then begin
      Result := Problem;
      Exit;
    end;
    Problem := FieldsProblemText;
    if Problem <> '' then begin
      Result := Problem;
      Exit;
    end;
    if not RunBackup(Problem) then begin
      Result := Problem;
      Exit;
    end;
  end;
  Log('Ready to install into ' + ConvDir + ' (backup: ' + BackupDir + ')');
end;

{ The AppId an Inno uninstall log (unins???.dat) belongs to: the text after
  its 64-byte header id ("Inno Setup Uninstall Log ..."); '' when the file is
  no such log. }
function UninstallLogAppId(const DatFile: String): String;
var
  Raw: AnsiString;
  I: Integer;
begin
  Result := '';
  if not LoadStringFromFile(DatFile, Raw) then
    Exit;
  if (Length(Raw) < 192) or (Pos('Inno Setup Uninstall Log', Copy(Raw, 1, 64)) <> 1) then
    Exit;
  for I := 65 to 192 do begin
    if Raw[I] = #0 then
      Break;
    Result := Result + Raw[I];
  end;
end;

{ The program of an Apps entry's UninstallString (a quoted path to
  unins000.exe, maybe followed by switches): the text between the first
  pair of quotes, or up to the first blank; '' when empty. }
function UninstallStringExe(const S: String): String;
var
  T: String;
  P: Integer;
begin
  T := Trim(S);
  Result := '';
  if T = '' then
    Exit;
  if T[1] = '"' then begin
    T := Copy(T, 2, Length(T));
    P := Pos('"', T);
    if P > 0 then
      Result := Copy(T, 1, P - 1)
    else
      Result := T;
  end else begin
    P := Pos(' ', T);
    if P > 0 then
      Result := Copy(T, 1, P - 1)
    else
      Result := T;
  end;
end;

{ An install into a Convergence folder that was moved since an earlier
  install: the AppId comes from the folder's path, so this run gets a new
  Apps entry, and without this Inno would add a second uninstaller (unins001
  next to unins000) while Windows still lists the earlier entry for the old
  place (repair 3, verifier 4 D3). Called when the installation starts
  (ssInstall), BEFORE Inno writes this run's uninstaller: every uninstall
  log in CXCXM_uninstall of another of our AppIds whose Apps entry is gone
  or whose folder no longer exists is removed with that entry (the earlier
  uninstaller refuses to run from a moved folder anyway, and this run's
  uninstaller restores every backup of this folder); an empty
  CXCXM_uninstall is removed too, so Inno makes it again and the uninstall
  removes it. An entry whose folder still exists (this folder is a copy of
  it) stays as it is - unless its own uninstaller is gone (repair 4,
  verifier 5: the folder was moved here and a fresh Convergence was put at
  the old place; that entry points at an uninstaller that no longer exists,
  so it is removed too). }
procedure CleanStaleUninstallers;
var
  FR: TFindRec;
  Dir, Base, Id, Key, Loc, UninsExe: String;
  Stale: TStringList;
  I: Integer;
begin
  Dir := ConvPath(UNINSTALL_DIR_NAME);
  if not DirExists(Dir) then
    Exit;
  Stale := TStringList.Create;
  try
    if FindFirst(AddBackslash(Dir) + 'unins*.dat', FR) then begin
      try
        repeat
          if (FR.Attributes and FA_DIRECTORY) = 0 then
            Stale.Add(FR.Name);
        until not FindNext(FR);
      finally
        FindClose(FR);
      end;
    end;
    for I := 0 to Stale.Count - 1 do begin
      Base := ChangeFileExt(AddBackslash(Dir) + Stale[I], '');
      Id := UninstallLogAppId(Base + '.dat');
      if CompareText(Id, GetAppId('')) = 0 then
        Continue;                           { this folder's own uninstaller (a re-run) }
      if (Id = '') or (GetFileSizeSafe(Base + '.dat') <= 0) then begin
        { an EMPTY uninstall log, or one that names no AppId: a Setup that
          was stopped hard inside Inno's own step that writes it (between
          "Creating new uninstall log" and "Saving uninstall information").
          Only this installer writes this folder, so it is a dead copy of
          one of its own uninstallers: it can uninstall nothing (it exits at
          once), and left alone it made Inno write unins001 and stayed in
          the folder for good (repair 6, TEST lane after repair 5, finding B) }
        DeleteFileForced(Base + '.exe');
        DeleteFileForced(Base + '.dat');
        DeleteFileForced(Base + '.msg');
        Log('Removed the dead uninstaller ' + Stale[I] + ' (an empty uninstall log without an AppId: a Setup ' +
          'stopped while Inno wrote it)');
        Continue;
      end;
      if not StartsWithStr(Id, 'CanalpaCXCXM_') then begin
        Log('Uninstaller ' + Stale[I] + ' (' + Id + ') is not one of this installer''s: left as it is');
        Continue;
      end;
      Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + Id + '_is1';
      if RegKeyExists(HKA, Key) then begin
        Loc := '';
        RegQueryStringValue(HKA, Key, 'InstallLocation', Loc);
        Loc := NormalizeDir(Loc);
        UninsExe := '';
        RegQueryStringValue(HKA, Key, 'UninstallString', UninsExe);
        UninsExe := UninstallStringExe(UninsExe);
        if (Loc <> '') and DirExists(Loc) and not PathSame(Loc, ConvDir) and (UninsExe <> '') and
          FileExists(UninsExe) then
        begin
          Log('Earlier uninstaller ' + Stale[I] + ' belongs to ' + Loc + ', which still exists with its own ' +
            'uninstaller (this folder is a copy of it): left as it is');
          Continue;
        end;
        if (Loc <> '') and DirExists(Loc) and not PathSame(Loc, ConvDir) then
          Log('Earlier uninstaller ' + Stale[I] + ' belongs to ' + Loc + ', which exists, but its Apps entry points ' +
            'at an uninstaller that is gone (' + UninsExe + '): the entry is stale');
        if not RegDeleteKeyIncludingSubkeys(HKA, Key) then begin
          Log('Could not remove the stale Windows Apps entry ' + Key);
          Continue;
        end;
        Log('Removed the stale Windows Apps entry ' + Id + ' of ' + Loc + ' (that folder, or its uninstaller, is ' +
          'gone: the folder was moved here)');
      end;
      DeleteFileForced(Base + '.exe');
      DeleteFileForced(Base + '.dat');
      DeleteFileForced(Base + '.msg');
      Log('Removed the earlier uninstaller ' + Stale[I] + ' (this run''s uninstaller restores every backup of this ' +
        'folder)');
    end;
    { an uninstaller program without its uninstall log: an uninstall that was
      stopped hard right after it deleted its log (Inno's "Deleting Uninstall
      data files"), or a first install stopped before Inno wrote the log.
      It cannot run (no log), and only this installer writes this folder
      (repair 6, finding B) }
    Stale.Clear;
    if FindFirst(AddBackslash(Dir) + 'unins*.exe', FR) then begin
      try
        repeat
          if (FR.Attributes and FA_DIRECTORY) = 0 then
            Stale.Add(FR.Name);
        until not FindNext(FR);
      finally
        FindClose(FR);
      end;
    end;
    for I := 0 to Stale.Count - 1 do begin
      Base := ChangeFileExt(AddBackslash(Dir) + Stale[I], '');
      if FileExists(Base + '.dat') then
        Continue;
      DeleteFileForced(Base + '.exe');
      DeleteFileForced(Base + '.msg');
      Log('Removed the dead uninstaller ' + Stale[I] + ' (no uninstall log next to it: an uninstall or a Setup ' +
        'stopped while Inno wrote or deleted it)');
    end;
  finally
    Stale.Free;
  end;
  if RemoveDir(Dir) then
    Log('Removed the empty ' + Dir + ' (Setup makes it again for this run''s uninstaller)');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then begin
    InstallStarted := True;
    Log('Installing ' + CAT_VERSION_SHORT + ' into ' + ConvDir + ': ' + SelectionText(' ', '='));
    { before Inno writes this run's uninstaller (repair 3, verifier 4 D3) }
    CleanStaleUninstallers;
    { other mods' files are moved at the start of the post-install step
      (RunPostInstall), AFTER Inno registered this run's uninstaller: a
      Setup stopped hard at any point after its first change can be
      uninstalled (repair 5) }
  end else if CurStep = ssPostInstall then begin
    BeginWork('Finishing the installation', 'Copying the files and checking every one...');
    try
      RunPostInstall;
    finally
      EndWork;
    end;
    InstallFinished := True;
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  Result := 0;
  if VerifyFailed then begin
    if RolledBack then
      Result := EXIT_VERIFY_FAILED_RESTORED
    else if PostInstallFailed then
      Result := EXIT_POSTINSTALL_FAILED
    else
      Result := EXIT_VERIFY_FAILED_KEPT;
  end;
end;

{ Safety net: the work folder with the unpacked downloads is deleted; a
  backup that was never used is removed; an installation that started but
  did not finish (cancel, fatal error) is rolled back.
  After a rollback of the FIRST install in a folder, the uninstaller that
  Inno registered at the end of ssInstall (CXCXM_uninstall and the Windows
  Apps entry) is removed too: there is nothing left to uninstall. With an
  earlier install's backup still present they stay, because that install
  still needs them. }
procedure DeinitializeSetup;
var
  Report, Key: String;
  Dirs: TStringList;
begin
  ReleaseWorkRoot;
  if RolledBack and (ConvDir <> '') then begin
    Dirs := TStringList.Create;
    try
      ListBackupDirs(ConvDir, Dirs);
      if Dirs.Count = 0 then begin
        Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + GetAppId('') + '_is1';
        if RegKeyExists(HKA, Key) then begin
          if RegDeleteKeyIncludingSubkeys(HKA, Key) then
            Log('Removed the Windows Apps entry ' + Key)
          else
            Log('Could not remove the Windows Apps entry ' + Key);
        end;
        if DirExists(ConvPath(UNINSTALL_DIR_NAME)) then begin
          if DelTree(ConvPath(UNINSTALL_DIR_NAME), True, True, True) then
            Log('Removed ' + ConvPath(UNINSTALL_DIR_NAME))
          else
            Log('Could not remove ' + ConvPath(UNINSTALL_DIR_NAME));
        end;
      end else
        Log('An earlier install''s backup is still here; its uninstaller stays registered');
    finally
      Dirs.Free;
    end;
    Exit;
  end;
  if not BackupMade then
    Exit;
  if not InstallStarted then begin
    DiscardBackup;
    Exit;
  end;
  if not InstallFinished then begin
    Log('Setup ended before the installation finished; restoring the backup');
    if RestoreBackups(ConvDir, BackupDir, Report) then
      ShowInfo('The installation did not finish, so Setup restored your Convergence folder to how it ' +
        'was before. Nothing was changed.')
    else
      ShowError('The installation did not finish and the backup could not be fully ' +
        'restored.' + #13#10#13#10 + Report);
  end;
end;

{ ------------------------------------------------------- uninstall events --- }

var
  UninstallResultText: String;       { shown after the uninstall (usPostUninstall) }
  UninstallMutex1, UninstallMutex2: THandle;   { Setup's mutex names, held while the uninstaller runs (repair 6) }

function InitializeUninstall: Boolean;
var
  AppDir, OwnDir: String;
begin
  Result := True;
  UninstallResultText := '';
  RestoreKeptCount := 0;
  RestoreKeptText := '';
  { the .me3 code (restore of kind E) needs the profile names, the stock
    profiles and the natives of the catalog }
  InitProfileNames;
  InitCatalog;
  InitRuntimeArrays;
  ResetSelection;
  { unins000.dat remembers the ORIGINAL folder. Run from a copy of the
    Convergence folder, it would restore and delete files in the original
    and then remove the copy's own uninstaller. Refuse instead. }
  AppDir := RemoveBackslashUnlessRoot(ExpandConstant('{app}'));
  OwnDir := ExtractFileDir(ExtractFileDir(ExpandConstant('{uninstallexe}')));
  Log('Uninstall: {app} = ' + AppDir + ', uninstaller folder = ' + OwnDir);
  if not PathSame(OwnDir, AppDir) then begin
    ShowError('This uninstaller belongs to' + #13#10 + AppDir + #13#10#13#10 +
      'but it was started from' + #13#10 + OwnDir + #13#10#13#10 +
      'This folder looks like a copy (or a moved Convergence folder). Nothing was changed. ' +
      'Run the uninstaller of the folder it belongs to, or run the installer on this folder instead.');
    Result := False;
    Exit;
  end;
  { the installer must not run at the same time }
  while CheckForMutexes(SETUP_MUTEX_NAME) do begin
    if UninstallSilent then begin
      Log('The installer is running; uninstall refused');
      Result := False;
      Exit;
    end;
    if MsgBox('The ' + CAT_MOD_TITLE + ' installer is running.' + #13#10#13#10 +
      'Close it, then click Retry.', mbError, MB_RETRYCANCEL) <> IDRETRY then
    begin
      Result := False;
      Exit;
    end;
  end;
  { ... and while the uninstall runs, a Setup started now must wait: the
    uninstaller holds the installer's own mutex names (Windows closes them
    when the uninstaller ends, also when it is stopped hard; repair 6) }
  UninstallMutex1 := CxCreateMutexW(0, False, SETUP_MUTEX_NAME);
  UninstallMutex2 := CxCreateMutexW(0, False, 'Global\' + SETUP_MUTEX_NAME);
  if (UninstallMutex1 = 0) and (UninstallMutex2 = 0) then
    Log('Could not take the installer''s mutex names (a Setup started during the uninstall would not wait)');
  while IsProcessRunning(GAME_EXE_NAME) do begin
    if UninstallSilent then begin
      Log('Elden Ring is running; uninstall refused');
      Result := False;
      Exit;
    end;
    if MsgBox('Elden Ring (eldenring.exe) is running.' + #13#10#13#10 +
      'Close the game completely, then click Retry.', mbError, MB_RETRYCANCEL) <> IDRETRY then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

{ usUninstall: restore the backups (nothing of ours is in Inno's own
  uninstall log). A failed restore raises an exception, which aborts the
  uninstall BEFORE Inno removes the uninstaller and its Windows Apps entry,
  so the user can close the program that holds the files and run it again.
  A work folder an interrupted Setup left behind is deleted.
  usPostUninstall: tell the user what really happened. }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Conv, Report, OldVer, CurVer: String;
  Dirs: TStringList;
  Lines: TArrayOfString;
  DoRestore: Boolean;
begin
  if CurUninstallStep = usPostUninstall then begin
    if UninstallResultText <> '' then
      ShowInfo(UninstallResultText);
    Exit;
  end;
  if CurUninstallStep <> usUninstall then
    Exit;
  Conv := RemoveBackslashUnlessRoot(ExpandConstant('{app}'));
  if DirExists(AddBackslash(Conv) + WORK_DIR_NAME) then begin
    Log('Deleting the work folder an interrupted Setup left: ' + AddBackslash(Conv) + WORK_DIR_NAME);
    DelTree(AddBackslash(Conv) + WORK_DIR_NAME, True, True, True);
  end;
  { the partial backup of a Setup that was stopped while it made it (verifier 3, D4) }
  DeleteOrphanBackups(Conv, '');
  { the complete backup of a Setup stopped before its first change (repair 6) }
  DeleteUnstartedBackups(Conv, '');
  { the temporary files of a Setup or an uninstall that was stopped hard
    (repair 5): before the restore, which writes through the same names }
  DeleteStaleTempFiles(Conv);
  Dirs := TStringList.Create;
  try
    ListBackupDirs(Conv, Dirs);
    if Dirs.Count = 0 then begin
      Log('No CXCXM backups in ' + Conv + '; nothing to restore');
      if FileExists(AddBackslash(Conv) + MARKER_NAME) then
        UninstallResultText := 'No backup was found in ' + AddBackslash(Conv) + BACKUP_ROOT_NAME +
          ', so nothing was restored. The ' + CAT_VERSION_SHORT + ' files are still in ' + Conv + '.'
      else
        { an uninstall that was stopped after it had restored everything
          (repair 5), or a Setup stopped before its first change (repair 6):
          only the uninstaller's own entry is left, which Inno removes now }
        UninstallResultText := 'There is nothing left to restore in ' + Conv + ': the original files are ' +
          'already in place (an earlier uninstall put them back, or the installation stopped before it changed ' +
          'anything). The uninstaller now removes its own entry.';
      Exit;
    end;

    { The oldest backup holds the original Convergence files. If The
      Convergence was updated since, putting them back would downgrade it. }
    DoRestore := True;
    if ReadBackupManifest(Dirs[0], Lines) then begin
      OldVer := ManifestValue(Lines, 'CONVERGENCE_VERSION');
      CurVer := ReadConvergenceVersion(Conv);
      if (OldVer <> '') and (CurVer <> OldVer) then
        DoRestore := AskYesNo('The Convergence in this folder is now version ' + CurVer +
          ', but the backup was made from version ' + OldVer + '.' + #13#10#13#10 +
          'Restoring it would put old ' + OldVer + ' files back over the newer version. ' +
          'Restore the backup anyway?' + #13#10#13#10 +
          'Click No to leave the files as they are (the backup stays in ' + BACKUP_ROOT_NAME + ').', IDNO);
    end;
    if DoRestore then begin
      if not RestoreBackups(Conv, '', Report) then
        RaiseException('Some files could not be restored, so the uninstall stopped here. ' +
          'Close the program that uses them (the game, a mod tool, an antivirus scan), then run ' +
          'the uninstaller again: it continues where it stopped.' + #13#10#13#10 + Report);
      UninstallResultText := 'The original Convergence files were restored from the installer''s backup.';
      if RestoreKeptCount > 0 then begin
        UninstallResultText := UninstallResultText + #13#10#13#10 + Format('%d file(s) at paths of this ' +
          'release hold other mods'' files now (you or another mod put them there), so they were left in ' +
          'place:', [RestoreKeptCount]) + #13#10 + RestoreKeptText;
        if RestoreKeptCount > 20 then
          UninstallResultText := UninstallResultText + '  ... (the uninstall log lists all)' + #13#10;
        Log(Format('Uninstall: %d file(s) of other mods at paths of this release left in place', [RestoreKeptCount]));
      end;
    end else begin
      Log('Restore skipped by the user (Convergence version changed)');
      UninstallResultText := 'No backup was restored, so the ' + CAT_VERSION_SHORT + ' files are still in ' +
        Conv + '.' + #13#10 + 'The backup stays in ' + AddBackslash(Conv) + BACKUP_ROOT_NAME + '.';
    end;
  finally
    Dirs.Free;
  end;
end;
