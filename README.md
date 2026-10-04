# Convergence X Clever X McKenyu - Auto Installer

**Convergence X Clever X McKenyu** is an Elden Ring merge by Canalpa (Luka): The Convergence together with Clever's Moveset
Modpack and McKenyu's Modpack, plus optional add-ons. Merge page: https://www.nexusmods.com/eldenring/mods/10388

From v6.5 on, players install the merge with the **Auto Installer**, one small .exe from the merge's Nexus
page. This repository holds:

- `installer/` - the installer's source: the Inno Setup 6 script (`CXCXM_v65_Installer.iss`, `code/*.iss`) and the Python release
  pipeline (`release.py`, `pipeline/`) that builds the files, the catalog and the exe from a release candidate.
- `releases/<tag>/catalog.json` - what each release installs: every file, its SHA-256 and where it comes from.
- **Releases** - the files the installer downloads: the merge's own files and the merged versions of files that
  several mods change. They are not a mod on their own (see below).

## How players use it

1. Install The Convergence 3.0.2 from its own site (convergencemod.com).
2. On the merge's Nexus page (Files tab), download the Main Files zip and the Auto Installer.
3. Download the other mods from their own pages:
   - required: Clever's Moveset Modpack 26.2: https://www.nexusmods.com/eldenring/mods/1928?tab=files
   - required: McKenyu's Modpack 1.4: https://www.nexusmods.com/eldenring/mods/8762?tab=files
   - only if you tick it in the installer: Nightreign Movement 1.2 (Wylder, Convergence 3.0.2 edition): https://www.nexusmods.com/eldenring/mods/11174?tab=files
   - only if you tick it in the installer: Seamless Co-op: https://www.nexusmods.com/eldenring/mods/510?tab=files
   - only if you tick it in the installer: Deflect Me Not - ConXCleverXMcKenyu EXP37.1: https://www.nexusmods.com/eldenring/mods/4138?tab=files
4. Run the Auto Installer and tick the options you want. It finds your Convergence folder and your downloads
   (in Downloads, or you pick them), checks every file by SHA-256, downloads the merge's own files from this
   repository's release (checked by SHA-256 too), installs your picks and checks the result. It keeps a backup
   of everything it replaces.
5. Start the game the usual way for The Convergence.

Run the installer again to change your picks. Uninstall it from Windows' Apps list: the Convergence folder goes
back to how it was before.

## Every mod comes from its own page

The installer never re-hosts another author's mod. For every mod made by someone else, the player downloads
the author's own file from the author's own page, and the installer checks that file before it uses it. The
files in this repository's releases only complete an install that is built from those downloads; on their own
they do nothing. The options made by Canalpa (Lucy, Infinite Durations, Infinite Arrows and Bolts) download from this repository's release.
ERCapacityExpansion downloads from its author's own GitHub release first; this repository keeps a fallback copy.

## Credits

- The Convergence by AronTheBaron and The Convergence Team - convergencemod.com
- The original Convergence X Clever's Moveset merge by windshadowruins; the balancing and +15 upgrade paths that carried this merge up to v6.2 by Kinder
- me3 mod loader by the me3 authors (shipped with The Convergence)
- Scripts-Data-Exposer-FS by ElaDiDu (shipped with The Convergence)
- Unpacking of .rar and .zip downloads: 7-Zip's 7z.dll by Igor Pavlov (GNU LGPL, unRAR licence restriction; 7-zip.org), built into the installer by Inno Setup
- Convergence X Clever X McKenyu by Canalpa (Luka) - nexusmods.com/eldenring/mods/10388
- The Convergence by The Convergence Team - convergencemod.com
- Clever's Moveset Modpack by clevererraptor6 - nexusmods.com/eldenring/mods/1928
- McKenyu's Modpack by McKenyu - nexusmods.com/eldenring/mods/8762
- Lucy Character and Chevaleresse Armor by Canalpa (Luka) - nexusmods.com/eldenring/mods/11128
- Lucy's armor: Chevaleresse II by yurica, from the Skyrim SE ports by THBG0 (SMP SE) and by yurica, THBossGamer, Jeir and docteure (CBBE BodySlide)
- Lucy's hair: KS Hairdos by Kalilies and Stealthic, via the HDT SMP version by ousnius
- Lucy's body mesh: based on CBBE by Caliente and ousnius
- Nightreign Movement 1.2 (Wylder, Convergence 3.0.2 edition) by neiroxgod - nexusmods.com/eldenring/mods/11174
- Infinite Durations by Canalpa (Luka)
- Infinite Arrows and Bolts v1.2 (Canalpa rebuild for Patch 1.17) - nexusmods.com/eldenring/mods/10389
- Infinite Arrows and Bolts is built on fromsoftware-rs by vswarte (MIT or Apache-2.0); the idea comes from the original Infinite arrows and bolts by its author (nexusmods.com/eldenring/mods/9032)
- Seamless Co-op by Yui (LukeYui) - nexusmods.com/eldenring/mods/510
- ERCapacityExpansion v0.3.0-experimental.3 by KamiyamaShiki0704 (MIT License, Copyright (c) 2026 KamiyamaShiki0704) - github.com/KamiyamaShiki0704/ERCapacityExpansion
- Deflect Me Not by Rei Jr. - nexusmods.com/eldenring/mods/4138 (experimental here; DMN bugs go to Rei Jr., everything else to Canalpa)

Per-option credits: [CREDITS.md](CREDITS.md). Who owns what, and the licence texts of the parts that have one
(ERCapacityExpansion, fromsoftware-rs): [LICENSE-NOTES.md](LICENSE-NOTES.md), [LICENSES/](LICENSES/).

## Release v6.5.0

- Release candidate: `rc8`
- Catalog sha256: `be29ddf07264173b3e34fa9a3f292cb922ca6842355203a79ffad0b724bea6e9` ([catalog.json](releases/v6.5.0/catalog.json))
- 110 release assets, 1003.8 MB, listed in [releases/v6.5.0/ASSETS.md](releases/v6.5.0/ASSETS.md). Each asset is named
  `<first 16 hex of its sha256>-<file name>`; the installer downloads it from
  `https://github.com/LukaTheHero/Convergence-X-Clever-X-McKenyu/releases/download/v6.5.0/<asset>` and checks its SHA-256 before anything in the game folder changes.

## Building (maintainer)

`installer/release.py --rc <rc> --all` turns a release candidate into the main zip, the hosted files, the
catalog, the installer exe, the test gate and this repository's draft release in one command
(`installer/pipeline/oneshot.py` lists the steps). The pipeline reads its
inputs (the release candidate builds and the authors' original downloads, used as references) from the
maintainer's PC, so it does not run anywhere else. The contract between the pipeline and the Inno code:
[installer/README_CONTRACT.md](installer/README_CONTRACT.md).
