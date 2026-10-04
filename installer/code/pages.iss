{ =============================================================================
  pages.iss - the custom wizard pages and their controls.

    GamePage     Elden Ring found in Steam: version and Shadow of the Erdtree
                 (Next stays disabled when they are wrong; when the game is
                 not found, until the player ticks the confirmation box).
                 Browse only when Steam's own copy cannot be found or read.
    ConvPage     pick the Convergence folder (detected list, Browse, Search
                 again); Next checks every Convergence 3.0.2 file
    ForeignPage  other mods: files found under mod\ and entries in the .me3
                 profiles, and the "move / switch them off" box (skipped
                 when there are none)
    OptionsPage  every component of the catalog (generic list), the fields
                 (Seamless session password), what is installed now and the
                 animation slots
    DlPage       "Get these downloads": one line per download the selection
                 needs; Next stays disabled until every one is found and
                 checked (skipped when none is needed)
    CreditsPage  every author whose work the selection uses
    WorkPage     progress page used by every long operation (scan, checks,
                 unpacking, backup, post-install); shown only while it runs
    FetchPage    Inno's download page (fetch.iss), after the Install click
  ============================================================================= }

const
  COLOR_GOOD = $00006400;     { dark green (BGR) }
  COLOR_BAD  = $000000B0;     { dark red (BGR) }

var
  WorkPage: TOutputProgressWizardPage;

  GamePage: TWizardPage;
  GameStatusLabel: TNewStaticText;
  GameRecheckButton: TNewButton;
  GameBrowseButton: TNewButton;
  GameConfirmCheck: TNewCheckBox;
  GameHelpLabel: TNewStaticText;

  ForeignPage: TWizardPage;
  ForeignIntroLabel: TNewStaticText;
  ForeignMemo: TNewMemo;
  ForeignMoveCheck: TNewCheckBox;
  ForeignMoveLabel: TNewStaticText;
  ForeignNoteLabel: TNewStaticText;

  ConvPage: TWizardPage;
  ConvIntroLabel: TNewStaticText;
  ConvList: TNewCheckListBox;
  ConvBrowseButton: TNewButton;
  ConvRescanButton: TNewButton;
  ConvGetButton: TNewButton;
  ConvStatusLabel: TNewStaticText;

  OptionsPage: TWizardPage;
  OptList: TNewCheckListBox;
  OptDescLabel: TNewStaticText;
  OptFieldLabel: array of TNewStaticText;
  OptFieldEdit: array of TNewEdit;
  InstalledNowLabel: TNewStaticText;
  WallLabel: TNewStaticText;
  OptItemComp: array of Integer;       { list line -> component }
  OptItemState: array of Integer;      { list line -> state (radio), -1 check box, -2 group line }
  OptUpdating: Boolean;                { the code is setting the list: ignore its click events }

  DlPage: TWizardPage;
  DlIntroLabel: TNewStaticText;
  DlList: TNewCheckListBox;
  DlNexusButton: TNewButton;
  DlArchiveButton: TNewButton;
  DlFolderButton: TNewButton;
  DlSearchButton: TNewButton;
  DlStatusLabel: TNewStaticText;
  DlRowArch: array of Integer;         { list line -> archive }

  CreditsPage: TWizardPage;
  CreditsMemo: TNewMemo;

{ ------------------------------------------------------------ WorkPage use --- }

procedure BeginWork(const Caption, Line1: String);
begin
  if WizardSilent then begin
    ActiveProgress := nil;
    Exit;
  end;
  ActiveProgress := WorkPage;
  WorkPage.Caption := Caption;
  WorkPage.SetText(Line1, '');
  WorkPage.SetProgress(0, 0);
  WorkPage.Show;
end;

procedure EndWork;
begin
  if ActiveProgress <> nil then
    WorkPage.Hide;
  ActiveProgress := nil;
end;

function NewLabel(Page: TWizardPage; const Top, Height: Integer; const Caption: String): TNewStaticText;
begin
  Result := TNewStaticText.Create(Page);
  Result.Parent := Page.Surface;
  Result.Left := 0;
  Result.Top := Top;
  Result.Width := Page.SurfaceWidth;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.Height := Height;
  Result.Caption := Caption;
end;

{ A word-wrapped label whose height is fitted to its text (static texts). }
function NewFittedLabel(Page: TWizardPage; const Top: Integer; const Caption: String): TNewStaticText;
begin
  Result := NewLabel(Page, Top, ScaleY(14), Caption);
  WizardForm.AdjustLabelHeight(Result);
end;

function NewButton(Page: TWizardPage; const Left, Top, Width: Integer; const Caption: String): TNewButton;
begin
  Result := TNewButton.Create(Page);
  Result.Parent := Page.Surface;
  Result.Left := Left;
  Result.Top := Top;
  Result.Width := Width;
  Result.Height := ScaleY(23);
  Result.Caption := Caption;
end;

{ ========================================================= Elden Ring page === }

procedure UpdateGamePage;
var
  NeedConfirm: Boolean;
begin
  GameStatusLabel.Caption := GameStatusText;
  if GameStatus = GS_OK then
    GameStatusLabel.Font.Color := COLOR_GOOD
  else
    GameStatusLabel.Font.Color := COLOR_BAD;
  { the box only exists for a game Setup cannot check itself; a wrong
    version or a missing DLC can never be confirmed away }
  NeedConfirm := (GameStatus = GS_NOTFOUND) or (GameStatus = GS_NOVERSION);
  GameConfirmCheck.Visible := NeedConfirm;
  GameConfirmed := NeedConfirm and GameConfirmCheck.Checked;
  { another folder must never replace the copy Steam launches }
  GameBrowseButton.Enabled := GameBrowseAllowed;
  if WizardForm.CurPageID = GamePage.ID then
    WizardForm.NextButton.Enabled := GameCheckPassed;
end;

procedure GameRecheckClick(Sender: TObject);
begin
  RunGameCheck;
  UpdateGamePage;
end;

procedure GameBrowseClick(Sender: TObject);
var
  Dir, Problem: String;
begin
  if not GameBrowseAllowed then
    Exit;
  Dir := '';
  if GameExePath <> '' then
    Dir := ExtractFileDir(ExtractFileDir(GameExePath));
  if not BrowseForFolder('Select your ELDEN RING folder (the one that contains the Game folder):', Dir, False) then
    Exit;
  Problem := ApplyGameBrowse(Dir);
  if Problem <> '' then begin
    MsgBox(Problem, mbError, MB_OK);
    Exit;
  end;
  UpdateGamePage;
end;

procedure GameConfirmClick(Sender: TObject);
begin
  UpdateGamePage;
end;

{ Layout, top to bottom: intro, the two buttons, the status text (it gets all
  the room that is left: a refusal can run to ten lines), the confirmation
  box, a short help text at the bottom. }
procedure CreateGamePage(const AfterID: Integer);
var
  Top, W, HelpH, StatusH: Integer;
  Intro, Help: TNewStaticText;
begin
  GamePage := CreateCustomPage(AfterID, 'Elden Ring',
    CAT_VERSION_SHORT + ' needs Elden Ring ' + GAME_PATCH_NAME + ' with Shadow of the Erdtree.');
  Intro := NewFittedLabel(GamePage, 0,
    'The Convergence 3.0.2 and this merge only work with Elden Ring ' + GAME_PATCH_NAME + ' (Steam) ' +
    'with the Shadow of the Erdtree DLC installed. Setup looked for the game in your Steam libraries:');

  Top := Intro.Top + Intro.Height + ScaleY(8);
  W := ScaleX(150);
  { access keys must not clash with the wizard's own buttons (&Back, &Next) }
  GameRecheckButton := NewButton(GamePage, 0, Top, W, 'Check &again');
  GameRecheckButton.OnClick := @GameRecheckClick;
  GameBrowseButton := NewButton(GamePage, W + ScaleX(8), Top, W, 'Bro&wse...');
  GameBrowseButton.OnClick := @GameBrowseClick;

  Top := Top + ScaleY(23) + ScaleY(10);
  HelpH := ScaleY(34);     { two lines at any DPI }
  StatusH := GamePage.SurfaceHeight - Top - ScaleY(8) - ScaleY(17) - ScaleY(6) - HelpH;
  if StatusH < ScaleY(118) then
    StatusH := ScaleY(118);
  GameStatusLabel := NewLabel(GamePage, Top, StatusH, '');

  Top := Top + StatusH + ScaleY(8);
  GameConfirmCheck := TNewCheckBox.Create(GamePage);
  GameConfirmCheck.Parent := GamePage.Surface;
  GameConfirmCheck.Left := 0;
  GameConfirmCheck.Top := Top;
  GameConfirmCheck.Width := GamePage.SurfaceWidth;
  GameConfirmCheck.Height := ScaleY(17);
  GameConfirmCheck.Caption := '&I have Elden Ring ' + GAME_PATCH_NAME + ' with Shadow of the Erdtree';
  GameConfirmCheck.Checked := ParamGameOk = '1';
  GameConfirmCheck.Visible := False;
  GameConfirmCheck.OnClick := @GameConfirmClick;

  Top := Top + ScaleY(17) + ScaleY(6);
  Help := NewLabel(GamePage, Top, HelpH,
    'Setup only reads the game''s version and checks that the DLC files are there; it never changes ' +
    'the game folder. Browse is only for a game Setup cannot find in Steam.');
  Help.Font.Color := clGrayText;
  GameHelpLabel := Help;
end;

{ ============================================== other mods' files page === }

procedure ForeignMoveClick(Sender: TObject);
begin
  ForeignMove := ForeignMoveCheck.Checked;
end;

procedure ForeignMoveLabelClick(Sender: TObject);
begin
  if ForeignMoveCheck.Enabled then begin
    ForeignMoveCheck.Checked := not ForeignMoveCheck.Checked;
    ForeignMove := ForeignMoveCheck.Checked;
  end;
end;

{ Fills the page from the last ScanForeignFiles (files and .me3 entries). }
procedure UpdateForeignPage;
var
  Movable, Kept, Pkg, Nat, I: Integer;
  S: String;
  Names: TStringList;
begin
  Movable := ForeignCountOf('M');
  Kept := ForeignCount - Movable;
  Pkg := Me3ExtraCountOf('P');
  Nat := Me3ExtraCountOf('N');
  { other mods' files under names an option uses (repair 3, verifier 4 D2):
    moved or kept as chosen here while that option is off }
  Names := TStringList.Create;
  try
    ForeignUnderOptionNames(ForeignScannedFor, Names);
    ForeignNamesCount := Names.Count;
    S := 'Setup found ';
    if ForeignCount + Names.Count > 0 then
      S := S + Format('%d file(s) in %s that are not part of The Convergence 3.0.2 or %s (with its options)', [ForeignCount + Names.Count, AddBackslash(ForeignScannedFor) + 'mod', CAT_VERSION_SHORT]);
    if Me3ExtraCount > 0 then begin
      if ForeignCount + Names.Count > 0 then
        S := S + ', and ';
      S := S + Format('%d entr(ies) in your .me3 profiles that load other mods', [Me3ExtraCount]);
    end;
    ForeignIntroLabel.Caption := S + '. Other mods (an older merge, a DMN copied in by hand, another overhaul) can ' +
      'break the merge.';
    S := '';
    if Movable > 0 then
      S := S + Format('Files from other mods (%d):', [Movable]) + #13#10 + ForeignLines('M', False);
    if Names.Count > 0 then begin
      if S <> '' then
        S := S + #13#10;
      S := S + Format('Files from other mods under names an option of %s uses too (%d; while that option is off ' +
        'they are moved or kept as chosen below, while it is on its own file replaces them and the backup keeps ' +
        'them):', [CAT_VERSION_SHORT, Names.Count]) + #13#10;
      for I := 0 to Names.Count - 1 do
        if I < FOREIGN_LIST_MAX then
          S := S + '  ' + Names[I] + #13#10;
    end;
    Movable := Movable + Names.Count;
  finally
    Names.Free;
  end;
  if Pkg > 0 then begin
    if S <> '' then
      S := S + #13#10;
    S := S + Format('.me3 entries that load another mod''s folder ([[package]], %d):', [Pkg]) + #13#10 +
      Me3ExtraLines('P', False);
  end;
  if Kept + Nat > 0 then begin
    if S <> '' then
      S := S + #13#10;
    S := S + Format('Kept (%d):', [Kept + Nat]) + #13#10 + ForeignLines('DL', True) + Me3ExtraLines('N', True);
  end;
  ForeignMemo.Text := S;
  ForeignMoveCheck.Enabled := OtherModsMovable or (ForeignNamesCount > 0);
  if ForeignMoveCheck.Enabled then
    ForeignMoveLabel.Font.Color := clWindowText
  else
    ForeignMoveLabel.Font.Color := clGrayText;
  if (Movable > 0) and (Pkg > 0) then
    ForeignMoveLabel.Caption := '&Move these files into the backup and switch off these .me3 entries ' +
      '(recommended - other mods can break the merge)'
  else if Pkg > 0 then
    ForeignMoveLabel.Caption := '&Switch off these .me3 entries (recommended - other mods can break the merge)'
  else
    ForeignMoveLabel.Caption := '&Move these files into the backup (recommended - files from other mods ' +
      'can break the merge)';
  if (Movable > 0) and (Pkg > 0) then
    ForeignNoteLabel.Caption := 'Moved files go to ' + BACKUP_ROOT_NAME + '\<date and time> in your ' +
      'Convergence folder; switched-off entries become comments. Uninstalling puts both back.'
  else if Pkg > 0 then
    ForeignNoteLabel.Caption := 'Switched-off entries become comments in the .me3 profile (it is backed ' +
      'up first). Uninstalling switches them back on.'
  else if Movable > 0 then
    ForeignNoteLabel.Caption := 'Moved files go to ' + BACKUP_ROOT_NAME + '\<date and time> in your ' +
      'Convergence folder, in the same folders. Uninstalling puts them back.'
  else
    ForeignNoteLabel.Caption := 'Nothing needs to be moved: me3 only loads a DLL in mod\dll when a .me3 ' +
      'profile lists it.';
end;

procedure CreateForeignPage(const AfterID: Integer);
var
  Top, MemoH: Integer;
begin
  ForeignPage := CreateCustomPage(AfterID, 'Other mods',
    'These files and .me3 entries do not belong to The Convergence 3.0.2 or ' + CAT_VERSION_SHORT + '.');
  { four lines: the text names the (possibly long) Convergence folder }
  ForeignIntroLabel := NewLabel(ForeignPage, 0, ScaleY(70), '');

  Top := ScaleY(74);
  { memo, then the box with its label (30) and a two-line note (36) }
  MemoH := ForeignPage.SurfaceHeight - Top - ScaleY(8) - ScaleY(30) - ScaleY(36);
  if MemoH < ScaleY(60) then
    MemoH := ScaleY(60);
  ForeignMemo := TNewMemo.Create(ForeignPage);
  ForeignMemo.Parent := ForeignPage.Surface;
  ForeignMemo.Left := 0;
  ForeignMemo.Top := Top;
  ForeignMemo.Width := ForeignPage.SurfaceWidth;
  ForeignMemo.Height := MemoH;
  ForeignMemo.ReadOnly := True;
  ForeignMemo.WordWrap := False;
  ForeignMemo.ScrollBars := ssBoth;

  Top := Top + MemoH + ScaleY(8);
  { a check box cannot wrap its caption: the box plus a clickable label }
  ForeignMoveCheck := TNewCheckBox.Create(ForeignPage);
  ForeignMoveCheck.Parent := ForeignPage.Surface;
  ForeignMoveCheck.Left := 0;
  ForeignMoveCheck.Top := Top;
  ForeignMoveCheck.Width := ScaleX(17);
  ForeignMoveCheck.Height := ScaleY(17);
  ForeignMoveCheck.Caption := '';
  ForeignMoveCheck.Checked := ForeignMove;
  ForeignMoveCheck.OnClick := @ForeignMoveClick;
  ForeignMoveLabel := TNewStaticText.Create(ForeignPage);
  ForeignMoveLabel.Parent := ForeignPage.Surface;
  ForeignMoveLabel.Left := ScaleX(20);
  ForeignMoveLabel.Top := Top + ScaleY(1);
  ForeignMoveLabel.Width := ForeignPage.SurfaceWidth - ScaleX(20);
  ForeignMoveLabel.AutoSize := False;
  ForeignMoveLabel.WordWrap := True;
  ForeignMoveLabel.Height := ScaleY(28);
  ForeignMoveLabel.Caption := '&Move these files into the backup (recommended - files from other mods can break the merge)';
  ForeignMoveLabel.FocusControl := ForeignMoveCheck;
  ForeignMoveLabel.OnClick := @ForeignMoveLabelClick;

  Top := Top + ScaleY(30);
  ForeignNoteLabel := NewLabel(ForeignPage, Top, ForeignPage.SurfaceHeight - Top, '');
  if ForeignNoteLabel.Height < ScaleY(36) then
    ForeignNoteLabel.Height := ScaleY(36);
  ForeignNoteLabel.Font.Color := clGrayText;
end;

{ ======================================================== Convergence page === }

function SelectedConvIndex: Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to ConvList.Items.Count - 1 do
    if ConvList.Checked[I] then begin
      Result := I;
      Exit;
    end;
end;

procedure UpdateConvStatus;
var
  Idx: Integer;
begin
  Idx := SelectedConvIndex;
  if Idx < 0 then begin
    ConvStatusLabel.Font.Color := clWindowText;
    if FoundCount > 0 then
      ConvStatusLabel.Caption := 'Select the Convergence folder you want to install ' + CAT_VERSION_SHORT + ' into.'
    else
      ConvStatusLabel.Caption := 'Click Browse and select your Convergence folder.';
  end else if FoundProblem[Idx] <> '' then begin
    ConvStatusLabel.Font.Color := COLOR_BAD;
    ConvStatusLabel.Caption := 'This folder cannot be used:' + #13#10 + FoundProblem[Idx];
  end else begin
    ConvStatusLabel.Font.Color := COLOR_GOOD;
    ConvStatusLabel.Caption := 'OK: The Convergence ' + FoundVersion[Idx] + #13#10 + FoundDir[Idx];
    if (LauncherConvDir <> '') and PathSame(FoundDir[Idx], LauncherConvDir) then
      ConvStatusLabel.Caption := ConvStatusLabel.Caption + #13#10 +
        'This is the folder the Convergence Launcher uses.';
  end;
end;

{ Rebuilds the radio list from the Found* arrays and selects SelectIndex. }
procedure RefreshConvList(const SelectIndex: Integer);
var
  I: Integer;
  Sub: String;
begin
  ConvList.Items.Clear;
  for I := 0 to FoundCount - 1 do begin
    Sub := FoundVersion[I];
    if Sub = '' then
      Sub := 'unknown version'
    else if Length(Sub) > 24 then
      Sub := SubStr(Sub, 1, 21) + '...';
    if (LauncherConvDir <> '') and PathSame(FoundDir[I], LauncherConvDir) then
      Sub := Sub + ' - Convergence Launcher';
    if FoundProblem[I] <> '' then
      Sub := Sub + ' - not usable';
    ConvList.AddRadioButton(FoundDir[I], Sub, 0, I = SelectIndex, True, nil);
  end;

  if FoundCount = 0 then
    ConvIntroLabel.Caption :=
      'Setup could not find The Convergence on this PC. Click Browse and select your Convergence ' +
      'folder (the one that contains Start_Convergence.bat, me3 and mod).' + #13#10 +
      'Not installed yet? Click "Get The Convergence", install The Convergence 3.0.2 with the ' +
      'official Convergence Launcher, launch it once, then run this installer again.'
  else if CountValidFound = 0 then
    ConvIntroLabel.Caption := Format(
      'Setup found %d Convergence folder(s), but none of them is The Convergence 3.0.2 (see below). ' +
      'Update it with the Convergence Launcher, launch it once and click Search again, or click ' +
      'Browse.', [FoundCount])
  else if FoundCount = 1 then
    ConvIntroLabel.Caption :=
      'Setup found one Convergence install and selected it. Click Next to use it, or Browse ' +
      'to pick a different folder.'
  else
    ConvIntroLabel.Caption := Format(
      'Setup found %d Convergence installs on this PC. Pick the one you want to install %s ' +
      'into, or Browse to pick another folder.', [FoundCount, CAT_VERSION_SHORT]);
  if ScanTimedOut then
    ConvIntroLabel.Caption := ConvIntroLabel.Caption + ' (The search stopped early; use Browse if yours is missing.)';
  UpdateConvStatus;
end;

{ Which entry to preselect: the /CONVDIR folder, the folder chosen earlier,
  or the only one found. With more than one, the user must pick. }
function DefaultConvSelection: Integer;
begin
  Result := -1;
  if ConvDir <> '' then
    Result := FindFoundIndex(ConvDir);
  if (Result < 0) and (ParamConvDir <> '') then
    Result := FindFoundIndex(ResolveConvergenceDir(ParamConvDir));
  if (Result < 0) and (FoundCount = 1) then
    Result := 0;
end;

procedure RunConvergenceScan;
begin
  BeginWork('Looking for The Convergence', 'Searching this PC for The Convergence...');
  try
    ScanForConvergence;
    if ParamConvDir <> '' then
      AddFoundDir(ParamConvDir);
  finally
    EndWork;
  end;
end;

procedure ConvListClickCheck(Sender: TObject);
begin
  UpdateConvStatus;
end;

procedure ConvBrowseClick(Sender: TObject);
var
  Dir: String;
  Idx: Integer;
begin
  Idx := SelectedConvIndex;
  if Idx >= 0 then
    Dir := FoundDir[Idx]
  else
    Dir := '';
  if not BrowseForFolder('Select your Convergence folder (the one that contains Start_Convergence.bat, me3 and mod):',
    Dir, False) then
    Exit;
  { AddFoundDir re-checks a folder that is already listed }
  Idx := AddFoundDir(Dir);
  RefreshConvList(Idx);
end;

procedure ConvRescanClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := SelectedConvIndex;
  RunConvergenceScan;
  if Idx < 0 then
    Idx := DefaultConvSelection;
  RefreshConvList(Idx);
end;

procedure ConvGetClick(Sender: TObject);
var
  ErrorCode: Integer;
begin
  if not ShellExec('open', CONVERGENCE_SITE_URL, '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode) then
    MsgBox('Could not open the browser. Open this page yourself:' + #13#10 + CONVERGENCE_SITE_URL,
      mbInformation, MB_OK);
end;

procedure CreateConvPage(const AfterID: Integer);
var
  Top: Integer;
begin
  ConvPage := CreateCustomPage(AfterID, 'Your Convergence folder',
    'Where should ' + CAT_VERSION_SHORT + ' be installed? It goes into The Convergence 3.0.2 folder.');

  { the intro text changes with the scan result: reserve four to five lines }
  ConvIntroLabel := NewLabel(ConvPage, 0, ScaleY(66), '');

  Top := ScaleY(70);
  ConvList := TNewCheckListBox.Create(ConvPage);
  ConvList.Parent := ConvPage.Surface;
  ConvList.Left := 0;
  ConvList.Top := Top;
  ConvList.Width := ConvPage.SurfaceWidth;
  ConvList.Height := ScaleY(88);
  ConvList.OnClickCheck := @ConvListClickCheck;
  ConvList.OnClick := @ConvListClickCheck;

  Top := ConvList.Top + ConvList.Height + ScaleY(8);
  { access keys must not clash with the wizard's own buttons (&Back, &Next) }
  ConvBrowseButton := NewButton(ConvPage, 0, Top, ScaleX(120), 'B&rowse...');
  ConvBrowseButton.OnClick := @ConvBrowseClick;
  ConvRescanButton := NewButton(ConvPage, ScaleX(128), Top, ScaleX(120), '&Search again');
  ConvRescanButton.OnClick := @ConvRescanClick;
  ConvGetButton := NewButton(ConvPage, ConvPage.SurfaceWidth - ScaleX(150), Top, ScaleX(150),
    '&Get The Convergence');
  ConvGetButton.OnClick := @ConvGetClick;

  Top := Top + ScaleY(23) + ScaleY(8);
  ConvStatusLabel := NewLabel(ConvPage, Top, ConvPage.SurfaceHeight - Top, '');
end;

{ Next on the Convergence page: full validation (including a write test),
  then check B (every Convergence 3.0.2 file) and scan C (other mods' files,
  shown on the next page). }
function ConvPageNext: Boolean;
var
  Idx: Integer;
  Problem: String;
  Ok: Boolean;
begin
  Result := False;
  Idx := SelectedConvIndex;
  if Idx < 0 then begin
    MsgBox('Select your Convergence folder first (or click Browse).', mbError, MB_OK);
    Exit;
  end;
  Problem := DescribeConvergenceProblem(FoundDir[Idx], True);
  FoundProblem[Idx] := Problem;
  if Problem <> '' then begin
    UpdateConvStatus;
    MsgBox(Problem, mbError, MB_OK);
    Exit;
  end;
  BeginWork('Checking The Convergence 3.0.2', 'Checking every file of The Convergence 3.0.2...');
  try
    Ok := CheckConvergenceIntegrity(FoundDir[Idx], Problem, ConvCheckSummary);
    if Ok then
      ScanForeignFiles(FoundDir[Idx]);
  finally
    EndWork;
  end;
  if not Ok then begin
    FoundProblem[Idx] := Problem;
    UpdateConvStatus;
    MsgBox(Problem, mbError, MB_OK);
    Exit;
  end;
  UpdateForeignPage;
  if not PathSame(ConvDir, FoundDir[Idx]) then
    Log('Convergence folder chosen: ' + FoundDir[Idx]);
  ConvDir := FoundDir[Idx];
  ConvVersion := FoundVersion[Idx];
  WizardForm.DirEdit.Text := ConvDir;
  Result := True;
end;

{ ========================================================= Options page === }

{ Top to bottom:
    the list, one line per optional component, in catalog order:
      T  a check box (sub-item: where its files come from, when it fits)
      C  a group line and one radio button per state
      X  an unticked, greyed check box (not available yet)
    "(experimental)" after the caption of experimental components
    the DLL component (ERCapacityExpansion) ticked, greyed and captioned
    "<its short name> - <reason>" while the ticked options need it (a D rule:
    DMN + Nightreign's Wylder; or the animation wall); unticking one of them
    releases it to the player's own choice (2026-10-03)
    two grey lines: "Always installed: ..." (the R components) until a list
    line is clicked, then that line's description
    one row per field: its label and an edit box (enabled while its
    component is ticked)
    a grey line "Installed in this folder now: ..." and the animation slots
  The list gets exactly the height its lines need when the page has room
  (LB_GETITEMHEIGHT), so it does not scroll at any DPI. A text line needs
  about ScaleY(16): one-line labels get ScaleY(16), two-line ones ScaleY(32). }

const
  LB_GETITEMHEIGHT = $01A1;

procedure OptMapItem(const Idx, C, S: Integer);
begin
  if Idx >= GetArrayLength(OptItemComp) then begin
    SetArrayLength(OptItemComp, Idx + 1);
    SetArrayLength(OptItemState, Idx + 1);
  end;
  OptItemComp[Idx] := C;
  OptItemState[Idx] := S;
end;

{ CompShortTitle (a component's title without its " - explanation" part) is in backup.iss. }

function AlwaysInstalledText: String;
var
  C: Integer;
begin
  Result := '';
  for C := 0 to CompCount - 1 do
    if CompKind[C] = 'R' then begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + CompShortTitle(C);
    end;
  Result := 'Always installed: ' + Result + '.';
end;

{ The width a one-line text needs in AFont (a hidden label measures it). }
function TextWidthPx(const Text: String; AFont: TFont): Integer;
var
  L: TNewStaticText;
begin
  L := TNewStaticText.Create(OptionsPage);
  try
    L.Parent := OptionsPage.Surface;
    L.Visible := False;
    L.AutoSize := True;
    L.WordWrap := False;
    L.Font.Assign(AFont);
    L.Caption := Text;
    Result := L.Width;
  finally
    L.Free;
  end;
end;

{ The sub-item of a list line: dropped when caption + sub-item do not fit. }
function OptSubItem(const Caption, Sub: String; const Level: Integer): String;
begin
  Result := Sub;
  if (Sub <> '') and (TextWidthPx(Caption + '      ' + Sub, OptList.Font) >
    OptList.Width - ScaleX(44) - Level * ScaleX(16)) then
    Result := '';
end;

procedure BuildOptionsList;
var
  C, S, I: Integer;
begin
  OptUpdating := True;
  try
    OptList.Items.Clear;
    SetArrayLength(OptItemComp, 0);
    SetArrayLength(OptItemState, 0);
    for C := 0 to CompCount - 1 do begin
      if CompKind[C] = 'T' then begin
        I := OptList.AddCheckBox(CompCaption(C), OptSubItem(CompCaption(C), CompSourceText[C], 0), 0, CompOn(C),
          True, False, False, nil);
        OptMapItem(I, C, -1);
      end else if CompKind[C] = 'C' then begin
        I := OptList.AddGroup(CompCaption(C) + ':', OptSubItem(CompCaption(C) + ':', CompSourceText[C], 0), 0, nil);
        OptMapItem(I, C, -2);
        for S := 0 to CompStateCount[C] - 1 do begin
          I := OptList.AddRadioButton(CompStateTitle(C, S), '', 1, ChosenState[C] = S, True, nil);
          OptMapItem(I, C, S);
        end;
      end else if CompKind[C] = 'X' then begin
        I := OptList.AddCheckBox(CompCaption(C), '', 0, False, False, False, False, nil);
        OptMapItem(I, C, -1);
      end;
    end;
  finally
    OptUpdating := False;
  end;
end;

{ The selection -> the list (after presets, rules or the wall changed it). }
procedure SyncOptionsList;
var
  I, C, S: Integer;
begin
  OptUpdating := True;
  try
    for I := 0 to OptList.Items.Count - 1 do begin
      C := OptItemComp[I];
      S := OptItemState[I];
      if CompKind[C] = 'T' then
        OptList.Checked[I] := CompOn(C)
      else if (CompKind[C] = 'C') and (S >= 0) then
        OptList.Checked[I] := ChosenState[C] = S;
    end;
  finally
    OptUpdating := False;
  end;
end;

{ The list and the edit boxes -> the selection and the field values. }
procedure ReadOptionsList;
var
  I, C, S: Integer;
begin
  for I := 0 to OptList.Items.Count - 1 do begin
    C := OptItemComp[I];
    S := OptItemState[I];
    { the DLL component's line while it is locked (greyed) shows what the
      selection needs, not the player's choice: ChosenState / DllAuto keep it }
    if (C = WALL_DLL_COMP) and (CompKind[C] = 'T') and not OptList.ItemEnabled[I] then
      Continue;
    if (C = WALL_DLL_COMP) and (CompKind[C] = 'T') then
      DllAuto := False;      { an enabled box is the player's own choice }
    if CompKind[C] = 'T' then begin
      if OptList.Checked[I] then
        ChosenState[C] := 1
      else
        ChosenState[C] := 0;
    end else if (CompKind[C] = 'C') and (S >= 0) and OptList.Checked[I] then
      ChosenState[C] := S;
  end;
  for I := 0 to FieldCount - 1 do
    FieldValue[I] := Trim(OptFieldEdit[I].Text);
end;

{ The list line of a T component (-1 = none). }
function OptItemOf(const C: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to GetArrayLength(OptItemComp) - 1 do
    if (OptItemComp[I] = C) and (OptItemState[I] = -1) then begin
      Result := I;
      Exit;
    end;
end;

{ 2026-10-03 (Luka: DMN + Nightreign's Wylder need ERCapacityExpansion): the
  DLL component's line follows the ticks at once. While the ticked options
  need it (DllNeededReason: a D rule, or the animation wall) it is ticked,
  greyed and captioned "<short name> - <reason>"; once they no longer do it
  goes back to the player's own choice (DllOwn: the tick it had before it was
  locked, or the one he set since). }
procedure UpdateDllLock;
var
  I, Dll: Integer;
  Reason: String;
  WasLocked: Boolean;
begin
  Dll := WALL_DLL_COMP;
  if (Dll < 0) or (CompKind[Dll] <> 'T') then
    Exit;
  I := OptItemOf(Dll);
  if I < 0 then
    Exit;
  WasLocked := not OptList.ItemEnabled[I];
  DllTakeOwnChoice;
  Reason := DllNeededReason;
  OptUpdating := True;
  try
    if Reason <> '' then begin
      if not CompOn(Dll) then begin
        ChosenState[Dll] := 1;
        DllAuto := True;
      end;
      DllReason := Reason;
      OptList.Checked[I] := True;
      OptList.ItemEnabled[I] := False;
      OptList.ItemCaption[I] := CompShortTitle(Dll) + ' - ' + Reason;
      OptList.ItemSubItem[I] := '';
      if not WasLocked then
        Log('CXCXM OPTIONS ' + CompId[Dll] + ' locked on: ' + Reason + ' (your own choice: ' + BoolText(DllOwn >= 1) +
          ')');
    end else begin
      OptList.ItemEnabled[I] := True;
      OptList.Checked[I] := CompOn(Dll);
      OptList.ItemCaption[I] := CompCaption(Dll);
      OptList.ItemSubItem[I] := OptSubItem(CompCaption(Dll), CompSourceText[Dll], 0);
      if WasLocked then
        Log('CXCXM OPTIONS ' + CompId[Dll] + ' released: back to your own choice (' + BoolText(CompOn(Dll)) + ')');
    end;
  finally
    OptUpdating := False;
  end;
end;

procedure UpdateOptionsExtras;
var
  I: Integer;
begin
  for I := 0 to FieldCount - 1 do begin
    OptFieldEdit[I].Enabled := CompOn(FieldComp[I]);
    OptFieldLabel[I].Enabled := CompOn(FieldComp[I]);
  end;
  WallLabel.Caption := WallLineText;
  { red only while the slots are over what the selection gets (the DLL switched
    on by itself makes room: grey) }
  if (CurrentWallTotal > WALL_LIMIT_DLL) or ((CurrentWallTotal > WallLimitNoDll) and
     ((WALL_DLL_COMP < 0) or not CompOn(WALL_DLL_COMP))) then
    WallLabel.Font.Color := COLOR_BAD
  else
    WallLabel.Font.Color := clGrayText;
end;

procedure OptListClickCheck(Sender: TObject);
begin
  if OptUpdating then
    Exit;
  ReadOptionsList;
  UpdateDllLock;
  UpdateOptionsExtras;
end;

function OptDescText(const C: Integer): String;
begin
  Result := CompShortTitle(C) + ': ' + CompDesc[C];
  if CompExperimental[C] then
    Result := Result + ' Experimental: it was not tested as much as the rest.';
end;

procedure OptListClick(Sender: TObject);
var
  I: Integer;
begin
  I := OptList.ItemIndex;
  if (I < 0) or (I >= GetArrayLength(OptItemComp)) then
    Exit;
  OptDescLabel.Caption := OptDescText(OptItemComp[I]);
end;

{ Places every control: the list as tall as its lines need (when there is
  room), the description label two lines. }
procedure LayoutOptionsPage;
var
  Top, I, ItemH, Need, Below, ListH, H: Integer;
begin
  H := OptionsPage.SurfaceHeight;
  { below the list: description (2 lines), the fields (2-line rows), installed-now (2 lines), slots (1 line) }
  Below := ScaleY(4) + ScaleY(32) + FieldCount * (ScaleY(4) + ScaleY(32)) + ScaleY(4) + ScaleY(32) + ScaleY(2) +
    ScaleY(16);
  ItemH := SendMessage(OptList.Handle, LB_GETITEMHEIGHT, 0, 0);
  if ItemH <= 0 then
    ItemH := ScaleY(18);
  Need := OptList.Items.Count * ItemH + ScaleY(4);
  ListH := H - Below;
  if Need < ListH then
    ListH := Need;
  if ListH < ScaleY(100) then
    ListH := ScaleY(100);
  OptList.Top := 0;
  OptList.Height := ListH;
  Top := ListH + ScaleY(4);
  OptDescLabel.Top := Top;
  OptDescLabel.Height := ScaleY(32);
  Top := Top + ScaleY(32);
  for I := 0 to FieldCount - 1 do begin
    Top := Top + ScaleY(4);
    OptFieldLabel[I].Top := Top;
    OptFieldLabel[I].Height := ScaleY(32);
    OptFieldEdit[I].Top := Top + ScaleY(4);
    Top := Top + ScaleY(32);
  end;
  Top := Top + ScaleY(4);
  InstalledNowLabel.Top := Top;
  InstalledNowLabel.Height := ScaleY(32);
  Top := Top + ScaleY(32) + ScaleY(2);
  WallLabel.Top := Top;
  WallLabel.Height := ScaleY(16);
  Log(Format('Options page layout: surface %dx%d, %d list lines of %d pixels, list height %d (needs %d), ' +
    'last line ends at %d', [OptionsPage.SurfaceWidth, H, OptList.Items.Count, ItemH, ListH, Need, Top + ScaleY(16)]));
end;

procedure CreateOptionsPage(const AfterID: Integer);
var
  I, LabelW: Integer;
begin
  OptionsPage := CreateCustomPage(AfterID, 'Options',
    'Pick any combination. What is installed in this folder now is preselected; run this installer ' +
    'again later to change it.');
  OptList := TNewCheckListBox.Create(OptionsPage);
  OptList.Parent := OptionsPage.Surface;
  OptList.Left := 0;
  OptList.Top := 0;
  OptList.Width := OptionsPage.SurfaceWidth;
  OptList.Height := ScaleY(200);
  OptList.OnClickCheck := @OptListClickCheck;
  OptList.OnClick := @OptListClick;

  OptDescLabel := NewLabel(OptionsPage, 0, ScaleY(32), AlwaysInstalledText);
  OptDescLabel.Font.Color := clGrayText;

  { one row per field: the label (up to two lines) left, the edit box right }
  LabelW := (OptionsPage.SurfaceWidth * 58) div 100;
  SetArrayLength(OptFieldLabel, FieldCount);
  SetArrayLength(OptFieldEdit, FieldCount);
  for I := 0 to FieldCount - 1 do begin
    OptFieldLabel[I] := NewLabel(OptionsPage, 0, ScaleY(32), FieldLabel[I]);
    OptFieldLabel[I].Width := LabelW - ScaleX(8);
    OptFieldEdit[I] := TNewEdit.Create(OptionsPage);
    OptFieldEdit[I].Parent := OptionsPage.Surface;
    OptFieldEdit[I].Left := LabelW;
    OptFieldEdit[I].Width := OptionsPage.SurfaceWidth - LabelW;
    OptFieldEdit[I].Text := FieldValue[I];
  end;

  InstalledNowLabel := NewLabel(OptionsPage, 0, ScaleY(32), '');
  InstalledNowLabel.Font.Color := clGrayText;
  WallLabel := NewLabel(OptionsPage, 0, ScaleY(16), '');
  WallLabel.Font.Color := clGrayText;
  BuildOptionsList;
  LayoutOptionsPage;
end;

{ Shown each time the page is entered: the presets were made for the chosen
  folder already (events.iss), so the list only shows the selection. }
procedure UpdateOptionsPage;
var
  I: Integer;
begin
  SyncOptionsList;
  UpdateDllLock;
  for I := 0 to FieldCount - 1 do
    if OptFieldEdit[I].Text <> FieldValue[I] then
      OptFieldEdit[I].Text := FieldValue[I];
  InstalledNowLabel.Caption := InstalledNowText;
  UpdateOptionsExtras;
end;

{ ====================================================== Downloads page === }

function DlSelectedArch: Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to DlList.Items.Count - 1 do
    if DlList.Checked[I] and (I < GetArrayLength(DlRowArch)) then begin
      Result := DlRowArch[I];
      Exit;
    end;
end;

function DlShortStatus(const A: Integer): String;
begin
  if (ArchState[A] = AS_ACCEPTED) and not ArchTested[A] then
    Result := 'found (not the tested version)'
  else if ArchState[A] = AS_ACCEPTED then
    Result := 'found and checked'
  else if (ArchState[A] = AS_REJECTED) and (Pos('not the tested version', ArchProblem[A]) > 0) then
    Result := 'other version found'
  else if ArchState[A] = AS_REJECTED then
    Result := 'wrong files'
  else
    Result := 'missing';
end;

{ What the status text says about archive A. }
function DlLongStatus(const A: Integer): String;
begin
  Result := ArchTitle[A] + ' by ' + ArchAuthor[A] + '.';
  if (ArchState[A] = AS_ACCEPTED) and not ArchTested[A] then begin
    Result := Result + #13#10 + 'Found, but NOT the tested version ' + ModeVTestedVersion(A) + ' (you chose it). ' +
      'Setup copies its files as they are and cannot check them:' + #13#10 + ArchSource[A];
    Exit;
  end;
  if ArchState[A] = AS_ACCEPTED then begin
    Result := Result + #13#10 + 'Found and checked (every file it gives matches, SHA-256):' + #13#10 + ArchSource[A];
    Exit;
  end;
  if ArchNeedNote[A] <> '' then
    Result := Result + ' ' + ArchNeedNote[A];
  if ArchState[A] = AS_REJECTED then
    Result := Result + #13#10 + 'Not usable: ' + ArchProblem[A]
  else begin
    Result := Result + #13#10 + ArchHint[A];
    if ArchNexusUrl[A] <> '' then
      Result := Result + #13#10 + 'Click "Open download page", download it, then click "Search again" (or ' +
        '"Select archive" and pick the file).'
    else
      Result := Result + #13#10 + 'Search Nexus Mods for "' + ArchTitle[A] + '", download it, then click ' +
        '"Search again" (or "Select archive" and pick the file).';
  end;
end;

procedure UpdateDlStatus;
var
  A: Integer;
begin
  A := DlSelectedArch;
  DlNexusButton.Enabled := (A >= 0) and (ArchNexusUrl[A] <> '');
  DlArchiveButton.Enabled := A >= 0;
  DlFolderButton.Enabled := A >= 0;
  if A < 0 then begin
    DlStatusLabel.Font.Color := clWindowText;
    if ArchivesNeededCount = 0 then
      DlStatusLabel.Caption := 'No downloads are needed for the chosen options.'
    else
      DlStatusLabel.Caption := 'Select a line to see what to do.';
  end else begin
    DlStatusLabel.Caption := DlLongStatus(A);
    if ArchState[A] = AS_ACCEPTED then
      DlStatusLabel.Font.Color := COLOR_GOOD
    else
      DlStatusLabel.Font.Color := COLOR_BAD;
  end;
  if WizardForm.CurPageID = DlPage.ID then
    WizardForm.NextButton.Enabled := ArchivesMissingCount = 0;
end;

{ Rebuilds the list from the needed archives and selects SelectA (else the
  first one that is not accepted, else the first one). }
procedure RefreshDownloadsPage(const SelectA: Integer);
var
  A, N, Sel: Integer;
begin
  Sel := -1;
  if (SelectA >= 0) and (SelectA < ArchCount) and ArchNeeded[SelectA] then
    Sel := SelectA;
  if Sel < 0 then
    for A := 0 to ArchCount - 1 do
      if (Sel < 0) and ArchNeeded[A] and (ArchState[A] <> AS_ACCEPTED) then
        Sel := A;
  if Sel < 0 then
    for A := 0 to ArchCount - 1 do
      if (Sel < 0) and ArchNeeded[A] then
        Sel := A;
  DlList.Items.Clear;
  SetArrayLength(DlRowArch, 0);
  N := 0;
  for A := 0 to ArchCount - 1 do
    if ArchNeeded[A] then begin
      DlList.AddRadioButton(ArchTitle[A], DlShortStatus(A), 0, A = Sel, True, nil);
      SetArrayLength(DlRowArch, N + 1);
      DlRowArch[N] := A;
      N := N + 1;
    end;
  if ArchivesMissingCount = 0 then
    DlIntroLabel.Caption := 'Every download the chosen options need was found and checked. Click Next.'
  else
    DlIntroLabel.Caption := 'These mods come from their authors'' own pages, so the authors get their ' +
      'downloads. Download each one marked missing (on Nexus: MANUAL DOWNLOAD on its Files tab). Setup finds it in ' +
      'your Downloads folder, takes only the files the merge uses and checks every one of them (SHA-256). ' +
      'Next stays disabled until every download is found.';
  UpdateDlStatus;
end;

procedure DlTryPath(const A: Integer; const P: String);
begin
  BeginWork('Checking your download', 'Checking ' + P + ' ...');
  try
    TryArchivePath(A, P);
  finally
    EndWork;
  end;
  RefreshDownloadsPage(A);
end;

procedure DlListClick(Sender: TObject);
begin
  UpdateDlStatus;
end;

procedure DlNexusClick(Sender: TObject);
var
  A, ErrorCode: Integer;
begin
  A := DlSelectedArch;
  if (A < 0) or (ArchNexusUrl[A] = '') then
    Exit;
  { only a web address is ever opened (the pipeline checks it too: code
    review repair 2, D9) }
  if not StartsWithStr(Lowercase(ArchNexusUrl[A]), 'https://') then begin
    MsgBox('Open this page yourself:' + #13#10 + ArchNexusUrl[A], mbInformation, MB_OK);
    Exit;
  end;
  if not ShellExec('open', ArchNexusUrl[A], '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode) then
    MsgBox('Could not open the browser. Open this page yourself:' + #13#10 + ArchNexusUrl[A],
      mbInformation, MB_OK);
end;

procedure DlArchiveClick(Sender: TObject);
var
  A: Integer;
  FileName: String;
begin
  A := DlSelectedArch;
  if A < 0 then
    Exit;
  FileName := '';
  if GetOpenFileName('Select the archive of ' + ArchTitle[A] + ' you downloaded', FileName,
    GetDownloadsDir, 'Archives (*.zip;*.7z;*.rar)|*.zip;*.7z;*.rar|All files (*.*)|*.*', 'zip') then
    DlTryPath(A, FileName);
end;

procedure DlFolderClick(Sender: TObject);
var
  A: Integer;
  Dir: String;
begin
  A := DlSelectedArch;
  if A < 0 then
    Exit;
  Dir := GetDownloadsDir;
  if BrowseForFolder('Select the folder you extracted ' + ArchTitle[A] + ' into (any folder that ' +
    'holds its files is fine):', Dir, False) then
    DlTryPath(A, Dir);
end;

procedure DlSearchClick(Sender: TObject);
var
  A: Integer;
begin
  A := DlSelectedArch;
  BeginWork('Looking for your downloads', 'Searching your Downloads folder...');
  try
    AutoFindArchives(True, -1, True);
  finally
    EndWork;
  end;
  RefreshDownloadsPage(A);
end;

procedure CreateDownloadsPage(const AfterID: Integer);
var
  Top, W: Integer;
begin
  DlPage := CreateCustomPage(AfterID, 'Get these downloads',
    'The chosen options need these mods from their authors'' pages.');
  DlIntroLabel := NewLabel(DlPage, 0, ScaleY(56), '');
  Top := ScaleY(60);
  DlList := TNewCheckListBox.Create(DlPage);
  DlList.Parent := DlPage.Surface;
  DlList.Left := 0;
  DlList.Top := Top;
  DlList.Width := DlPage.SurfaceWidth;
  DlList.Height := ScaleY(84);
  DlList.OnClickCheck := @DlListClick;
  DlList.OnClick := @DlListClick;
  Top := Top + ScaleY(84) + ScaleY(6);
  W := (DlPage.SurfaceWidth - 3 * ScaleX(6)) div 4;
  { access keys must not clash with the wizard's own buttons (&Back, &Next) }
  { the page may be Nexus or another author's site }
  DlNexusButton := NewButton(DlPage, 0, Top, W, 'Open download &page');
  DlNexusButton.OnClick := @DlNexusClick;
  DlArchiveButton := NewButton(DlPage, W + ScaleX(6), Top, W, 'Select &archive...');
  DlArchiveButton.OnClick := @DlArchiveClick;
  DlFolderButton := NewButton(DlPage, 2 * (W + ScaleX(6)), Top, W, 'Select &folder...');
  DlFolderButton.OnClick := @DlFolderClick;
  DlSearchButton := NewButton(DlPage, 3 * (W + ScaleX(6)), Top, W, '&Search again');
  DlSearchButton.OnClick := @DlSearchClick;
  Top := Top + ScaleY(23) + ScaleY(8);
  DlStatusLabel := NewLabel(DlPage, Top, DlPage.SurfaceHeight - Top, '');
end;

{ ========================================================= Credits page === }

procedure UpdateCreditsPage;
var
  L: TStringList;
  I: Integer;
  S: String;
begin
  L := TStringList.Create;
  try
    GetCredits(L);
    S := '';
    for I := 0 to L.Count - 1 do
      S := S + L[I] + #13#10;
    CreditsMemo.Text := S;
  finally
    L.Free;
  end;
end;

procedure CreateCreditsPage(const AfterID: Integer);
var
  Intro: TNewStaticText;
  Top: Integer;
begin
  CreditsPage := CreateCustomPage(AfterID, 'Credits',
    'The chosen options use the work of these authors. Thank you!');
  Intro := NewFittedLabel(CreditsPage, 0,
    'Every mod below was made by its author; the merge and the installer only bring them together. ' +
    'Endorse them on their pages if you enjoy their work.');
  Top := Intro.Top + Intro.Height + ScaleY(8);
  CreditsMemo := TNewMemo.Create(CreditsPage);
  CreditsMemo.Parent := CreditsPage.Surface;
  CreditsMemo.Left := 0;
  CreditsMemo.Top := Top;
  CreditsMemo.Width := CreditsPage.SurfaceWidth;
  CreditsMemo.Height := CreditsPage.SurfaceHeight - Top;
  CreditsMemo.ReadOnly := True;
  CreditsMemo.WordWrap := True;
  CreditsMemo.ScrollBars := ssVertical;
end;

#if Defined(CodeCheck) || Defined(TestBuild)
{ ================================================== test builds: layout === }

{ /TESTLAYOUT=1 (test builds only): for every fixed-height label of the new
  pages, logs how tall its longest text needs to be against the height the
  page gives it, so clipped text shows up in a silent test run. }
procedure LogLabelFit(L: TNewStaticText; const Name, Text: String);
var
  H, Need: Integer;
  Saved, Verdict: String;
begin
  H := L.Height;
  Saved := L.Caption;
  L.Caption := Text;
  L.AdjustHeight;
  Need := L.Height;
  if Need <= H then
    Verdict := 'fits'
  else
    Verdict := 'CLIPPED';
  Log(Format('LAYOUT %s: width %d, height %d, text needs %d -> %s', [Name, L.Width, H, Need, Verdict]));
  L.Height := H;
  L.Caption := Saved;
end;

{ One line of text (a list item, a button) against the width it gets. }
procedure LogWidthFit(const Name, Text: String; AFont: TFont; const Avail: Integer);
var
  L: TNewStaticText;
  Need: Integer;
  Verdict: String;
begin
  L := TNewStaticText.Create(OptionsPage);
  try
    L.Parent := OptionsPage.Surface;
    L.AutoSize := True;
    L.WordWrap := False;
    L.Font.Assign(AFont);
    L.Caption := Text;
    Need := L.Width;
    if Need <= Avail then
      Verdict := 'fits'
    else
      Verdict := 'CLIPPED';
    Log(Format('LAYOUT %s: width %d, text needs %d -> %s', [Name, Avail, Need, Verdict]));
  finally
    L.Free;
  end;
end;

procedure LogLayoutFit;
var
  Exes: TStringList;
  I, C, A, Avail: Integer;
  S: String;
  SavedDet: array of Integer;
begin
  Log(Format('LAYOUT surface %dx%d', [GamePage.SurfaceWidth, GamePage.SurfaceHeight]));
  { Options: every list line (caption + sub-item + check box + indent + scroll bar) }
  for I := 0 to OptList.Items.Count - 1 do begin
    Avail := OptList.Width - ScaleX(24) - ScaleX(20) - OptList.ItemLevel[I] * ScaleX(16);
    S := OptList.ItemCaption[I];
    if OptList.ItemSubItem[I] <> '' then
      S := S + '      ' + OptList.ItemSubItem[I];
    LogWidthFit('Options line ' + IntToStr(I), S, OptList.Font, Avail);
  end;
  Log(Format('LAYOUT Options list %d rows in %d pixels (rows of about %d)', [OptList.Items.Count,
    OptList.Height, ScaleY(18)]));
  { 2026-10-03: the DLL component's line while a D rule locks it (and with the wall's reason) }
  if (WALL_DLL_COMP >= 0) and (OptItemOf(WALL_DLL_COMP) >= 0) then begin
    Avail := OptList.Width - ScaleX(24) - ScaleX(20);
    for I := 0 to GetArrayLength(RuleKind) - 1 do
      if RuleKind[I] = 'D' then
        LogWidthFit('Options line ' + CompId[WALL_DLL_COMP] + ' locked by rule ' + IntToStr(I),
          CompShortTitle(WALL_DLL_COMP) + ' - ' + RuleText[I], OptList.Font, Avail);
    LogWidthFit('Options line ' + CompId[WALL_DLL_COMP] + ' locked by the wall', CompShortTitle(WALL_DLL_COMP) +
      ' - needed for your options'' animation slots', OptList.Font, Avail);
  end;
  for C := 0 to CompCount - 1 do
    if CompKind[C] <> 'R' then
      LogLabelFit(OptDescLabel, 'Options description ' + CompId[C], OptDescText(C));
  LogLabelFit(OptDescLabel, 'Options always installed', AlwaysInstalledText);
  SetArrayLength(SavedDet, CompCount);
  for C := 0 to CompCount - 1 do begin
    SavedDet[C] := DetectedState[C];
    if CompIsOptional(C) then
      DetectedState[C] := CompStateCount[C] - 1;
  end;
  LogLabelFit(InstalledNowLabel, 'Options installed-now (longest)', InstalledNowText);
  for C := 0 to CompCount - 1 do
    DetectedState[C] := SavedDet[C];
  { the longest wall line: the DLL component's short name (WallLineText; final pass: it used the LAST component's
    full title, which is no longer the DLL component's) }
  if WALL_DLL_COMP >= 0 then
    LogLabelFit(WallLabel, 'Options animation slots (longest)', 'Animation slots used: 64,999 of 32,768 - too ' +
      'many: ' + CompShortTitle(WALL_DLL_COMP) + ' will be switched on.')
  else
    LogLabelFit(WallLabel, 'Options animation slots (longest)', 'Animation slots used: 64,999 of 32,768 - too ' +
      'many: switch some options off.');
  for I := 0 to FieldCount - 1 do
    LogLabelFit(OptFieldLabel[I], 'Options field ' + FieldId[I], FieldLabel[I]);
  { Downloads: the status of every archive, missing (the longest text) }
  for A := 0 to ArchCount - 1 do begin
    ArchNeedNote[A] := 'Setup checks this download once per Convergence folder, even when its files are ' +
      'already there.';
    LogLabelFit(DlStatusLabel, 'Downloads status ' + ArchId[A], DlLongStatus(A));
    ArchNeedNote[A] := '';
    LogWidthFit('Downloads line ' + ArchId[A], ArchTitle[A] + '      found and checked', DlList.Font,
      DlList.Width - ScaleX(44));
  end;
  LogLabelFit(DlIntroLabel, 'Downloads intro', 'These mods come from their authors'' own pages, so the ' +
    'authors get their downloads. Download each one marked missing (on Nexus: MANUAL DOWNLOAD on its Files tab). ' +
    'Setup finds it in your Downloads folder, takes only the files the merge uses and checks every one of ' +
    'them (SHA-256). Next stays disabled until every download is found.');
  LogWidthFit('Downloads button Nexus', 'Open download page', DlNexusButton.Font, DlNexusButton.Width - ScaleX(8));
  LogWidthFit('Downloads button archive', 'Select archive...', DlArchiveButton.Font, DlArchiveButton.Width - ScaleX(8));
  LogLabelFit(WizardForm.WelcomeLabel2, 'Welcome text', WizardForm.WelcomeLabel2.Caption);
  LogLabelFit(GameHelpLabel, 'Elden Ring help', GameHelpLabel.Caption);
  { the status text for every game copy given in /TESTLAYOUTEXES (a ; list)
    and for "not found" }
  Exes := TStringList.Create;
  try
    S := CmdParam('TESTLAYOUTEXES');
    while S <> '' do begin
      I := Pos(';', S);
      if I = 0 then I := Length(S) + 1;
      Exes.Add(Copy(S, 1, I - 1));
      S := Copy(S, I + 1, Length(S));
    end;
    Exes.Add('');
    for I := 0 to Exes.Count - 1 do begin
      EvaluateGameExe(Exes[I]);
      LogLabelFit(GameStatusLabel, 'Elden Ring status (' + ExtractFileName(ExtractFileDir(ExtractFileDir(
        ExtractFileDir(ExtractFileDir(ExtractFileDir(Exes[I])))))) + ')', GameStatusText);
    end;
  finally
    Exes.Free;
  end;
  RunGameCheck;
  if OtherModsFound then begin
    UpdateForeignPage;
    LogLabelFit(ForeignIntroLabel, 'Other mods intro', ForeignIntroLabel.Caption);
    LogLabelFit(ForeignMoveLabel, 'Other mods move box', ForeignMoveLabel.Caption);
    LogLabelFit(ForeignNoteLabel, 'Other mods note', ForeignNoteLabel.Caption);
  end;
  LogLabelFit(ForeignMoveLabel, 'Other mods move box (files + entries)', '&Move these files into the ' +
    'backup and switch off these .me3 entries (recommended - other mods can break the merge)');
  LogLabelFit(ForeignNoteLabel, 'Other mods note (files + entries)', 'Moved files go to ' + BACKUP_ROOT_NAME +
    '\<date and time> in your Convergence folder; switched-off entries become comments. Uninstalling ' +
    'puts both back.');
end;
#endif

{ ============================================================ all pages ===== }

procedure CreateWizardPages;
begin
  WorkPage := CreateOutputProgressPage('Working', 'Please wait.');
  FetchPage := CreateDownloadPage('Downloading the option files',
    'Setup downloads the files of the chosen options and checks each one (SHA-256). Nothing in your ' +
    'Convergence folder changes before every file is here.', nil);
  CreateGamePage(wpWelcome);
  CreateConvPage(GamePage.ID);
  CreateForeignPage(ConvPage.ID);
  CreateOptionsPage(ForeignPage.ID);
  CreateDownloadsPage(OptionsPage.ID);
  CreateCreditsPage(DlPage.ID);
end;
