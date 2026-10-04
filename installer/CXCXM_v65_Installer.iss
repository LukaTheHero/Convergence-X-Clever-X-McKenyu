; =============================================================================
;  Convergence X Clever X McKenyu V6.5 - Auto Installer ("installer v2")
;  Inno Setup 6.7 script. Build it with the release pipeline (release.py):
;  it writes generated\catalog.iss + generated\build_info.iss and the
;  Convergence 3.0.2 manifest, checks the never-bundle rules, then calls ISCC
;  with /DFromPipeline. Do not compile this file on its own.
;  Builder contract: README_CONTRACT.md (CAT_FORMAT 2).
;
;  The exe carries no mod files. It carries the catalog: every file the
;  installer may write, the variant each path must hold for each selection,
;  and where each variant comes from:
;    - a member of one of the player's own downloads (the merge's main zip,
;      Clever's and McKenyu's modpacks, Nightreign Movement, Seamless Co-op),
;      found in the Downloads folder (or picked by hand) and checked by
;      SHA-256 file by file ("Wabbajack style": the authors get their
;      downloads);
;    - a hosted file on Luka's GitHub release (Lucy, Infinite Durations,
;      the merged Nightreign Movement files, Infinite Arrows, the
;      ERCapacityExpansion DLL), downloaded before anything changes and
;      checked by SHA-256.
;
;  Page flow
;    Welcome -> Elden Ring (Patch 1.17 + Shadow of the Erdtree)
;    -> Convergence folder (detected; Next checks every Convergence 3.0.2 file)
;    -> Other mods (only when found)
;    -> Options (every component of the catalog; presets = what is installed)
;    -> Get these downloads (only when the selection needs some)
;    -> Credits -> Ready
;    -> Install click: game check again, plan, download, backup
;    -> Installing: other mods' files moved; post-install writes the files,
;       removes what the selection must not have, .me3 natives, fields,
;       marker, SHA-256 verification of everything, rollback offer
;
;  Unattended use (details and all exit codes in code\events.iss):
;    "Convergence X Clever X McKenyu V6.5 - Auto Installer.exe" /VERYSILENT
;      /SUPPRESSMSGBOXES /LOG="C:\path\setup.log" /CONVDIR="path"
;      /COMPONENTS=lucy,nrm,infdur:v2 (or /LUCY= /NRM= /INFDUR= /ARROWS=
;      /SEAMLESS= /ERCAP=) /ARCHIVE_<ID>="archive or folder" /ARCHIVEDIR=
;      /SEARCHDOWNLOADS=0|1 /BASEURL= /UPSTREAM=0|1 /COOPPASSWORD=
;      /FOREIGN=move|keep /GAMEOK=1
;    Exit codes: 0 ok; 1 validation failed (nothing changed, incl. missing
;    downloads); 7 refused at Preparing (incl. a failed download; nothing
;    changed); 20 verification failed, rolled back; 21 verification failed,
;    kept; 22 a post-install step failed.
;    Uninstall: CXCXM_uninstall\unins000.exe /VERYSILENT /SUPPRESSMSGBOXES
; =============================================================================

; The pipeline enforces the never-bundle rules (Clever's parts, McKenyu's,
; Nightreign Movement's and Seamless's files are never hosted or embedded)
; before it calls ISCC with /DFromPipeline. A direct compile would skip
; those checks, so it is refused.
#ifndef FromPipeline
  #error Build with the release pipeline (release.py): it enforces the never-bundle rules. Do not compile this file on its own.
#endif

; /DCatalogStub (code-check builds only): compile against the INNO lane's
; stub include (tests\stub), which follows the contract, instead of the
; pipeline's generated\ files. Never for a test or release build.
#ifdef CatalogStub
  #ifndef CodeCheck
    #error CatalogStub is only allowed together with CodeCheck.
  #endif
  #include "tests\stub\build_info_stub.iss"
  #define CatalogInclude "tests\stub\catalog_stub.iss"
  #define ConvManifestSource "tests\stub\CXCXM_conv302_manifest.txt"
#else
  #include "generated\build_info.iss"
  #define CatalogInclude "generated\catalog.iss"
  #define ConvManifestSource "staging\meta\CXCXM_conv302_manifest.txt"
#endif

#ifndef CatFormat
  #error generated\build_info.iss does not define CatFormat. Rebuild with the release pipeline.
#endif
#if CatFormat != 2
  #error The catalog has format {#CatFormat}; this installer code reads CAT_FORMAT 2. Update the code or the pipeline.
#endif

; the installer code fingerprint (pipeline\codefp.py) is passed by the pipeline as /DCodeFp=...; it and the
; catalog sha256 go into the exe's version resource (the ProductVersion string), so publish_github.py and the test
; runner can tell which catalog and which code an exe was compiled from (repair 1)
#ifndef CodeFp
  #define CodeFp "unknown"
#endif

#define MyAppShortVersion Copy(CatVersion, 1, RPos(".", CatVersion) - 1)
#define MyAppName      "Convergence X Clever X McKenyu v" + MyAppShortVersion
#define MyAppPublisher "canalpa"

[Setup]
; AppId is per Convergence folder, so every Convergence install gets its own
; uninstall entry and uninstall log (see GetAppId in code\events.iss). It is
; the same formula as v6.3/v6.4, so v6.5 takes over their entry.
AppId={code:GetAppId}
AppName={#MyAppName}
AppVersion={#CatVersion}
AppVerName={#MyAppName}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://canalpa.com
AppSupportURL=https://www.nexusmods.com/eldenring/mods/10388
UninstallDisplayName={code:GetUninstallDisplayName}
VersionInfoVersion={#VersionInfo}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Auto Installer ({#CatRc}, built {#BuildStamp})
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#CatVersion}
; Inno keeps at most 50 characters of this string (FileVersion: 20), so it carries the first 16 hex digits of each
; id: "6.5.0 cat <catalog sha256> code <code fingerprint>"
VersionInfoProductTextVersion={#CatVersion} cat {#Copy(CatSha256, 1, 16)} code {#Copy(CodeFp, 1, 16)}

; The destination is ALWAYS the Convergence folder chosen on our own page; the
; standard directory page is never shown. DefaultDirName is only a placeholder:
; PrepareToInstall refuses to continue unless {app} equals the validated folder.
DefaultDirName={userdocs}\ConvergenceER
DisableDirPage=yes
UsePreviousAppDir=no
UsePreviousLanguage=no
DirExistsWarning=no
AppendDefaultDirName=no
DisableProgramGroupPage=yes
DisableWelcomePage=no
DisableReadyPage=no
DisableFinishedPage=no
AlwaysShowDirOnReadyPage=no
#ifndef CodeCheck
Uninstallable=yes
#endif
UninstallFilesDir={app}\CXCXM_uninstall
CreateUninstallRegKey=yes

; Convergence installs are ordinary user folders. If a folder needs admin
; rights the Convergence page says so (run the installer as administrator).
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=no
RestartIfNeededByRun=no
; one installer at a time; the uninstaller also refuses while this mutex exists
SetupMutex=CanalpaCXCXMInstaller,Global\CanalpaCXCXMInstaller
SetupLogging=yes
UninstallLogging=yes
ShowLanguageDialog=no

; The players' downloads may be .zip/.7z/.rar; "full" is the fallback
; extractor when the Windows tar.exe cannot read them (code\archives.iss).
ArchiveExtraction=full

OutputDir=output
#if Defined(CodeCheck)
; Pascal syntax check only, never shipped
OutputBaseFilename=CODECHECK - not a release
Compression=none
Uninstallable=no
#elif Defined(TestBuild)
; test build: watches a dummy game process instead of eldenring.exe (so it
; can be tested while the game runs) and knows the /TEST... switches;
; never shipped; no compression (as v6.4's test build: fast to build and
; to start)
OutputBaseFilename=TESTBUILD - not a release
Compression=none
#else
OutputBaseFilename={#InstallerBaseName}
Compression=lzma2/max
SolidCompression=yes
#endif
WizardStyle=modern
WizardSizePercent=130

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel1={#MyAppName}%nAuto Installer
WelcomeLabel2=This installs the merge into your Convergence folder, with any mix of its options (Lucy, Nightreign Movement, Infinite Durations, Infinite Arrows, Seamless Co-op, ERCapacityExpansion).%n%nYou need:%n- Elden Ring Patch 1.17 with Shadow of the Erdtree (Steam)%n- The Convergence 3.0.2 from the Convergence Launcher, launched once%n- The downloads Setup asks for, from their authors' pages%n- Internet for the option files, and a backup of your saves%n%nSetup checks the game, The Convergence, other mods and every downloaded file before it changes anything. Play offline; close Elden Ring first.
ReadyLabel2a=Check the summary below, then click Install.
ButtonInstall=&Install
FinishedHeadingLabel=Installation finished
ConfirmUninstall=This removes %1 from this Convergence folder and puts back the original files from the backup the installer made.%n%nSettings files that the installer created for its options are removed too (for example mod\dll\NightreignMovement.ini, or SeamlessCoop\ersc_settings.ini with your co-op password); copy them first if you want to keep your changes. Continue?
UninstalledAll=%1 was removed from this Convergence folder.

; Never installed: the Convergence 3.0.2 manifest (paths, sizes, a few md5s),
; extracted to the temp folder at start-up for the integrity check and the
; foreign-file scan (code\checks.iss). The files of the mod are written by
; the code (code\install.iss), never by [Files].
[Files]
Source: "{#ConvManifestSource}"; Flags: dontcopy

[Code]
#include "code\globals.iss"
#include CatalogInclude

{ The catalog's InitCatalog fills the contract arrays; this check stops a
  catalog of another format before anything else runs. }
procedure CheckCatalogFormat;
begin
  if CAT_FORMAT <> 2 then
    RaiseException('The installer''s catalog has an unknown format. Download the installer again.');
end;

#include "code\util.iss"
#include "code\convergence.iss"
#include "code\me3.iss"
#include "code\checks.iss"
#include "code\catalogrt.iss"
#include "code\archives.iss"
#include "code\fetch.iss"
#include "code\backup.iss"
#include "code\install.iss"
#include "code\pages.iss"
#include "code\events.iss"
