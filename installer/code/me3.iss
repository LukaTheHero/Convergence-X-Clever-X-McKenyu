{ =============================================================================
  me3.iss - the [[natives]] entries this installer manages in the two .me3
  profiles (me3\convergence.me3 and me3\convergence - seamless.me3).
  (Inno parses [Code] line by line: no line here may start with "[" or "#".)

  Every native comes from the catalog (Nat* arrays, contract 3.2), in array
  order, which is also the append order (Nightreign Movement is the last):
    NatComp     the component whose state >= 1 puts the block in BOTH profiles
    NatMatch    squeezed substring: a [[natives]] table whose path line holds
                it belongs to this native (ours or an older/foreign copy)
    NatPath     our exact path line, squeezed
    NatForeign  R = the v6.3 arrows rule: with the native on, our exact entry
                is kept where it is, ONE foreign path line is pointed at our
                DLL, two or more are refused, none = our block is appended;
                with it off only our exact tables are taken out (a foreign
                entry stays, and so does the DLL it needs)
                S = every matching table is taken out, and the block is
                appended again when the native is on
                K = as S while the native is on (the player's own copy is
                replaced by ours); while it is off only our exact table is
                taken out, so the player's own copy at another path keeps
                loading (ERCapacityExpansion: players install it themselves
                for other animation mods; verifier 3, defect D1)
    NatLf       a profile that carries this block is written LF + final LF
    NatLine     the block, line by line; its "#" lines directly above its
                header are part of it when it is taken out

  A .me3 profile is TOML. Every line is classified in its context
  (Me3Classify; repair 3, verifier 4 D1): blank, comment, header (a table
  or an array of tables, a trailing # comment allowed), key = value, or a
  continuation line that starts inside an open array, inline table or
  multi-line string (load_after = [ ... ] over several lines may hold blank
  lines, comments, and lines that start with "["). A table's own lines run
  from its header to the next header.
  An ENTRY (repair 4, verifier 5 / code review D1 residual): a header with
  two or more key parts whose first part names a list of tables declared
  above it - [natives.initializer], [[natives.load_after]], [package.x] -
  is a table INSIDE the last element of that list (TOML), so it belongs to
  the [[natives]] (or [[package]]) header above it: Me3HeaderRoots. An entry
  is its element header with its own lines plus every such sub-table with
  its lines. Taking an entry out removes all of it: its header down to its
  last key or continuation line, every sub-table of it (header down to its
  last key), and the blank lines and comments between parts of it that
  follow each other; blank lines and comments after its last part stay
  (they sit above the next header and belong to it), and so do the comments
  above its header unless they are lines of our own block. Headers are read
  as TOML keys: quoted parts ([["natives"]]) and blanks around the dots are
  allowed (Me3ParseHeader).
  Squeezed form (Me3Squeeze): the line without its # comment, lowercase,
  without blanks, double quotes turned into single quotes, a quoted key made
  only of bare-key characters unquoted ("path" = is path =), and a header in
  its plain form ([[natives]]).

  Target profile for the chosen options (Me3ComputeTarget): S natives are
  taken out; R natives follow the rule above; then the blocks of every
  native that is on and not already in place are appended in array order,
  each after one blank line. Lines of one native's table that name another
  native's DLL (NRM's load_after list names infinite_arrows.dll) belong to
  that table only. Before any change: the profile must be readable
  (Me3StructureProblem: also no table or key defined twice, counting the
  sub-tables of every entry), the result must be readable too, and every
  entry that is not a catalog native's must stay as it was, each sub-table
  with the entry it belongs to (Me3OtherTablesText); otherwise Setup
  refuses before anything changes.

  Writing (SaveMe3Lines) is canonical, so every state has one exact form:
    a block with NatLf is there   -> LF line ends and one final LF (byte for
                                     byte the Nexus NRM zips' profile)
    the lines are the stock ones  -> the stock bytes (CRLF, no final break)
    anything else                 -> UTF-8 without BOM, CRLF (as v6.3)
  A profile whose lines do not change is never rewritten.

  Backup kind E ("our entries were appended", code\backup.iss) is restored by
  Me3RemoveAddedEntries: every catalog native the saved copy lacks is taken
  out; when the rest equals the saved copy, the saved copy is put back byte
  for byte, otherwise (the user edited the profile since) only our entries
  are removed - unless that would leave a profile me3 cannot read or change
  another entry: then the saved copy is put back whole. Any native of the
  catalog counts as "ours", so this also undoes what v6.3/v6.4 added
  (arrows, Nightreign Movement).

  Verification (Me3VerifyProfile + Me3VerifyProfileEdit): every native as
  chosen, in catalog order, NRM last; a profile Setup rewrote must be
  readable, keep every other table as it was before Setup's edit, and pass
  me3's own reader (me3\Windows\me3.exe profile show, run from a checked
  copy in Setup's temp folder; never in an elevated Setup).

  Repair 5 (sixth verifier DEFECT 2): a profile Setup cannot read is never
  acted on, also when nothing of ours would change in it (which DLLs stay
  depends on reading it); a multi-line string may close with 3 to 5 quotes
  (more = not TOML); a key with an escape ("path") and a path with a
  \u escape or written over several lines are refused; natives headers
  are compared case-sensitively ([[Natives]] is not natives: me3 ignores
  it) and [[native]] (me3's alias) is read as natives; and before Setup
  acts on a profile, and after it wrote one, me3's own reader must list the
  same natives as Setup reads (Me3ExeProblem: Me3NativesSignature =
  Me3ExeNativesSignature), so any layout the line reader takes differently
  is refused, never mis-edited (where me3.exe can run).
  ============================================================================= }

{ ---------------------------------------------------------------- lines --- }

{ The part of a line before its # comment (a # inside quotes is no comment). }
function Me3CodePart(const Line: String): String;
var
  I, L: Integer;
  C, Q: Char;
begin
  Result := Line;
  L := Length(Line);
  Q := #0;
  I := 1;
  while I <= L do begin
    C := Line[I];
    if Q <> #0 then begin
      if (Q = '"') and (C = '\') then
        I := I + 1
      else if C = Q then
        Q := #0;
    end else if (C = '"') or (C = '''') then
      Q := C
    else if C = '#' then begin
      Result := Copy(Line, 1, I - 1);
      Exit;
    end;
    I := I + 1;
  end;
end;

{ True for a character of a bare TOML key (A-Z, a-z, 0-9, _ and -). }
function Me3IsBareKeyChar(const C: Char): Boolean;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or ((C >= '0') and (C <= '9')) or
    (C = '_') or (C = '-');
end;

{ Reads a TOML key (bare, "basic" or 'literal' parts joined by dots, blanks
  around the parts allowed): Path = its parts without quotes, joined by
  ME3_PART_SEP, Count = the number of parts. False when Text is no valid
  key - or holds an escape in a "basic" part ("path" is the key path
  for TOML and me3): Setup does not decode escapes in keys, so such a key
  makes the profile one Setup does not read (Me3StructureProblem refuses
  it; repair 5, sixth verifier DEFECT 2 b). }
function Me3ParseKeyPath(const Text: String; var Path: String; var Count: Integer): Boolean;
var
  I, L: Integer;
  Seg: String;
  Q: Char;
  NeedPart: Boolean;
begin
  Result := False;
  Path := '';
  Count := 0;
  L := Length(Text);
  I := 1;
  NeedPart := True;
  while True do begin
    while (I <= L) and ((Text[I] = ' ') or (Text[I] = #9)) do
      I := I + 1;
    if not NeedPart then begin
      if I > L then begin
        Result := True;
        Exit;
      end;
      if Text[I] <> '.' then
        Exit;
      I := I + 1;
      NeedPart := True;
      Continue;
    end;
    if I > L then
      Exit;
    Seg := '';
    if (Text[I] = '"') or (Text[I] = '''') then begin
      Q := Text[I];
      I := I + 1;
      while (I <= L) and (Text[I] <> Q) do begin
        if (Q = '"') and (Text[I] = '\') then
          Exit;
        Seg := Seg + Text[I];
        I := I + 1;
      end;
      if I > L then
        Exit;
      I := I + 1;
    end else begin
      while (I <= L) and Me3IsBareKeyChar(Text[I]) do begin
        Seg := Seg + Text[I];
        I := I + 1;
      end;
      if Seg = '' then
        Exit;
    end;
    if Count > 0 then
      Path := Path + ME3_PART_SEP;
    Path := Path + Seg;
    Count := Count + 1;
    NeedPart := False;
  end;
end;

{ A header line: IsArray for [[...]], Path and Count its key (see
  Me3ParseKeyPath). False when the line (without its # comment) is no valid
  header. }
function Me3ParseHeader(const Line: String; var IsArray: Boolean; var Path: String; var Count: Integer): Boolean;
var
  S: String;
  L: Integer;
begin
  Result := False;
  IsArray := False;
  Path := '';
  Count := 0;
  S := Trim(Me3CodePart(Line));
  L := Length(S);
  if (L >= 4) and (Copy(S, 1, 2) = '[[') then begin
    if Copy(S, L - 1, 2) <> ']]' then
      Exit;
    IsArray := True;
    S := Copy(S, 3, L - 4);
  end else if (L >= 2) and (S[1] = '[') and (S[L] = ']') then
    S := Copy(S, 2, L - 2)
  else
    Exit;
  Result := Me3ParseKeyPath(S, Path, Count);
end;

{ A key path for messages: its parts joined by dots. }
function Me3PathText(const Path: String): String;
begin
  Result := Path;
  StringChangeEx(Result, ME3_PART_SEP, '.', True);
end;

{ The first part of a key path, and the rest ('' for a one-part path). }
function Me3FirstPart(const Path: String): String;
var
  P: Integer;
begin
  P := Pos(ME3_PART_SEP, Path);
  if P > 0 then
    Result := Copy(Path, 1, P - 1)
  else
    Result := Path;
end;

function Me3RestParts(const Path: String): String;
var
  P: Integer;
begin
  P := Pos(ME3_PART_SEP, Path);
  if P > 0 then
    Result := Copy(Path, P + 1, Length(Path))
  else
    Result := '';
end;

{ The text of a key line before its "=" (outside quotes), '' when none. }
function Me3KeyText(const Line: String): String;
var
  I, L: Integer;
  C, Q: Char;
begin
  Result := '';
  L := Length(Line);
  Q := #0;
  I := 1;
  while I <= L do begin
    C := Line[I];
    if Q <> #0 then begin
      if (Q = '"') and (C = '\') then
        I := I + 1
      else if C = Q then
        Q := #0;
    end else if (C = '"') or (C = '''') then
      Q := C
    else if C = '=' then begin
      Result := Copy(Line, 1, I - 1);
      Exit;
    end;
    I := I + 1;
  end;
end;

{ Without its # comment, lowercase, no spaces or tabs, double quotes turned
  into single quotes; a quoted key made only of bare-key characters loses
  its quotes ("path" = ... is path = ..., repair 4); a header comes in its
  plain form ([["natives"]] and [[ natives ]] are [[natives]]). }
function Me3Squeeze(const Line: String): String;
var
  IsArray, Bare: Boolean;
  Path: String;
  Count, I, Q: Integer;
begin
  if Me3ParseHeader(Line, IsArray, Path, Count) then begin
    Result := Lowercase(Me3PathText(Path));
    if IsArray then
      Result := '[[' + Result + ']]'
    else
      Result := '[' + Result + ']';
    Exit;
  end;
  Result := Lowercase(Trim(Me3CodePart(Line)));
  StringChangeEx(Result, ' ', '', True);
  StringChangeEx(Result, #9, '', True);
  StringChangeEx(Result, '"', '''', True);
  if (Length(Result) >= 4) and (Result[1] = '''') then begin
    Q := 0;
    for I := 2 to Length(Result) do
      if (Q = 0) and (Result[I] = '''') then
        Q := I;
    if (Q > 2) and (Q < Length(Result)) and (Result[Q + 1] = '=') then begin
      Bare := True;
      for I := 2 to Q - 1 do
        if not Me3IsBareKeyChar(Result[I]) then
          Bare := False;
      if Bare then
        Result := Copy(Result, 2, Q - 2) + Copy(Result, Q + 1, Length(Result));
    end;
  end;
end;

function Me3IsActiveLine(const Line: String): Boolean;
var
  S: String;
begin
  S := Trim(Line);
  Result := (S <> '') and (S[1] <> '#');
end;

{ A line that starts with "[" (out of context: a header only when it is not
  inside an open value, see Me3Classify). }
function Me3IsHeaderLine(const Line: String): Boolean;
var
  S: String;
begin
  S := Trim(Line);
  Result := (S <> '') and (S[1] = '[');
end;

{ The header of a new element of the list of tables natives: [[natives]]
  (quoted, with blanks or a trailing # comment as well; repair 4) or its
  me3 alias [[native]]. Compared as TOML compares keys, case-sensitive:
  me3 0.13.0 ignores [[Natives]] (measured), so Setup must not take it for
  natives (repair 5, sixth verifier DEFECT 2 c), and it reads [[native]]
  as natives, so Setup must see the natives of a profile written with it
  (repair 5, DEFECT 2 d: with NRM off its [[native]] entry stayed while
  its DLL was removed). A profile that uses both names is refused
  (Me3AliasProblem), so Setup never appends [[natives]] to a [[native]]
  profile. }
function IsNativesHeaderLine(const Line: String): Boolean;
var
  IsArray: Boolean;
  Path: String;
  Count: Integer;
begin
  Result := Me3ParseHeader(Line, IsArray, Path, Count) and IsArray and (Count = 1) and
    ((Path = 'natives') or (Path = 'native'));
end;

{ An active "path = ..." line. }
function Me3IsPathLine(const Line: String): Boolean;
begin
  Result := Me3IsActiveLine(Line) and StartsWithStr(Me3Squeeze(Line), 'path=');
end;

{ The prefix that turns another mod's [[package]] line into a comment. }
function Me3OffPrefix: String;
begin
  Result := '# switched off by the CXCXM ' + CAT_VERSION_SHORT + ' installer: ';
end;

{ ------------------------------------------------------- classification --- }

var
  { Me3ClassifyEx: the first line that holds a run of more than five quotes
    in a multi-line string, which no TOML reader takes (-1: none; repair 5) }
  Me3BadValueAt: Integer;

{ Scans a value from Start: strings (one-line and multi-line), brackets and
  braces outside strings, a # comment ends the scan. Depth = open brackets
  and braces; ML = the delimiter of an open multi-line string ('' none).
  Inside a multi-line string a run of 3, 4 or 5 delimiter quotes closes it
  (TOML: one or two quotes may stand right before the closing delimiter, so
  """a"""" is the text a" - repair 5, sixth verifier DEFECT 2 a: the 4th
  quote was read as a new string that swallowed the rest of the line); a
  run of 6 or more sets Bad (not TOML). }
procedure Me3ScanValue(const Line: String; const Start: Integer; var Depth: Integer; var ML: String;
  var Bad: Boolean);
var
  I, L, R: Integer;
  C, Q: Char;
  Three: String;
begin
  L := Length(Line);
  I := Start;
  while I <= L do begin
    if ML <> '' then begin
      if Line[I] = ML[1] then begin
        R := 0;
        while (I + R <= L) and (Line[I + R] = ML[1]) do
          R := R + 1;
        if R >= 3 then begin
          if R > 5 then
            Bad := True;
          ML := '';
        end;
        I := I + R;
        Continue;
      end;
      if (ML = '"""') and (Line[I] = '\') then
        I := I + 2
      else
        I := I + 1;
      Continue;
    end;
    C := Line[I];
    if C = '#' then
      Exit;
    if (C = '"') or (C = '''') then begin
      Three := Copy(Line, I, 3);
      if Three = StringOfChar(C, 3) then begin
        ML := Three;
        I := I + 3;
        Continue;
      end;
      Q := C;
      I := I + 1;
      while (I <= L) and (Line[I] <> Q) do begin
        if (Q = '"') and (Line[I] = '\') then
          I := I + 1;
        I := I + 1;
      end;
      I := I + 1;
      Continue;
    end;
    if (C = '[') or (C = '{') then
      Depth := Depth + 1
    else if ((C = ']') or (C = '}')) and (Depth > 0) then
      Depth := Depth - 1;
    I := I + 1;
  end;
end;

{ Kinds[i] = ME3_K_* of every line (see the header). OpenAt = the line where
  a value that is never closed starts (-1: everything is closed). }
procedure Me3ClassifyEx(const Lines: TArrayOfString; var Kinds: TArrayOfInteger; var OpenAt: Integer);
var
  I, N, Depth: Integer;
  ML, S: String;
  Bad: Boolean;
begin
  N := GetArrayLength(Lines);
  SetArrayLength(Kinds, N);
  Depth := 0;
  ML := '';
  OpenAt := -1;
  Me3BadValueAt := -1;
  for I := 0 to N - 1 do begin
    Bad := False;
    if (Depth > 0) or (ML <> '') then begin
      Kinds[I] := ME3_K_CONT;
      Me3ScanValue(Lines[I], 1, Depth, ML, Bad);
    end else begin
      S := Trim(Lines[I]);
      if S = '' then
        Kinds[I] := ME3_K_BLANK
      else if S[1] = '#' then
        Kinds[I] := ME3_K_COMMENT
      else if S[1] = '[' then
        Kinds[I] := ME3_K_HEADER
      else if Pos('=', S) > 1 then begin
        Kinds[I] := ME3_K_KEY;
        Me3ScanValue(Lines[I], 1, Depth, ML, Bad);
        if (Depth > 0) or (ML <> '') then
          OpenAt := I;
      end else
        Kinds[I] := ME3_K_BAD;
    end;
    if Bad and (Me3BadValueAt < 0) then
      Me3BadValueAt := I;
    if (Depth = 0) and (ML = '') then
      OpenAt := -1;
  end;
end;

procedure Me3Classify(const Lines: TArrayOfString; var Kinds: TArrayOfInteger);
var
  OpenAt: Integer;
begin
  Me3ClassifyEx(Lines, Kinds, OpenAt);
end;

{ A key line or a continuation line: the content of a table. }
function Me3IsContentKind(const K: Integer): Boolean;
begin
  Result := (K = ME3_K_KEY) or (K = ME3_K_CONT);
end;

{ Index of the header that owns line I (-1 when none). }
function Me3OwnerHeaderK(const Kinds: TArrayOfInteger; const I: Integer): Integer;
begin
  Result := I - 1;
  while (Result >= 0) and (Kinds[Result] <> ME3_K_HEADER) do
    Result := Result - 1;
end;

function Me3OwnerHeader(const Lines: TArrayOfString; const I: Integer): Integer;
var
  Kinds: TArrayOfInteger;
begin
  Me3Classify(Lines, Kinds);
  Result := Me3OwnerHeaderK(Kinds, I);
end;

{ The first header after header H (or the line count). }
function Me3TableEndK(const Kinds: TArrayOfInteger; const H: Integer): Integer;
begin
  Result := H + 1;
  while (Result < GetArrayLength(Kinds)) and (Kinds[Result] <> ME3_K_HEADER) do
    Result := Result + 1;
end;

function Me3TableEnd(const Lines: TArrayOfString; const H: Integer): Integer;
var
  Kinds: TArrayOfInteger;
begin
  Me3Classify(Lines, Kinds);
  Result := Me3TableEndK(Kinds, H);
end;

{ The last key or continuation line of the table at header H (H itself when
  the table is empty). }
function Me3TableLastK(const Kinds: TArrayOfInteger; const H: Integer): Integer;
var
  I, E: Integer;
begin
  Result := H;
  E := Me3TableEndK(Kinds, H);
  for I := H + 1 to E - 1 do
    if Me3IsContentKind(Kinds[I]) then
      Result := I;
end;

{ The path line (a key line "path = ...") of the table at header H, -1. }
function Me3TablePathLineK(const Lines: TArrayOfString; const Kinds: TArrayOfInteger; const H: Integer): Integer;
var
  I, E: Integer;
begin
  Result := -1;
  E := Me3TableEndK(Kinds, H);
  for I := H + 1 to E - 1 do
    if (Kinds[I] = ME3_K_KEY) and StartsWithStr(Me3Squeeze(Lines[I]), 'path=') then begin
      Result := I;
      Exit;
    end;
end;

{ Roots[i] for every header line i: the header of the ENTRY it belongs to
  (repair 4). A header with two or more key parts whose first part names a
  list of tables declared above it (the headers [natives.initializer]
  and [[natives.load_after]] below a [[natives]] header) is a table inside
  the last element of that list, so its root is the last such [[...]] header
  above it; every other header is its own root. -1 for lines that are no
  header. Parts compare as TOML compares keys (case-sensitive). }
procedure Me3HeaderRoots(const Lines: TArrayOfString; const Kinds: TArrayOfInteger; var Roots: TArrayOfInteger);
var
  I, J, N, Count: Integer;
  IsArray, Found: Boolean;
  Path, First: String;
  Names: TArrayOfString;
  Last: TArrayOfInteger;
begin
  N := GetArrayLength(Lines);
  SetArrayLength(Roots, N);
  SetArrayLength(Names, 0);
  SetArrayLength(Last, 0);
  for I := 0 to N - 1 do begin
    Roots[I] := -1;
    if Kinds[I] <> ME3_K_HEADER then
      Continue;
    Roots[I] := I;
    if not Me3ParseHeader(Lines[I], IsArray, Path, Count) then
      Continue;
    First := Me3FirstPart(Path);
    if Count >= 2 then begin
      for J := 0 to GetArrayLength(Names) - 1 do
        if Names[J] = First then
          Roots[I] := Last[J];
    end else if IsArray then begin
      Found := False;
      for J := 0 to GetArrayLength(Names) - 1 do
        if Names[J] = First then begin
          Last[J] := I;
          Found := True;
        end;
      if not Found then begin
        J := GetArrayLength(Names);
        SetArrayLength(Names, J + 1);
        SetArrayLength(Last, J + 1);
        Names[J] := First;
        Last[J] := I;
      end;
    end;
  end;
end;

{ The root header (Me3HeaderRoots) of the entry line I belongs to, -1 for a
  line above the first header. }
function Me3EntryOfK(const Kinds, Roots: TArrayOfInteger; const I: Integer): Integer;
var
  H: Integer;
begin
  if Kinds[I] = ME3_K_HEADER then
    H := I
  else
    H := Me3OwnerHeaderK(Kinds, I);
  if H < 0 then
    Result := -1
  else
    Result := Roots[H];
end;

{ Marks every line of the entry whose root header is H in Drop: H down to
  its last key or continuation line, and every sub-table of it (header down
  to its last key); the blank lines and comments between two parts of it
  that follow each other directly are marked too. Returns the last line
  marked. }
function Me3MarkEntry(const Kinds, Roots: TArrayOfInteger; const H: Integer; var Drop: TArrayOfBoolean): Integer;
var
  S, K, PrevHdr: Integer;
begin
  Result := Me3TableLastK(Kinds, H);
  for K := H to Result do
    Drop[K] := True;
  PrevHdr := H;
  for S := H + 1 to GetArrayLength(Kinds) - 1 do
    if (Kinds[S] = ME3_K_HEADER) and (Roots[S] = H) then begin
      if Me3TableEndK(Kinds, PrevHdr) = S then
        for K := Result + 1 to S - 1 do
          Drop[K] := True;
      Result := Me3TableLastK(Kinds, S);
      for K := S to Result do
        Drop[K] := True;
      PrevHdr := S;
    end;
end;

{ ------------------------------------------------------------ array helpers --- }

procedure AddLine(var A: TArrayOfString; const S: String);
var
  N: Integer;
begin
  N := GetArrayLength(A);
  SetArrayLength(A, N + 1);
  A[N] := S;
end;

procedure CopyLines(const Src: TArrayOfString; var Dst: TArrayOfString);
var
  I: Integer;
begin
  SetArrayLength(Dst, GetArrayLength(Src));
  for I := 0 to GetArrayLength(Src) - 1 do
    Dst[I] := Src[I];
end;

procedure TrimTrailingBlankLines(var A: TArrayOfString);
var
  N: Integer;
begin
  N := GetArrayLength(A);
  while (N > 0) and (Trim(A[N - 1]) = '') do
    N := N - 1;
  SetArrayLength(A, N);
end;

function SameLines(const A, B: TArrayOfString): Boolean;
var
  I: Integer;
begin
  Result := GetArrayLength(A) = GetArrayLength(B);
  if not Result then
    Exit;
  for I := 0 to GetArrayLength(A) - 1 do
    if A[I] <> B[I] then begin
      Result := False;
      Exit;
    end;
end;

function JoinLines(const A: TArrayOfString; const Sep: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(A) - 1 do begin
    if I > 0 then
      Result := Result + Sep;
    Result := Result + A[I];
  end;
end;

{ -------------------------------------------------------- catalog natives --- }

function NatCount: Integer;
begin
  Result := GetArrayLength(NatComp);
end;

function NativeOn(const N: Integer): Boolean;
begin
  Result := ChosenState[NatComp[N]] >= 1;
end;

function AnyNativeOn: Boolean;
var
  N: Integer;
begin
  Result := False;
  for N := 0 to NatCount - 1 do
    if NativeOn(N) then
      Result := True;
end;

{ ------------------------------------------------------ path line values --- }

{ The text a "path = ..." line's value holds, as TOML reads it: a 'literal'
  string, a "basic" one (escapes decoded: \\ \" \b \t \n \f \r \e and
  \uXXXX / \UXXXXXXXX up to $FFFF), or a one-line '''...''' / """...""".
  '' when the value is no string Setup can read (an open multi-line
  string, an unknown escape, no value). Repair 6 (TEST lane after repair 5,
  finding A; seventh verifier, findings A and C). }
function Me3PathLineValue(const Line: String): String;
var
  S, Q, H: String;
  I, L, K, Code: Integer;
  C: Char;
  Basic: Boolean;
begin
  Result := '';
  S := Me3CodePart(Line);
  I := Length(Me3KeyText(S));
  if (I = 0) or (I >= Length(S)) then
    Exit;
  S := Trim(Copy(S, I + 2, Length(S)));
  L := Length(S);
  if L < 2 then
    Exit;
  Basic := False;
  if (Copy(S, 1, 3) = '''''''') or (Copy(S, 1, 3) = '"""') then begin
    Q := Copy(S, 1, 3);
    { open here: the string runs over several lines }
    if (L < 6) or (Copy(S, L - 2, 3) <> Q) then
      Exit;
    Basic := Q = '"""';
    S := Copy(S, 4, L - 6);
  end else if S[1] = '''' then begin
    if S[L] <> '''' then
      Exit;
    S := Copy(S, 2, L - 2);
  end else if S[1] = '"' then begin
    if S[L] <> '"' then
      Exit;
    Basic := True;
    S := Copy(S, 2, L - 2);
  end else
    Exit;
  if not Basic then begin
    Result := S;
    Exit;
  end;
  L := Length(S);
  I := 1;
  while I <= L do begin
    C := S[I];
    if C <> '\' then begin
      Result := Result + C;
      I := I + 1;
      Continue;
    end;
    if I = L then begin
      Result := '';
      Exit;
    end;
    C := S[I + 1];
    K := 0;
    if C = '\' then
      Result := Result + '\'
    else if C = '"' then
      Result := Result + '"'
    else if C = 'b' then
      Result := Result + #8
    else if C = 't' then
      Result := Result + #9
    else if C = 'n' then
      Result := Result + #10
    else if C = 'f' then
      Result := Result + #12
    else if C = 'r' then
      Result := Result + #13
    else if C = 'e' then
      Result := Result + #27
    else if C = 'u' then
      K := 4
    else if C = 'U' then
      K := 8
    else begin
      Result := '';
      Exit;
    end;
    if K > 0 then begin
      H := Copy(S, I + 2, K);
      Code := -1;
      if Length(H) = K then
        Code := StrToIntDef('$' + H, -1);
      if (Code < 1) or (Code > $FFFF) then begin
        Result := '';
        Exit;
      end;
      Result := Result + Chr(Code);
      I := I + 2 + K;
    end else
      I := I + 2;
  end;
end;

{ An absolute Windows path in one form: lower-case, backslashes, the drive
  ('c:') or UNC share ('\\server\share') first, no '', '.' or '..' parts
  ('..' takes the part before it out). '' when '..' climbs above the drive
  or the path has no drive or share. }
function Me3NormAbsPath(const Path: String): String;
var
  S, Prefix, Seg: String;
  Parts, Kept: TArrayOfString;
  I, N: Integer;
begin
  Result := '';
  S := Path;
  StringChangeEx(S, '/', '\', True);
  if StartsWithStr(S, '\\') then begin
    SplitStr(Copy(S, 3, Length(S)), '\', Parts);
    if (GetArrayLength(Parts) < 2) or (Parts[0] = '') or (Parts[1] = '') then
      Exit;
    Prefix := '\\' + Parts[0] + '\' + Parts[1];
    S := '';
    for I := 2 to GetArrayLength(Parts) - 1 do
      S := S + '\' + Parts[I];
  end else if (Length(S) >= 2) and (S[2] = ':') and (((S[1] >= 'A') and (S[1] <= 'Z')) or
    ((S[1] >= 'a') and (S[1] <= 'z'))) then
  begin
    Prefix := Copy(S, 1, 2);
    S := Copy(S, 3, Length(S));
  end else
    Exit;
  SplitStr(S, '\', Parts);
  SetArrayLength(Kept, GetArrayLength(Parts));
  N := 0;
  for I := 0 to GetArrayLength(Parts) - 1 do begin
    Seg := Parts[I];
    if (Seg = '') or (Seg = '.') then
      Continue;
    if Seg = '..' then begin
      if N = 0 then
        Exit;
      N := N - 1;
      Continue;
    end;
    Kept[N] := Seg;
    N := N + 1;
  end;
  Result := Prefix;
  for I := 0 to N - 1 do
    Result := Result + '\' + Kept[I];
  Result := Lowercase(Result);
end;

{ A path as me3 resolves it from a profile (against the profile's folder,
  <Convergence>\me3), relative to the Convergence folder, lower-case, with
  backslashes: './../mod/dll/X.dll', '../mod//dll/./X.dll', '.\..\mod\dll\X.dll'
  and an absolute path into the Convergence folder all give 'mod\dll\x.dll'.
  '' when it points outside the Convergence folder. Without a Convergence
  folder (the /TESTUNIT runs) a stand-in root is used, so relative paths
  resolve the same way. Repair 6. }
function Me3ResolveConvRel(const Value: String): String;
var
  S, Base, Full, NB, NF: String;
begin
  Result := '';
  S := Value;
  if S = '' then
    Exit;
  StringChangeEx(S, '/', '\', True);
  if ConvDir <> '' then
    Base := RemoveBackslashUnlessRoot(ConvDir)
  else
    Base := 'Z:\CXCXM-NO-CONVERGENCE-FOLDER';
  if StartsWithStr(S, '\\') or ((Length(S) >= 2) and (S[2] = ':')) then
    Full := S
  else if StartsWithStr(S, '\') then
    Full := Copy(Base, 1, 2) + S
  else
    Full := Base + '\me3\' + S;
  NB := Me3NormAbsPath(Base);
  NF := Me3NormAbsPath(Full);
  if (NB = '') or (NF = '') or (Length(NF) <= Length(NB) + 1) then
    Exit;
  if Copy(NF, 1, Length(NB) + 1) <> NB + '\' then
    Exit;
  Result := Copy(NF, Length(NB) + 2, Length(NF));
end;

{ The relative path (inside the Convergence folder, lower-case) the file a
  "path = ..." line loads, as me3 resolves it (Me3PathLineValue +
  Me3ResolveConvRel); '' when the line is no path line, its value cannot be
  read or it points elsewhere. Repair 6: every spelling of one file counts
  as that file (it used to know only paths starting with ./../). }
function Me3PathLineRel(const Line: String): String;
begin
  Result := '';
  if not StartsWithStr(Me3Squeeze(Line), 'path=') then
    Exit;
  Result := Me3ResolveConvRel(Me3PathLineValue(Line));
end;

var
  { NativeDllRel of every native (filled on first use; the paths of the
    catalog's blocks are relative, so they do not depend on the folder) }
  NatRelCache: TArrayOfString;
  NatRelCached: Boolean;

{ The relative path of the DLL native N loads (from its path line), '' when
  it does not point into the Convergence folder. }
function NativeDllRel(const N: Integer): String;
var
  I: Integer;
begin
  if not NatRelCached or (GetArrayLength(NatRelCache) <> NatCount) then begin
    SetArrayLength(NatRelCache, NatCount);
    for I := 0 to NatCount - 1 do
      NatRelCache[I] := Me3PathLineRel(NatPath[I]);
    NatRelCached := True;
  end;
  Result := NatRelCache[N];
end;

{ A path line of a table that belongs to native N (ours or another copy). }
function NativeMatchesPathLine(const N: Integer; const Line: String): Boolean;
begin
  Result := Me3IsPathLine(Line) and (Pos(Lowercase(NatMatch[N]), Me3Squeeze(Line)) > 0);
end;

{ Our path line of native N: our exact line, or any other spelling of a path
  that loads the very file ours loads (Me3PathLineRel: quotes, ''' and """
  strings, escapes, / or \, '.', '..' and '//' parts, an absolute path into
  the Convergence folder). Repair 6 (TEST lane after repair 5, finding A;
  seventh verifier, findings A and C): an entry the player re-spelled (or
  wrote himself) that loads the option's own file at the option's own path
  belongs to the option - it is taken out when the option is off and by
  the uninstall, together with that file, so no profile is ever left
  naming a DLL Setup deleted; an entry that loads a copy at ANOTHER path is
  another mod's (R: re-pointed or kept with its DLL; K: kept while off). }
function IsOurNativePathLine(const N: Integer; const Line: String): Boolean;
var
  R, S: String;
begin
  Result := False;
  if not Me3IsActiveLine(Line) then
    Exit;
  S := Me3Squeeze(Line);
  if S = Lowercase(NatPath[N]) then begin
    Result := True;
    Exit;
  end;
  if not StartsWithStr(S, 'path=') then
    Exit;
  R := NativeDllRel(N);
  if R = '' then
    Exit;
  Result := CompareText(Me3PathLineRel(Line), R) = 0;
end;

{ True when Line is the path line of any catalog native's table. }
function Me3LineIsCatalogNative(const Line: String): Boolean;
var
  N: Integer;
begin
  Result := False;
  for N := 0 to NatCount - 1 do
    if NativeMatchesPathLine(N, Line) then begin
      Result := True;
      Exit;
    end;
end;

{ The text of our path line of native N, as the block writes it. }
function NativeOurPathLineText(const N: Integer): String;
var
  I: Integer;
begin
  Result := '';
  for I := NatLineStart[N] to NatLineStart[N] + NatLineCount[N] - 1 do
    if Me3IsActiveLine(NatLine[I]) and (Me3Squeeze(NatLine[I]) = Lowercase(NatPath[N])) then begin
      Result := NatLine[I];
      Exit;
    end;
end;

{ One of the comment lines of native N's block (they sit above its header). }
function IsNativeBlockComment(const N: Integer; const Line: String): Boolean;
var
  I: Integer;
  S: String;
begin
  Result := False;
  S := Trim(Line);
  if (S = '') or (S[1] <> '#') then
    Exit;
  for I := NatLineStart[N] to NatLineStart[N] + NatLineCount[N] - 1 do
    if Trim(NatLine[I]) = S then begin
      Result := True;
      Exit;
    end;
end;

{ The catalog native whose [[natives]] table is the one at header H (-1 when
  H is no [[natives]] header or its path line is no catalog native's). }
function Me3HeaderNativeK(const Lines: TArrayOfString; const Kinds: TArrayOfInteger; const H: Integer): Integer;
var
  P, N: Integer;
begin
  Result := -1;
  if (H < 0) or (Kinds[H] <> ME3_K_HEADER) or not IsNativesHeaderLine(Lines[H]) then
    Exit;
  P := Me3TablePathLineK(Lines, Kinds, H);
  if P < 0 then
    Exit;
  for N := 0 to NatCount - 1 do
    if NativeMatchesPathLine(N, Lines[P]) then begin
      Result := N;
      Exit;
    end;
end;

{ The catalog native whose [[natives]] entry owns line I (-1 when the line
  is outside such an entry): decided by the path line of the entry's
  table [[natives]]; a line of a sub-table of it ([[natives.load_after]])
  belongs to it too (repair 4). }
function Me3TableNativeK(const Lines: TArrayOfString; const Kinds, Roots: TArrayOfInteger; const I: Integer): Integer;
begin
  Result := Me3HeaderNativeK(Lines, Kinds, Me3EntryOfK(Kinds, Roots, I));
end;

function Me3TableNative(const Lines: TArrayOfString; const I: Integer): Integer;
var
  Kinds, Roots: TArrayOfInteger;
begin
  Me3Classify(Lines, Kinds);
  Me3HeaderRoots(Lines, Kinds, Roots);
  Result := Me3TableNativeK(Lines, Kinds, Roots, I);
end;

{ -------------------------------------------------------------- analysis --- }

{ True when a line is an inline natives list ("natives = [ ... ]", or with
  me3's alias "native = [ ... ]"; repair 5). }
function Me3LinesHaveInline(const Lines: TArrayOfString): Boolean;
var
  Kinds: TArrayOfInteger;
  I: Integer;
  S: String;
begin
  Result := False;
  Me3Classify(Lines, Kinds);
  for I := 0 to GetArrayLength(Lines) - 1 do
    if Kinds[I] = ME3_K_KEY then begin
      S := Me3Squeeze(Lines[I]);
      if StartsWithStr(S, 'natives=') or StartsWithStr(S, 'native=') then begin
        Result := True;
        Exit;
      end;
    end;
end;

{ Classifies every key or continuation line that names native N's DLL:
  Exact (our path line in a [[natives]] table), Foreign (another path line
  in a [[natives]] table; ForeignIdx = the last one) and Other (inline
  lists, load order lists of other natives, ...). Lines of ANOTHER catalog
  native's table are left out (NRM's load_after list names
  infinite_arrows.dll, also when it spans several lines or is a sub-table
  of that native's entry). }
procedure Me3AnalyzeNative(const Lines: TArrayOfString; const N: Integer; var Exact, Foreign,
  ForeignIdx, Other: Integer);
var
  Kinds, Roots: TArrayOfInteger;
  I, Owner, T: Integer;
  S: String;
begin
  Exact := 0;
  Foreign := 0;
  ForeignIdx := -1;
  Other := 0;
  Me3Classify(Lines, Kinds);
  Me3HeaderRoots(Lines, Kinds, Roots);
  for I := 0 to GetArrayLength(Lines) - 1 do begin
    if not Me3IsContentKind(Kinds[I]) then
      Continue;
    S := Me3Squeeze(Lines[I]);
    if Pos(Lowercase(NatMatch[N]), S) = 0 then
      Continue;
    T := Me3TableNativeK(Lines, Kinds, Roots, I);
    if (T >= 0) and (T <> N) then
      Continue;
    Owner := Me3OwnerHeaderK(Kinds, I);
    if (Owner >= 0) and IsNativesHeaderLine(Lines[Owner]) and (Kinds[I] = ME3_K_KEY) and
      StartsWithStr(S, 'path=') then
    begin
      if IsOurNativePathLine(N, Lines[I]) then
        Exact := Exact + 1
      else begin
        Foreign := Foreign + 1;
        ForeignIdx := I;
      end;
    end else
      Other := Other + 1;
  end;
end;

{ True for the natives whose "our entry" is only our exact path line (R, K);
  for S every table of the native counts as ours. }
function NativeOursIsExact(const N: Integer): Boolean;
begin
  Result := (NatForeign[N] = 'R') or (NatForeign[N] = 'K');
end;

{ A K native's path line that is NOT our exact one: the player's own copy. }
function IsForeignKPathLine(const N: Integer; const Line: String): Boolean;
begin
  Result := (NatForeign[N] = 'K') and NativeMatchesPathLine(N, Line) and not IsOurNativePathLine(N, Line);
end;

{ The K native whose own copy (another path) Line loads, -1 when none. }
function Me3OwnKNative(const Line: String): Integer;
var
  N: Integer;
begin
  Result := -1;
  for N := 0 to NatCount - 1 do
    if IsForeignKPathLine(N, Line) then begin
      Result := N;
      Exit;
    end;
end;

{ The path line index of every [[natives]] table of native N, in order. }
procedure Me3NativeTablePathLines(const Lines: TArrayOfString; const Kinds: TArrayOfInteger; const N: Integer;
  var Found: TArrayOfInteger);
var
  H, P, C: Integer;
begin
  SetArrayLength(Found, 0);
  C := 0;
  for H := 0 to GetArrayLength(Lines) - 1 do
    if (Kinds[H] = ME3_K_HEADER) and IsNativesHeaderLine(Lines[H]) then begin
      P := Me3TablePathLineK(Lines, Kinds, H);
      if (P >= 0) and NativeMatchesPathLine(N, Lines[P]) then begin
        SetArrayLength(Found, C + 1);
        Found[C] := P;
        C := C + 1;
      end;
    end;
end;

{ True when a .me3 profile has a [[natives]] table of native N that is not
  ours but loads the same file as ours (the DLL must then stay when the
  option is off). Since repair 6 an entry that loads our very file counts
  as ours (IsOurNativePathLine resolves every spelling), so it is taken out
  with ours and this stays False; kept as the safety net it was. }
function Me3FileForeignLoadsOurDll(const FileName: String; const N: Integer): Boolean;
var
  Lines: TArrayOfString;
  Kinds, Found: TArrayOfInteger;
  I: Integer;
begin
  Result := False;
  if (NativeDllRel(N) = '') or not LoadStringsFromFile(FileName, Lines) then
    Exit;
  Me3Classify(Lines, Kinds);
  Me3NativeTablePathLines(Lines, Kinds, N, Found);
  for I := 0 to GetArrayLength(Found) - 1 do
    if not IsOurNativePathLine(N, Lines[Found[I]]) and
      (CompareText(Me3PathLineRel(Lines[Found[I]]), NativeDllRel(N)) = 0) then
    begin
      Result := True;
      Exit;
    end;
end;

{ True when the lines carry "our" entry of native N: R and K = our exact
  path line; S = any table of it. }
function Me3LinesHaveNative(const Lines: TArrayOfString; const N: Integer): Boolean;
var
  Kinds, Found: TArrayOfInteger;
  Exact, Foreign, ForeignIdx, Other: Integer;
begin
  if NativeOursIsExact(N) then begin
    Me3AnalyzeNative(Lines, N, Exact, Foreign, ForeignIdx, Other);
    Result := Exact > 0;
  end else begin
    Me3Classify(Lines, Kinds);
    Me3NativeTablePathLines(Lines, Kinds, N, Found);
    Result := GetArrayLength(Found) > 0;
  end;
end;

function Me3FileHasNative(const FileName: String; const N: Integer): Boolean;
var
  Lines: TArrayOfString;
begin
  Result := LoadStringsFromFile(FileName, Lines) and Me3LinesHaveNative(Lines, N);
end;

{ True when an active line names native N's DLL other than through our exact
  entry (an entry this installer did not add). }
function Me3FileHasOtherMention(const FileName: String; const N: Integer): Boolean;
var
  Lines: TArrayOfString;
  Exact, Foreign, ForeignIdx, Other: Integer;
begin
  Result := False;
  if not LoadStringsFromFile(FileName, Lines) then
    Exit;
  Me3AnalyzeNative(Lines, N, Exact, Foreign, ForeignIdx, Other);
  Result := (Foreign > 0) or (Other > 0);
end;

{ True when the lines carry a [[natives]] table of a native written with LF
  line ends. }
function Me3LinesHaveLfNative(const Lines: TArrayOfString): Boolean;
var
  Kinds, Found: TArrayOfInteger;
  N: Integer;
begin
  Result := False;
  Me3Classify(Lines, Kinds);
  for N := 0 to NatCount - 1 do
    if NatLf[N] then begin
      Me3NativeTablePathLines(Lines, Kinds, N, Found);
      if GetArrayLength(Found) > 0 then begin
        Result := True;
        Exit;
      end;
    end;
end;

{ ------------------------------------------------- readable / other tables --- }

{ True when Item is one of the #10-separated items of List (List starts
  and ends with #10). }
function Me3InList(const List, Item: String): Boolean;
begin
  Result := Pos(#10 + Item + #10, List) > 0;
end;

procedure Me3AddToList(var List: String; const Item: String);
begin
  if not Me3InList(List, Item) then
    List := List + Item + #10;
end;

{ Scope + key path: Scope ends with "|" (the root of a table inside an
  element of a list of tables, or "-" for the others) or with a part. }
function Me3JoinScope(const Scope, Path: String): String;
begin
  if (Scope <> '') and (Scope[Length(Scope)] = '|') then
    Result := Scope + Path
  else
    Result := Scope + ME3_PART_SEP + Path;
end;

{ The scope of header H for the duplicate checks: "<root>|rest" for a table
  inside the element <root> of a list of tables (Me3HeaderRoots), "<H>|"
  for such an element itself, "-|path" for every other table. '' when H is
  no valid header. }
function Me3HeaderScope(const Lines: TArrayOfString; const Roots: TArrayOfInteger; const H: Integer;
  var IsArray: Boolean; var Count: Integer; var Path: String): String;
begin
  Result := '';
  if not Me3ParseHeader(Lines[H], IsArray, Path, Count) then
    Exit;
  if Roots[H] <> H then
    Result := IntToStr(Roots[H]) + '|' + Me3RestParts(Path)
  else if IsArray and (Count = 1) then
    Result := IntToStr(H) + '|'
  else
    Result := '-|' + Path;
end;

{ Every proper prefix of a key path (a.b.c gives a and a.b), each followed
  by #10. }
function Me3PathPrefixes(const Path: String): String;
var
  P: Integer;
  Rest, Cur: String;
begin
  Result := '';
  Rest := Path;
  Cur := '';
  P := Pos(ME3_PART_SEP, Rest);
  while P > 0 do begin
    if Cur <> '' then
      Cur := Cur + ME3_PART_SEP;
    Cur := Cur + Copy(Rest, 1, P - 1);
    Result := Result + Cur + #10;
    Rest := Copy(Rest, P + 1, Length(Rest));
    P := Pos(ME3_PART_SEP, Rest);
  end;
end;

{ Scope joined with every item of Prefixes (#10-separated), each followed
  by #10. }
function Me3ScopeEach(const Scope, Prefixes: String): String;
var
  P: Integer;
  Rest: String;
begin
  Result := '';
  Rest := Prefixes;
  P := Pos(#10, Rest);
  while P > 0 do begin
    if P > 1 then
      Result := Result + Me3JoinScope(Scope, Copy(Rest, 1, P - 1)) + #10;
    Rest := Copy(Rest, P + 1, Length(Rest));
    P := Pos(#10, Rest);
  end;
end;

{ Every proper prefix of a scoped path below its scope ("7|a.b.c" gives
  "7|a" and "7|a.b"), each followed by #10. }
function Me3ScopePrefixes(const X: String): String;
var
  P: Integer;
begin
  P := Pos('|', X);
  Result := Me3ScopeEach(Copy(X, 1, P), Me3PathPrefixes(Copy(X, P + 1, Length(X))));
end;

{ True when one of the #10-separated items of Items is in List. }
function Me3AnyInList(const List, Items: String): Boolean;
var
  Rest, Item: String;
  P: Integer;
begin
  Result := False;
  Rest := Items;
  P := Pos(#10, Rest);
  while P > 0 do begin
    Item := Copy(Rest, 1, P - 1);
    if (Item <> '') and Me3InList(List, Item) then begin
      Result := True;
      Exit;
    end;
    Rest := Copy(Rest, P + 1, Length(Rest));
    P := Pos(#10, Rest);
  end;
end;

{ Records in TopLine the first line of the top-level names me3 reads as
  aliases: 0 natives, 1 native, 2 packages, 3 package (case-sensitive, as
  TOML keys). }
procedure Me3NoteTopName(const Name: String; const Line: Integer; var TopLine: TArrayOfInteger);
var
  K: Integer;
begin
  K := -1;
  if Name = 'natives' then
    K := 0
  else if Name = 'native' then
    K := 1
  else if Name = 'packages' then
    K := 2
  else if Name = 'package' then
    K := 3;
  if (K >= 0) and (TopLine[K] < 0) then
    TopLine[K] := Line;
end;

{ '' unless a profile uses both names of one of me3's aliases (natives and
  native, packages and package): me3 then refuses it ("duplicate field"). }
function Me3AliasProblem(const TopLine: TArrayOfInteger): String;
begin
  Result := '';
  if (TopLine[0] >= 0) and (TopLine[1] >= 0) then
    Result := Format('lines %d and %d use both natives and native, which me3 reads as one list (it refuses such a ' +
      'profile)', [TopLine[1] + 1, TopLine[0] + 1])
  else if (TopLine[2] >= 0) and (TopLine[3] >= 0) then
    Result := Format('lines %d and %d use both packages and package, which me3 reads as one list (it refuses such a ' +
      'profile)', [TopLine[3] + 1, TopLine[2] + 1]);
end;

{ '' when Lines are a profile Setup (and me3) can read: every line outside a
  value is blank, a comment, a valid header ([name] or [[name]], TOML keys)
  or key = value with a valid key; every array, inline table and string is
  closed; no table repeats a key (a dotted key included: a = 1 next to
  a.b = 2); no table is defined twice; no name is both a table and a list
  of tables; and no table header names a key its table already has - with
  the sub-tables of every entry counted in that entry (repair 4, verifier 5:
  the header [natives.initializer] below a [[natives]] table that has an
  initializer key is a key defined twice, which me3 refuses); and no two
  top-level names that me3 reads as one (Me3AliasProblem). Else the first
  problem, with its line number. }
function Me3StructureProblem(const Lines: TArrayOfString): String;
var
  Kinds, Roots: TArrayOfInteger;
  OpenAt, I, Count: Integer;
  IsArray: Boolean;
  Scope, Path, KeyPath, Seen, SeenPre, FullKeys, DotPre, Plain, Arrays, Flat, Pre, X, Top: String;
  Scopes: TArrayOfString;
  TopLine: TArrayOfInteger;
begin
  Result := '';
  Me3ClassifyEx(Lines, Kinds, OpenAt);
  if OpenAt >= 0 then begin
    Result := Format('line %d opens a list, table or text that is never closed', [OpenAt + 1]);
    Exit;
  end;
  if Me3BadValueAt >= 0 then begin
    Result := Format('line %d holds a run of more than five quotes in a multi-line text', [Me3BadValueAt + 1]);
    Exit;
  end;
  Me3HeaderRoots(Lines, Kinds, Roots);
  SetArrayLength(Scopes, GetArrayLength(Lines));
  { the first line of each of the top-level names natives, native, packages,
    package (-1: not used) }
  SetArrayLength(TopLine, 4);
  for I := 0 to 3 do
    TopLine[I] := -1;
  Scope := '-|';
  Seen := #10;
  SeenPre := #10;
  FullKeys := #10;
  DotPre := #10;
  Plain := #10;
  Arrays := #10;
  Flat := #10;
  for I := 0 to GetArrayLength(Lines) - 1 do begin
    Scopes[I] := '';
    if Kinds[I] = ME3_K_BAD then begin
      Result := Format('line %d is neither a [table] header nor "key = value": %s', [I + 1, Trim(Lines[I])]);
      Exit;
    end;
    if Kinds[I] = ME3_K_HEADER then begin
      Scope := Me3HeaderScope(Lines, Roots, I, IsArray, Count, Path);
      if Scope = '' then begin
        Result := Format('line %d is not a valid [table] header: %s', [I + 1, Trim(Lines[I])]);
        Exit;
      end;
      Scopes[I] := Scope;
      Seen := #10;
      SeenPre := #10;
      if Roots[I] = I then
        Me3NoteTopName(Me3FirstPart(Path), I, TopLine);
      if IsArray and (Count = 1) and (Roots[I] = I) then begin
        { a new element of the list of tables Path }
        if Me3InList(Flat, Path) then begin
          Result := Format('line %d makes %s a list of tables, but a line above already uses it as a table: %s', [
            I + 1, Me3PathText(Path), Trim(Lines[I])]);
          Exit;
        end;
        Me3AddToList(Arrays, '-|' + Path);
      end else begin
        if Roots[I] = I then
          Me3AddToList(Flat, Me3FirstPart(Path));
        if IsArray then
          Me3AddToList(Arrays, Scope)
        else begin
          if Me3InList(Plain, Scope) and not Me3AnyInList(Arrays, Me3ScopePrefixes(Scope)) then begin
            Result := Format('line %d defines the table %s a second time', [I + 1, Trim(Lines[I])]);
            Exit;
          end;
          Me3AddToList(Plain, Scope);
        end;
      end;
    end else if Kinds[I] = ME3_K_KEY then begin
      if not Me3ParseKeyPath(Me3KeyText(Lines[I]), KeyPath, Count) then begin
        Result := Format('line %d does not start with a valid key: %s', [I + 1, Trim(Lines[I])]);
        Exit;
      end;
      { the proper prefixes of the key (a.b.c: a and a.b), each followed by #10 }
      Pre := Me3PathPrefixes(KeyPath);
      if Me3InList(Seen, KeyPath) or Me3InList(SeenPre, KeyPath) or Me3AnyInList(Seen, Pre) then begin
        Result := Format('line %d repeats the key %s of its table', [I + 1, Me3PathText(KeyPath)]);
        Exit;
      end;
      Seen := Seen + KeyPath + #10;
      SeenPre := SeenPre + Pre;
      if Scope = '-|' then
        Me3NoteTopName(Me3FirstPart(KeyPath), I, TopLine);
      X := Me3JoinScope(Scope, KeyPath);
      Me3AddToList(FullKeys, X);
      DotPre := DotPre + Me3ScopeEach(Scope, Pre);
    end;
  end;
  { two names me3 reads as one list (measured with me3 0.13.0: [[native]]
    next to [[natives]], [[package]] next to [[packages]] = "duplicate
    field"; repair 4, the fifth verifier's u1 probe native_alias: Setup
    appended [[natives]] to a profile written with [[native]]) }
  Top := Me3AliasProblem(TopLine);
  if Top <> '' then begin
    Result := Top;
    Exit;
  end;
  { a table header that names a key a key line defines (in any order) }
  for I := 0 to GetArrayLength(Lines) - 1 do begin
    X := Scopes[I];
    if X = '' then
      Continue;
    if X[Length(X)] = '|' then begin
      { an element [[a]]: a top-level key a = ... (or a.b = ...) is the same name }
      Me3ParseHeader(Lines[I], IsArray, Path, Count);
      if Me3InList(FullKeys, '-|' + Path) or Me3InList(DotPre, '-|' + Path) then begin
        Result := Format('line %d: %s names a key that is already defined', [I + 1, Trim(Lines[I])]);
        Exit;
      end;
      Continue;
    end;
    if Me3InList(Plain, X) and Me3InList(Arrays, X) then begin
      Result := Format('line %d: %s is used both as a table and as a list of tables', [I + 1, Trim(Lines[I])]);
      Exit;
    end;
    if Me3InList(FullKeys, X) or Me3InList(DotPre, X) or Me3AnyInList(FullKeys, Me3ScopePrefixes(X)) then begin
      Result := Format('line %d: %s defines a table or key that its entry already has as a key', [I + 1,
        Trim(Lines[I])]);
      Exit;
    end;
  end;
end;

{ Every entry of Lines that is not this installer's to change, and the keys
  before the first header, as squeezed text (comments and blank lines left
  out); every sub-table comes right after the entry it belongs to, so a
  sub-table that would change entries changes the text (repair 4). Not this
  installer's: every entry that is no catalog native's, and while a native
  is off the player's own copy of an R or K native at another path (it
  stays). Setup's edits must leave this text unchanged. }
function Me3OtherTablesText(const Lines: TArrayOfString): String;
var
  Kinds, Roots: TArrayOfInteger;
  I, N, H, E, T, P, S: Integer;
  Mine: Boolean;
begin
  Result := '';
  Me3Classify(Lines, Kinds);
  Me3HeaderRoots(Lines, Kinds, Roots);
  N := GetArrayLength(Lines);
  I := 0;
  while (I < N) and (Kinds[I] <> ME3_K_HEADER) do begin
    if Me3IsContentKind(Kinds[I]) then
      Result := Result + Me3Squeeze(Lines[I]) + #10;
    I := I + 1;
  end;
  for H := I to N - 1 do begin
    if (Kinds[H] <> ME3_K_HEADER) or (Roots[H] <> H) then
      Continue;
    T := Me3HeaderNativeK(Lines, Kinds, H);
    Mine := T >= 0;
    if Mine and (NatForeign[T] <> 'S') and not NativeOn(T) then begin
      P := Me3TablePathLineK(Lines, Kinds, H);
      Mine := (P >= 0) and IsOurNativePathLine(T, Lines[P]);
    end;
    if Mine then
      Continue;
    for S := H to N - 1 do
      if (Kinds[S] = ME3_K_HEADER) and (Roots[S] = H) then begin
        if S > H then
          Result := Result + '  ';
        Result := Result + Me3Squeeze(Lines[S]) + #10;
        E := Me3TableEndK(Kinds, S);
        for P := S + 1 to E - 1 do
          if Me3IsContentKind(Kinds[P]) then
            Result := Result + Me3Squeeze(Lines[P]) + #10;
      end;
    Result := Result + #10;
  end;
end;

{ '' unless a "path = ..." key line holds its value as a "basic" string with
  a \u or \U escape - TOML (and me3) decode it, so "infinite\u005farrows.dll"
  is infinite_arrows.dll to me3 but not to Setup's line reader, which does
  not decode escapes - or as a multi-line string that runs over several
  lines (the value on the next line, or a line-ending backslash). Repair 5;
  me3's own reader catches both too, but it is not started in an elevated
  Setup. A 'literal' string (C:\Users\...) has no escapes, \\ in a basic
  string is fine, and so is a multi-line string that closes on its own
  line. Else the problem with its line number. }
function Me3PathEscapeProblem(const Lines: TArrayOfString): String;
var
  Kinds: TArrayOfInteger;
  I, J, P: Integer;
  V, ML: String;
begin
  Result := '';
  Me3Classify(Lines, Kinds);
  for I := 0 to GetArrayLength(Lines) - 1 do begin
    if (Kinds[I] <> ME3_K_KEY) or not StartsWithStr(Me3Squeeze(Lines[I]), 'path=') then
      Continue;
    V := Me3CodePart(Lines[I]);
    P := Length(Me3KeyText(V));
    V := Copy(V, P + 2, Length(V));
    V := Trim(V);
    { a path in a multi-line string: fine when it closes on its own line
      ('''./../mod/dll/x.dll''' reads the same for TOML and Setup); one
      that runs over several lines (its value is on the next line, or a
      line-ending backslash joins lines) is what Setup's line reader cannot
      see, so it is refused }
    ML := '';
    if StartsWithStr(V, '"""') or StartsWithStr(V, '''''''') then begin
      ML := Copy(V, 1, 3);
      if Pos(ML, Copy(V, 4, Length(V))) = 0 then begin
        Result := Format('line %d writes a path over several lines: %s', [I + 1, Trim(Lines[I])]);
        Exit;
      end;
    end;
    if (V = '') or (V[1] <> '"') then
      Continue;
    { walk the escapes of the basic string (a one-line """ one too): \\ and
      \" are fine, \u and \U not }
    if ML <> '' then
      J := 4
    else
      J := 2;
    while J < Length(V) do begin
      if (V[J] = '"') and ((ML = '') or (Copy(V, J, 3) = ML)) then
        Break;
      if V[J] = '\' then begin
        if (V[J + 1] = 'u') or (V[J + 1] = 'U') then begin
          Result := Format('line %d writes a path with a \u escape, which Setup does not decode: %s', [I + 1,
            Trim(Lines[I])]);
          Exit;
        end;
        J := J + 2;
      end else
        J := J + 1;
    end;
  end;
end;

{ '' unless a "path = ..." key line holds a value Setup cannot read as one
  string on its line (Me3PathLineValue = ''): a path over several lines, an
  unknown escape. Used by the uninstall (kind E), where such a line may be
  an entry of ours the player re-spelled (repair 6, finding A). }
function Me3UnreadablePathProblem(const Lines: TArrayOfString): String;
var
  Kinds: TArrayOfInteger;
  I: Integer;
begin
  Result := '';
  Me3Classify(Lines, Kinds);
  for I := 0 to GetArrayLength(Lines) - 1 do
    if (Kinds[I] = ME3_K_KEY) and StartsWithStr(Me3Squeeze(Lines[I]), 'path=') and
      (Me3PathLineValue(Lines[I]) = '') then
    begin
      Result := Format('line %d holds a path Setup cannot read: %s', [I + 1, Trim(Lines[I])]);
      Exit;
    end;
end;

{ ------------------------------------------------------------- stripping --- }

{ Lines minus every [[natives]] entry of native N (ExactOnly: only entries
  whose path line is our exact one): the whole entry (Me3MarkEntry: its
  table, every sub-table of it, the blank lines and comments between parts
  of it), the comment lines of our block directly above its header, and one
  blank line above those. Blank lines and comments after its last part
  stay: they sit above the next header. Returns True when an entry was
  found. }
function Me3StripNative(const Lines: TArrayOfString; const N: Integer; const ExactOnly: Boolean;
  var Kept: TArrayOfString): Boolean;
var
  Kinds, Roots: TArrayOfInteger;
  Drop: TArrayOfBoolean;
  H, P, K, C: Integer;
  Hit: Boolean;
begin
  Result := False;
  C := GetArrayLength(Lines);
  Me3Classify(Lines, Kinds);
  Me3HeaderRoots(Lines, Kinds, Roots);
  SetArrayLength(Drop, C);
  for H := 0 to C - 1 do
    Drop[H] := False;
  for H := 0 to C - 1 do begin
    if (Kinds[H] <> ME3_K_HEADER) or (Roots[H] <> H) or not IsNativesHeaderLine(Lines[H]) then
      Continue;
    P := Me3TablePathLineK(Lines, Kinds, H);
    if P < 0 then
      Continue;
    if ExactOnly then
      Hit := IsOurNativePathLine(N, Lines[P])
    else
      Hit := NativeMatchesPathLine(N, Lines[P]);
    if not Hit then
      Continue;
    Me3MarkEntry(Kinds, Roots, H, Drop);
    K := H - 1;
    while (K >= 0) and (Kinds[K] = ME3_K_COMMENT) and IsNativeBlockComment(N, Lines[K]) do begin
      Drop[K] := True;
      K := K - 1;
    end;
    if (K >= 0) and (Kinds[K] = ME3_K_BLANK) then
      Drop[K] := True;
    Result := True;
  end;
  SetArrayLength(Kept, C);
  K := 0;
  for H := 0 to C - 1 do
    if not Drop[H] then begin
      Kept[K] := Lines[H];
      K := K + 1;
    end;
  SetArrayLength(Kept, K);
end;

{ Lines minus "our" entries of every native the saved copy (Saved) does not
  carry; with HaveSaved = False every native's entries are taken out. }
procedure Me3StripNativesNotIn(const Lines, Saved: TArrayOfString; const HaveSaved: Boolean;
  var Kept: TArrayOfString);
var
  N: Integer;
  T: TArrayOfString;
begin
  CopyLines(Lines, Kept);
  for N := 0 to NatCount - 1 do
    if not (HaveSaved and Me3LinesHaveNative(Saved, N)) then begin
      Me3StripNative(Kept, N, NativeOursIsExact(N), T);
      CopyLines(T, Kept);
    end;
end;

{ ---------------------------------------------------------------- target --- }

{ The profile for the chosen options (see the header). False (TargetLines
  untouched, Problem says why) when the profile cannot take them: an inline
  natives list, an R native's DLL loaded more than once, a profile that is
  not readable TOML, or an edit that would not stay readable or would change
  another entry (repair 3). }
function Me3ComputeTarget(const Lines: TArrayOfString; const RelName: String;
  var TargetLines: TArrayOfString; var Problem: String): Boolean;
var
  S, T: TArrayOfString;
  Append: array of Boolean;
  N, I, Exact, Foreign, ForeignIdx, Other: Integer;
  P: String;
begin
  Result := False;
  Problem := '';
  { 0. a profile Setup cannot read is never acted on - also when Setup would
       not change it: which DLLs stay depends on reading it (repair 5, sixth
       verifier DEFECT 2: with an entry Setup could not see, it removed a DLL
       me3 still loads) }
  P := Me3StructureProblem(Lines);
  if P = '' then
    P := Me3PathEscapeProblem(Lines);
  if P <> '' then begin
    Problem := RelName + ' cannot be read safely (' + P + '), so Setup does not edit it. Restore the profile ' +
      'with the Convergence Launcher (repair), or correct that line.';
    Exit;
  end;
  CopyLines(Lines, S);
  SetArrayLength(Append, NatCount);
  { 1. S natives: every table of theirs goes (appended again when on); K
       natives: the same while on, only our exact table while off }
  for N := 0 to NatCount - 1 do begin
    Append[N] := False;
    if NatForeign[N] <> 'R' then begin
      Me3StripNative(S, N, (NatForeign[N] = 'K') and not NativeOn(N), T);
      CopyLines(T, S);
      Append[N] := NativeOn(N);
    end;
  end;
  { 2. the inline list check (what v6.3/v6.4 refused too) }
  if AnyNativeOn and Me3LinesHaveInline(S) then begin
    Problem := RelName + ' uses an inline natives list (natives = [ ... ]). Setup cannot add its ' +
      'entries to it safely. Restore the profile with the Convergence Launcher (repair).';
    Exit;
  end;
  { 3. R natives: the v6.3 rule }
  for N := 0 to NatCount - 1 do
    if NatForeign[N] = 'R' then begin
      if NativeOn(N) then begin
        Me3AnalyzeNative(S, N, Exact, Foreign, ForeignIdx, Other);
        if Exact + Foreign > 1 then begin
          Problem := RelName + ' already loads ' + NatMatch[N] + ' more than once';
          if ForeignIdx >= 0 then
            Problem := Problem + ' (line ' + IntToStr(ForeignIdx + 1) + ': ' + Trim(S[ForeignIdx]) + ')';
          Problem := Problem + '. Remove the extra [[natives]] entries, or restore the profile with the ' +
            'Convergence Launcher (repair).';
          Exit;
        end;
        if Foreign = 1 then
          S[ForeignIdx] := NativeOurPathLineText(N)   { an entry that loads the DLL from elsewhere: point it at ours }
        else if Exact = 0 then
          Append[N] := True;
      end else begin
        Me3StripNative(S, N, True, T);
        CopyLines(T, S);
      end;
    end;
  { 4. append the blocks in catalog order }
  for N := 0 to NatCount - 1 do
    if Append[N] then begin
      TrimTrailingBlankLines(S);
      AddLine(S, '');
      for I := NatLineStart[N] to NatLineStart[N] + NatLineCount[N] - 1 do
        AddLine(S, NatLine[I]);
    end;
  { 5. a change only to a readable result (the profile itself was checked in
       step 0), and never to another entry (verifier 4 D1: a player's own
       layout that me3 accepts must survive every run) }
  if not SameLines(Lines, S) then begin
    P := Me3StructureProblem(S);
    if P <> '' then begin
      Problem := RelName + ': Setup''s edit of the natives would not be readable (' + P + '), so nothing was ' +
        'changed. Restore the profile with the Convergence Launcher (repair).';
      Exit;
    end;
    if Me3OtherTablesText(Lines) <> Me3OtherTablesText(S) then begin
      Problem := RelName + ': Setup''s edit of the natives would also change another entry of the profile, so ' +
        'nothing was changed. Restore the profile with the Convergence Launcher (repair).';
      Exit;
    end;
  end;
  CopyLines(S, TargetLines);
  Result := True;
end;

{ '' when the chosen natives can be set up in this profile, else the reason. }
function Me3ProfileProblem(const FileName, RelName: String): String;
var
  Lines, Target: TArrayOfString;
begin
  Result := '';
  if not LoadStringsFromFile(FileName, Lines) then begin
    Result := 'Setup cannot read ' + RelName + '.';
    Exit;
  end;
  Me3ComputeTarget(Lines, RelName, Target, Result);
end;

{ ---------------------------------------------------------------- writing --- }

{ 0 or 1 when FileName is one of the two Convergence profiles, else -1. }
function Me3ProfileIndexOf(const FileName: String): Integer;
var
  I: Integer;
  L, Tail: String;
begin
  Result := -1;
  L := Lowercase(FileName);
  for I := 0 to ME3_PROFILE_COUNT - 1 do begin
    Tail := Lowercase('\' + Me3Profile[I]);
    if (Length(L) >= Length(Tail)) and (Copy(L, Length(L) - Length(Tail) + 1, Length(Tail)) = Tail) then
      Result := I;
  end;
end;

function Me3IsStockLines(const FileName: String; const Lines: TArrayOfString): Boolean;
var
  Idx: Integer;
begin
  Idx := Me3ProfileIndexOf(FileName);
  if Idx = 0 then
    Result := SameLines(Lines, PristineMe3Lines0)
  else if Idx = 1 then
    Result := SameLines(Lines, PristineMe3Lines1)
  else
    Result := False;
end;

{ Writes a profile in its canonical form (see the header), through a
  temporary file that replaces it (never in place: util.iss
  ReplaceFileWithTemp). The file is read back and compared. }
function SaveMe3Lines(const FileName: String; const Lines: TArrayOfString): Boolean;
var
  Back: TArrayOfString;
begin
  if Me3LinesHaveLfNative(Lines) then
    Result := SaveBytesReplacing(FileName, UTF8Encode(JoinLines(Lines, #10) + #10))
  else if Me3IsStockLines(FileName, Lines) then
    Result := SaveBytesReplacing(FileName, UTF8Encode(JoinLines(Lines, #13#10)))
  else
    Result := SaveLinesUTF8Replacing(FileName, Lines);
  if Result and not (LoadStringsFromFile(FileName, Back) and SameLines(Back, Lines)) then begin
    Log('Written, but reads back differently: ' + FileName);
    Result := False;
  end;
  if not Result then
    Log('Cannot write ' + FileName);
end;

{ Brings one profile to the target for the chosen options. Changed = it was
  rewritten. False when it cannot be read, cannot take the options, or
  cannot be written. }
function Me3ApplyTarget(const FileName, RelName: String; var Changed: Boolean): Boolean;
var
  Lines, Target: TArrayOfString;
  Problem: String;
begin
  Changed := False;
  Result := False;
  if not LoadStringsFromFile(FileName, Lines) then begin
    Log('Cannot read ' + FileName);
    Exit;
  end;
  if not Me3ComputeTarget(Lines, RelName, Target, Problem) then begin
    Log('Refusing to edit ' + FileName + ': ' + Problem);
    Exit;
  end;
  if SameLines(Lines, Target) then begin
    Result := True;
    Exit;
  end;
  Result := SaveMe3Lines(FileName, Target);
  Changed := Result;
  if Result then
    Log('Updated ' + FileName + ' (natives of the chosen options)');
end;

{ How the backup must record a profile before this run edits it:
    ''  nothing changes
    'E' only entries of ours are added (uninstall takes them out again, and
        puts the saved copy back byte for byte when nothing else changed)
    'B' anything else (the whole profile is put back on uninstall) }
function Me3PlanKind(const FileName, RelName: String): String;
var
  Lines, Target, S: TArrayOfString;
  Problem: String;
begin
  Result := 'B';
  if not LoadStringsFromFile(FileName, Lines) then
    Exit;
  if not Me3ComputeTarget(Lines, RelName, Target, Problem) then
    Exit;
  if SameLines(Lines, Target) then begin
    Result := '';
    Exit;
  end;
  Me3StripNativesNotIn(Target, Lines, True, S);
  if SameLines(S, Lines) then
    Result := 'E';
end;

{ Uninstall of backup kind E: takes out every entry of ours that the saved
  copy (BackupCopy) does not have. When the rest is line for line the saved
  copy, that copy is put back (byte for byte); when the user changed the
  profile since, only our entries are removed - unless the result would not
  be readable, or would change another entry, or the profile is not
  readable now (a broken edit): then the saved copy is put back whole
  (repair 3, verifier 4 D1: an uninstall never leaves a profile me3 cannot
  read). }
function Me3RemoveAddedEntries(const FileName, BackupCopy: String): Boolean;
var
  Lines, Saved, Kept: TArrayOfString;
  HaveSaved: Boolean;
  Why: String;
begin
  Result := True;
  if not FileExists(FileName) then
    Exit;
  if not LoadStringsFromFile(FileName, Lines) then begin
    Result := False;
    Exit;
  end;
  HaveSaved := (BackupCopy <> '') and FileExists(BackupCopy) and LoadStringsFromFile(BackupCopy, Saved);
  Me3StripNativesNotIn(Lines, Saved, HaveSaved, Kept);
  if HaveSaved and SameLines(Kept, Saved) then begin
    if SameLines(Lines, Saved) and (GetFileSizeSafe(FileName) = GetFileSizeSafe(BackupCopy)) and
      (SafeMD5(FileName) = SafeMD5(BackupCopy)) then
      Exit;
    Result := CopyFileChecked(BackupCopy, FileName);
    if Result then
      Log('Restored ' + FileName + ' from its backup (our entries removed)');
    Exit;
  end;
  { a profile Setup cannot read safely now - e.g. a path written over
    several lines, which may be an entry of ours that the player re-spelled
    and that Setup's reader cannot see: with a saved copy, that copy is put
    back whole (also when no entry of ours was found), rather than leaving
    an entry that names a DLL the uninstall deletes (repair 6, TEST lane
    after repair 5, finding A) }
  Why := Me3StructureProblem(Lines);
  if Why = '' then
    Why := Me3UnreadablePathProblem(Lines);
  if (Why = '') or not HaveSaved then
    if SameLines(Kept, Lines) then
      Exit;
  if Why <> '' then
    Why := 'the profile is not readable now (' + Why + ')'
  else begin
    Why := Me3StructureProblem(Kept);
    if Why <> '' then
      Why := 'taking our entries out would leave it unreadable (' + Why + ')'
    else if Me3OtherTablesText(Kept) <> Me3OtherTablesText(Lines) then
      Why := 'taking our entries out would change another entry';
  end;
  if Why <> '' then begin
    if HaveSaved then begin
      Result := CopyFileChecked(BackupCopy, FileName);
      if Result then
        Log('Restored ' + FileName + ' whole from its backup: ' + Why);
    end else begin
      Log('Left ' + FileName + ' as it is: ' + Why + ', and its saved copy is missing');
      Result := False;
    end;
    Exit;
  end;
  Result := SaveMe3Lines(FileName, Kept);
  if Result then
    Log('Removed our [[natives]] entries from ' + FileName);
end;

{ ----------------------------------------------------------- verification --- }

{ The index of the path line of the first table of native N (-1 when none). }
function Me3NativeFirstPathLine(const Lines: TArrayOfString; const N: Integer): Integer;
var
  Kinds, Found: TArrayOfInteger;
begin
  Result := -1;
  Me3Classify(Lines, Kinds);
  Me3NativeTablePathLines(Lines, Kinds, N, Found);
  if GetArrayLength(Found) > 0 then
    Result := Found[0];
end;

{ '' when profile Lines are right for native N with the chosen options,
  else what is wrong. On, R: our exact entry exactly once, no foreign one.
  On, S: exactly one table of it, ours, holding every active line of our
  block. Off: no entry of ours (R) / no table of it at all (S). }
function Me3NativeVerify(const Lines: TArrayOfString; const N: Integer): String;
var
  Kinds, Found: TArrayOfInteger;
  I, J, E, K, Tables, Exact, Foreign, ForeignIdx, Other: Integer;
  Have: TStringList;
  Idx: Integer;
begin
  Result := '';
  if (NatForeign[N] = 'R') or ((NatForeign[N] = 'K') and not NativeOn(N)) then begin
    { R; K while off: no entry of ours (the player's own copy may stay) }
    Me3AnalyzeNative(Lines, N, Exact, Foreign, ForeignIdx, Other);
    if NativeOn(N) then begin
      if Exact = 0 then
        Result := 'does not load ' + NatMatch[N]
      else if Exact + Foreign > 1 then
        Result := 'loads ' + NatMatch[N] + ' more than once';
    end else if Exact > 0 then
      Result := 'still loads ' + NatMatch[N] + ' although it was switched off';
    Exit;
  end;
  Me3Classify(Lines, Kinds);
  Me3NativeTablePathLines(Lines, Kinds, N, Found);
  Tables := GetArrayLength(Found);
  if not NativeOn(N) then begin
    if Tables > 0 then
      Result := 'still loads ' + NatMatch[N] + ' although it was switched off';
    Exit;
  end;
  if Tables <> 1 then begin
    Result := Format('loads %s %d times instead of once', [NatMatch[N], Tables]);
    Exit;
  end;
  J := Found[0];
  if not IsOurNativePathLine(N, Lines[J]) then begin
    Result := 'loads ' + NatMatch[N] + ' from another path: ' + Trim(Lines[J]);
    Exit;
  end;
  K := Me3OwnerHeaderK(Kinds, J);
  E := Me3TableEndK(Kinds, K);
  Have := TStringList.Create;
  try
    Have.Sorted := True;
    Have.Duplicates := dupIgnore;
    for I := K to E - 1 do
      if Me3IsContentKind(Kinds[I]) or (Kinds[I] = ME3_K_HEADER) then
        Have.Add(Me3Squeeze(Lines[I]));
    for I := NatLineStart[N] to NatLineStart[N] + NatLineCount[N] - 1 do
      if Me3IsActiveLine(NatLine[I]) and not Have.Find(Me3Squeeze(NatLine[I]), Idx) then begin
        Result := 'the ' + NatMatch[N] + ' table lacks the line ' + Trim(NatLine[I]);
        Exit;
      end;
  finally
    Have.Free;
  end;
end;

{ '' when a profile file is right for every native of the catalog: each one
  as Me3NativeVerify says, the ones that are on in catalog order, and the
  last appended one (Nightreign Movement) the last [[natives]] table. }
function Me3VerifyProfile(const FileName: String): String;
var
  Lines: TArrayOfString;
  Kinds: TArrayOfInteger;
  N, P, LastPos, LastS, H, K: Integer;
  Problem: String;
begin
  Result := '';
  if not LoadStringsFromFile(FileName, Lines) then begin
    Result := 'cannot be read';
    Exit;
  end;
  for N := 0 to NatCount - 1 do begin
    Problem := Me3NativeVerify(Lines, N);
    if Problem <> '' then begin
      if Result <> '' then
        Result := Result + '; ';
      Result := Result + Problem;
    end;
  end;
  if Result <> '' then
    Exit;
  Me3Classify(Lines, Kinds);
  LastPos := -1;
  LastS := -1;
  for N := 0 to NatCount - 1 do
    if NativeOn(N) then begin
      P := Me3NativeFirstPathLine(Lines, N);
      if P < LastPos then begin
        Result := 'the natives are not in the installer''s order (' + NatMatch[N] + ' comes too early)';
        Exit;
      end;
      LastPos := P;
      if NatForeign[N] <> 'R' then
        LastS := N;
    end;
  if LastS >= 0 then begin
    P := Me3NativeFirstPathLine(Lines, LastS);
    H := Me3OwnerHeaderK(Kinds, P);
    for K := Me3TableEndK(Kinds, H) to GetArrayLength(Lines) - 1 do
      if (Kinds[K] = ME3_K_HEADER) and IsNativesHeaderLine(Lines[K]) then begin
        Result := NatMatch[LastS] + ' is not the last native';
        Exit;
      end;
  end;
end;

{ The md5 the Convergence 3.0.2 manifest gives for Rel ('' when none). }
function ConvManifestMd5Of(const Rel: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to CmCount - 1 do
    if CompareText(CmRel[I], Rel) = 0 then begin
      Result := CmMd5[I];
      Exit;
    end;
end;

{ The natives a profile loads as Setup reads them: one item per [[natives]]
  (or [[native]]) entry, the catalog native whose path line it holds
  (NatMatch) or "other", sorted, joined by ", " (repair 5). }
function Me3NativesSignature(const Lines: TArrayOfString): String;
var
  Kinds, Roots: TArrayOfInteger;
  Items: TStringList;
  H, P, N, T: Integer;
begin
  Items := TStringList.Create;
  try
    Me3Classify(Lines, Kinds);
    Me3HeaderRoots(Lines, Kinds, Roots);
    for H := 0 to GetArrayLength(Lines) - 1 do
      if (Kinds[H] = ME3_K_HEADER) and (Roots[H] = H) and IsNativesHeaderLine(Lines[H]) then begin
        T := -1;
        P := Me3TablePathLineK(Lines, Kinds, H);
        if P >= 0 then
          for N := 0 to NatCount - 1 do
            if (T < 0) and NativeMatchesPathLine(N, Lines[P]) then
              T := N;
        if T >= 0 then
          Items.Add(Lowercase(NatMatch[T]))
        else
          Items.Add('other');
      end;
    Items.Sort;
    Result := Items.CommaText;
    StringChangeEx(Result, ',', ', ', True);
  finally
    Items.Free;
  end;
end;

{ The same from me3's own reader: every "Path:" line of the Natives section
  of "me3 profile show" (me3 0.13.0 prints one section per heading line
  that starts in the first column, and each native's "Path:" indented). }
function Me3ExeNativesSignature(const Output: TExecOutput): String;
var
  Items: TStringList;
  I, N, T: Integer;
  Line, S: String;
  InNatives: Boolean;
begin
  Items := TStringList.Create;
  try
    InNatives := False;
    for I := 0 to GetArrayLength(Output.StdOut) - 1 do begin
      Line := Output.StdOut[I];
      if Trim(Line) = '' then
        Continue;
      if (Line[1] <> ' ') and (Line[1] <> #9) then begin
        { a section heading }
        S := Trim(Line);
        InNatives := (Length(S) >= 7) and (Copy(S, Length(S) - 6, 7) = 'Natives');
        Continue;
      end;
      if not InNatives then
        Continue;
      S := Trim(Line);
      if not StartsWithStr(S, 'Path:') then
        Continue;
      S := Lowercase(Copy(S, 6, Length(S)));
      StringChangeEx(S, ' ', '', True);
      T := -1;
      for N := 0 to NatCount - 1 do
        if (T < 0) and (Pos(Lowercase(NatMatch[N]), S) > 0) then
          T := N;
      if T >= 0 then
        Items.Add(Lowercase(NatMatch[T]))
      else
        Items.Add('other');
    end;
    Items.Sort;
    Result := Items.CommaText;
    StringChangeEx(Result, ',', ', ', True);
  finally
    Items.Free;
  end;
end;

{ Runs me3's own reader on a profile ("me3 profile show --file"). True when
  it ran (ResultCode and Output are me3's); False when that check cannot run
  (logged: the uninstaller, no Convergence folder, an elevated Setup - a
  program from a folder a normal user can change is never started with
  administrator rights -, no me3.exe of The Convergence 3.0.2 or no manifest
  md5). me3.exe is copied into Setup's own temp folder and its md5 is
  checked there (the official release's), and only that copy is started.
  Test builds: /TESTME3EXE=<me3.exe> runs that file instead (the /TESTUNIT
  cases, which have no Convergence folder). }
function Me3ExeRun(const FileName: String; var ResultCode: Integer; var Output: TExecOutput): Boolean;
var
  Src, Dir, Exe, Md5: String;
  Given: Boolean;
begin
  Result := False;
  Given := False;
  Exe := '';
  Dir := '';
#if Defined(CodeCheck) || Defined(TestBuild)
  if CmdParam('TESTME3EXE') <> '' then begin
    Exe := CmdParam('TESTME3EXE');
    Dir := ExtractFileDir(Exe);
    Given := FileExists(Exe);
  end;
#endif
  if not Given then begin
    if IsUninstaller or (ConvDir = '') then
      Exit;
    if SetupElevated then begin
      Log('me3 reader check skipped: Setup runs as administrator');
      Exit;
    end;
    Src := ConvPath('me3\Windows\me3.exe');
    Md5 := ConvManifestMd5Of('me3\Windows\me3.exe');
    if (Md5 = '') or not FileExists(Src) then begin
      Log('me3 reader check skipped: no checked me3\Windows\me3.exe');
      Exit;
    end;
    Dir := ExpandConstant('{tmp}\cxcxm_me3');
    Exe := AddBackslash(Dir) + 'me3.exe';
    if not FileExists(Exe) or (CompareText(SafeMD5(Exe), Md5) <> 0) then begin
      ForceDirectories(Dir);
      DeleteFile(Exe);
      if not CopyFile(Src, Exe, False) or (CompareText(SafeMD5(Exe), Md5) <> 0) then begin
        DeleteFile(Exe);
        Log('me3 reader check skipped: me3.exe is not The Convergence 3.0.2''s (md5)');
        Exit;
      end;
    end;
  end;
  try
    { hidden: it now also runs before the install (Options page, plan; repair 5) }
    if not ExecAndCaptureOutput(Exe, 'profile show --file "' + FileName + '"', Dir, SW_HIDE,
      ewWaitUntilTerminated, ResultCode, Output) then
    begin
      Log('me3 reader check skipped: me3.exe could not be started: ' + SysErrorMessage(ResultCode));
      Exit;
    end;
  except
    Log('me3 reader check skipped: ' + GetExceptionMessage);
    Exit;
  end;
  Result := True;
end;

{ me3's own reader on a profile: '' when "me3 profile show --file" reads it
  AND lists the same natives as Setup reads in the file (Me3NativesSignature
  = Me3ExeNativesSignature: repair 5, sixth verifier DEFECT 2 - a layout
  Setup's line reader takes differently from me3 is caught before Setup
  acts on it and after it wrote it), or when that check cannot run
  (Me3ExeRun); else what is wrong. }
function Me3ExeProblem(const FileName: String): String;
var
  ResultCode, I: Integer;
  Output: TExecOutput;
  Lines: TArrayOfString;
  Ours, Theirs: String;
begin
  Result := '';
  if not Me3ExeRun(FileName, ResultCode, Output) then
    Exit;
  if ResultCode <> 0 then begin
    Result := 'me3 cannot read it';
    for I := 0 to GetArrayLength(Output.StdErr) - 1 do
      if (Pos('error', Lowercase(Output.StdErr[I])) > 0) and (Length(Result) < 200) then
        Result := Result + ': ' + Trim(Output.StdErr[I]);
    for I := 0 to GetArrayLength(Output.StdOut) - 1 do
      if (Pos('error', Lowercase(Output.StdOut[I])) > 0) and (Length(Result) < 200) then
        Result := Result + ': ' + Trim(Output.StdOut[I]);
    Log(Format('me3 profile show %s: exit %d', [FileName, ResultCode]));
    Exit;
  end;
  if not LoadStringsFromFile(FileName, Lines) then begin
    Result := 'cannot be read';
    Exit;
  end;
  { an inline natives list (natives = [ ... ]) has no [[natives]] tables to
    compare; Setup refuses to edit such a profile as soon as one of its
    natives is on (Me3ComputeTarget), and reads its mentions of our DLLs as
    another mod's (they stay) }
  if Me3LinesHaveInline(Lines) then begin
    Log('me3 profile show: reads ' + FileName + ' (an inline natives list: natives not compared)');
    Exit;
  end;
  Ours := Me3NativesSignature(Lines);
  Theirs := Me3ExeNativesSignature(Output);
  if Ours <> Theirs then begin
    Result := 'me3 reads its natives differently from Setup (me3: ' + Theirs + '; Setup: ' + Ours + ')';
    Log('CXCXM ME3READ differs ' + FileName + ': me3 [' + Theirs + '] Setup [' + Ours + ']');
  end else
    Log('me3 profile show: reads ' + FileName + ' with the same natives as Setup [' + Ours + ']');
end;

{ '' when a profile that Setup rewrote in this run is still right as a whole:
  readable, every other table as it was before Setup's edit (OtherBefore =
  Me3OtherTablesText of the profile right before the edit; '' = not known),
  and me3's own reader takes it. }
function Me3VerifyProfileEdit(const FileName, OtherBefore: String): String;
var
  Lines: TArrayOfString;
begin
  Result := '';
  if not LoadStringsFromFile(FileName, Lines) then begin
    Result := 'cannot be read';
    Exit;
  end;
  Result := Me3StructureProblem(Lines);
  if Result <> '' then begin
    Result := 'not readable any more: ' + Result;
    Exit;
  end;
  if (OtherBefore <> '') and (Me3OtherTablesText(Lines) <> OtherBefore) then begin
    Result := 'another entry of the profile changed';
    Exit;
  end;
  Result := Me3ExeProblem(FileName);
end;
