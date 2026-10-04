{ =============================================================================
  archives.iss - the players' own downloads ("Wabbajack style"): the merge's
  main zip, Clever's and McKenyu's modpacks, Nightreign Movement, Seamless
  Co-op. The installer never carries their files: the catalog lists, per
  archive, the members it needs (file name + sha256, or for a mode V
  archive just the name) and the player provides the download.

  Needed (contract 5.3): the archive's component is on AND (a wanted variant
  taken from one of its members is not in place in the Convergence folder,
  OR the archive must be verified once per folder and the folder's marker
  does not list it under VERIFIED_ARCHIVES).

  Accepting (contract 5.4) a folder or an archive file:
    folder   every file below it (any depth, Convergence folders below the
             root are never entered) whose name is a member name is a
             candidate; a member is found when a candidate has its sha256
             (mode P; the size is compared first) or exists (mode V: the
             candidate whose path ends with the member's reference path
             wins; its sha256 becomes the expected content of every variant
             taken from it)
    archive  unpacked into <Conv>\CXCXM_work\a<index> (Setup's temp folder
             when the Convergence path is too long): Windows' tar.exe first,
             fed the archive on stdin (tar cannot open non-ASCII paths) and
             only the member names (ArchGlobs, case-insensitive patterns,
             given in a pattern file), then Inno's own extractor
             (ArchiveExtraction=full) for the whole archive; then checked
             like a folder
  An archive is accepted only when every member is found.
  Pinned whole-archive files (PinSize/PinSha) are recognised by size, then
  sha256: the download search tries them first, and a mode V archive that
  matches a pin is the tested version.
  ============================================================================= }

{ ----------------------------------------------------------------- basics --- }

function ArchCompOn(const A: Integer): Boolean;
begin
  Result := (ArchComp[A] >= 0) and (ArchComp[A] < CompCount) and CompOn(ArchComp[A]);
end;

function ArchIsModeV(const A: Integer): Boolean;
begin
  Result := ArchMode[A] = 'V';
end;

function ArchLabel(const A: Integer): String;
begin
  Result := ArchTitle[A];
end;

{ How many archives are needed and not accepted. }
function ArchivesMissingCount: Integer;
var
  A: Integer;
begin
  Result := 0;
  for A := 0 to ArchCount - 1 do
    if ArchNeeded[A] and (ArchState[A] <> AS_ACCEPTED) then
      Result := Result + 1;
end;

function ArchivesNeededCount: Integer;
var
  A: Integer;
begin
  Result := 0;
  for A := 0 to ArchCount - 1 do
    if ArchNeeded[A] then
      Result := Result + 1;
end;

{ ---------------------------------------------------------- work folder --- }

{ <Conv>\CXCXM_work (same drive as the target), or Setup's temp folder when
  the Convergence path leaves too little room for the archives' own paths. }
function WorkRoot: String;
begin
  if WorkDirRoot <> '' then begin
    Result := WorkDirRoot;
    Exit;
  end;
  Result := '';
  if (ConvDir <> '') and (Length(ConvDir) <= 120) then begin
    Result := ConvPath(WORK_DIR_NAME);
    if not ForceDirectories(Result) then begin
      Log('Cannot create ' + Result + '; the downloads are unpacked in Setup''s temp folder');
      Result := '';
    end;
  end;
  if Result = '' then begin
    Result := ExpandConstant('{tmp}\') + WORK_DIR_NAME;
    ForceDirectories(Result);
  end;
  WorkDirRoot := Result;
  Log('Work folder for the downloads: ' + WorkDirRoot);
end;

{ A fresh folder for one extraction of archive A: a name never used before
  in this run (a<index>_<n>). Reusing the name of a deleted folder let the
  hash cache (path + size + time) answer for the files of a DIFFERENT
  archive: tar and 7-Zip restore the members' times and pad a truncated
  member to its full size, so a good download unpacked after a damaged one
  was checked against the damaged one's hashes (verifier 1, defect D1). }
function NewWorkDir(const A: Integer): String;
begin
  repeat
    WorkCounter := WorkCounter + 1;
    Result := AddBackslash(WorkRoot) + 'a' + IntToStr(A) + '_' + IntToStr(WorkCounter);
  until not (DirExists(Result) or FileExists(Result));
  ShaCacheForgetUnder(Result);
  ForceDirectories(Result);
end;

{ Deletes one extraction folder; its files' cached hashes are forgotten. }
procedure DelWorkDir(const Dir: String);
begin
  if Dir = '' then
    Exit;
  ShaCacheForgetUnder(Dir);
  DelTree(Dir, True, True, True);
end;

{ Deletes the whole work folder (Setup's end, a new Convergence folder). }
procedure ReleaseWorkRoot;
begin
  if WorkDirRoot <> '' then begin
    Log('Deleting the work folder ' + WorkDirRoot);
    ShaCacheForgetUnder(WorkDirRoot);
    if not DelTree(WorkDirRoot, True, True, True) then
      Log('Could not delete ' + WorkDirRoot + ' completely');
  end;
  WorkDirRoot := '';
end;

{ A work folder an earlier Setup left behind in <Conv> (it crashed, or the
  PC was switched off) is never used again. }
procedure DeleteStaleWorkDir(const Dir: String);
begin
  if (Dir <> '') and DirExists(AddBackslash(Dir) + WORK_DIR_NAME) and
    not PathSame(AddBackslash(Dir) + WORK_DIR_NAME, WorkDirRoot) then
  begin
    Log('Deleting a work folder left by an earlier run: ' + AddBackslash(Dir) + WORK_DIR_NAME);
    DelWorkDir(AddBackslash(Dir) + WORK_DIR_NAME);
  end;
end;

{ -------------------------------------------------------- needed archives --- }

{ Contract 5.3. Hashes the files the members would give (cached, so the
  backup plan does not hash them again). }
procedure ComputeArchivesNeeded;
var
  A, P, K, M, Total: Integer;
  InPlace: array of Boolean;
begin
  SetArrayLength(InPlace, ArchCount);
  for A := 0 to ArchCount - 1 do begin
    ArchNeeded[A] := False;
    ArchNeedNote[A] := '';
    InPlace[A] := False;
  end;
  if ConvDir = '' then
    Exit;
  Total := PathCount;
  for P := 0 to Total - 1 do begin
    K := DesiredVariant(P);
    if (K < 0) or (VarSrc[K] <> 'A') then
      Continue;
    M := VarRef[K];
    A := MemArch[M];
    if ArchNeeded[A] or not ArchCompOn(A) then
      Continue;
    InPlace[A] := True;
    ProgressText(Format('Checking which downloads are needed (%d of %d)...', [P + 1, Total]), PathRel[P]);
    ProgressPos(P, Total);
    if not VariantInPlace(K) then begin
      ArchNeeded[A] := True;
      Log('Download needed: ' + ArchId[A] + ' (' + PathRel[P] + ' is not in place)');
    end;
  end;
  ProgressPos(Total, Total);
  for A := 0 to ArchCount - 1 do begin
    if ArchCompOn(A) and ArchMustVerify[A] and not ArchNeeded[A] and
      not CommaListHas(PrevVerifiedArchives, ArchId[A]) then
    begin
      ArchNeeded[A] := True;
      ArchNeedNote[A] := 'Setup checks this download once per Convergence folder, even when its files are ' +
        'already there (older versions of the merge carried them).';
      Log('Download needed: ' + ArchId[A] + ' (verified once per folder; this folder''s marker does not list it)');
    end;
    if ArchNeeded[A] then begin
      if ArchState[A] = AS_NOTNEEDED then
        ArchState[A] := AS_MISSING;
    end else begin
      if ArchState[A] <> AS_ACCEPTED then
        ArchState[A] := AS_NOTNEEDED;
      if not ArchCompOn(A) then
        Log('CXCXM ARCHIVE ' + ArchId[A] + ' not-needed component off')
      else if InPlace[A] then
        Log('CXCXM ARCHIVE ' + ArchId[A] + ' in-place ' + ConvDir)
      else
        Log('CXCXM ARCHIVE ' + ArchId[A] + ' not-needed no file of it is wanted');
    end;
  end;
end;

{ ------------------------------------------------------ tested version --- }

{ True when member M only feeds user config paths (Seamless's
  ersc_settings.ini): the player edits those, so their bytes say nothing
  about the version. }
function MemFeedsUserConfig(const M: Integer): Boolean;
var
  K: Integer;
begin
  Result := False;
  for K := 0 to VarCount - 1 do
    if (VarSrc[K] = 'A') and (VarRef[K] = M) and PathIsUserConfig(VarPath[K]) then begin
      Result := True;
      Exit;
    end;
end;

{ Mode V: True when Files (Files[i] = the file of member ArchMemStart[A]+i)
  are the tested version: every member that is not user config equals its
  MemSha (the catalog keeps the tested version's sha256 there for mode V;
  contract change log, repair 1). False when the catalog knows no tested
  hash or a file is missing. }
function ModeVFilesTested(const A: Integer; const Files: TArrayOfString): Boolean;
var
  I, M, N: Integer;
begin
  Result := False;
  N := 0;
  for I := 0 to ArchMemCount[A] - 1 do begin
    M := ArchMemStart[A] + I;
    if (MemSha[M] = '') or MemFeedsUserConfig(M) then
      Continue;
    if I >= GetArrayLength(Files) then
      Exit;
    if (Files[I] = '') or not FileExists(Files[I]) then
      Exit;
    if CompareText(FileSha256(Files[I]), MemSha[M]) <> 0 then
      Exit;
    N := N + 1;
  end;
  Result := N > 0;
end;

{ ----------------------------------------------------------- candidates --- }

{ The member names of archive A, lower case, sorted (fast "is this one of
  them" for big folder walks). }
procedure MemberNameList(const A: Integer; Names: TStringList);
var
  M: Integer;
begin
  Names.Clear;
  Names.Sorted := True;
  Names.Duplicates := dupIgnore;
  for M := ArchMemStart[A] to ArchMemStart[A] + ArchMemCount[A] - 1 do
    Names.Add(Lowercase(MemName[M]));
end;

{ Walks Root (depth <= ARCH_MAX_DEPTH) and records every file whose name is
  a member name of archive A, as "MMMMMM|full path" (M = member index).
  Convergence folders BELOW Root are not entered (a stock Convergence ships
  files with some of the same names and other content). TooBig is set when
  the folder is too large to search sensibly. }
procedure CollectMemberCandidates(const A: Integer; const Root: String; Cands: TStringList; var TooBig: Boolean);
var
  Queue, Names: TStringList;
  Head, Depth, Bar, Idx, DirCount, M: Integer;
  Entry, Dir, Child: String;
  FindRec: TFindRec;
begin
  TooBig := False;
  DirCount := 0;
  Queue := TStringList.Create;
  Names := TStringList.Create;
  try
    MemberNameList(A, Names);
    Queue.Add('0|' + RemoveBackslashUnlessRoot(Root));
    Head := 0;
    while Head < Queue.Count do begin
      Entry := Queue[Head];
      Head := Head + 1;
      Bar := Pos('|', Entry);
      Depth := StrToIntDef(Copy(Entry, 1, Bar - 1), 0);
      Dir := Copy(Entry, Bar + 1, Length(Entry));
      DirCount := DirCount + 1;
      if DirCount > ARCH_MAX_DIRS then begin
        TooBig := True;
        Exit;
      end;
      if (DirCount mod 50) = 0 then
        ProgressText('Looking for the files of ' + ArchLabel(A) + '...', Dir);
      if FindFirst(AddBackslash(Dir) + '*', FindRec) then begin
        try
          repeat
            if (FindRec.Name = '.') or (FindRec.Name = '..') then
              Continue;
            Child := AddBackslash(Dir) + FindRec.Name;
            if (FindRec.Attributes and FA_DIRECTORY) <> 0 then begin
              if (Depth < ARCH_MAX_DEPTH) and ((FindRec.Attributes and FA_REPARSE_POINT) = 0) and
                not LooksLikeConvergence(Child) then
                Queue.Add(IntToStr(Depth + 1) + '|' + Child);
            end else if Names.Find(Lowercase(FindRec.Name), Idx) then begin
              for M := ArchMemStart[A] to ArchMemStart[A] + ArchMemCount[A] - 1 do
                if CompareText(MemName[M], FindRec.Name) = 0 then
                  Cands.Add(Format('%.6d|%s', [M, Child]));
            end;
          until not FindNext(FindRec);
        finally
          FindClose(FindRec);
        end;
      end;
    end;
  finally
    Queue.Free;
    Names.Free;
  end;
end;

{ How many trailing components of Path equal those of the reference path
  Tail (case-insensitive; at least the file name for a candidate), and Root
  = Path without them: the folder the member's package was extracted to. }
function TailMatch(const Path, Tail: String; var Root: String): Integer;
var
  P, T: TArrayOfString;
  I, J: Integer;
  S: String;
begin
  S := Tail;
  StringChangeEx(S, '/', '\', True);
  SplitStr(Path, '\', P);
  SplitStr(S, '\', T);
  Result := 0;
  I := GetArrayLength(P) - 1;
  J := GetArrayLength(T) - 1;
  while (I >= 1) and (J >= 0) do begin
    if CompareText(P[I], T[J]) <> 0 then
      Break;
    Result := Result + 1;
    I := I - 1;
    J := J - 1;
  end;
  Root := '';
  for J := 0 to I do begin
    if J > 0 then
      Root := Root + '\';
    Root := Root + P[J];
  end;
end;

{ Mode V: every member must come from ONE package folder. Each candidate's
  package folder is its path minus the longest end it shares with the
  member's reference path (SeamlessCoop\locale\english.json); the folder
  holding the most members wins (ties: more matching path components, then
  the first one found), and in it each member takes the candidate that
  shares the most components. A file of the same name somewhere else (some
  other program's english.json next to the download) is never taken
  (verifier 1, defect D4). Found / Missing / Wrong as VerifyMemberCandidates. }
procedure PickModeVPackage(const A: Integer; Cands: TStringList; var Found: TArrayOfString;
  Missing, Wrong: TStringList);
var
  Roots: TStringList;
  CandM, CandN, CandRoot: array of Integer;
  CandPath: TArrayOfString;
  I, J, M, Bar, N, R, BestR, BestCount, BestSum, Count, Sum, BestJ, Total: Integer;
  Path, Root: String;
  HasAny, Tested, BestTested: Boolean;
  RootFiles: TArrayOfString;
begin
  Total := ArchMemCount[A];
  Roots := TStringList.Create;
  try
    N := Cands.Count;
    SetArrayLength(CandM, N);
    SetArrayLength(CandN, N);
    SetArrayLength(CandRoot, N);
    SetArrayLength(CandPath, N);
    for J := 0 to N - 1 do begin
      Bar := Pos('|', Cands[J]);
      CandM[J] := StrToIntDef(Copy(Cands[J], 1, Bar - 1), -1);
      Path := Copy(Cands[J], Bar + 1, Length(Cands[J]));
      CandPath[J] := Path;
      CandN[J] := TailMatch(Path, MemTail[CandM[J]], Root);
      R := Roots.IndexOf(Lowercase(Root));
      if R < 0 then
        R := Roots.Add(Lowercase(Root));
      CandRoot[J] := R;
    end;
    { the package folder: the most members; among complete ones the TESTED
      version first (two packages below one picked folder, e.g. Mods\A_other
      and Mods\B_Seamless_199: verifier 3, defect D3); then more matching
      path components; then the first one found }
    BestR := -1;
    BestCount := 0;
    BestSum := 0;
    BestTested := False;
    SetArrayLength(RootFiles, Total);
    for R := 0 to Roots.Count - 1 do begin
      Count := 0;
      Sum := 0;
      for I := 0 to Total - 1 do begin
        M := ArchMemStart[A] + I;
        RootFiles[I] := '';
        BestJ := -1;
        for J := 0 to N - 1 do
          if (CandRoot[J] = R) and (CandM[J] = M) then begin
            if BestJ < 0 then
              BestJ := J
            else if CandN[J] > CandN[BestJ] then
              BestJ := J;
          end;
        if BestJ >= 0 then begin
          Count := Count + 1;
          Sum := Sum + CandN[BestJ];
          RootFiles[I] := CandPath[BestJ];
        end;
      end;
      Tested := (Count = Total) and ModeVFilesTested(A, RootFiles);
      if (Count > BestCount) or
        ((Count = BestCount) and Tested and not BestTested) or
        ((Count = BestCount) and (Tested = BestTested) and (Sum > BestSum)) then
      begin
        BestR := R;
        BestCount := Count;
        BestSum := Sum;
        BestTested := Tested;
      end;
    end;
    if BestR >= 0 then
      Log(Format('%s: package folder %s (%d of %d files there)', [ArchId[A], Roots[BestR], BestCount, Total]));
    for I := 0 to Total - 1 do begin
      M := ArchMemStart[A] + I;
      Found[I] := '';
      BestJ := -1;
      HasAny := False;
      for J := 0 to N - 1 do
        if CandM[J] = M then begin
          HasAny := True;
          if CandRoot[J] = BestR then begin
            if BestJ < 0 then
              BestJ := J
            else if CandN[J] > CandN[BestJ] then
              BestJ := J;
          end;
        end;
      if BestJ >= 0 then
        Found[I] := CandPath[BestJ]
      else if HasAny then
        Wrong.Add(MemName[M] + ' (not in the same folder as the others)')
      else
        Missing.Add(MemName[M]);
    end;
  finally
    Roots.Free;
  end;
end;

{ Picks, for every member of archive A, a candidate: sha256 equal (mode P)
  or, in mode V, from one package folder (PickModeVPackage). Found[i]
  (i = member - ArchMemStart[A]) receives the file. Problem explains what is
  missing or wrong. }
function VerifyMemberCandidates(const A: Integer; Cands: TStringList; var Found: TArrayOfString;
  var Problem: String): Boolean;
var
  Missing, Wrong: TStringList;
  I, J, M, Bar, Total: Integer;
  Path: String;
  HasCandidate: Boolean;
begin
  Total := ArchMemCount[A];
  SetArrayLength(Found, Total);
  Missing := TStringList.Create;
  Wrong := TStringList.Create;
  try
    if ArchIsModeV(A) then
      PickModeVPackage(A, Cands, Found, Missing, Wrong)
    else
    for I := 0 to Total - 1 do begin
      M := ArchMemStart[A] + I;
      Found[I] := '';
      HasCandidate := False;
      ProgressText(Format('Checking the files of %s (%d of %d)...', [ArchLabel(A), I + 1, Total]), MemName[M]);
      ProgressPos(I, Total);
      for J := 0 to Cands.Count - 1 do begin
        Bar := Pos('|', Cands[J]);
        if StrToIntDef(Copy(Cands[J], 1, Bar - 1), -1) <> M then
          Continue;
        HasCandidate := True;
        Path := Copy(Cands[J], Bar + 1, Length(Cands[J]));
        if FileHasSHA256(Path, MemSha[M], MemSize[M]) then begin
          Found[I] := Path;
          Break;
        end;
      end;
      if Found[I] = '' then begin
        if HasCandidate then
          Wrong.Add(MemName[M])
        else
          Missing.Add(MemName[M]);
      end;
    end;
    ProgressPos(Total, Total);

    Result := (Missing.Count = 0) and (Wrong.Count = 0);
    Problem := '';
    if Result then
      Exit;
    if Missing.Count = Total then
      Problem := 'None of the files of ' + ArchLabel(A) + ' are in there.'
    else begin
      if Missing.Count > 0 then
        Problem := Format('%d of %d files are missing: ', [Missing.Count, Total]) + JoinLimited(Missing, 6) + '.';
      if Wrong.Count > 0 then begin
        if Problem <> '' then
          Problem := Problem + #13#10;
        Problem := Problem + Format('%d files do not match %s (another version?): ', [Wrong.Count,
          ArchLabel(A)]) + JoinLimited(Wrong, 6) + '.';
      end;
    end;
    Problem := Problem + #13#10 + ArchHint[A];
  finally
    Missing.Free;
    Wrong.Free;
  end;
end;

{ Checks a folder (any depth) for archive A. }
function CheckArchiveFolder(const A: Integer; const Root: String; var Found: TArrayOfString;
  var Problem: String): Boolean;
var
  Cands: TStringList;
  TooBig: Boolean;
begin
  Result := False;
  if (Root = '') or not DirExists(Root) then begin
    Problem := 'This folder does not exist: ' + Root;
    Exit;
  end;
  Cands := TStringList.Create;
  try
    CollectMemberCandidates(A, Root, Cands, TooBig);
    if TooBig then begin
      Problem := 'That folder is too big to search. Pick the folder you extracted ' + ArchLabel(A) + ' into.';
      Exit;
    end;
    Log(Format('%s: %d candidate file(s) under %s', [ArchId[A], Cands.Count, Root]));
    Result := VerifyMemberCandidates(A, Cands, Found, Problem);
  finally
    Cands.Free;
  end;
end;

{ --------------------------------------------------------------- pins --- }

{ True when the file's size matches one of archive A's pins (cheap). }
function ArchPinSizeMatch(const A: Integer; const Size: Int64): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := ArchPinStart[A] to ArchPinStart[A] + ArchPinCount[A] - 1 do
    if PinSize[I] = Size then begin
      Result := True;
      Exit;
    end;
end;

{ True when the file is one of archive A's pinned files (size, then sha256). }
function ArchFileIsPinned(const A: Integer; const FileName: String): Boolean;
var
  I: Integer;
  Size: Int64;
begin
  Result := False;
  Size := GetFileSizeSafe(FileName);
  if (Size < 0) or not ArchPinSizeMatch(A, Size) then
    Exit;
  ProgressText('Checking ' + ExtractFileName(FileName) + ' (SHA-256)...', '');
  for I := ArchPinStart[A] to ArchPinStart[A] + ArchPinCount[A] - 1 do
    if (PinSize[I] = Size) and (CompareText(FileSha256(FileName), PinSha[I]) = 0) then begin
      Result := True;
      Exit;
    end;
end;

{ ------------------------------------------------------ tested version --- }

{ The tested version's name: the catalog's CAT_SEAMLESS_TESTED_VERSION for
  the Seamless Co-op archive (the pipeline takes it from the reference's
  tested_version), else from the archive hint ("... tested with 1.9.9)");
  '' when neither names one. }
function ModeVTestedVersion(const A: Integer): String;
var
  P: Integer;
  Ver: String;
begin
  Result := '';
  if (CAT_SEAMLESS_TESTED_VERSION <> '') and (CompareText(ArchId[A], 'seamless') = 0) then begin
    Result := CAT_SEAMLESS_TESTED_VERSION;
    Exit;
  end;
  P := Pos('tested with ', Lowercase(ArchHint[A]));
  if P = 0 then
    Exit;
  Ver := Copy(ArchHint[A], P + Length('tested with '), Length(ArchHint[A]));
  P := Pos(')', Ver);
  if P > 0 then
    Ver := Copy(Ver, 1, P - 1);
  P := Pos(' ', Ver);
  if P > 0 then
    Ver := Copy(Ver, 1, P - 1);
  if (Ver <> '') and (Ver[Length(Ver)] = '.') then
    Ver := Copy(Ver, 1, Length(Ver) - 1);
  Result := Ver;
end;

{ The member a mode V version text names: the first DLL (Seamless: ersc.dll). }
function ModeVVersionMember(const A: Integer): Integer;
var
  I: Integer;
begin
  Result := ArchMemStart[A];
  for I := ArchMemStart[A] + ArchMemCount[A] - 1 downto ArchMemStart[A] do
    if CompareText(ExtractFileExt(MemName[I]), '.dll') = 0 then
      Result := I;
end;

{ "ersc.dll sha256 <hash>" of the files Files (see ModeVFilesTested). }
function ModeVHashText(const A: Integer; const Files: TArrayOfString): String;
var
  M: Integer;
  F: String;
begin
  M := ModeVVersionMember(A);
  F := '';
  if M - ArchMemStart[A] < GetArrayLength(Files) then
    F := Files[M - ArchMemStart[A]];
  Result := MemName[M] + ' sha256 ' + FileSha256(F);
end;

{ ------------------------------------------------------------- extraction --- }

function ArchExtractProgress(const ArchiveName, FileName: String; const Progress, ProgressMax: Int64): Boolean;
var
  Permille: Integer;
begin
  if ActiveProgress <> nil then begin
    ActiveProgress.SetText('Unpacking ' + ExtractFileName(ArchiveName) + ' ...', FileName);
    if ProgressMax > 0 then begin
      Permille := Progress * 1000 div ProgressMax;
      ActiveProgress.SetProgress(Permille, 1000);
    end;
  end;
  { the unpacked size cap (repair 3): stop as soon as the archive says, or
    turns out, to unpack to more }
  if (UnpackCapBytes > 0) and ((Progress > UnpackCapBytes) or (ProgressMax > UnpackCapBytes)) then begin
    if not UnpackCapHit then
      Log(Format('Unpacking stopped: %s unpacks to more than %s (the cap for it)', [ExtractFileName(ArchiveName),
        BytesToMB(UnpackCapBytes)]));
    UnpackCapHit := True;
    Result := False;
    Exit;
  end;
  Result := True;
end;

{ The most bytes one archive may unpack to (repair 3, code review LOW): at
  most UNPACK_RATIO_MAX times its own size + 256 MB, and never more than the
  free space of OutDir's drive minus UNPACK_RESERVE_BYTES. }
function UnpackCapFor(const Archive, OutDir: String): Int64;
var
  Size, FreeBytes, TotalBytes: Int64;
begin
  Size := GetFileSizeSafe(Archive);
  if Size < 0 then
    Size := 0;
  Result := Size * UNPACK_RATIO_MAX + 268435456;
  if GetSpaceOnDisk64(OutDir, FreeBytes, TotalBytes) and (FreeBytes - UNPACK_RESERVE_BYTES < Result) then
    Result := FreeBytes - UNPACK_RESERVE_BYTES;
  if Result < 1 then
    Result := 1;
end;

{ The most bytes the built-in extractor may unpack into OutDir's drive: its
  free space minus UNPACK_RESERVE_BYTES (0 = not known: no cap). }
function FreeUnpackCap(const OutDir: String): Int64;
var
  FreeBytes, TotalBytes: Int64;
begin
  Result := 0;
  if GetSpaceOnDisk64(OutDir, FreeBytes, TotalBytes) then begin
    Result := FreeBytes - UNPACK_RESERVE_BYTES;
    if Result < 1 then
      Result := 1;
  end;
end;

{ Room on OutDir's drive for unpacking Archive (its size + 64 MB). }
function RoomToUnpack(const Archive, OutDir: String; var Problem: String): Boolean;
var
  FreeBytes, TotalBytes, Need: Int64;
begin
  Result := True;
  Need := GetFileSizeSafe(Archive);
  if Need < 0 then
    Need := 0;
  Need := Need + 67108864;
  if GetSpaceOnDisk64(OutDir, FreeBytes, TotalBytes) and (FreeBytes < Need) then begin
    Problem := 'Not enough free disk space to unpack ' + ExtractFileName(Archive) + ' (needed: about ' +
      BytesToMB(Need) + ', free: ' + BytesToMB(FreeBytes) + ').';
    Result := False;
  end;
end;

{ True when tar's only complaints are patterns it did not find: it read
  the whole archive, which simply lacks some member names. }
function TarOnlyNotFound(const Output: TExecOutput): Boolean;
var
  I, N: Integer;
  L: String;
begin
  Result := False;
  if Output.Error then
    Exit;
  N := 0;
  for I := 0 to GetArrayLength(Output.StdErr) - 1 do begin
    L := Lowercase(Trim(Output.StdErr[I]));
    if L = '' then
      Continue;
    N := N + 1;
    if (Pos('not found in archive', L) = 0) and (Pos('error exit delayed', L) = 0) then
      Exit;
  end;
  Result := N > 0;
end;

{ The bytes tar's listing (-t -v) gives for the entries that match the
  patterns, -1 when the listing cannot be read (the caller then does not use
  tar: repair 4, code review LOW - a listing that failed must never let an
  uncapped extraction through). The archive comes on stdin, as for the
  extraction; tar never writes more than an entry's listed size (measured:
  "Write request too large"), so this bounds what it unpacks. An entry's
  size is read as the LARGEST number among the blank-separated fields of
  its line (an upper bound: the size field is always one of them, while
  owner or group names with blanks move it to another position - repair 4);
  a number of more than 18 digits counts as too big. }
function TarListedBytes(const Tar, Archive, PatFile, WorkDir: String): Int64;
var
  Params, L: String;
  Output: TExecOutput;
  ResultCode, I, J, K: Integer;
  Tok: String;
  Size, V, Huge: Int64;
  Digits: Boolean;
begin
  Huge := StrToInt64Def('999999999999999999', 0);
  Result := -1;
  Params := '/C ""' + Tar + '" -t -v -f -';
  if PatFile <> '' then
    Params := Params + ' -T "' + PatFile + '"';
  Params := Params + ' < "' + Archive + '""';
  try
    if not ExecAndCaptureOutput(ExpandConstant('{cmd}'), Params, WorkDir, SW_SHOWNORMAL, ewWaitUntilTerminated,
      ResultCode, Output) or Output.Error then
      Exit;
  except
    Exit;
  end;
  if (ResultCode <> 0) and not TarOnlyNotFound(Output) then
    Exit;
  Result := 0;
  for I := 0 to GetArrayLength(Output.StdOut) - 1 do begin
    { mode links owner group SIZE month day time name: the size is one of the
      fields; the largest number of the line is taken }
    L := Trim(Output.StdOut[I]);
    Tok := '';
    Size := 0;
    J := 1;
    while J <= Length(L) + 1 do begin
      if (J > Length(L)) or (L[J] = ' ') or (L[J] = #9) then begin
        if Tok <> '' then begin
          Digits := True;
          for K := 1 to Length(Tok) do
            if (Tok[K] < '0') or (Tok[K] > '9') then
              Digits := False;
          if Digits then begin
            if Length(Tok) > 18 then
              V := Huge
            else
              V := StrToInt64Def(Tok, 0);
            if V > Size then
              Size := V;
          end;
          Tok := '';
        end;
      end else
        Tok := Tok + L[J];
      J := J + 1;
    end;
    Result := Result + Size;
    if Result > Huge then
      Result := Huge;
  end;
end;

{ Unpacks archive A's members from Archive into a fresh work folder.
  1st try: Windows' tar.exe (bsdtar), only the member names: the patterns
           (ArchGlobs) go into a pattern file (-T), the archive comes on
           stdin. Its result is used when tar read the whole archive (exit
           code 0, or only "not found in archive" complaints: the archive
           lacks some names, which the member check then reports), or for a
           mode P archive whenever it produced member files (every member is
           checked by sha256 anyway); TarClean is False only in that last
           case.
  2nd try (Full = True, or tar could not read the archive): Inno's own
           extractor, whole archive.
  A failed attempt's folder is deleted at once. }
function UnpackArchive(const A: Integer; const Archive: String; const Full, Capped: Boolean; var OutDir: String;
  var TarClean: Boolean; var Problem: String): Boolean;
var
  Tar, Params, PatFile, Pats: String;
  Globs: TArrayOfString;
  ResultCode, I: Integer;
  Cands: TStringList;
  TooBig, ReadAll, UseTar: Boolean;
  Output: TExecOutput;
  Listed, SavedCap: Int64;
begin
  Result := False;
  TarClean := False;
  Problem := '';
  if not FileExists(Archive) then begin
    Problem := 'The file does not exist: ' + Archive;
    Exit;
  end;
  OutDir := NewWorkDir(A);
  if not RoomToUnpack(Archive, OutDir, Problem) then begin
    DelWorkDir(OutDir);
    OutDir := '';
    Exit;
  end;
  { a candidate of the automatic download search that is not a known
    (pinned) file gets the unpacked-size cap (repair 3, code review LOW) }
  if Capped then begin
    UnpackCapBytes := UnpackCapFor(Archive, OutDir);
    Log(Format('%s: a search candidate; it may unpack to %s at most', [ExtractFileName(Archive),
      BytesToMB(UnpackCapBytes)]));
  end else
    UnpackCapBytes := 0;

  if not Full then begin
    Tar := ExpandConstant('{sys}\tar.exe');
#ifdef CodeCheck
    { code-check build only: /NOTAR=1 forces the fallback extractor for testing }
    if CmdParam('NOTAR') = '1' then
      Tar := '';
#endif
#if Defined(CodeCheck) || Defined(TestBuild)
    { test builds: /TESTNOTAR=1 forces the built-in extractor (is7z.dll, ArchiveExtraction=full), so the tests run
      it on the real downloads too (repair 6: McKenyu's 1.4 pack is a RAR5 file) }
    if CmdParam('TESTNOTAR') = '1' then
      Tar := '';
#endif
    { an elevated Setup never starts tar: tar is a child process, which
      Windows' RedirectionGuard does not protect, writing into a folder a
      normal user can change; the built-in extractor runs inside Setup
      (repair 3, code review LOW) }
    if SetupElevated then begin
      Log('Setup runs as administrator: the built-in extractor unpacks ' + ExtractFileName(Archive) + ' (tar is ' +
        'not used)');
      Tar := '';
    end;
    if (Tar <> '') and FileExists(Tar) then begin
      ProgressText('Unpacking the files of ' + ArchLabel(A) + ' from ' + ExtractFileName(Archive) + ' ...',
        'This can take a minute for a big archive.');
      ProgressPos(0, 0);
      Params := '/C ""' + Tar + '" -x -f -';
      SplitStr(ArchGlobs[A], '|', Globs);
      if GetArrayLength(Globs) > 0 then begin
        PatFile := OutDir + '.patterns.txt';
        Pats := '';
        for I := 0 to GetArrayLength(Globs) - 1 do
          if Trim(Globs[I]) <> '' then
            Pats := Pats + Trim(Globs[I]) + #10;
        if not SaveStringToFile(PatFile, Pats, False) then begin
          Log('Cannot write ' + PatFile);
          PatFile := '';
        end else
          Params := Params + ' -T "' + PatFile + '"';
      end;
      Params := Params + ' < "' + Archive + '""';
      { a candidate of the automatic search that is not a known (pinned)
        file: what tar would unpack is listed first and must stay below the
        cap (repair 3, code review LOW: no cap on the unpacked size); a
        listing that fails means no tar for this candidate: the built-in
        extractor below stops at the cap (repair 4, code review LOW) }
      UseTar := True;
      if UnpackCapBytes > 0 then begin
        Listed := TarListedBytes(Tar, Archive, PatFile, OutDir);
        if Listed < 0 then begin
          Log('tar cannot list ' + ExtractFileName(Archive) + ' completely, so tar is not used for it (the ' +
            'built-in extractor stops at the cap)');
          UseTar := False;
          if PatFile <> '' then
            DeleteFile(PatFile);
        end else begin
          Log(Format('tar lists %s for %s (cap %s)', [BytesToMB(Listed), ExtractFileName(Archive),
            BytesToMB(UnpackCapBytes)]));
          if Listed > UnpackCapBytes then begin
            if PatFile <> '' then
              DeleteFile(PatFile);
            DelWorkDir(OutDir);
            OutDir := '';
            Problem := Format('%s would unpack to %s, more than Setup allows for it (%s). If it really is the ' +
              'download, unpack it yourself and select the unpacked folder.', [ExtractFileName(Archive),
              BytesToMB(Listed), BytesToMB(UnpackCapBytes)]);
            Exit;
          end;
        end;
      end;
      if UseTar then begin
        Log('cmd ' + Params);
        ReadAll := False;
        try
          if ExecAndCaptureOutput(ExpandConstant('{cmd}'), Params, OutDir, SW_SHOWNORMAL, ewWaitUntilTerminated,
            ResultCode, Output) then
          begin
            Log('tar exit code ' + IntToStr(ResultCode));
            for I := 0 to GetArrayLength(Output.StdErr) - 1 do
              if I < 10 then
                Log('  tar: ' + Output.StdErr[I]);
            ReadAll := (ResultCode = 0) or ((ResultCode > 0) and TarOnlyNotFound(Output));
          end else begin
            Log('tar could not be started: ' + SysErrorMessage(ResultCode));
            ResultCode := -1;
          end;
        except
          Log('tar could not be run: ' + GetExceptionMessage);
          ResultCode := -1;
        end;
        if PatFile <> '' then
          DeleteFile(PatFile);
        if ReadAll then begin
          TarClean := True;
          Result := True;
          Exit;
        end;
        if (ResultCode > 0) and not ArchIsModeV(A) then begin
          Cands := TStringList.Create;
          try
            CollectMemberCandidates(A, OutDir, Cands, TooBig);
            if Cands.Count > 0 then begin
              Result := True;
              Exit;
            end;
          finally
            Cands.Free;
          end;
        end;
        Log('tar result not used; trying the built-in extractor');
      end;
    end else
      Log('tar.exe not found at ' + Tar);
    DelWorkDir(OutDir);
    OutDir := NewWorkDir(A);
  end;

  { the built-in extractor, whole archive; it always stops at the cap (the
    free space of the drive, and for a search candidate the size cap) }
  UnpackCapHit := False;
  SavedCap := UnpackCapBytes;
  if UnpackCapBytes <= 0 then
    UnpackCapBytes := FreeUnpackCap(OutDir);
  try
    ProgressText('Unpacking ' + ExtractFileName(Archive) + ' ...', '');
    ExtractArchive(Archive, OutDir, '', True, @ArchExtractProgress);
    Log('Unpacked ' + ExtractFileName(Archive) + ' with the built-in extractor (7-Zip''s 7z.dll in Setup)');
    TarClean := True;
    Result := True;
  except
    Log('ExtractArchive failed: ' + GetExceptionMessage);
    DelWorkDir(OutDir);
    OutDir := '';
    if UnpackCapHit then
      Problem := ExtractFileName(Archive) + ' unpacks to more than Setup allows for it (' + BytesToMB(UnpackCapBytes) +
        '). If it really is the download, unpack it yourself and select the unpacked folder.'
    else
      Problem := 'Setup could not unpack ' + ExtractFileName(Archive) + '.' + #13#10 +
        'Unpack it yourself (right-click > Extract All, or 7-Zip), then click "Select extracted folder" ' +
        'and pick the unpacked folder.';
  end;
  UnpackCapBytes := SavedCap;
end;

{ ------------------------------------------------------------ entry points --- }

{ Checks a folder or archive file for archive A. On success Found holds the
  member files, WorkDir the extraction folder ('' for a folder) and Pinned
  whether the file is a pinned one. A rejected archive's extraction folder
  is deleted. }
function CheckArchivePath(const A: Integer; const PathIn: String; var Found: TArrayOfString;
  var WorkDir: String; var Pinned: Boolean; var Problem, SourceLabel: String): Boolean;
var
  P, OutDir, Problem2: String;
  TarClean, Capped: Boolean;
begin
  Result := False;
  WorkDir := '';
  Pinned := False;
  P := Trim(RemoveQuotes(Trim(PathIn)));
  if P <> '' then
    P := ExpandFileName(P);         { a relative path means the current folder }
  SourceLabel := P;
  if P = '' then begin
    Problem := 'No file or folder given.';
    Exit;
  end;
  if DirExists(P) then begin
    P := NormalizeDir(P);
    SourceLabel := P;
    if (ConvDir <> '') and PathIsWithin(P, ConvDir) then begin
      Problem := 'That folder is (inside) your Convergence folder. Select the download itself (the archive ' +
        'or the folder you extracted it into); files that are already in place are found by themselves.';
      Exit;
    end;
    Result := CheckArchiveFolder(A, P, Found, Problem);
    if not Result then
      Problem := 'Checked the folder ' + P + ':' + #13#10 + Problem;
    Exit;
  end;
  if FileExists(P) then begin
    if not IsArchiveFileName(P) then begin
      Problem := 'That file is not a .zip, .7z or .rar archive: ' + ExtractFileName(P);
      Exit;
    end;
    Pinned := ArchFileIsPinned(A, P);
    if Pinned then
      Log(ArchId[A] + ': ' + P + ' is a pinned (known) file');
    Capped := SearchUnpack and not Pinned;
    if not UnpackArchive(A, P, False, Capped, OutDir, TarClean, Problem) then
      Exit;
    Result := CheckArchiveFolder(A, OutDir, Found, Problem);
    if (not Result) and (not TarClean) then begin
      { tar stopped with an error: the whole archive with the other extractor }
      Log(ArchId[A] + ': tar''s partial result failed the check; trying the built-in extractor');
      DelWorkDir(OutDir);
      if UnpackArchive(A, P, True, Capped, OutDir, TarClean, Problem2) then
        Result := CheckArchiveFolder(A, OutDir, Found, Problem)
      else
        OutDir := '';
    end;
    if Result then
      WorkDir := OutDir
    else begin
      if OutDir <> '' then
        DelWorkDir(OutDir);
      Problem := 'Checked the archive ' + ExtractFileName(P) + ':' + #13#10 + Problem;
    end;
    Exit;
  end;
  Problem := 'This file or folder does not exist: ' + P;
  P := LinkBlockedNote(P);
  if P <> '' then
    Problem := Problem + #13#10 + P;
end;

{ Records an accepted source of archive A. The extraction folder of a source
  accepted earlier is deleted. Mode V: the sha256 of every member becomes the
  expected content of the variants taken from it. }
procedure AcceptArchive(const A: Integer; const Found: TArrayOfString; const WorkDir: String;
  const Pinned: Boolean; const SourceLabel: String);
var
  I, M, K: Integer;
  Sha: String;
begin
  if (ArchWorkDir[A] <> '') and not PathSame(ArchWorkDir[A], WorkDir) then begin
    Log('Deleting the unpacked copy ' + ArchWorkDir[A]);
    DelWorkDir(ArchWorkDir[A]);
  end;
  ArchWorkDir[A] := WorkDir;
  for I := 0 to ArchMemCount[A] - 1 do begin
    M := ArchMemStart[A] + I;
    MemPath[M] := Found[I];
    if ArchIsModeV(A) then begin
      Sha := FileSha256(Found[I]);
      for K := 0 to VarCount - 1 do
        if (VarSrc[K] = 'A') and (VarRef[K] = M) then
          VarShaRt[K] := Sha;
      Log(Format('%s member %s = %s (sha256 %s)', [ArchId[A], MemName[M], Found[I], Sha]));
    end;
  end;
  ArchState[A] := AS_ACCEPTED;
  ArchSource[A] := SourceLabel;
  ArchProblem[A] := '';
  ArchPinned[A] := Pinned;
  if ArchIsModeV(A) and not Pinned then
    ArchTested[A] := ModeVFilesTested(A, Found)
  else
    ArchTested[A] := True;
  Log('CXCXM ARCHIVE ' + ArchId[A] + ' accepted ' + SourceLabel);
  if ArchIsModeV(A) then begin
    if ArchTested[A] then
      Log(ArchId[A] + ': the tested version ' + ModeVTestedVersion(A) + ' (' + ModeVHashText(A, Found) + ')')
    else
      Log(ArchId[A] + ': NOT the tested version ' + ModeVTestedVersion(A) + ' (' + ModeVHashText(A, Found) +
        '); its files are copied as they are');
  end;
end;

procedure RejectArchive(const A: Integer; const Problem, SourceLabel: String);
begin
  if ArchState[A] = AS_ACCEPTED then
    Exit;               { an accepted source stays; a later failed try changes nothing }
  ArchState[A] := AS_REJECTED;
  ArchProblem[A] := Problem;
  ArchSource[A] := SourceLabel;
  Log('CXCXM ARCHIVE ' + ArchId[A] + ' rejected ' + SourceLabel + ': ' + Problem);
end;

{ Forgets every accepted source and deletes the unpacked copies (a new
  Convergence folder was chosen). }
procedure ReleaseAllArchives;
var
  A, M: Integer;
begin
  for A := 0 to ArchCount - 1 do begin
    ArchState[A] := AS_NOTNEEDED;
    ArchNeeded[A] := False;
    ArchSource[A] := '';
    ArchProblem[A] := '';
    ArchNeedNote[A] := '';
    ArchWorkDir[A] := '';
    ArchPinned[A] := False;
    ArchTested[A] := False;
    ArchSearchedFor[A] := '';
  end;
  for M := 0 to MemCount - 1 do
    MemPath[M] := '';
  for M := 0 to VarCount - 1 do
    VarShaRt[M] := '';
  ReleaseWorkRoot;
end;

{ Tries one folder or file for archive A; True when it was accepted. }
function TryArchivePath(const A: Integer; const P: String): Boolean;
var
  Found: TArrayOfString;
  WorkDir, Problem, SourceLabel: String;
  Pinned: Boolean;
begin
  Result := CheckArchivePath(A, P, Found, WorkDir, Pinned, Problem, SourceLabel);
  if Result then
    AcceptArchive(A, Found, WorkDir, Pinned, SourceLabel)
  else
    RejectArchive(A, Problem, SourceLabel);
end;

{ ------------------------------------------------------- download search --- }

{ A file name (or a name hint) as words: lower case, every character that is
  not a letter or a digit becomes one blank, with a blank at both ends:
  "moveset_modpack 26.2 1928 26.2 2026-08-29T15-47Z x.zip" ->
  " moveset modpack 26 2 1928 26 2 2026 08 29t15 47z x zip ". Nexus's own
  download names use '_', '-' and '.' where the page title has blanks. }
function NameWords(const S: String): String;
var
  I: Integer;
  C: Char;
  Blank: Boolean;
begin
  Result := ' ';
  Blank := True;
  for I := 1 to Length(S) do begin
    C := S[I];
    if (C >= 'A') and (C <= 'Z') then
      C := Chr(Ord(C) + 32);
    if ((C >= 'a') and (C <= 'z')) or ((C >= '0') and (C <= '9')) or (Ord(C) > 127) then begin
      Result := Result + C;
      Blank := False;
    end else if not Blank then begin
      Result := Result + ' ';
      Blank := True;
    end;
  end;
  if not Blank then
    Result := Result + ' ';
end;

function IsAllDigits(const S: String): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if (S[I] < '0') or (S[I] > '9') then begin
      Result := False;
      Exit;
    end;
end;

{ True when the name (NameWords form) holds the hint: a number (a Nexus mod
  id such as 1928) only as a whole word, anything else anywhere. }
function NameHasHint(const Words, Hint: String): Boolean;
var
  H: String;
begin
  H := Trim(NameWords(Hint));
  if H = '' then
    Result := False
  else if IsAllDigits(H) then
    Result := Pos(' ' + H + ' ', Words) > 0
  else
    Result := Pos(H, Words) > 0;
end;

{ The archive whose name hints match FileName best (the longest matching
  hint wins: "clever x mckenyu" is the merge, not Clever's or McKenyu's pack),
  among the archives in DlWanted; -1 when none matches. Score = the summed
  length of all of that archive's hints in the name: "Clever's Moveset
  Modpack 26.2.zip" (clever + moveset + moveset modpack) is tried before
  "Greatsword Moveset Overhaul.zip" (moveset only), however new that one is
  (verifier 1, defect D5). Names and hints are compared as words
  (NameWords), so Nexus's own download name "moveset_modpack 26.2 1928 ..."
  matches "moveset modpack", and the Nexus mod id (1928, 8762) counts as a
  hint of its own (verifier 3, defect D2). }
function ArchiveByNameHint(const FileName: String; var Score: Integer): Integer;
var
  A, I, Best, Sum: Integer;
  Hints: TArrayOfString;
  L, H: String;
begin
  Result := -1;
  Best := 0;
  Score := 0;
  L := NameWords(FileName);
  for A := 0 to ArchCount - 1 do begin
    SplitStr(Lowercase(ArchNameHints[A]), '|', Hints);
    Sum := 0;
    for I := 0 to GetArrayLength(Hints) - 1 do begin
      H := Trim(Hints[I]);
      if (H <> '') and NameHasHint(L, H) then begin
        Sum := Sum + Length(H);
        if Length(H) > Best then begin
          Best := Length(H);
          Result := A;
        end;
      end;
    end;
    if Result = A then
      Score := Sum;
  end;
  if Score > 999 then
    Score := 999;
  if (Result >= 0) and not DlWanted[Result] then
    Result := -1;
end;

{ The path of a search list entry ("AAA|...|path": everything after the
  last '|'; a Windows path never holds one). }
function EntryPath(const E: String): String;
var
  I: Integer;
begin
  Result := E;
  for I := Length(E) downto 1 do
    if E[I] = '|' then begin
      Result := Copy(E, I + 1, Length(E));
      Exit;
    end;
end;

{ The time stamp field of a search list entry "AAA|[SSS|]STAMP|path". }
function EntryStamp(const E: String): String;
var
  P: String;
  I: Integer;
begin
  Result := '0000000000000000';
  P := Copy(E, 1, Length(E) - Length(EntryPath(E)) - 1);    { "AAA|[SSS|]STAMP" }
  I := Length(P) - 16 + 1;
  if I > 0 then
    Result := Copy(P, I, 16);
end;

{ Walks one download root (depth <= MaxDepth) for every archive in DlWanted:
  - a file with a member name of archive A adds the TOP-LEVEL folder below
    Root that holds it to Folders as "AAA|folder", once;
  - an archive file whose size matches a pin of A goes to Pinned as
    "AAA|<FILETIME>|path", one whose name matches A's hints best (and no
    pin of another archive) to Hinted as "AAA|<SCORE>|<FILETIME>|path"
    (sorted: best name match, then newest, last).
  Convergence folders are not entered. }
procedure SearchDownloadRoot(const RootIn: String; const MaxDepth: Integer; Folders, Pinned,
  Hinted: TStringList);
var
  Queue, Names: TStringList;
  Head, Depth, Bar, DirCount, A, M, Idx, H, Score: Integer;
  Entry, Dir, Child, Root, Rel, F, Stamp: String;
  FindRec: TFindRec;
  Size, Low: Int64;
  PinHit: Boolean;
begin
  Root := RemoveBackslashUnlessRoot(RootIn);
  if Root = '' then
    Exit;
  if not DirExists(Root) then begin
    Entry := LinkBlockedNote(Root);
    if Entry <> '' then
      Log('Download search: ' + Root + ' cannot be searched. ' + Entry);
    Exit;
  end;
  { "AAA|member name" of every wanted archive, lower case, sorted }
  Names := TStringList.Create;
  Names.Sorted := True;
  Names.Duplicates := dupIgnore;
  for A := 0 to ArchCount - 1 do
    if DlWanted[A] then
      for M := ArchMemStart[A] to ArchMemStart[A] + ArchMemCount[A] - 1 do
        Names.Add(Format('%.3d|%s', [A, Lowercase(MemName[M])]));
  DirCount := 0;
  Queue := TStringList.Create;
  try
    Queue.Add('0|' + Root);
    Head := 0;
    while Head < Queue.Count do begin
      Entry := Queue[Head];
      Head := Head + 1;
      Bar := Pos('|', Entry);
      Depth := StrToIntDef(Copy(Entry, 1, Bar - 1), 0);
      Dir := Copy(Entry, Bar + 1, Length(Entry));
      DirCount := DirCount + 1;
      if DirCount > ARCH_MAX_DIRS then
        Break;
      if (DirCount mod 50) = 0 then
        ProgressText('Looking for your downloads...', Dir);
      if FindFirst(AddBackslash(Dir) + '*', FindRec) then begin
        try
          repeat
            if (FindRec.Name = '.') or (FindRec.Name = '..') then
              Continue;
            Child := AddBackslash(Dir) + FindRec.Name;
            if (FindRec.Attributes and FA_DIRECTORY) <> 0 then begin
              if (Depth < MaxDepth) and ((FindRec.Attributes and FA_REPARSE_POINT) = 0) and
                not LooksLikeConvergence(Child) and (CompareText(FindRec.Name, WORK_DIR_NAME) <> 0) then
                Queue.Add(IntToStr(Depth + 1) + '|' + Child);
              Continue;
            end;
            { an extracted copy: the top-level folder below Root }
            for A := 0 to ArchCount - 1 do
              if DlWanted[A] and Names.Find(Format('%.3d|%s', [A, Lowercase(FindRec.Name)]), Idx) then begin
                if Depth = 0 then
                  F := Root
                else begin
                  Rel := Copy(Dir, Length(AddBackslash(Root)) + 1, Length(Dir));
                  if Pos('\', Rel) > 0 then
                    Rel := Copy(Rel, 1, Pos('\', Rel) - 1);
                  F := AddBackslash(Root) + Rel;
                end;
                if Folders.IndexOf(Format('%.3d|%s', [A, F])) < 0 then
                  Folders.Add(Format('%.3d|%s', [A, F]));
              end;
            { an archive file }
            if IsArchiveFileName(FindRec.Name) then begin
              Size := FindRec.SizeHigh;
              Size := Size * 65536;
              Size := Size * 65536;
              Low := FindRec.SizeLow;
              Size := Size + Low;
              Stamp := Format('%.8x%.8x', [FindRec.LastWriteTime.dwHighDateTime, FindRec.LastWriteTime.dwLowDateTime]);
              PinHit := False;
              for A := 0 to ArchCount - 1 do
                if ArchPinSizeMatch(A, Size) then begin
                  PinHit := True;
                  if DlWanted[A] then
                    Pinned.Add(Format('%.3d|%s|%s', [A, Stamp, Child]));
                end;
              if not PinHit then begin
                H := ArchiveByNameHint(FindRec.Name, Score);
                if H >= 0 then
                  Hinted.Add(Format('%.3d|%.3d|%s|%s', [H, Score, Stamp, Child]));
              end;
            end;
          until not FindNext(FindRec);
        finally
          FindClose(FindRec);
        end;
      end;
    end;
  finally
    Queue.Free;
    Names.Free;
  end;
end;

{ The search roots: the Downloads folder (depth 4) and Vortex's download and
  mod folders for Elden Ring (depth 3) when Downloads is True; ExtraDir
  (/ARCHIVEDIR, depth 4) when given. }
procedure FindDownloads(const Downloads: Boolean; const ExtraDir: String; Folders, Pinned,
  Hinted: TStringList);
begin
  Folders.Clear;
  Pinned.Clear;
  Hinted.Clear;
  if ExtraDir <> '' then
    SearchDownloadRoot(NormalizeDir(ExtraDir), DL_SEARCH_DEPTH, Folders, Pinned, Hinted);
  if Downloads then begin
    SearchDownloadRoot(GetDownloadsDir, DL_SEARCH_DEPTH, Folders, Pinned, Hinted);
#if Defined(CodeCheck) || Defined(TestBuild)
    if CmdParam('TESTDOWNLOADS') = '' then begin
#endif
    SearchDownloadRoot(ExpandConstant('{userappdata}\Vortex\downloads\eldenring'), DL_VORTEX_DEPTH,
      Folders, Pinned, Hinted);
    SearchDownloadRoot(ExpandConstant('{userappdata}\Vortex\eldenring\mods'), DL_VORTEX_DEPTH,
      Folders, Pinned, Hinted);
#if Defined(CodeCheck) || Defined(TestBuild)
    end;
#endif
  end;
  { newest first: "AAA|<FILETIME>|path" sorts by archive, then by time }
  Pinned.Sort;
  Hinted.Sort;
  Log(Format('Download search: %d extracted folder(s), %d pinned archive(s), %d archive(s) by name', [
    Folders.Count, Pinned.Count, Hinted.Count]));
end;

{ Mode V, found by the search (not chosen by the player): only the TESTED
  version is taken by itself. Any other version found is reported (the
  newest one) and must be chosen explicitly: "Select archive" / "Select
  folder" in the wizard, /ARCHIVE_<ID>= in a silent run. A file planted in
  Downloads under a matching name is never installed unasked, and an old
  extracted copy never wins over the download the player just made
  (verifier 1 defect D3, review finding "mode V accepts any executable").
  Candidates: extracted folders and archives by name together, newest
  first (archives: at most DL_MAX_TRIES unpacked). An extracted folder of
  the search is the top-level folder below the search root; every complete
  package folder inside it (ModeVPackageFolders) is a candidate of its own
  (verifier 3, defect D3). }
procedure ModeVPackageFolders(const A: Integer; const Folder: String; Roots: TStringList);
var
  Cands, Seen: TStringList;
  TooBig: Boolean;
  I, J, Bar, M, N: Integer;
  Path, Root: String;
begin
  Roots.Clear;
  Cands := TStringList.Create;
  Seen := TStringList.Create;
  try
    CollectMemberCandidates(A, Folder, Cands, TooBig);
    if not TooBig then
      for I := 0 to Cands.Count - 1 do begin
        Bar := Pos('|', Cands[I]);
        M := StrToIntDef(Copy(Cands[I], 1, Bar - 1), -1);
        Path := Copy(Cands[I], Bar + 1, Length(Cands[I]));
        if (M < 0) or (M >= MemCount) then
          Continue;
        TailMatch(Path, MemTail[M], Root);
        { a package root above the searched folder (SeamlessCoop\ extracted
          straight into Downloads) is the searched folder itself: never widen
          the search to its parents }
        if not PathIsWithin(Root, Folder) then
          Root := Folder;
        { "root|member" once per member }
        if Seen.IndexOf(Lowercase(Root) + '|' + IntToStr(M)) < 0 then
          Seen.Add(Lowercase(Root) + '|' + IntToStr(M));
        if Roots.IndexOf(Root) < 0 then
          Roots.Add(Root);
      end;
    { only the folders that hold every member }
    for I := Roots.Count - 1 downto 0 do begin
      N := 0;
      for J := 0 to Seen.Count - 1 do
        if StartsWithStr(Seen[J], Lowercase(Roots[I]) + '|') and
          (Pos('|', Copy(Seen[J], Length(Roots[I]) + 2, Length(Seen[J]))) = 0) then
          N := N + 1;
      if N < ArchMemCount[A] then
        Roots.Delete(I);
    end;
    if Roots.Count = 0 then
      Roots.Add(Folder)
    else if (Roots.Count > 1) or not PathSame(Roots[0], Folder) then
      Log(Format('%s: %d package folder(s) below %s: %s', [ArchId[A], Roots.Count, Folder,
        JoinLimited(Roots, 6)]));
  finally
    Cands.Free;
    Seen.Free;
  end;
end;

function TryFoundModeV(const A: Integer; Folders, Hinted: TStringList): Boolean;
var
  Cands, Roots: TStringList;
  Found: TArrayOfString;
  I, J, Tries: Integer;
  Prefix, P, Kind, WorkDir, Problem, SourceLabel, Untested, UntestedHash, Ver: String;
  Pinned: Boolean;
begin
  Result := False;
  Prefix := Format('%.3d|', [A]);
  Cands := TStringList.Create;
  Roots := TStringList.Create;
  try
    { "STAMP|F|folder" / "STAMP|H|archive", sorted: newest last }
    for I := 0 to Folders.Count - 1 do
      if StartsWithStr(Folders[I], Prefix) then begin
        P := EntryPath(Folders[I]);
        ModeVPackageFolders(A, P, Roots);
        for J := 0 to Roots.Count - 1 do
          if Cands.IndexOf(PathStamp(Roots[J]) + '|F|' + Roots[J]) < 0 then
            Cands.Add(PathStamp(Roots[J]) + '|F|' + Roots[J]);
      end;
    for I := 0 to Hinted.Count - 1 do
      if StartsWithStr(Hinted[I], Prefix) then begin
        P := EntryPath(Hinted[I]);
        Cands.Add(EntryStamp(Hinted[I]) + '|H|' + P);
      end;
    Cands.Sort;
    Untested := '';
    UntestedHash := '';
    Tries := 0;
    for I := Cands.Count - 1 downto 0 do begin
      Kind := Copy(Cands[I], 18, 1);
      P := EntryPath(Cands[I]);
      if Kind = 'H' then begin
        if Tries >= DL_MAX_TRIES then
          Continue;
        Tries := Tries + 1;
      end;
      if not CheckArchivePath(A, P, Found, WorkDir, Pinned, Problem, SourceLabel) then begin
        RejectArchive(A, Problem, SourceLabel);
        Continue;
      end;
      if Pinned or ModeVFilesTested(A, Found) then begin
        AcceptArchive(A, Found, WorkDir, Pinned, SourceLabel);
        Result := True;
        Exit;
      end;
      Log(ArchId[A] + ': found ' + SourceLabel + ', not the tested version (' + ModeVHashText(A, Found) +
        '); not taken by itself');
      if Untested = '' then begin
        Untested := SourceLabel;
        UntestedHash := ModeVHashText(A, Found);
      end;
      DelWorkDir(WorkDir);
    end;
    if Untested <> '' then begin
      Ver := ModeVTestedVersion(A);
      if Ver <> '' then
        Ver := ' ' + Ver;
      RejectArchive(A, 'Found ' + Untested + ', but it is not the tested version' + Ver + ' of ' + ArchTitle[A] +
        ' (' + UntestedHash + '). Setup takes only the tested version by itself. To use this one anyway, choose ' +
        'it yourself: "Select archive" or "Select folder" (unattended: /ARCHIVE_' + Uppercase(ArchId[A]) +
        '="path").', Untested);
    end;
  finally
    Cands.Free;
    Roots.Free;
  end;
end;

{ Tries the search results for archive A: pinned archives (newest first),
  then for a mode V archive TryFoundModeV; for a mode P archive extracted
  folders, then archives by name (best name match first, newest first among
  equals, at most DL_MAX_TRIES). True when one was accepted. }
function TryFoundDownloads(const A: Integer; Folders, Pinned, Hinted: TStringList): Boolean;
var
  I, Tries: Integer;
  Prefix, P: String;
begin
  Result := False;
  Prefix := Format('%.3d|', [A]);
  for I := Pinned.Count - 1 downto 0 do
    if StartsWithStr(Pinned[I], Prefix) then begin
      P := EntryPath(Pinned[I]);
      if ArchFileIsPinned(A, P) then begin
        if TryArchivePath(A, P) then begin
          Result := True;
          Exit;
        end;
      end else
        { the exact size of the known download, other bytes: say so instead of "not found" (rc8 switch prep,
          review MINOR); a later candidate can still be accepted }
        RejectArchive(A, 'Found ' + ExtractFileName(P) + ', which has the exact size of the known download but ' +
          'other content (SHA-256 check): it is damaged, incomplete or another version. Download it again.', P);
    end;
  if ArchIsModeV(A) then begin
    Result := TryFoundModeV(A, Folders, Hinted);
    Exit;
  end;
  for I := 0 to Folders.Count - 1 do
    if StartsWithStr(Folders[I], Prefix) then begin
      P := EntryPath(Folders[I]);
      if TryArchivePath(A, P) then begin
        Result := True;
        Exit;
      end;
    end;
  Tries := 0;
  for I := Hinted.Count - 1 downto 0 do
    if StartsWithStr(Hinted[I], Prefix) then begin
      if Tries >= DL_MAX_TRIES then
        Break;
      Tries := Tries + 1;
      P := EntryPath(Hinted[I]);
      if TryArchivePath(A, P) then begin
        Result := True;
        Exit;
      end;
    end;
end;

{ The automatic part of the Downloads page and of a silent run, for every
  needed archive that is not accepted yet: its /ARCHIVE_<ID> switch, then a
  search of /ARCHIVEDIR and (Downloads = True) the Downloads and Vortex
  folders. Only = -1 for every archive, else only that one. Without Force an
  archive already searched for this Convergence folder is not searched again
  (the wizard's Options page: Back/Next must not unpack the same wrong
  archives again; "Search again" forces). }
procedure AutoFindArchives(const Downloads: Boolean; const Only: Integer; const Force: Boolean);
var
  Folders, Pinned, Hinted: TStringList;
  A: Integer;
  Any: Boolean;
begin
  SetArrayLength(DlWanted, ArchCount);
  Any := False;
  for A := 0 to ArchCount - 1 do begin
    DlWanted[A] := ArchNeeded[A] and (ArchState[A] <> AS_ACCEPTED) and ((Only < 0) or (Only = A)) and
      (Force or not PathSame(ArchSearchedFor[A], ConvDir) or (ConvDir = ''));
    if DlWanted[A] and (ParamArch[A] <> '') then begin
      Log(ArchId[A] + ': trying /ARCHIVE_' + Uppercase(ArchId[A]) + '=' + ParamArch[A]);
      if TryArchivePath(A, ParamArch[A]) then
        DlWanted[A] := False;
    end;
    if DlWanted[A] and not Downloads and (ParamArchiveDir = '') then
      ArchSearchedFor[A] := ConvDir;
    if DlWanted[A] then
      Any := True;
  end;
  if not Any or (not Downloads and (ParamArchiveDir = '')) then
    Exit;
  Folders := TStringList.Create;
  Pinned := TStringList.Create;
  Hinted := TStringList.Create;
  try
    FindDownloads(Downloads, ParamArchiveDir, Folders, Pinned, Hinted);
    { what the search found was not picked by the player: its archives get
      the unpacked-size cap (repair 3) }
    SearchUnpack := True;
    try
      for A := 0 to ArchCount - 1 do
        if DlWanted[A] then begin
          TryFoundDownloads(A, Folders, Pinned, Hinted);
          ArchSearchedFor[A] := ConvDir;
        end;
    finally
      SearchUnpack := False;
    end;
  finally
    Folders.Free;
    Pinned.Free;
    Hinted.Free;
  end;
end;

{ CXCXM ARCHIVE <id> missing ... for every needed archive nothing was found
  for (a rejected one was logged when it was refused). }
procedure LogMissingArchives;
var
  A: Integer;
begin
  for A := 0 to ArchCount - 1 do
    if ArchNeeded[A] and (ArchState[A] = AS_MISSING) then
      Log('CXCXM ARCHIVE ' + ArchId[A] + ' missing not provided and not found');
end;

{ One line per needed archive that is not accepted (silent runs' message). }
function MissingArchivesText: String;
var
  A: Integer;
begin
  Result := '';
  for A := 0 to ArchCount - 1 do
    if ArchNeeded[A] and (ArchState[A] <> AS_ACCEPTED) then begin
      Result := Result + '- ' + ArchTitle[A] + ' (by ' + ArchAuthor[A] + ')';
      if ArchNexusUrl[A] <> '' then
        Result := Result + ': ' + ArchNexusUrl[A];
      Result := Result + #13#10;
      if ArchProblem[A] <> '' then
        Result := Result + '  ' + ArchProblem[A] + #13#10;
      Result := Result + '  Pass /ARCHIVE_' + Uppercase(ArchId[A]) + '="archive or extracted folder" ' +
        '(or /ARCHIVEDIR="folder with your downloads").' + #13#10;
    end;
end;

{ The files of mode V archive A as they are now: the accepted download's
  members, else the files in the Convergence folder (in place). }
procedure ModeVCurrentFiles(const A: Integer; var Files: TArrayOfString);
var
  I, M, K: Integer;
begin
  SetArrayLength(Files, ArchMemCount[A]);
  for I := 0 to ArchMemCount[A] - 1 do begin
    M := ArchMemStart[A] + I;
    Files[I] := '';
    if (ArchState[A] = AS_ACCEPTED) and (MemPath[M] <> '') and FileExists(MemPath[M]) then
      Files[I] := MemPath[M]
    else
      for K := 0 to VarCount - 1 do
        if (VarSrc[K] = 'A') and (VarRef[K] = M) then
          Files[I] := ConvPath(PathRel[VarPath[K]]);
  end;
end;

{ The tested-version text of a mode V archive for the marker:
  "tested 1.9.9 (ersc.dll sha256 ...)" when the files are the tested
  version (a pinned archive, or every member's bytes equal the tested
  version's: also files installed by hand), else "not a tested version
  (ersc.dll sha256 ...)". }
function ModeVVersionText(const A: Integer): String;
var
  Files: TArrayOfString;
  Ver, H: String;
  Tested: Boolean;
begin
  ModeVCurrentFiles(A, Files);
  H := ModeVHashText(A, Files);
  if (ArchState[A] = AS_ACCEPTED) and ArchPinned[A] then
    Tested := True
  else
    Tested := ModeVFilesTested(A, Files);
  if Tested then begin
    Ver := ModeVTestedVersion(A);
    if Ver = '' then
      Ver := '(pinned archive)';
    Result := 'tested ' + Ver + ' (' + H + ')';
  end else
    Result := 'not a tested version (' + H + ')';
end;
