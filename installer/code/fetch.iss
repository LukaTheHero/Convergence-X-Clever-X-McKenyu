{ =============================================================================
  fetch.iss - the hosted files ("blobs": Lucy, Infinite Durations, the merged
  Nightreign Movement files, Infinite Arrows, ERCapacityExpansion, the
  Convergence originals NRM replaces) are downloaded BEFORE the backup, so a
  network problem never leaves a half-changed Convergence folder
  (contract 5.5).

  Every wanted variant whose source is a blob and that is not in place
  already is fetched once per blob into Setup's temp folder (cxcxm_blobs)
  with Inno's own SHA-256 check. URLs, in order: BlobUpstream (the author's
  own release, unless /UPSTREAM=0), then every mirror BaseUrls[i] + BlobTag
  + '/' + BlobAsset (/BASEURL= replaces the mirror list). The wizard shows
  Inno's download page (with an Abort button); a silent run uses
  DownloadTemporaryFile. Any failure: nothing was changed; the wizard stays
  on the Ready page, a silent run ends with exit code 7 (PrepareToInstall).
  ============================================================================= }

var
  FetchPage: TDownloadWizardPage;

{ Setup's temp folder for the downloaded blobs. }
function BlobDir: String;
begin
  Result := ExpandConstant('{tmp}\') + BLOB_DIR_NAME;
end;

function BlobLocalPath(const B: Integer): String;
begin
  Result := AddBackslash(BlobDir) + BlobAsset[B];
end;

{ The URLs to try for blob B, in order: the author's own release (unless
  /UPSTREAM=0), then the release mirrors - or, for a file of another
  download site (BlobSite; CAT_FORMAT 2), that site only. /BASEURL= (the
  tests' local server, or a full mirror) replaces every root. }
procedure BlobUrls(const B: Integer; Urls: TStringList);
var
  I: Integer;
begin
  Urls.Clear;
  if (BlobUpstream[B] <> '') and UseUpstream then
    Urls.Add(BlobUpstream[B]);
  if (BlobSite[B] = '') or BaseUrlsReplaced then begin
    for I := 0 to GetArrayLength(BaseUrls) - 1 do
      Urls.Add(BaseUrls[I] + BlobTag[B] + '/' + BlobAsset[B]);
  end else
    Urls.Add(BlobSite[B] + BlobTag[B] + '/' + BlobAsset[B]);
end;

{ The host part of a URL. }
function UrlHost(const Url: String): String;
var
  S: String;
  P: Integer;
begin
  S := Url;
  P := Pos('://', S);
  if P > 0 then
    S := Copy(S, P + 3, Length(S));
  P := Pos('/', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  Result := S;
end;

{ The hosts the needed downloads come from (for the Ready page; BlobNeeded
  must be up to date): the first URL of each needed blob. }
function MirrorHostText: String;
var
  Urls, Hosts: TStringList;
  B: Integer;
  H: String;
begin
  Result := '(no download address)';
  Urls := TStringList.Create;
  Hosts := TStringList.Create;
  try
    for B := 0 to BlobCount - 1 do begin
      if not BlobNeeded[B] then
        Continue;
      BlobUrls(B, Urls);
      if Urls.Count = 0 then
        Continue;
      H := UrlHost(Urls[0]);
      if Hosts.IndexOf(H) < 0 then
        Hosts.Add(H);
    end;
    if Hosts.Count = 0 then begin
      if GetArrayLength(BaseUrls) > 0 then
        Result := UrlHost(BaseUrls[0]);
    end else
      Result := JoinLimited(Hosts, 4);
  finally
    Urls.Free;
    Hosts.Free;
  end;
end;

{ ------------------------------------------------------------- what to get --- }

{ The blobs this run needs: every wanted, not-in-place variant taken from a
  blob (VarSkip must be up to date: BuildBackupPlan). }
procedure ComputeNeededBlobs;
var
  P, K, B: Integer;
begin
  for B := 0 to BlobCount - 1 do
    BlobNeeded[B] := False;
  FetchFiles := 0;
  FetchBytes := 0;
  for P := 0 to PathCount - 1 do begin
    K := DesiredVariant(P);
    if (K < 0) or VarSkip[K] or (VarSrc[K] <> 'B') then
      Continue;
    B := VarRef[K];
    if not BlobNeeded[B] then begin
      BlobNeeded[B] := True;
      FetchFiles := FetchFiles + 1;
      FetchBytes := FetchBytes + BlobSize[B];
    end;
  end;
end;

{ The same, for the Ready page, before the plan exists: a variant counts as
  in place when the file there has its sha256 (cached hashing). }
procedure ComputeFetchPreview;
var
  P, K, B, Total: Integer;
begin
  for B := 0 to BlobCount - 1 do
    BlobNeeded[B] := False;
  FetchFiles := 0;
  FetchBytes := 0;
  Total := PathCount;
  for P := 0 to Total - 1 do begin
    K := DesiredVariant(P);
    if (K < 0) or (VarSrc[K] <> 'B') then
      Continue;
    B := VarRef[K];
    if BlobNeeded[B] then
      Continue;
    ProgressText(Format('Checking which files must be downloaded (%d of %d)...', [P + 1, Total]), PathRel[P]);
    ProgressPos(P, Total);
    if not VariantInPlace(K) then begin
      BlobNeeded[B] := True;
      FetchFiles := FetchFiles + 1;
      FetchBytes := FetchBytes + BlobSize[B];
    end;
  end;
  ProgressPos(Total, Total);
  Log(Format('Download preview: %d file(s), %s', [FetchFiles, BytesToMB(FetchBytes)]));
end;

{ ---------------------------------------------------------------- download --- }

function FetchProgress(const Url, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  Result := True;
end;

{ Moves Inno's download (Setup's temp folder\<asset>) into cxcxm_blobs. }
function KeepDownloaded(const B: Integer): Boolean;
var
  Src, Dst: String;
begin
  Src := ExpandConstant('{tmp}\') + BlobAsset[B];
  Dst := BlobLocalPath(B);
  Result := False;
  if not FileExists(Src) then begin
    Log('Downloaded file not found: ' + Src);
    Exit;
  end;
  if FileExists(Dst) then
    DeleteFileForced(Dst);
  if RenameFile(Src, Dst) then
    Result := True
  else if CopyFileChecked(Src, Dst) then begin
    DeleteFile(Src);
    Result := True;
  end;
  { Inno checked the SHA-256 while downloading; the rename keeps the bytes }
  if Result then
    Result := GetFileSizeSafe(Dst) = BlobSize[B];
end;

{ Fetches blob B (unless a checked copy is there). Reason: why it failed. }
function FetchOneBlob(const B: Integer; var Reason: String): Boolean;
var
  Urls: TStringList;
  I: Integer;
begin
  Result := False;
  Reason := '';
  if FileHasSHA256(BlobLocalPath(B), BlobSha[B], BlobSize[B]) then begin
    BlobPath[B] := BlobLocalPath(B);
    Log('CXCXM FETCH ' + BlobAsset[B] + ' ok (already downloaded in this run)');
    Result := True;
    Exit;
  end;
  Urls := TStringList.Create;
  try
    BlobUrls(B, Urls);
    if Urls.Count = 0 then begin
      Reason := 'no download address';
      Log('CXCXM FETCH ' + BlobAsset[B] + ' fail - ' + Reason);
      Exit;
    end;
    for I := 0 to Urls.Count - 1 do begin
      try
        if (FetchPage <> nil) and not WizardSilent then begin
          FetchPage.Clear;
          FetchPage.Add(Urls[I], BlobAsset[B], BlobSha[B]);
          FetchPage.Download;
        end else
          DownloadTemporaryFile(Urls[I], BlobAsset[B], BlobSha[B], @FetchProgress);
        if KeepDownloaded(B) then begin
          BlobPath[B] := BlobLocalPath(B);
          Log('CXCXM FETCH ' + BlobAsset[B] + ' ok ' + Urls[I]);
          Result := True;
          Exit;
        end;
        Reason := 'the downloaded file could not be kept';
        Log('CXCXM FETCH ' + BlobAsset[B] + ' fail ' + Urls[I] + ' ' + Reason);
      except
        Reason := GetExceptionMessage;
        Log('CXCXM FETCH ' + BlobAsset[B] + ' fail ' + Urls[I] + ' ' + Reason);
        if (FetchPage <> nil) and not WizardSilent and FetchPage.AbortedByUser then begin
          Reason := 'cancelled';
          Exit;
        end;
      end;
    end;
  finally
    Urls.Free;
  end;
end;

{ The downloads of a Setup that was stopped hard (Task Manager, a crash, a
  power cut): its own temp folder (%TEMP%\is-*.tmp) is never deleted, and
  with it up to about 0.5 GB of downloads in cxcxm_blobs. Only that
  subfolder - this installer's own name - of every OTHER is-*.tmp folder
  next to this Setup's own is deleted; one Setup runs at a time
  (SetupMutex), so none of them is in use (repair 5). }
procedure DeleteStaleBlobDirs;
var
  FR: TFindRec;
  Own, Parent, D: String;
begin
  Own := RemoveBackslashUnlessRoot(ExpandConstant('{tmp}'));
  Parent := ExtractFileDir(Own);
  if (Parent = '') or not FindFirst(AddBackslash(Parent) + 'is-*.tmp', FR) then
    Exit;
  try
    repeat
      if ((FR.Attributes and FA_DIRECTORY) <> 0) and ((FR.Attributes and FA_REPARSE_POINT) = 0) then begin
        D := AddBackslash(Parent) + FR.Name;
        if not PathSame(D, Own) and DirExists(AddBackslash(D) + BLOB_DIR_NAME) then begin
          Log('Deleting the downloads a stopped Setup left: ' + AddBackslash(D) + BLOB_DIR_NAME);
          if not DelTree(AddBackslash(D) + BLOB_DIR_NAME, True, True, True) then
            Log('Could not delete ' + AddBackslash(D) + BLOB_DIR_NAME + ' completely');
        end;
      end;
    until not FindNext(FR);
  finally
    FindClose(FR);
  end;
end;

{ Every needed blob, once. False (Problem) = nothing was changed. }
function FetchBlobs(var Problem: String): Boolean;
var
  B, N, Done: Integer;
  Reason: String;
  Bytes: Int64;
begin
  Result := False;
  Problem := '';
  FetchDone := False;
  ComputeNeededBlobs;
  if FetchFiles = 0 then begin
    Log('CXCXM FETCH DONE files=0 bytes=0');
    FetchDone := True;
    Result := True;
    Exit;
  end;
  DeleteStaleBlobDirs;
  ForceDirectories(BlobDir);
  Log(Format('Downloading %d file(s), %s', [FetchFiles, BytesToMB(FetchBytes)]));
  if (FetchPage <> nil) and not WizardSilent then
    FetchPage.Show;
  try
    N := 0;
    Done := 0;
    Bytes := 0;
    for B := 0 to BlobCount - 1 do begin
      if not BlobNeeded[B] then
        Continue;
      N := N + 1;
      if (FetchPage <> nil) and not WizardSilent then
        FetchPage.Caption := Format('Downloading the option files (%d of %d)', [N, FetchFiles]);
      if not FetchOneBlob(B, Reason) then begin
        if Reason = 'cancelled' then
          Problem := 'The download was cancelled. Nothing was changed.'
        else
          Problem := 'Setup could not download ' + BlobAsset[B] + ' (' + Reason + ').' + #13#10#13#10 +
            'Nothing was changed. Check your internet connection and try again.';
        Log('CXCXM FETCH FAILED ' + BlobAsset[B] + ': ' + Reason);
        FetchProblem := Problem;
        Exit;
      end;
      Done := Done + 1;
      Bytes := Bytes + BlobSize[B];
    end;
  finally
    if (FetchPage <> nil) and not WizardSilent then
      FetchPage.Hide;
  end;
  Log(Format('CXCXM FETCH DONE files=%d bytes=%d', [Done, Bytes]));
  FetchDone := True;
  Result := True;
end;

{ Where every variant this run writes comes from (VarSrcPath). False
  (Problem) when a source is missing: an archive that was not provided, a
  blob that was not downloaded. }
function ResolveVarSrcPaths(var Problem: String): Boolean;
var
  P, K: Integer;
begin
  Result := True;
  Problem := '';
  for K := 0 to VarCount - 1 do
    VarSrcPath[K] := '';
  for P := 0 to PathCount - 1 do begin
    K := DesiredVariant(P);
    if (K < 0) or VarSkip[K] then
      Continue;
    if VarSrc[K] = 'A' then
      VarSrcPath[K] := MemPath[VarRef[K]]
    else
      VarSrcPath[K] := BlobPath[VarRef[K]];
    if (VarSrcPath[K] = '') or not FileExists(VarSrcPath[K]) then begin
      if VarSrc[K] = 'A' then
        Problem := PathRel[P] + ' must come from ' + ArchTitle[MemArch[VarRef[K]]] + ', which was not provided.'
      else
        Problem := PathRel[P] + ' must be downloaded (' + BlobAsset[VarRef[K]] + '), which did not happen.';
      Problem := Problem + #13#10#13#10 + 'Nothing was changed.';
      Log('Source missing: ' + Problem);
      Result := False;
      Exit;
    end;
  end;
end;
