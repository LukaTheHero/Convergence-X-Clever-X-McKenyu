{ =============================================================================
  util.iss - small helpers: command line, lists, paths, files, hashing,
  messages, progress, processes.
  ============================================================================= }

function BoolText(const B: Boolean): String;
begin
  if B then Result := 'yes' else Result := 'no';
end;

{ ---------------------------------------------------------------- messages --- }

{ True in /SILENT and /VERYSILENT runs of Setup or of the uninstaller. }
function IsSilentRun: Boolean;
begin
  if IsUninstaller then
    Result := UninstallSilent
  else
    Result := WizardSilent;
end;

{ Message helpers. They are always logged. In silent runs they never open a
  box (even without /SUPPRESSMSGBOXES), so an unattended run cannot hang on a
  click; questions then take DefaultAnswer. Interactive runs show the box,
  which /SUPPRESSMSGBOXES also suppresses. }
procedure ShowError(const Msg: String);
begin
  Log('ERROR: ' + Msg);
  if not IsSilentRun then
    SuppressibleMsgBox(Msg, mbError, MB_OK, IDOK);
end;

procedure ShowInfo(const Msg: String);
begin
  Log('INFO: ' + Msg);
  if not IsSilentRun then
    SuppressibleMsgBox(Msg, mbInformation, MB_OK, IDOK);
end;

function AskYesNo(const Msg: String; const DefaultAnswer: Integer): Boolean;
begin
  Log('QUESTION: ' + Msg);
  if IsSilentRun then begin
    Result := DefaultAnswer = IDYES;
    Log('Silent run: answered ' + BoolText(Result));
  end else
    Result := SuppressibleMsgBox(Msg, mbConfirmation, MB_YESNO, DefaultAnswer) = IDYES;
end;

{ ---------------------------------------------------------------- progress --- }

{ All long operations report through ActiveProgress, which is nil when Setup
  runs silently or before the wizard exists (InitializeSetup). The progress
  page also pumps window messages, which keeps the wizard responsive. }
procedure ProgressText(const Line1, Line2: String);
begin
  if ActiveProgress <> nil then
    ActiveProgress.SetText(Line1, Line2);
end;

procedure ProgressPos(const Position, Max: Integer);
begin
  if ActiveProgress <> nil then
    ActiveProgress.SetProgress(Position, Max);
end;

{ ------------------------------------------------------------------ strings --- }

{ Copy() as a real String function. Pascal Script turns the result of a
  Copy() that is used directly inside another call or a concatenation into an
  AnsiString, which loses every character outside the ANSI code page (a Steam
  library or a user folder named in Chinese, Cyrillic, ...). Only a Copy()
  assigned straight to a variable keeps them. Use SubStr wherever the result
  goes into another expression. }
function SubStr(const S: String; const Index, Count: Integer): String;
begin
  Result := Copy(S, Index, Count);
end;

{ True when S starts with Prefix (exact case). }
function StartsWithStr(const S, Prefix: String): Boolean;
var
  Head: String;
begin
  Head := Copy(S, 1, Length(Prefix));
  Result := Head = Prefix;
end;

function BytesToMB(const Bytes: Int64): String;
begin
  Result := Format('%.1f MB', [Bytes / 1048576.0]);
end;

{ Joins the first MaxItems entries of L with ', ' and appends "and N more". }
function JoinLimited(L: TStringList; const MaxItems: Integer): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to L.Count - 1 do begin
    if I >= MaxItems then begin
      Result := Result + Format(' and %d more', [L.Count - MaxItems]);
      Exit;
    end;
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + L[I];
  end;
end;

function NowForDisplay: String;
begin
  Result := GetDateTimeString('yyyy/mm/dd hh:nn:ss', '-', ':');
end;

{ yyyy-mm-dd_hh-nn-ss, used for backup folder names (sorts chronologically). }
function NowForFolder: String;
begin
  Result := GetDateTimeString('yyyy/mm/dd_hh:nn:ss', '-', '-');
end;

{ ------------------------------------------------------------ command line --- }

{ The value of /Name=value (or -Name=value) on Setup's command line, read
  with ParamStr so a value may hold any character ('=', '|', quotes around
  it are removed). Found tells "not given" apart from "given empty". The
  LAST occurrence wins, like Inno's own switches. }
function CmdParamEx(const Name: String; var Found: Boolean): String;
var
  I, P: Integer;
  S, N, V: String;
begin
  Result := '';
  Found := False;
  for I := 1 to ParamCount do begin
    S := Trim(ParamStr(I));
    if (Length(S) < 2) or ((S[1] <> '/') and (S[1] <> '-')) then
      Continue;
    N := Copy(S, 2, Length(S));
    P := Pos('=', N);
    if P > 0 then begin
      V := Copy(N, P + 1, Length(N));
      N := Copy(N, 1, P - 1);
    end else
      V := '';
    if CompareText(N, Name) = 0 then begin
      Found := True;
      V := Trim(RemoveQuotes(Trim(V)));
      Result := V;
    end;
  end;
end;

function CmdParam(const Name: String): String;
var
  Found: Boolean;
begin
  Result := CmdParamEx(Name, Found);
end;

{ True when Setup (or the uninstaller) runs with administrator rights. Test
  builds only: /TESTASADMIN=1 makes a normal run take the elevated paths
  (no tar, no /NOREDIRECTIONGUARD advice, no me3.exe check) so they can be
  tested without a UAC prompt (repair 3). }
function SetupElevated: Boolean;
begin
  Result := IsAdmin;
#if Defined(CodeCheck) || Defined(TestBuild)
  if not IsUninstaller and (CmdParam('TESTASADMIN') = '1') then
    Result := True;
#endif
end;

{ ------------------------------------------------------------------ lists --- }

{ Splits S at every Sep (no trimming, empty pieces kept, '' gives no piece). }
procedure SplitStr(const S, Sep: String; var Parts: TArrayOfString);
var
  Rest, Piece: String;
  P, N: Integer;
begin
  SetArrayLength(Parts, 0);
  if S = '' then
    Exit;
  Rest := S;
  N := 0;
  while True do begin
    P := Pos(Sep, Rest);
    if P = 0 then begin
      SetArrayLength(Parts, N + 1);
      Parts[N] := Rest;
      Exit;
    end;
    Piece := Copy(Rest, 1, P - 1);
    SetArrayLength(Parts, N + 1);
    Parts[N] := Piece;
    N := N + 1;
    Rest := Copy(Rest, P + Length(Sep), Length(Rest));
  end;
end;

{ True when Item is one of the comma separated entries of List (case-insensitive). }
function CommaListHas(const List, Item: String): Boolean;
begin
  Result := (Item <> '') and (Pos(',' + Lowercase(Item) + ',', ',' + Lowercase(List) + ',') > 0);
end;

{ 31519 -> '31,519' }
function FormatThousands(const N: Int64): String;
var
  S: String;
  I, Digits: Integer;
  Neg: Boolean;
begin
  Neg := N < 0;
  if Neg then
    S := IntToStr(-N)
  else
    S := IntToStr(N);
  Result := '';
  Digits := 0;
  for I := Length(S) downto 1 do begin
    if (Digits > 0) and ((Digits mod 3) = 0) then
      Result := ',' + Result;
    Result := S[I] + Result;
    Digits := Digits + 1;
  end;
  if Neg then
    Result := '-' + Result;
end;

{ -------------------------------------------------------------------- paths --- }

{ Trims, strips quotes, turns / into \, makes absolute and drops the trailing
  backslash (except for a drive root). Returns '' for empty input. }
function NormalizeDir(const S: String): String;
begin
  Result := Trim(RemoveQuotes(Trim(S)));
  if Result = '' then
    Exit;
  StringChangeEx(Result, '/', '\', True);
  Result := RemoveBackslashUnlessRoot(ExpandFileName(Result));
end;

{ True when Path is Parent itself or anything below it (case-insensitive). }
function PathIsWithin(const Path, Parent: String): Boolean;
var
  P, R: String;
begin
  P := AddBackslash(Lowercase(NormalizeDir(Path)));
  R := AddBackslash(Lowercase(NormalizeDir(Parent)));
  Result := (R <> '\') and StartsWithStr(P, R);
end;

{ A relative path that stays inside the folder it is relative to: not empty,
  no drive or stream (':'), not rooted, and no component that is '.', '..'
  or only dots and spaces (Windows drops trailing dots and spaces, so '...'
  or '.. ' would climb too). A file NAME that merely contains '..' (for
  example 'a..b.dcx') is fine. }
function IsSafeRelPath(const Rel: String): Boolean;
var
  S, Part, Rest: String;
  P: Integer;
begin
  Result := False;
  if (Rel = '') or (Pos(':', Rel) > 0) then
    Exit;
  S := Rel;
  StringChangeEx(S, '/', '\', True);
  if S[1] = '\' then
    Exit;
  S := S + '\';
  while S <> '' do begin
    P := Pos('\', S);
    Part := Copy(S, 1, P - 1);
    Rest := Copy(S, P + 1, Length(S));
    S := Rest;
    StringChangeEx(Part, '.', '', True);
    StringChangeEx(Part, ' ', '', True);
    if Part = '' then
      Exit;
  end;
  Result := True;
end;

function ConvPath(const Rel: String): String;
begin
  Result := AddBackslash(ConvDir) + Rel;
end;

{ Volume label of the drive that holds Path ('' when unknown). }
function GetVolumeLabelOf(const Path: String): String;
var
  Root, Buf, NoName: String;
  Serial, MaxLen, Flags: Cardinal;
  P: Integer;
begin
  Result := '';
  Root := AddBackslash(ExtractFileDrive(Path));
  if Root = '\' then
    Exit;
  Buf := StringOfChar(' ', 261);
  NoName := '';
  if GetVolumeInformationW(Root, Buf, 261, Serial, MaxLen, Flags, NoName, 0) then begin
    P := Pos(#0, Buf);
    if P > 0 then
      Result := Copy(Buf, 1, P - 1)
    else
      Result := Trim(Buf);
  end;
end;

{ -------------------------------------------------------------------- files --- }

function GetFileSizeSafe(const FileName: String): Int64;
begin
  if not FileSize64(FileName, Result) then
    Result := -1;
end;

{ MD5 of a file, lowercase hex; '' when the file cannot be read. }
function SafeMD5(const FileName: String): String;
begin
  Result := '';
  try
    Result := Lowercase(GetMD5OfFile(FileName));
  except
    Log('MD5 failed for ' + FileName + ': ' + GetExceptionMessage);
    Result := '';
  end;
end;

function FileHasMD5(const FileName, WantMd5: String): Boolean;
begin
  Result := FileExists(FileName) and (CompareText(SafeMD5(FileName), WantMd5) = 0);
end;

{ SHA-256 of a file, lowercase hex; '' when the file cannot be read. }
function SafeSHA256(const FileName: String): String;
begin
  Result := '';
  try
    Result := Lowercase(GetSHA256OfFile(FileName));
  except
    Log('SHA-256 failed for ' + FileName + ': ' + GetExceptionMessage);
    Result := '';
  end;
end;

{ The size and last-write time of a file as one key ('' when it does not
  exist): a changed file gets a new key, so the hash cache never answers
  for old bytes. }
function FileStampKey(const FileName: String): String;
var
  FR: TFindRec;
  Size, Low: Int64;
begin
  Result := '';
  if not FindFirst(FileName, FR) then
    Exit;
  try
    if (FR.Attributes and FA_DIRECTORY) = 0 then begin
      Size := FR.SizeHigh;
      Size := Size * 65536;
      Size := Size * 65536;
      Low := FR.SizeLow;
      Size := Size + Low;
      Result := Lowercase(FileName) + '|' + IntToStr(Size) + '|' +
        Format('%.8x%.8x', [FR.LastWriteTime.dwHighDateTime, FR.LastWriteTime.dwLowDateTime]);
    end;
  finally
    FindClose(FR);
  end;
end;

{ The last-write time of a file or folder as 16 hex digits (sorts in time
  order); '0000000000000000' when it cannot be read. }
function PathStamp(const Path: String): String;
var
  FR: TFindRec;
begin
  Result := '0000000000000000';
  if not FindFirst(RemoveBackslashUnlessRoot(Path), FR) then
    Exit;
  try
    Result := Format('%.8x%.8x', [FR.LastWriteTime.dwHighDateTime, FR.LastWriteTime.dwLowDateTime]);
  finally
    FindClose(FR);
  end;
end;

procedure ShaCacheReset;
begin
  if ShaCacheKey = nil then begin
    ShaCacheKey := TStringList.Create;
    ShaCacheVal := TStringList.Create;
  end;
  ShaCacheKey.Clear;
  ShaCacheVal.Clear;
end;

{ Forgets every cached hash of FileName (it was just written or deleted: a
  copy keeps the source's last-write time, so size + time alone could match
  the old bytes' entry). }
procedure ShaCacheForget(const FileName: String);
var
  I: Integer;
  Prefix: String;
begin
  if ShaCacheKey = nil then
    Exit;
  Prefix := Lowercase(FileName) + '|';
  { StartsWithStr, not Copy() in the comparison: see SubStr (non-ANSI paths) }
  for I := ShaCacheKey.Count - 1 downto 0 do
    if StartsWithStr(ShaCacheKey[I], Prefix) then begin
      ShaCacheKey.Delete(I);
      ShaCacheVal.Delete(I);
    end;
end;

{ Forgets every cached hash of a file below Dir. Called before a folder is
  deleted and when a fresh one is made: a later folder may hold other bytes
  under the same names, sizes and times (tar and 7-Zip restore the times
  from the archive, and a truncated member is padded to its full size). }
procedure ShaCacheForgetUnder(const Dir: String);
var
  I: Integer;
  Prefix: String;
begin
  if (ShaCacheKey = nil) or (Dir = '') then
    Exit;
  Prefix := AddBackslash(Lowercase(Dir));
  for I := ShaCacheKey.Count - 1 downto 0 do
    if StartsWithStr(ShaCacheKey[I], Prefix) then begin
      ShaCacheKey.Delete(I);
      ShaCacheVal.Delete(I);
    end;
end;

{ SHA-256 of a file, cached by path + size + last-write time (big files are
  hashed once per run even when several steps ask). '' when unreadable. }
function FileSha256(const FileName: String): String;
var
  Key: String;
  Idx: Integer;
begin
  Result := '';
  Key := FileStampKey(FileName);
  if Key = '' then
    Exit;
  if ShaCacheKey = nil then
    ShaCacheReset;
  Idx := ShaCacheKey.IndexOf(Key);
  if Idx >= 0 then begin
    Result := ShaCacheVal[Idx];
    Exit;
  end;
  Result := SafeSHA256(FileName);
  if Result <> '' then begin
    ShaCacheKey.Add(Key);
    ShaCacheVal.Add(Result);
  end;
end;

{ True when the file exists with this size (WantSize < 0: any size) and
  this SHA-256 (the size is checked first: no hashing of a file that
  cannot match). }
function FileHasSHA256(const FileName, WantSha: String; const WantSize: Int64): Boolean;
var
  Size: Int64;
begin
  Result := False;
  if (WantSha = '') or not FileExists(FileName) then
    Exit;
  if WantSize >= 0 then begin
    if not FileSize64(FileName, Size) then
      Exit;
    if Size <> WantSize then
      Exit;
  end;
  Result := CompareText(FileSha256(FileName), WantSha) = 0;
end;

{ Clears read-only/hidden/system so the file can be overwritten or deleted. }
procedure MakeFileWritable(const FileName: String);
var
  Attr: Cardinal;
begin
  Attr := GetFileAttributesW(FileName);
  if (Attr <> $FFFFFFFF) and ((Attr and (FA_READONLY or FA_HIDDEN or FA_SYSTEM)) <> 0) then
    SetFileAttributesW(FileName, FA_NORMAL);
end;

function DeleteFileForced(const FileName: String): Boolean;
begin
  if not FileExists(FileName) then begin
    Result := True;
    Exit;
  end;
  MakeFileWritable(FileName);
  ShaCacheForget(FileName);
  Result := DeleteFile(FileName);
end;

{ The number of names (NTFS hard links) of a file; 0 when it cannot be told.
  The file is opened for no access at all (attributes only), which works
  even while another program holds it without sharing. }
function FileLinkCount(const FileName: String): Integer;
var
  H: THandle;
  Info: TCxByHandleFileInfo;
begin
  Result := 0;
  H := CxCreateFileW(FileName, 0, WIN_FILE_SHARE_ALL, 0, WIN_OPEN_EXISTING, 0, 0);
  try
    if CxGetFileInformationByHandle(H, Info) then
      Result := Info.nNumberOfLinks;
  finally
    CxCloseHandle(H);
  end;
end;

{ True when an existing file may be written in place (the last resort when
  it cannot be replaced): only a file with exactly one name. A file with more
  names (an NTFS hard link to a file outside the Convergence folder) is never
  written through: the step fails instead, which leads to the rollback
  (repair 3, code review LOW: the residual of repair 2's D2). }
function InPlaceWriteAllowed(const FileName: String): Boolean;
var
  N: Integer;
begin
  N := FileLinkCount(FileName);
  Result := N = 1;
  if not Result then
    Log(Format('Not written in place: %s has %d name(s) (hard links) or cannot be checked; this step fails ' +
      'instead', [FileName, N]));
end;

{ Writes the bytes of a file Setup has just written (a temporary file) from
  Windows' cache to the disk (FlushFileBuffers), so the rename that gives
  it its name never makes a name point at bytes a power cut could lose
  (repair 5). False (logged, not fatal: the rename still keeps a stop by
  Task Manager or a crash safe) when the file cannot be opened. }
function FlushFileToDisk(const FileName: String): Boolean;
var
  H: THandle;
  Attr: Cardinal;
  Err: Integer;
  WasReadOnly: Boolean;
begin
  { a copy of a read-only file is read-only too (CopyFile copies the
    attributes), and FlushFileBuffers needs write access: the flag is taken
    off this temporary file (Setup's own, one name) for the flush and put
    back (the sixth verifier's read-only profiles: repair 5) }
  Attr := GetFileAttributesW(FileName);
  WasReadOnly := (Attr <> $FFFFFFFF) and ((Attr and FA_READONLY) <> 0);
  if WasReadOnly then
    SetFileAttributesW(FileName, Attr and not FA_READONLY);
  H := CxCreateFileW(FileName, WIN_GENERIC_WRITE, WIN_FILE_SHARE_ALL, 0, WIN_OPEN_EXISTING, WIN_FILE_ATTR_NORMAL, 0);
  try
    Result := CxFlushFileBuffers(H);
    Err := DLLGetLastError;
  finally
    CxCloseHandle(H);
  end;
  if WasReadOnly then
    SetFileAttributesW(FileName, Attr);
  if not Result then
    Log('Could not flush ' + FileName + ' to the disk (' + SysErrorMessage(Err) + '); continuing');
end;

{ Moves Tmp to Dest (MoveFileEx, replace; Dest may exist or not). A rename
  on the same folder replaces Dest's directory entry: when Dest is one name
  of an NTFS hard link (a second Convergence copy made with links, a dedupe
  tool) the other names keep their bytes, so Setup never writes outside the
  Convergence folder through a link (code review repair 2, D2); and Dest is
  either its old file or the complete new one at every moment, so a Setup
  stopped hard never leaves a half-written Dest (repair 5). A read-only
  Dest is made writable only when the first try fails (a hard-linked file's
  attributes are shared by all its names). False: Tmp is deleted, Dest is
  unchanged. }
function ReplaceFileWithTemp(const Tmp, Dest: String): Boolean;
var
  Attempt, Err, Wait: Integer;
begin
  Result := False;
  Err := 0;
  { repair 6 (code review of repair 5, LOW): every new file needs this rename
    now, and an antivirus scanner may hold a fresh file for a moment. A
    sharing or access error is tried again for about 4 seconds in all (the
    first retry right after making Dest writable); any other error, and
    the last attempt, end at once. }
  for Attempt := 1 to 8 do begin
    if MoveFileExW(Tmp, Dest, MOVE_REPLACE_EXISTING or MOVE_WRITE_THROUGH) then begin
      Result := True;
      Break;
    end;
    Err := DLLGetLastError;
    if Attempt = 8 then
      Break;
    if Attempt = 1 then begin
      MakeFileWritable(Dest);
      Continue;
    end;
    { 5 = access denied, 32 = sharing violation, 33 = lock violation }
    if (Err <> 5) and (Err <> 32) and (Err <> 33) then
      Break;
    Wait := 150 * (Attempt - 1);
    if Wait > 1000 then
      Wait := 1000;
    Sleep(Wait);
  end;
  ShaCacheForget(Dest);
  ShaCacheForget(Tmp);
  if not Result then begin
    Log('Could not replace ' + Dest + ' with ' + Tmp + ': ' + SysErrorMessage(Err));
    DeleteFileForced(Tmp);
  end;
end;

{ Gives the complete temporary file Tmp the name Dest: flushed to the disk,
  then moved to Dest (ReplaceFileWithTemp). False: Tmp is gone, Dest is
  unchanged. }
function CommitTempFile(const Tmp, Dest: String): Boolean;
begin
  FlushFileToDisk(Tmp);
  Result := ReplaceFileWithTemp(Tmp, Dest);
end;

{ Writes S (bytes) to FileName through a temporary file next to it
  (FileName + REPLACE_TMP_SUFFIX) that is then moved to its name
  (CommitTempFile) - a new file too (repair 5: a stop never leaves a
  half-written file under the name). Only an EXISTING file that cannot be
  replaced (another program holds it without delete sharing) is written in
  place instead, as before repair 2 (never through a hard link: repair 3). }
function SaveBytesReplacing(const FileName: String; const S: AnsiString): Boolean;
var
  Tmp: String;
  Existed: Boolean;
begin
  ShaCacheForget(FileName);
  Existed := FileExists(FileName);
  Tmp := FileName + REPLACE_TMP_SUFFIX;
  if FileExists(Tmp) then
    DeleteFileForced(Tmp);
  Result := SaveStringToFile(Tmp, S, False);
  if Result then
    Result := CommitTempFile(Tmp, FileName)
  else begin
    Log('Cannot write ' + Tmp);
    DeleteFile(Tmp);
  end;
  if not Result and Existed and InPlaceWriteAllowed(FileName) then begin
    Log('Writing ' + FileName + ' in place instead');
    MakeFileWritable(FileName);
    Result := SaveStringToFile(FileName, S, False);
  end;
  ShaCacheForget(FileName);
end;

{ The same for lines saved as UTF-8 without BOM, CRLF (SaveStringsToUTF8FileWithoutBOM). }
function SaveLinesUTF8Replacing(const FileName: String; const Lines: TArrayOfString): Boolean;
var
  Tmp: String;
  Existed: Boolean;
begin
  ShaCacheForget(FileName);
  Existed := FileExists(FileName);
  Tmp := FileName + REPLACE_TMP_SUFFIX;
  if FileExists(Tmp) then
    DeleteFileForced(Tmp);
  Result := SaveStringsToUTF8FileWithoutBOM(Tmp, Lines, False);
  if Result then
    Result := CommitTempFile(Tmp, FileName)
  else begin
    Log('Cannot write ' + Tmp);
    DeleteFile(Tmp);
  end;
  if not Result and Existed and InPlaceWriteAllowed(FileName) then begin
    Log('Writing ' + FileName + ' in place instead');
    MakeFileWritable(FileName);
    Result := SaveStringsToUTF8FileWithoutBOM(FileName, Lines, False);
  end;
  ShaCacheForget(FileName);
end;

{ Copies Src to Dest, creating Dest's folder. The copy ALWAYS goes to
  Dest + REPLACE_TMP_SUFFIX first; when it is complete (size checked) it is
  flushed to the disk and moved to Dest (CommitTempFile: no write through a
  hard link, and - repair 5, sixth verifier DEFECT 1 - no half-written file
  under Dest when Setup is stopped hard, for a NEW Dest as well: before, a
  new file was copied straight to its name, and a stop left a partial file
  there that the uninstall then kept as another mod's file). Only an
  EXISTING Dest that cannot be replaced (another program holds it without
  delete sharing) is copied over in place, as before repair 2 - and only
  when it has one name: a hard-linked Dest makes the copy fail (repair 3).
  Verifies the copy by size. }
function CopyFileChecked(const Src, Dest: String): Boolean;
var
  SrcSize: Int64;
  Tmp: String;
  Done, Existed: Boolean;
begin
  Result := False;
  if not ForceDirectories(ExtractFileDir(Dest)) then begin
    Log('Cannot create folder ' + ExtractFileDir(Dest));
    Exit;
  end;
  ShaCacheForget(Dest);
  SrcSize := GetFileSizeSafe(Src);
  Existed := FileExists(Dest);
  Done := False;
  Tmp := Dest + REPLACE_TMP_SUFFIX;
  if FileExists(Tmp) then
    DeleteFileForced(Tmp);
  if CopyFile(Src, Tmp, False) then begin
    ShaCacheForget(Tmp);
    if (SrcSize >= 0) and (GetFileSizeSafe(Tmp) = SrcSize) then
      Done := CommitTempFile(Tmp, Dest)
    else begin
      Log('Size mismatch after copy: ' + Src + ' -> ' + Tmp);
      DeleteFileForced(Tmp);
    end;
  end else begin
    Log('CopyFile failed: ' + Src + ' -> ' + Tmp);
    DeleteFile(Tmp);
  end;
  if not Done then begin
    { a new file is never written under its own name directly }
    if not Existed then
      Exit;
    if not InPlaceWriteAllowed(Dest) then
      Exit;
    Log('Writing ' + Dest + ' in place instead');
    MakeFileWritable(Dest);
    if not CopyFile(Src, Dest, False) then begin
      Log('CopyFile failed: ' + Src + ' -> ' + Dest);
      Exit;
    end;
  end;
  ShaCacheForget(Dest);
  Result := (SrcSize >= 0) and (SrcSize = GetFileSizeSafe(Dest));
  if not Result then
    Log('Size mismatch after copy: ' + Src + ' -> ' + Dest);
end;


{ First non-empty line of a small text file, trimmed ('' if missing). }
function ReadFirstLine(const FileName: String): String;
var
  Lines: TArrayOfString;
  I: Integer;
begin
  Result := '';
  if not LoadStringsFromFile(FileName, Lines) then
    Exit;
  for I := 0 to GetArrayLength(Lines) - 1 do begin
    if Trim(Lines[I]) <> '' then begin
      Result := Trim(Lines[I]);
      Exit;
    end;
  end;
end;

{ ------------------------------------------------------------ folder links --- }

{ The first component of Path (from the drive root down) that is an NTFS
  junction or symbolic link, '' when none (or when a component cannot be
  listed). FindFirst on the component itself lists its parent folder, so it
  never follows the link. }
function FirstLinkInPath(const Path: String): String;
var
  Parts: TArrayOfString;
  Cur: String;
  I: Integer;
  FR: TFindRec;
begin
  Result := '';
  SplitStr(RemoveBackslashUnlessRoot(NormalizeDir(Path)), '\', Parts);
  if GetArrayLength(Parts) < 2 then
    Exit;
  Cur := Parts[0];
  for I := 1 to GetArrayLength(Parts) - 1 do begin
    if Parts[I] = '' then
      Continue;
    Cur := Cur + '\' + Parts[I];
    if not FindFirst(Cur, FR) then
      Exit;
    try
      if (FR.Attributes and FA_REPARSE_POINT) <> 0 then begin
        Result := Cur;
        Exit;
      end;
    finally
      FindClose(FR);
    end;
  end;
end;

{ Where the link Link points ('' when unknown), read from "dir /AL" of its
  parent folder in a child process (Windows' RedirectionGuard only guards
  Setup's own process). }
function LinkTarget(const Link: String): String;
var
  Output: TExecOutput;
  ResultCode, I, P, Q: Integer;
  L, Key: String;
begin
  Result := '';
  try
    if not ExecAndCaptureOutput(ExpandConstant('{cmd}'), '/C dir /AL "' + ExtractFileDir(Link) + '"', '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode, Output) then
      Exit;
  except
    Exit;
  end;
  Key := ' ' + Lowercase(ExtractFileName(Link)) + ' [';
  for I := 0 to GetArrayLength(Output.StdOut) - 1 do begin
    L := Output.StdOut[I];
    if (Pos('<JUNCTION>', L) = 0) and (Pos('<SYMLINKD>', L) = 0) and (Pos('<SYMLINK>', L) = 0) then
      Continue;
    P := Pos(Key, Lowercase(L));
    if P = 0 then
      Continue;
    L := Copy(L, P + Length(Key), Length(L));
    Q := Length(L);
    while (Q > 0) and (L[Q] <> ']') do
      Q := Q - 1;
    if Q > 1 then begin
      Result := Copy(L, 1, Q - 1);
      Exit;
    end;
  end;
end;

{ '' when Path is not reached through a folder link, else a note for the
  player: Inno Setup 6.7 turns on Windows' RedirectionGuard, which blocks
  links that a normal (not elevated) user made, so such a folder looks like
  it does not exist (code review repair 2, D1). }
function LinkBlockedNote(const Path: String): String;
var
  Link, Target, Real: String;
begin
  Result := '';
  Link := FirstLinkInPath(Path);
  if Link = '' then
    Exit;
  Target := LinkTarget(Link);
  Real := '';
  if Target <> '' then begin
    Real := NormalizeDir(Path);
    Real := Copy(Real, Length(Link) + 1, Length(Real));
    Real := RemoveBackslashUnlessRoot(Target) + Real;
  end;
  Result := 'This path goes through a folder link (junction): ' + Link;
  if Target <> '' then
    Result := Result + ' -> ' + Target;
  Result := Result + '. Windows lets installers follow only links that an administrator made, so Setup cannot ' +
    'see the folder behind it.';
  if Real <> '' then
    Result := Result + ' Use the real folder instead: ' + Real
  else
    Result := Result + ' Use the real folder the link points to instead.';
  { /NOREDIRECTIONGUARD only for a Setup that is not elevated: as administrator the guard is what keeps a link a
    normal user made from redirecting Setup's writes (repair 3, code review LOW) }
  if SetupElevated then
    Result := Result + ' (Or make the link again from an administrator Command Prompt with mklink /J.)'
  else
    Result := Result + ' (Or make the link again from an administrator Command Prompt with mklink /J, or start ' +
      'Setup with /NOREDIRECTIONGUARD.)';
  Log('Folder link in the path: ' + Link + ' -> ' + Target);
end;

{ Tries to create and delete a small file in Dir. }
function CanWriteToDir(const Dir: String): Boolean;
var
  Probe: String;
begin
  Probe := AddBackslash(Dir) + 'CXCXM_write_test_' + NowForFolder + '.tmp';
  Result := SaveStringToFile(Probe, 'write test', False);
  if Result then
    DeleteFile(Probe);
end;

function IsArchiveFileName(const FileName: String): Boolean;
var
  Ext: String;
begin
  Ext := Lowercase(ExtractFileExt(FileName));
  Result := (Ext = '.zip') or (Ext = '.7z') or (Ext = '.rar');
end;

{ The user's Downloads folder (it can be redirected, so ask Explorer first). }
function GetDownloadsDir: String;
begin
  Result := '';
#if Defined(CodeCheck) || Defined(TestBuild)
  { test builds only: /TESTDOWNLOADS="folder" replaces the Downloads folder }
  Result := CmdParam('TESTDOWNLOADS');
  if Result <> '' then
    Exit;
#endif
  if not RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
    '{374DE290-123F-4565-9164-39C4925E467B}', Result) then
    Result := '';
  if (Result = '') or not DirExists(Result) then
    Result := AddBackslash(GetEnv('USERPROFILE')) + 'Downloads';
end;

{ ---------------------------------------------------------------- processes --- }

{ Uses WMI; falls back to tasklist.exe. Returns False if neither works. }
function IsProcessRunning(const ExeName: String): Boolean;
var
  Locator, Services, Found: Variant;
  ResultCode, I: Integer;
  Output: TExecOutput;
begin
  Result := False;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Services := Locator.ConnectServer('.', 'root\CIMV2');
    Found := Services.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE Name = ''' + ExeName + '''');
    Result := Found.Count > 0;
    Exit;
  except
    Log('WMI process query failed (' + GetExceptionMessage + '), trying tasklist');
  end;
  try
    if ExecAndCaptureOutput(ExpandConstant('{sys}\tasklist.exe'),
      '/FI "IMAGENAME eq ' + ExeName + '" /NH /FO CSV', '', SW_HIDE, ewWaitUntilTerminated,
      ResultCode, Output) then
    begin
      for I := 0 to GetArrayLength(Output.StdOut) - 1 do
        if Pos(Lowercase('"' + ExeName + '"'), Lowercase(Output.StdOut[I])) > 0 then
          Result := True;
    end;
  except
    Log('tasklist failed: ' + GetExceptionMessage);
  end;
end;

function EldenRingRunning: Boolean;
begin
  Result := IsProcessRunning(GAME_EXE_NAME);
  if Result then
    Log(GAME_EXE_NAME + ' is running');
end;

{ Interactive gate: loops with Retry/Cancel while the game runs. }
function WaitForEldenRingClosed: Boolean;
begin
  Result := True;
  while EldenRingRunning do begin
    if WizardSilent then begin
      Result := False;
      Exit;
    end;
    if MsgBox('Elden Ring (eldenring.exe) is running.' + #13#10#13#10 +
      'Close the game completely, then click Retry.' + #13#10 +
      'Setup will not change any file while the game is running.',
      mbError, MB_RETRYCANCEL) <> IDRETRY then
    begin
      Result := False;
      Exit;
    end;
  end;
end;
