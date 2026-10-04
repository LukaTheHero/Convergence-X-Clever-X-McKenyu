{ =============================================================================
  catalogrt.iss - the catalog at run time (contract sections 3.2, 5.1, 5.2, 7):
    - the selection model: one state per component (ChosenState). R = 1 and
      X = 0 always; T/C start at what the folder has now (detection rules),
      then /COMPONENTS= (/SELECT=), then /<CompSwitch>=, then the wizard
    - the key rule: which variant a path must hold for the selection
    - normalisation: rules Q (requires: switch the other one on), X
      (conflict: refuse), W (warning), D (2026-10-03: the two together need
      the DLL component - switched on by itself with the rule's text as the
      reason) and the animation wall (ERCap forced above WALL_LIMIT_NODLL,
      refused above WALL_LIMIT_DLL); a DLL switched on only because the
      selection needs it (DllAuto) is AUTO_ON in the marker, so a later run
      that no longer needs it takes it off again
    - the command line, read with ParamStr (values may hold any character);
      a switch that looks like ours but is not (same first three letters,
      not one of Inno's own), or one of ours without a value, is refused
    - the marker CXCXM_INSTALLED.txt of an earlier run (VERIFIED_ARCHIVES)
  ============================================================================= }

{ ------------------------------------------------------------------ counts --- }

function CompCount: Integer;
begin
  Result := GetArrayLength(CompId);
end;

function PathCount: Integer;
begin
  Result := GetArrayLength(PathRel);
end;

function VarCount: Integer;
begin
  Result := GetArrayLength(VarPath);
end;

function ArchCount: Integer;
begin
  Result := GetArrayLength(ArchId);
end;

function MemCount: Integer;
begin
  Result := GetArrayLength(MemArch);
end;

function BlobCount: Integer;
begin
  Result := GetArrayLength(BlobSha);
end;

function FieldCount: Integer;
begin
  Result := GetArrayLength(FieldComp);
end;

{ --------------------------------------------------------------- components --- }

function CompIndexOf(const Id: String): Integer;
var
  C: Integer;
begin
  Result := -1;
  for C := 0 to CompCount - 1 do
    if CompareText(CompId[C], Id) = 0 then begin
      Result := C;
      Exit;
    end;
end;

{ T and C components can be switched by the player. }
function CompIsOptional(const C: Integer): Boolean;
begin
  Result := (CompKind[C] = 'T') or (CompKind[C] = 'C');
end;

function CompOn(const C: Integer): Boolean;
begin
  Result := ChosenState[C] >= 1;
end;

function CompStateCode(const C, S: Integer): String;
begin
  Result := StateCode[CompStateStart[C] + S];
end;

function CompStateTitle(const C, S: Integer): String;
begin
  Result := StateTitle[CompStateStart[C] + S];
end;

function CompCaption(const C: Integer): String;
begin
  Result := CompTitle[C];
  if CompExperimental[C] then
    Result := Result + ' (experimental)';
end;

{ The short name of component C: its title up to " - " (was in backup.iss). }
function CompShortTitle(const C: Integer): String;
begin
  Result := CompTitle[C];
  if Pos(' - ', Result) > 0 then
    Result := Copy(Result, 1, Pos(' - ', Result) - 1);
end;

{ What a component is set to, in words (for the Ready page and the marker). }
function CompChoiceText(const C: Integer): String;
begin
  if CompKind[C] = 'C' then
    Result := CompStateTitle(C, ChosenState[C])
  else if CompOn(C) then
    Result := 'yes'
  else
    Result := 'no';
  { 2026-10-03: the DLL component switched on because the selection needs it }
  if (C = WALL_DLL_COMP) and DllAuto and CompOn(C) then
    Result := Result + ' (added automatically: ' + DllReason + ')';
end;

{ A switch value for component C: one of its state codes (any letter case);
  toggles also take 0/1/yes/no/true/false/on/off; choices also take the
  state's number (v6.4: /INFDUR=2 = V2) and off. }
function ParseStateCode(const C: Integer; const Value: String; var S: Integer): Boolean;
var
  V: String;
  I: Integer;
begin
  Result := True;
  V := Lowercase(Trim(Value));
  for I := 0 to CompStateCount[C] - 1 do
    if V = Lowercase(CompStateCode(C, I)) then begin
      S := I;
      Exit;
    end;
  if CompKind[C] = 'C' then begin
    if V = 'off' then begin
      S := 0;
      Exit;
    end;
    I := StrToIntDef(V, -1);
    if (I >= 0) and (I < CompStateCount[C]) and (IntToStr(I) = V) then begin
      S := I;
      Exit;
    end;
  end else begin
    if (V = '0') or (V = 'no') or (V = 'false') or (V = 'off') then begin
      S := 0;
      Exit;
    end;
    if ((V = '1') or (V = 'yes') or (V = 'true') or (V = 'on')) and (CompStateCount[C] >= 2) then begin
      S := 1;
      Exit;
    end;
  end;
  Result := False;
end;

{ 'none, v1, v2' - the codes a switch of component C takes. }
function CompCodeList(const C: Integer): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to CompStateCount[C] - 1 do begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + CompStateCode(C, I);
  end;
end;

{ ------------------------------------------------------------- the key rule --- }

{ key = sum state(AffComp[start + i]) * stride_i, stride_0 = 1,
  stride_(i+1) = stride_i * CompStateCount[AffComp[start + i]] }
function PathKey(const P: Integer): Integer;
var
  I, C, Stride: Integer;
begin
  Result := 0;
  Stride := 1;
  for I := 0 to PathAffCount[P] - 1 do begin
    C := AffComp[PathAffStart[P] + I];
    Result := Result + ChosenState[C] * Stride;
    Stride := Stride * CompStateCount[C];
  end;
end;

{ The variant path P must hold for the selection: >= 0 a variant, PT_ABSENT
  (the file must not exist) or PT_LEAVE (left as it is). }
function DesiredVariant(const P: Integer): Integer;
begin
  Result := PathTab[PathTabStart[P] + PathKey(P)];
end;

function PathIsUserConfig(const P: Integer): Boolean;
begin
  Result := Pos('U', PathFlags[P]) > 0;
end;

function PathIndexOf(const Rel: String): Integer;
var
  P: Integer;
begin
  Result := -1;
  for P := 0 to PathCount - 1 do
    if CompareText(PathRel[P], Rel) = 0 then begin
      Result := P;
      Exit;
    end;
end;

{ Every relative path the catalog writes, removes or edits must stay inside
  the Convergence folder (IsSafeRelPath). The pipeline checks this too
  (checks.catalog_checks); this is the installer's own guard, run once at
  start-up. '' = fine, else the first bad path. }
function CatalogPathsProblem: String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to PathCount - 1 do
    if not IsSafeRelPath(PathRel[I]) then begin
      Result := PathRel[I];
      Exit;
    end;
  for I := 0 to GetArrayLength(ObsRel) - 1 do
    if not IsSafeRelPath(ObsRel[I]) then begin
      Result := ObsRel[I];
      Exit;
    end;
  for I := 0 to GetArrayLength(FieldRel) - 1 do
    if not IsSafeRelPath(FieldRel[I]) then begin
      Result := FieldRel[I];
      Exit;
    end;
  if not IsSafeRelPath(CAT_CHANGELOG_REL) then
    Result := CAT_CHANGELOG_REL;
end;

{ The sha256 a variant must have: the catalog's, or for a dynamic variant
  the one of the archive member accepted in this run ('' = not known: the
  file is then only checked for existence). }
function VariantSha(const K: Integer): String;
begin
  Result := VarSha[K];
  if Result = '' then
    Result := VarShaRt[K];
end;

{ True when the file at variant K's path already holds it: same size and
  sha256; a dynamic variant without a known sha256 and a user config file:
  the file exists. }
function VariantInPlace(const K: Integer): Boolean;
var
  Full, Sha: String;
begin
  Full := ConvPath(PathRel[VarPath[K]]);
  if PathIsUserConfig(VarPath[K]) then begin
    Result := FileExists(Full);
    Exit;
  end;
  Sha := VariantSha(K);
  if Sha = '' then
    Result := FileExists(Full)
  else
    Result := FileHasSHA256(Full, Sha, VarSize[K]);
end;

{ ------------------------------------------------------------- selection --- }

{ Sizes every run-time array and sets the selection to its starting point:
  R = 1, X = 0, everything else its catalog default. }
procedure InitRuntimeArrays;
var
  I: Integer;
begin
  SetArrayLength(ChosenState, CompCount);
  SetArrayLength(ChosenExplicit, CompCount);
  SetArrayLength(DetectedState, CompCount);
  SetArrayLength(ParamComp, CompCount);
  for I := 0 to CompCount - 1 do begin
    ChosenExplicit[I] := False;
    DetectedState[I] := -1;
    ParamComp[I] := '';
  end;
  SetArrayLength(VarShaRt, VarCount);
  SetArrayLength(VarSkip, VarCount);
  SetArrayLength(VarSrcPath, VarCount);
  for I := 0 to VarCount - 1 do begin
    VarShaRt[I] := '';
    VarSkip[I] := False;
    VarSrcPath[I] := '';
  end;
  SetArrayLength(MemPath, MemCount);
  for I := 0 to MemCount - 1 do
    MemPath[I] := '';
  SetArrayLength(ArchState, ArchCount);
  SetArrayLength(ArchNeeded, ArchCount);
  SetArrayLength(ArchSource, ArchCount);
  SetArrayLength(ArchProblem, ArchCount);
  SetArrayLength(ArchNeedNote, ArchCount);
  SetArrayLength(ArchWorkDir, ArchCount);
  SetArrayLength(ArchPinned, ArchCount);
  SetArrayLength(ArchTested, ArchCount);
  SetArrayLength(ArchSearchedFor, ArchCount);
  SetArrayLength(ParamArch, ArchCount);
  for I := 0 to ArchCount - 1 do begin
    ArchState[I] := AS_NOTNEEDED;
    ArchNeeded[I] := False;
    ArchSource[I] := '';
    ArchProblem[I] := '';
    ArchNeedNote[I] := '';
    ArchWorkDir[I] := '';
    ArchPinned[I] := False;
    ArchTested[I] := False;
    ArchSearchedFor[I] := '';
    ParamArch[I] := '';
  end;
  SetArrayLength(BlobPath, BlobCount);
  SetArrayLength(BlobNeeded, BlobCount);
  for I := 0 to BlobCount - 1 do begin
    BlobPath[I] := '';
    BlobNeeded[I] := False;
  end;
  SetArrayLength(PathDelete, PathCount);
  SetArrayLength(PathKeepForeign, PathCount);
  SetArrayLength(PathForeignFile, PathCount);
  for I := 0 to PathCount - 1 do begin
    PathDelete[I] := False;
    PathKeepForeign[I] := False;
    PathForeignFile[I] := False;
  end;
  SetArrayLength(ObsDelete, GetArrayLength(ObsRel));
  for I := 0 to GetArrayLength(ObsRel) - 1 do
    ObsDelete[I] := False;
  SetArrayLength(FieldValue, FieldCount);
  SetArrayLength(FieldGiven, FieldCount);
  SetArrayLength(FieldWrite, FieldCount);
  for I := 0 to FieldCount - 1 do begin
    FieldValue[I] := '';
    FieldGiven[I] := False;
    FieldWrite[I] := False;
  end;
  SetArrayLength(RuleWarnings, 0);
  SetArrayLength(RuleNotes, 0);
  SetArrayLength(Me3OtherBefore, ME3_PROFILE_COUNT);
  SetArrayLength(Me3ChangedNow, ME3_PROFILE_COUNT);
  for I := 0 to ME3_PROFILE_COUNT - 1 do begin
    Me3OtherBefore[I] := '';
    Me3ChangedNow[I] := False;
  end;
  UnpackCapBytes := 0;
  UnpackCapHit := False;
  SearchUnpack := False;
end;

{ The catalog defaults (no detection, no command line). }
procedure ResetSelection;
var
  C: Integer;
begin
  DllAuto := False;
  DllOwn := 0;
  DllReason := '';
  for C := 0 to CompCount - 1 do begin
    ChosenExplicit[C] := False;
    if CompKind[C] = 'R' then
      ChosenState[C] := 1
    else if CompKind[C] = 'X' then
      ChosenState[C] := 0
    else
      ChosenState[C] := CompDefault[C];
    if (ChosenState[C] < 0) or (ChosenState[C] >= CompStateCount[C]) then
      ChosenState[C] := 0;
  end;
end;

{ 'main=1 conv=1 ... infdur=v2' (Sep ' ', Eq '=') or 'main:1,conv:1,...'. }
function SelectionText(const Sep, Eq: String): String;
var
  C: Integer;
begin
  Result := '';
  for C := 0 to CompCount - 1 do begin
    if C > 0 then
      Result := Result + Sep;
    Result := Result + CompId[C] + Eq + CompStateCode(C, ChosenState[C]);
  end;
end;

{ ------------------------------------------------------------- detection --- }

{ The active lines of both .me3 profiles of Dir, squeezed, one per line. }
function Me3SqueezedText(const Dir: String): String;
var
  Lines: TArrayOfString;
  I, J: Integer;
begin
  Result := #10;
  for I := 0 to ME3_PROFILE_COUNT - 1 do
    if LoadStringsFromFile(AddBackslash(Dir) + Me3Profile[I], Lines) then
      for J := 0 to GetArrayLength(Lines) - 1 do
        if Me3IsActiveLine(Lines[J]) then
          Result := Result + Me3Squeeze(Lines[J]) + #10;
end;

function DetRuleMatches(const D: Integer; const Me3Text: String): Boolean;
begin
  Result := False;
  if DetKind[D] = 'F' then
    Result := FileExists(ConvPath(DetArg[D]))
  else if DetKind[D] = 'N' then
    Result := Pos(Me3Squeeze(DetArg[D]), Me3Text) > 0
  else if DetKind[D] = 'H' then
    Result := FileExists(ConvPath(DetArg[D])) and
      (CompareText(FileSha256(ConvPath(DetArg[D])), DetSha[D]) = 0);
end;

{ What the Convergence folder has now: the first matching detection rule of
  each component (array order) sets DetectedState; none = -1. }
procedure DetectInstalledStates;
var
  D, C: Integer;
  Me3Text: String;
begin
  for C := 0 to CompCount - 1 do
    DetectedState[C] := -1;
  if ConvDir = '' then
    Exit;
  Me3Text := Me3SqueezedText(ConvDir);
  for D := 0 to GetArrayLength(DetComp) - 1 do begin
    C := DetComp[D];
    if (C < 0) or (C >= CompCount) or (DetectedState[C] >= 0) then
      Continue;
    if (DetState[D] < 0) or (DetState[D] >= CompStateCount[C]) then
      Continue;
    if DetRuleMatches(D, Me3Text) then begin
      DetectedState[C] := DetState[D];
      Log(Format('Detection: %s = %s (rule %d: %s %s)', [CompId[C], CompStateCode(C, DetState[D]), D,
        DetKind[D], DetArg[D]]));
    end;
  end;
end;

{ ---------------------------------------------- selection from the command line --- }

{ /COMPONENTS= (alias /SELECT=): "id" (state 1) or "id:code", comma
  separated; every optional component not listed is set to 0; "none" = all
  optional components off. }
function ApplyComponentsParam(var Problem: String): Boolean;
var
  Parts: TArrayOfString;
  I, C, P, S: Integer;
  Item, Id, Code: String;
begin
  Result := True;
  Problem := '';
  if ParamComponents = '' then
    Exit;
  { not listed = off, but not "given explicitly": a rule or the animation
    wall may still switch it on (only a named state is never overruled) }
  for C := 0 to CompCount - 1 do
    if CompIsOptional(C) then begin
      ChosenState[C] := 0;
      ChosenExplicit[C] := False;
    end;
  if CompareText(Trim(ParamComponents), 'none') = 0 then
    Exit;
  SplitStr(ParamComponents, ',', Parts);
  for I := 0 to GetArrayLength(Parts) - 1 do begin
    Item := Trim(Parts[I]);
    if Item = '' then
      Continue;
    P := Pos(':', Item);
    if P > 0 then begin
      Id := Trim(Copy(Item, 1, P - 1));
      Code := Copy(Item, P + 1, Length(Item));
      Code := Trim(Code);
    end else begin
      Id := Item;
      Code := '';
    end;
    C := CompIndexOf(Id);
    if C < 0 then begin
      Problem := 'Unknown component "' + Id + '" in /COMPONENTS. Known: ';
      for P := 0 to CompCount - 1 do begin
        if P > 0 then
          Problem := Problem + ', ';
        Problem := Problem + CompId[P];
      end;
      Problem := Problem + '.';
      Result := False;
      Exit;
    end;
    if Code = '' then
      S := 1
    else if not ParseStateCode(C, Code, S) then begin
      Problem := 'Invalid value "' + Code + '" for ' + CompId[C] + ' in /COMPONENTS. Use ' +
        CompCodeList(C) + '.';
      Result := False;
      Exit;
    end;
    if S >= CompStateCount[C] then begin
      Problem := CompId[C] + ' has no state ' + IntToStr(S) + '. Use ' + CompCodeList(C) + '.';
      Result := False;
      Exit;
    end;
    if (CompKind[C] = 'X') and (S <> 0) then begin
      Problem := CompTitle[C] + ' is not available in this version (' + CompId[C] + ' in /COMPONENTS).';
      Result := False;
      Exit;
    end;
    if (CompKind[C] = 'R') and (S <> 1) then begin
      Problem := CompTitle[C] + ' is always installed; it cannot be switched off (' + CompId[C] +
        ' in /COMPONENTS).';
      Result := False;
      Exit;
    end;
    ChosenState[C] := S;
    ChosenExplicit[C] := True;
  end;
end;

{ /<CompSwitch>=<code> per component (they win over /COMPONENTS). }
function ApplyComponentSwitches(var Problem: String): Boolean;
var
  C, S: Integer;
begin
  Result := True;
  Problem := '';
  for C := 0 to CompCount - 1 do begin
    if (CompSwitch[C] = '') or (ParamComp[C] = '') then
      Continue;
    if not ParseStateCode(C, ParamComp[C], S) then begin
      Problem := 'Invalid /' + CompSwitch[C] + ' value "' + ParamComp[C] + '". Use ' + CompCodeList(C) + '.';
      Result := False;
      Exit;
    end;
    if (CompKind[C] = 'X') and (S <> 0) then begin
      Problem := CompTitle[C] + ' is not available in this version, so /' + CompSwitch[C] + '=' +
        ParamComp[C] + ' cannot be used.';
      Result := False;
      Exit;
    end;
    if (CompKind[C] = 'R') and (S <> 1) then begin
      Problem := CompTitle[C] + ' is always installed; /' + CompSwitch[C] + '=' + ParamComp[C] +
        ' cannot switch it off.';
      Result := False;
      Exit;
    end;
    ChosenState[C] := S;
    ChosenExplicit[C] := True;
  end;
end;

{ The SELECTION= value of the newest backup of Dir (highest SEQ, then the
  folder name, as backup.iss ListBackupDirs orders them) when that backup
  folder still holds its run journal (RUN_JOURNAL_NAME): the run that made
  it changed the folder and was stopped hard before it finished (repair 5).
  '' when the newest backup's run finished, or there is none. Stamp = that
  backup folder's name. AutoOn = that backup's AUTO_ON= value (the ids its run
  switched on only because its selection needed them; 2026-10-03). }
function InterruptedRunSelection(const Dir: String; var Stamp, AutoOn: String): String;
var
  FR: TFindRec;
  Root, D, Sel, Auto, BestName: String;
  Lines: TArrayOfString;
  I, Seq, BestSeq: Integer;
begin
  Result := '';
  Stamp := '';
  AutoOn := '';
  if Dir = '' then
    Exit;
  Root := AddBackslash(Dir) + BACKUP_ROOT_NAME;
  BestSeq := -1;
  BestName := '';
  if not FindFirst(AddBackslash(Root) + '*', FR) then
    Exit;
  try
    repeat
      if ((FR.Attributes and FA_DIRECTORY) = 0) or (FR.Name = '.') or (FR.Name = '..') then
        Continue;
      D := AddBackslash(Root) + FR.Name;
      if not LoadStringsFromFile(AddBackslash(D) + BACKUP_MANIFEST_NAME, Lines) or (GetArrayLength(Lines) = 0) then
        Continue;
      if (Trim(Lines[0]) <> BACKUP_MANIFEST_MAGIC) and (Trim(Lines[0]) <> BACKUP_MANIFEST_MAGIC_2) then
        Continue;
      Seq := 0;
      Sel := '';
      Auto := '';
      for I := 1 to GetArrayLength(Lines) - 1 do begin
        if StartsWithStr(Lines[I], 'SEQ=') then
          Seq := StrToIntDef(Copy(Lines[I], 5, Length(Lines[I])), 0)
        else if StartsWithStr(Lines[I], 'SELECTION=') then
          Sel := Copy(Lines[I], 11, Length(Lines[I]))
        else if StartsWithStr(Lines[I], 'AUTO_ON=') then
          Auto := Copy(Lines[I], 9, Length(Lines[I]));
      end;
      if (Seq > BestSeq) or ((Seq = BestSeq) and (CompareText(FR.Name, BestName) > 0)) then begin
        BestSeq := Seq;
        BestName := FR.Name;
        Stamp := FR.Name;
        if FileExists(AddBackslash(D) + RUN_JOURNAL_NAME) then begin
          Result := Trim(Sel);
          AutoOn := Trim(Auto);
        end else begin
          Result := '';
          AutoOn := '';
        end;
      end;
    until not FindNext(FR);
  finally
    FindClose(FR);
  end;
  if Result = '' then begin
    Stamp := '';
    AutoOn := '';
  end;
end;

{ The value of the machine line Key= of the earlier run's marker (read by
  ReadPreviousMarker before the presets); '' when it has none. }
function PrevMarkerLineValue(const Key: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(PrevMarkerLines) - 1 do
    if StartsWithStr(PrevMarkerLines[I], Key + '=') then begin
      Result := Trim(Copy(PrevMarkerLines[I], Length(Key) + 2, Length(PrevMarkerLines[I])));
      Exit;
    end;
end;

{ Sets the optional components to the states of a saved selection
  ("id:code,id:code,..."; unknown ids, R and X components and codes that
  are no state are skipped). }
procedure ApplySavedSelection(const Sel: String);
var
  Parts: TArrayOfString;
  I, C, P, S: Integer;
  Id, Code: String;
begin
  SplitStr(Sel, ',', Parts);
  for I := 0 to GetArrayLength(Parts) - 1 do begin
    P := Pos(':', Parts[I]);
    if P = 0 then
      Continue;
    Id := Trim(Copy(Parts[I], 1, P - 1));
    Code := Copy(Parts[I], P + 1, Length(Parts[I]));
    Code := Trim(Code);
    C := CompIndexOf(Id);
    if (C < 0) or not CompIsOptional(C) then
      Continue;
    if ParseStateCode(C, Code, S) and (S >= 0) and (S < CompStateCount[C]) then
      ChosenState[C] := S;
  end;
end;

{ The presets for the chosen folder: catalog defaults, then what the folder
  has now (detection) - or, when the last run in this folder was stopped
  hard before it finished (its run journal is still in its backup folder),
  the options of that run (repair 5: a half-finished folder may show a mix
  of both selections to the detection) -, then the command line. Problem:
  an invalid command line value (the presets are made without it). }
function ApplySelectionPresets(var Problem: String): Boolean;
var
  C: Integer;
  Sel, Stamp, AutoOn, RunAutoOn: String;
begin
  ResetSelection;
  DetectInstalledStates;
  for C := 0 to CompCount - 1 do
    if CompIsOptional(C) and (DetectedState[C] >= 0) then
      ChosenState[C] := DetectedState[C];
  { what the last finished run switched on only because its selection needed it (2026-10-03) }
  AutoOn := PrevMarkerLineValue('AUTO_ON');
  Sel := InterruptedRunSelection(ConvDir, Stamp, RunAutoOn);
  InterruptedRunStamp := '';
  if Sel <> '' then begin
    ApplySavedSelection(Sel);
    AutoOn := RunAutoOn;
    InterruptedRunStamp := Stamp;
    Log('CXCXM RESUME ' + Stamp + ' ' + Sel);
    Log('The last run in this folder (backup ' + Stamp + ') was stopped before it finished; its options are ' +
      'preselected');
  end;
  { the DLL component the last run added by itself (a D rule or the animation
    wall) is not the player's own choice: its preset is off, and a selection
    that still needs it switches it on again (NormalizeSelection). So a run
    that drops DMN or Nightreign Movement removes ERCapacityExpansion, unless
    the player had ticked it himself (then the run wrote no AUTO_ON). }
  C := WALL_DLL_COMP;
  if (C >= 0) and CompIsOptional(C) and CompOn(C) and CommaListHas(AutoOn, CompId[C]) then begin
    ChosenState[C] := 0;
    Log('Presets: ' + CompId[C] + ' was added automatically by the last run (AUTO_ON=' + AutoOn + '), not ticked by ' +
      'you: preset off (switched on again while the selection needs it)');
  end;
  Result := ApplyComponentsParam(Problem);
  if Result then
    Result := ApplyComponentSwitches(Problem);
  SelectionPresetFor := ConvDir;
  Log('Presets for ' + ConvDir + ': ' + SelectionText(' ', '='));
end;

{ "Installed in this folder now: ..." (the optional components detected on). }
function InstalledNowText: String;
var
  C, P: Integer;
  S, Title: String;
begin
  S := '';
  for C := 0 to CompCount - 1 do
    if CompIsOptional(C) and (DetectedState[C] >= 1) then begin
      if S <> '' then
        S := S + ', ';
      { short: the title up to " - ", a choice's state code (Infinite Durations V2) }
      Title := CompTitle[C];
      P := Pos(' - ', Title);
      if P > 0 then
        Title := Copy(Title, 1, P - 1);
      if CompKind[C] = 'C' then
        S := S + Title + ' ' + Uppercase(CompStateCode(C, DetectedState[C]))
      else
        S := S + Title;
    end;
  if S = '' then
    Result := 'Installed in this folder now: none of the options.'
  else
    Result := 'Installed in this folder now: ' + S + '.';
end;

{ ---------------------------------------------------------- normalisation --- }

function StateInMask(const C, Mask: Integer): Boolean;
begin
  Result := ((Mask shr ChosenState[C]) and 1) = 1;
end;

function LowestStateInMask(const C, Mask: Integer): Integer;
var
  S: Integer;
begin
  Result := -1;
  for S := 0 to CompStateCount[C] - 1 do
    if ((Mask shr S) and 1) = 1 then begin
      Result := S;
      Exit;
    end;
end;

procedure AddNote(var A: TArrayOfString; const S: String);
var
  N: Integer;
begin
  N := GetArrayLength(A);
  SetArrayLength(A, N + 1);
  A[N] := S;
end;

function CurrentWallTotal: Integer;
var
  C, I, Idx, Radix: Integer;
  InCombo: Boolean;
begin
  if GetArrayLength(WallComboTotal) > 0 then begin
    { the measured total of this combination of the animation-touching
      options (exact), plus the deltas of every other option }
    Idx := 0;
    Radix := 1;
    for I := 0 to GetArrayLength(WallComboComp) - 1 do begin
      C := WallComboComp[I];
      Idx := Idx + ChosenState[C] * Radix;
      Radix := Radix * CompStateCount[C];
    end;
    Result := WallComboTotal[Idx];
    for C := 0 to CompCount - 1 do begin
      InCombo := False;
      for I := 0 to GetArrayLength(WallComboComp) - 1 do
        if WallComboComp[I] = C then
          InCombo := True;
      if not InCombo then
        Result := Result + StateWall[CompStateStart[C] + ChosenState[C]];
    end;
    Exit;
  end;
  Result := WALL_BASE;
  for C := 0 to CompCount - 1 do
    Result := Result + StateWall[CompStateStart[C] + ChosenState[C]];
end;

{ The limit without the DLL (test builds: /TESTWALLLIMIT=n replaces it). }
function WallLimitNoDll: Integer;
begin
  Result := WALL_LIMIT_NODLL;
#if Defined(CodeCheck) || Defined(TestBuild)
  if CmdParam('TESTWALLLIMIT') <> '' then begin
    Result := StrToIntDef(CmdParam('TESTWALLLIMIT'), WALL_LIMIT_NODLL);
    Log('TESTWALLLIMIT: the limit without the DLL is ' + IntToStr(Result));
  end;
#endif
end;

{ 2026-10-03: back to the player's own state of the DLL component (undoes a
  switch-on of this run that only the selection needed, so the next check
  starts from what the player chose). }
procedure DllTakeOwnChoice;
var
  Dll: Integer;
begin
  Dll := WALL_DLL_COMP;
  if Dll < 0 then
    Exit;
  if DllAuto then
    ChosenState[Dll] := DllOwn
  else
    DllOwn := ChosenState[Dll];
  DllAuto := False;
  DllReason := '';
end;

{ Why the current selection needs the DLL component: the text of the first D
  rule whose two sides hold, else the animation wall's reason when the slots
  exceed the limit without the DLL. '' = it does not need it. }
function DllNeededReason: String;
var
  R, Total, Limit: Integer;
begin
  Result := '';
  if (WALL_DLL_COMP < 0) or (CompKind[WALL_DLL_COMP] <> 'T') then
    Exit;
  for R := 0 to GetArrayLength(RuleKind) - 1 do
    if (RuleKind[R] = 'D') and StateInMask(RuleA[R], RuleAMask[R]) and StateInMask(RuleB[R], RuleBMask[R]) then begin
      Result := RuleText[R];
      Exit;
    end;
  Total := CurrentWallTotal;
  Limit := WallLimitNoDll;
  if Total > Limit then
    Result := 'needed for your options'' animation slots';
end;

{ The marker's / backup manifest's AUTO_ON= value: the DLL component's id
  when this run switched it on only because the selection needs it. }
function AutoOnText: String;
begin
  Result := '';
  if (WALL_DLL_COMP >= 0) and DllAuto and CompOn(WALL_DLL_COMP) then
    Result := CompId[WALL_DLL_COMP];
end;

{ Q rules until nothing changes. False (Problem) when a rule cannot be met. }
function ApplyRequireRules(const Silent: Boolean; var Problem: String): Boolean;
var
  Pass, R, A, B, S: Integer;
  Changed: Boolean;
begin
  Result := True;
  for Pass := 1 to 8 do begin
    Changed := False;
    for R := 0 to GetArrayLength(RuleKind) - 1 do begin
      if RuleKind[R] <> 'Q' then
        Continue;
      A := RuleA[R];
      B := RuleB[R];
      if not StateInMask(A, RuleAMask[R]) or StateInMask(B, RuleBMask[R]) then
        Continue;
      S := LowestStateInMask(B, RuleBMask[R]);
      if (S < 0) or (CompKind[B] = 'X') or ((CompKind[B] = 'R') and (S <> 1)) then begin
        Problem := RuleText[R];
        Log('CXCXM RULE Q ' + RuleText[R] + ' (cannot be met)');
        Result := False;
        Exit;
      end;
      if Silent and ChosenExplicit[B] then begin
        Problem := RuleText[R] + #13#10 + 'The command line set ' + CompId[B] + ' to ' +
          CompStateCode(B, ChosenState[B]) + ', which this rule does not allow.';
        Log('CXCXM RULE Q ' + RuleText[R] + ' (refused: ' + CompId[B] + ' was given explicitly)');
        Result := False;
        Exit;
      end;
      ChosenState[B] := S;
      Changed := True;
      AddNote(RuleNotes, RuleText[R] + ' (' + CompTitle[B] + ' was set to ' + CompStateTitle(B, S) + ')');
      Log('CXCXM RULE Q ' + RuleText[R] + ' (' + CompId[B] + ' set to ' + CompStateCode(B, S) + ')');
    end;
    if not Changed then
      Exit;
  end;
end;

{ Contract 5.2: rules and the animation wall. Silent: an explicit command
  line value is never overruled (refused instead). Logs CXCXM RULE / WALL /
  SELECTION. False (Problem) = the selection cannot be installed. }
function NormalizeSelection(const Silent: Boolean; var Problem: String): Boolean;
var
  R, Dll, Total, Limit: Integer;
begin
  Result := False;
  Problem := '';
  SetArrayLength(RuleWarnings, 0);
  SetArrayLength(RuleNotes, 0);
  { 2026-10-03: start from the player's own state of the DLL component (a
    second check after the Options page must not take this run's own
    switch-on for the player's choice) }
  DllTakeOwnChoice;
  if not ApplyRequireRules(Silent, Problem) then
    Exit;

  Dll := WALL_DLL_COMP;
  { D rules (2026-10-03): two options that together need the DLL component
    (DMN + Nightreign's Wylder need ERCapacityExpansion): switched on by
    itself, its text is the reason; an explicit off on the command line is
    refused, as for the animation wall }
  if Dll >= 0 then
    for R := 0 to GetArrayLength(RuleKind) - 1 do begin
      if (RuleKind[R] <> 'D') or not (StateInMask(RuleA[R], RuleAMask[R]) and StateInMask(RuleB[R], RuleBMask[R])) then
        Continue;
      if DllReason = '' then
        DllReason := RuleText[R];
      if CompOn(Dll) then
        Continue;
      if CompKind[Dll] = 'X' then begin
        Problem := CompShortTitle(RuleA[R]) + ' together with ' + CompShortTitle(RuleB[R]) + ' need ' +
          CompShortTitle(Dll) + ', which is not available in this version. Switch one of them off.';
        Log('CXCXM RULE D ' + RuleText[R] + ' (cannot be met: ' + CompId[Dll] + ' is not available)');
        Exit;
      end;
      if Silent and ChosenExplicit[Dll] then begin
        Problem := Format('%s is %s (%s and %s are both on), but the command line switches it off (%s=%s). ' +
          'Leave %s out of the command line - Setup adds it by itself - or switch one of the two options off.', [
          CompShortTitle(Dll), RuleText[R], CompShortTitle(RuleA[R]), CompShortTitle(RuleB[R]), CompId[Dll],
          CompStateCode(Dll, ChosenState[Dll]), CompId[Dll]]);
        Log('CXCXM RULE D ' + RuleText[R] + ' (refused: ' + CompId[Dll] + ' was given explicitly)');
        Exit;
      end;
      ChosenState[Dll] := 1;
      DllAuto := True;
      AddNote(RuleNotes, CompShortTitle(Dll) + ' was switched on automatically: ' + RuleText[R] + '.');
      Log('CXCXM RULE D ' + RuleText[R] + ' (' + CompId[Dll] + ' switched on)');
      if not ApplyRequireRules(Silent, Problem) then
        Exit;
    end;

  { the animation wall }
  Limit := WallLimitNoDll;
  Total := CurrentWallTotal;
  if (Total > Limit) and ((Dll < 0) or not CompOn(Dll)) then begin
    if (Dll < 0) or (CompKind[Dll] = 'X') then begin
      Problem := Format('The chosen options need %s animation slots, but the game has only %s. ' +
        'Switch some options off.', [FormatThousands(Total), FormatThousands(Limit)]);
      Log(Format('CXCXM WALL total=%d limit=%d dll=off (refused: no DLL component)', [Total, Limit]));
      Exit;
    end;
    if Silent and ChosenExplicit[Dll] then begin
      Problem := Format('The chosen options need %s animation slots, more than the game''s %s, so %s ' +
        'is required; /%s=%s switches it off. Leave /%s out, or switch some options off.', [
        FormatThousands(Total), FormatThousands(Limit), CompTitle[Dll], CompSwitch[Dll],
        CompStateCode(Dll, ChosenState[Dll]), CompSwitch[Dll]]);
      Log(Format('CXCXM WALL total=%d limit=%d dll=off (refused: switched off explicitly)', [Total, Limit]));
      Exit;
    end;
    ChosenState[Dll] := 1;
    DllAuto := True;
    if DllReason = '' then
      DllReason := DllNeededReason;
    AddNote(RuleNotes, Format('The chosen options need %s animation slots, more than the game''s %s: %s was ' +
      'switched on.', [FormatThousands(Total), FormatThousands(Limit), CompTitle[Dll]]));
    Log('CXCXM RULE Q the animation wall needs ' + CompId[Dll] + ' (switched on)');
    if not ApplyRequireRules(Silent, Problem) then
      Exit;
    Total := CurrentWallTotal;
  end;
  { off | on (the player's own) | forced (switched on because the selection needs it) }
  WallDllText := 'off';
  if (Dll >= 0) and CompOn(Dll) then begin
    if DllAuto then
      WallDllText := 'forced'
    else
      WallDllText := 'on';
  end;
  if (Dll >= 0) and DllAuto then
    Log('CXCXM AUTO_ON ' + CompId[Dll] + ' (' + DllReason + ')');
  if (Dll >= 0) and CompOn(Dll) then begin
    Limit := WALL_LIMIT_DLL;
    if Total > Limit then begin
      Problem := Format('The chosen options need %s animation slots, more than %s can give (%s). Switch ' +
        'some options off.', [FormatThousands(Total), CompTitle[Dll], FormatThousands(Limit)]);
      Log(Format('CXCXM WALL total=%d limit=%d dll=%s (refused: above the DLL limit)', [Total, Limit, WallDllText]));
      Exit;
    end;
  end;
  WallTotal := Total;
  WallLimitUsed := Limit;
  Log(Format('CXCXM WALL total=%d limit=%d dll=%s', [Total, Limit, WallDllText]));

  { conflicts and warnings }
  for R := 0 to GetArrayLength(RuleKind) - 1 do begin
    if not (StateInMask(RuleA[R], RuleAMask[R]) and StateInMask(RuleB[R], RuleBMask[R])) then
      Continue;
    if RuleKind[R] = 'X' then begin
      Problem := RuleText[R];
      Log('CXCXM RULE X ' + RuleText[R]);
      Exit;
    end;
    if RuleKind[R] = 'W' then begin
      AddNote(RuleWarnings, RuleText[R]);
      Log('CXCXM RULE W ' + RuleText[R]);
    end;
  end;
  Log('CXCXM SELECTION ' + SelectionText(' ', '='));
  Result := True;
end;

{ "Animation slots: 31,519 of 32,768" for the current selection. }
function WallLineText: String;
var
  Total, Limit, Dll: Integer;
  T: String;
begin
  Total := CurrentWallTotal;
  Dll := WALL_DLL_COMP;
  if (Dll >= 0) and CompOn(Dll) then
    Limit := WALL_LIMIT_DLL
  else
    Limit := WallLimitNoDll;
  Result := 'Animation slots used: ' + FormatThousands(Total) + ' of ' + FormatThousands(Limit);
  if Total > Limit then begin
    if (Dll >= 0) and not CompOn(Dll) then begin
      { the component's short name (its title up to " - "; final pass: one line on the Options page) }
      T := CompTitle[Dll];
      if Pos(' - ', T) > 0 then
        T := Copy(T, 1, Pos(' - ', T) - 1);
      Result := Result + ' - too many: ' + T + ' will be switched on';
    end
    else
      Result := Result + ' - too many: switch some options off';
  end;
  Result := Result + '.';
end;

{ ------------------------------------------------------------------- marker --- }

{ Reads the folder's CXCXM_INSTALLED.txt of an earlier run (format 3: the
  machine-readable lines before the first blank line). }
procedure ReadPreviousMarker(const Dir: String);
var
  Lines: TArrayOfString;
  I: Integer;
begin
  PrevVerifiedArchives := '';
  SetArrayLength(PrevMarkerLines, 0);
  if (Dir = '') or not LoadStringsFromFile(AddBackslash(Dir) + MARKER_NAME, Lines) then
    Exit;
  if (GetArrayLength(Lines) = 0) or (Trim(Lines[0]) <> MARKER_MAGIC_3) then
    Exit;
  for I := 1 to GetArrayLength(Lines) - 1 do begin
    if Trim(Lines[I]) = '' then
      Break;
    AddNote(PrevMarkerLines, Lines[I]);
    if StartsWithStr(Lines[I], 'VERIFIED_ARCHIVES=') then
      PrevVerifiedArchives := Trim(Copy(Lines[I], Length('VERIFIED_ARCHIVES=') + 1, Length(Lines[I])));
  end;
  Log('Marker of an earlier run: VERIFIED_ARCHIVES=' + PrevVerifiedArchives);
end;

function PrevMarkerValue(const Key: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(PrevMarkerLines) - 1 do
    if StartsWithStr(PrevMarkerLines[I], Key + '=') then begin
      Result := Copy(PrevMarkerLines[I], Length(Key) + 2, Length(PrevMarkerLines[I]));
      Exit;
    end;
end;

{ ------------------------------------------------------------- command line --- }

{ Inno's own command line switches (never ours, never refused): the Setup
  and Uninstaller command lines of Inno Setup 6.7's help, and the internal
  ones Setup passes to itself. pipeline\catalog_src.py reads this list (and
  OurSwitchNames) from this file, so a catalog switch can never take one of
  these names (repair 3, code review LOW). }
function IsInnoSwitchName(const N: String): Boolean;
begin
  Result := (N = 'SILENT') or (N = 'VERYSILENT') or (N = 'SUPPRESSMSGBOXES') or (N = 'LOG') or
    (N = 'NOCANCEL') or (N = 'NORESTART') or (N = 'RESTARTEXITCODE') or (N = 'CLOSEAPPLICATIONS') or
    (N = 'NOCLOSEAPPLICATIONS') or (N = 'FORCECLOSEAPPLICATIONS') or (N = 'NOFORCECLOSEAPPLICATIONS') or
    (N = 'LOGCLOSEAPPLICATIONS') or (N = 'RESTARTAPPLICATIONS') or (N = 'NORESTARTAPPLICATIONS') or
    (N = 'LOADINF') or (N = 'SAVEINF') or (N = 'LANG') or (N = 'DIR') or (N = 'GROUP') or
    (N = 'NOGROUP') or (N = 'NOICONS') or (N = 'TYPE') or (N = 'TASKS') or (N = 'MERGETASKS') or
    (N = 'PASSWORD') or (N = 'ALLUSERS') or (N = 'CURRENTUSER') or (N = 'HELP') or (N = '?') or
    (N = 'SP-') or (N = 'SL5') or (N = 'SPAWNWND') or (N = 'NOTIFYWND') or (N = 'DEBUGWND') or
    (N = 'DETACHEDMSG') or (N = 'ENABLEPRIVILEGESREQUIREDOVERRIDE') or (N = 'ADMIN') or
    (N = 'RESTARTREPLACE') or (N = 'NOSTYLE') or (N = 'DARKMODE') or (N = 'REDIRECTIONGUARD') or
    (N = 'NOREDIRECTIONGUARD');
end;

{ Every switch name of ours (upper case) in Names. }
procedure OurSwitchNames(Names: TStringList);
var
  I: Integer;
begin
  Names.Add('CONVDIR');
  Names.Add('COMPONENTS');
  Names.Add('SELECT');
  Names.Add('ARCHIVEDIR');
  Names.Add('CLEVER');
  Names.Add('SEARCHDOWNLOADS');
  Names.Add('BASEURL');
  Names.Add('UPSTREAM');
  Names.Add('FOREIGN');
  Names.Add('GAMEOK');
  for I := 0 to CompCount - 1 do
    if CompSwitch[I] <> '' then
      Names.Add(Uppercase(CompSwitch[I]));
  for I := 0 to ArchCount - 1 do
    Names.Add('ARCHIVE_' + Uppercase(ArchId[I]));
  for I := 0 to FieldCount - 1 do
    if FieldSwitch[I] <> '' then
      Names.Add(Uppercase(FieldSwitch[I]));
#if Defined(CodeCheck) || Defined(TestBuild)
  Names.Add('TESTGAMEONLY');
  Names.Add('TESTGAMEBROWSE');
  Names.Add('TESTDLSEARCH');
  Names.Add('TESTCHECKSONLY');
  Names.Add('TESTLAYOUT');
  Names.Add('TESTLAYOUTEXES');
  Names.Add('TESTDOWNLOADS');
  Names.Add('TESTWALLLIMIT');
  Names.Add('TESTFETCHONLY');
  Names.Add('TESTSTEAM');
  Names.Add('TESTUNIT');
  Names.Add('TESTASADMIN');
  Names.Add('TESTME3EXE');
  Names.Add('TESTNOTAR');
#endif
#ifdef CodeCheck
  Names.Add('NOTAR');
  Names.Add('SCANONLY');
#endif
end;

{ Rejects options that look like ours but are misspelled (they would be
  ignored and the run would use defaults), and ours without a value.
  Returns '' when the command line is fine. }
function CheckCommandLineOptions: String;
var
  I, J, P: Integer;
  S, Name, Value, Known: String;
  Ours: TStringList;
begin
  Result := '';
  Ours := TStringList.Create;
  try
    OurSwitchNames(Ours);
    for I := 1 to ParamCount do begin
      S := Trim(ParamStr(I));
      if (Length(S) < 2) or ((S[1] <> '/') and (S[1] <> '-')) then
        Continue;
      Name := Uppercase(Copy(S, 2, Length(S)));
      Value := '';
      P := Pos('=', Name);
      if P > 0 then begin
        Value := Copy(S, P + 2, Length(S));      { assigned first: see SubStr in util.iss }
        Value := Trim(RemoveQuotes(Trim(Value)));
        Name := Copy(Name, 1, P - 1);
      end;
      if Ours.IndexOf(Name) >= 0 then begin
        if Value = '' then
          Result := 'The option ' + S + ' has no value. Write it as /' + Name + '=value.';
      end else if not IsInnoSwitchName(Name) then begin
        for J := 0 to Ours.Count - 1 do
          if (Length(Name) >= 3) and (Copy(Name, 1, 3) = Copy(Ours[J], 1, 3)) then begin
            Known := '';
            for P := 0 to Ours.Count - 1 do
              if not StartsWithStr(Ours[P], 'TEST') then begin
                if Known <> '' then
                  Known := Known + ', ';
                Known := Known + '/' + Ours[P] + '=';
              end;
            Result := 'Unknown option ' + S + '. The options of this installer are ' + Known + '.';
            Break;
          end;
      end;
      if Result <> '' then
        Exit;
    end;
  finally
    Ours.Free;
  end;
end;

{ Reads every switch of ours once (InitializeSetup). The values are checked
  by ValidateCommandLine. }
procedure ReadCommandLine;
var
  I, C: Integer;
  Found: Boolean;
begin
  ParamConvDir := CmdParam('CONVDIR');
  ParamComponents := CmdParam('COMPONENTS');
  if ParamComponents = '' then
    ParamComponents := CmdParam('SELECT');
  for I := 0 to CompCount - 1 do
    if CompSwitch[I] <> '' then
      ParamComp[I] := CmdParam(CompSwitch[I]);
  for I := 0 to ArchCount - 1 do begin
    ParamArch[I] := CmdParam('ARCHIVE_' + Uppercase(ArchId[I]));
    { /CLEVER= (v6.3/v6.4) = the archive of the component "clever" }
    C := ArchComp[I];
    if (ParamArch[I] = '') and (C >= 0) and (CompareText(CompId[C], 'clever') = 0) then
      ParamArch[I] := CmdParam('CLEVER');
  end;
  for I := 0 to FieldCount - 1 do
    if FieldSwitch[I] <> '' then
      FieldValue[I] := CmdParamEx(FieldSwitch[I], Found);
  for I := 0 to FieldCount - 1 do
    FieldGiven[I] := (FieldSwitch[I] <> '') and (CmdParam(FieldSwitch[I]) <> '');
  ParamArchiveDir := CmdParam('ARCHIVEDIR');
  ParamSearchDownloads := CmdParam('SEARCHDOWNLOADS');
  ParamBaseUrl := CmdParam('BASEURL');
  ParamUpstream := CmdParam('UPSTREAM');
  ParamForeign := CmdParam('FOREIGN');
  ParamGameOk := CmdParam('GAMEOK');
end;

{ The command line for our own log, with the values of secret fields
  (FieldSecret: the Seamless password) replaced by ***. Inno's own "Setup
  command line:" line at the top of every Setup log is written before any
  script code runs and cannot be changed: a /COOPPASSWORD= given on the
  command line is in it as typed (SetupLogging=yes, as v6.4, keeps a log of
  every wizard run for support; the wizard's password box is never logged).
  SecretSwitchNote says so in the log (repair 3, code review LOW). }
function MaskedCmdTail: String;
var
  I, F, P: Integer;
  S, Name: String;
  Secret: Boolean;
begin
  Result := '';
  for I := 1 to ParamCount do begin
    S := ParamStr(I);
    Name := Uppercase(Copy(S, 2, Length(S)));
    P := Pos('=', Name);
    if P > 0 then
      Name := Copy(Name, 1, P - 1);
    Secret := False;
    for F := 0 to FieldCount - 1 do
      if FieldSecret[F] and (FieldSwitch[F] <> '') and (Name = Uppercase(FieldSwitch[F])) then
        Secret := True;
    if Secret then begin
      S := Copy(S, 1, Pos('=', S));       { assigned first: see SubStr in util.iss }
      S := S + '***';
    end;
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + S;
  end;
end;

{ '' when no secret field's value came on the command line, else a note for
  the log: Inno's own command line line above holds it as typed. }
function SecretSwitchNote: String;
var
  F: Integer;
begin
  Result := '';
  for F := 0 to FieldCount - 1 do
    if FieldSecret[F] and FieldGiven[F] then
      Result := 'Note: /' + FieldSwitch[F] + '= was given on the command line. Inno Setup''s own "Setup command ' +
        'line:" line at the top of this log shows it as typed (the installer cannot change that line). Delete this ' +
        'log before you share it, or type the value in the wizard instead (never logged).';
end;

{ Forgets /COMPONENTS and every /<CompSwitch> (the wizard after a bad one). }
procedure ClearSelectionParams;
var
  C: Integer;
begin
  ParamComponents := '';
  for C := 0 to CompCount - 1 do
    ParamComp[C] := '';
end;

{ '' when /BASEURL= is absent or every '|'-separated part is an http:// or
  https:// address with a host, else why not. }
function BaseUrlParamProblem: String;
var
  Parts: TArrayOfString;
  I, N: Integer;
  U, L: String;
begin
  Result := '';
  if ParamBaseUrl = '' then
    Exit;
  SplitStr(ParamBaseUrl, '|', Parts);
  N := 0;
  for I := 0 to GetArrayLength(Parts) - 1 do begin
    U := Trim(Parts[I]);
    if U = '' then
      Continue;
    L := Lowercase(U);
    if StartsWithStr(L, 'https://') then
      L := Copy(L, 9, Length(L))
    else if StartsWithStr(L, 'http://') then
      L := Copy(L, 8, Length(L))
    else
      L := '';
    if (L = '') or (L[1] = '/') then begin
      Result := 'Invalid /BASEURL value "' + ParamBaseUrl + '". Give full addresses such as ' +
        'http://127.0.0.1:8080/ (several: separate them with |).';
      Exit;
    end;
    N := N + 1;
  end;
  if N = 0 then
    Result := 'Invalid /BASEURL value "' + ParamBaseUrl + '": no address in it.';
end;

{ /BASEURL= replaces the mirror list ('|' separates several). Only applied
  when it is valid (BaseUrlParamProblem): a refused value used to stay the
  only mirror in the wizard, where the switch is reported as ignored (code
  review repair 2, D8). }
procedure ApplyBaseUrlParam;
var
  Parts: TArrayOfString;
  I, N: Integer;
  U: String;
begin
  if (ParamBaseUrl = '') or (BaseUrlParamProblem <> '') then
    Exit;
  SplitStr(ParamBaseUrl, '|', Parts);
  SetArrayLength(BaseUrls, 0);
  N := 0;
  for I := 0 to GetArrayLength(Parts) - 1 do begin
    U := Trim(Parts[I]);
    if U = '' then
      Continue;
    if Copy(U, Length(U), 1) <> '/' then
      U := U + '/';
    SetArrayLength(BaseUrls, N + 1);
    BaseUrls[N] := U;
    N := N + 1;
  end;
  BaseUrlsReplaced := N > 0;
  Log('/BASEURL: the download mirrors are ' + JoinLines(BaseUrls, ' | ') + ' (for every download site)');
end;

function ParseBoolSwitch(const S: String; const Default: Boolean; var Value: Boolean): Boolean;
var
  V: String;
begin
  Result := True;
  V := Lowercase(Trim(S));
  if V = '' then
    Value := Default
  else if (V = '0') or (V = 'no') or (V = 'false') or (V = 'off') then
    Value := False
  else if (V = '1') or (V = 'yes') or (V = 'true') or (V = 'on') then
    Value := True
  else
    Result := False;
end;

function ParseForeign(const S: String; var Move: Boolean): Boolean;
var
  V: String;
begin
  Result := True;
  V := Lowercase(Trim(S));
  if (V = '') or (V = 'move') then
    Move := True
  else if V = 'keep' then
    Move := False
  else
    Result := False;
end;

{ Checks every value of ours. '' when fine. The selection switches are
  tried on the catalog defaults (the presets of the chosen folder come
  later, see ApplySelectionPresets). }
function ValidateCommandLine: String;
var
  Dummy: Boolean;
  Problem: String;
begin
  Result := CheckCommandLineOptions;
  if Result <> '' then
    Exit;
  ResetSelection;
  if not ApplyComponentsParam(Problem) then begin
    Result := Problem;
    Exit;
  end;
  if not ApplyComponentSwitches(Problem) then begin
    Result := Problem;
    Exit;
  end;
  ResetSelection;
  if not ParseForeign(ParamForeign, ForeignMove) then begin
    Result := 'Invalid /FOREIGN value "' + ParamForeign + '". Use move or keep.';
    Exit;
  end;
  if not ParseBoolSwitch(ParamGameOk, False, GameConfirmed) then begin
    Result := 'Invalid /GAMEOK value "' + ParamGameOk + '". Use 1 (or leave it out).';
    Exit;
  end;
  if not ParseBoolSwitch(ParamUpstream, True, UseUpstream) then begin
    Result := 'Invalid /UPSTREAM value "' + ParamUpstream + '". Use 0 or 1.';
    Exit;
  end;
  if not ParseBoolSwitch(ParamSearchDownloads, False, Dummy) then begin
    Result := 'Invalid /SEARCHDOWNLOADS value "' + ParamSearchDownloads + '". Use 0 or 1.';
    Exit;
  end;
  Result := BaseUrlParamProblem;
end;

{ /SEARCHDOWNLOADS=1: a silent run may search the Downloads folder too. }
function SilentSearchDownloads: Boolean;
var
  V: Boolean;
begin
  V := False;
  if not ParseBoolSwitch(ParamSearchDownloads, False, V) then
    V := False;
  Result := V;
end;
