# Changelog

All notable changes to **ArchiveLens** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-11-26

### Added
- Fast Inventory / Dry-Run Mode (`-ListOnly`). Scans and inspects archives directly to console output without extracting file contents into the final report.
- Deep Classification Modifier (`-DeepScan`). When combined with `-ListOnly`, temporarily extracts the archive to run strict byte-level magic signature and encoding checks without dumping text contents into the final output.
- Parameter `-SaveReport` to complement `-ListOnly`, enabling disk file generation of the structural report without full content embedding.
- Internal optimization: ZIP entries are inspected purely via `[System.IO.Compression.ZipArchive]::OpenRead()` and 7-Zip processing utilizes `l -slt` strictly for pre-pass metadata checks.
    - *Note on Footprint:* For direct containers (`.zip`, `.rar`, `.7z`, `.tar`), a standard `-ListOnly` avoids the file system entirely. Compound streams (like `.tar.gz`) still require a temporary outer-layer extraction to safely inspect the inner `.tar` payload.
    - *Note on Classification:* Because standard dry-runs avoid disk extraction, files are marked as `Unverified` and classified using surface-level extension heuristics. Use `-ListOnly -DeepScan` to guarantee exact UTF encoding and disguised binary detection.

## [0.3.0] - 2026-10-22

### Added

- Built-in `Uninstall-ArchiveLens` cmdlet exported by the module, enabling full or version-targeted uninstallation
  directly from any PowerShell session without needing the original release `Install.ps1` script.
- Side-by-side semantic versioned installation layout (`Modules\ArchiveLens\<Version>\` without a `v` folder prefix).
- Installation version management switches in `Install.ps1`:
    - `-CleanInstall`: Installs the current version and removes all other version folders.
    - `-RemoveOlderVersions`: Installs the current version and removes only version folders strictly older than the
      current version.
- Granular uninstallation filters in both `Uninstall-ArchiveLens` and `Install.ps1 -Uninstall`:
    - `-TargetVersion <String>`: Removes only the matching version folder.
    - `-RemoveOlderThan <String>`: Removes version folders strictly less than the target version.
    - `-RemoveOlderThanOrEqualTo <String>`: Removes version folders less than or equal to the target version.
- Automatic version string sanitization (strips leading `v`/`V` prefixes and compares versions accurately via
  `[System.Version]`).
- Automatic cleanup of the shared CLI launcher (`%LOCALAPPDATA%\Programs\ArchiveLens\bin`) and User `PATH` entry when
  targeted uninstallation removes the last remaining version on the system, or automatic synchronization of the CLI
  launcher to the highest remaining version when other versions remain.

## [0.2.0] - 2026-10-22

### Added

- Support for seven additional archive and compressed stream formats via 7-Zip (`7z.exe`): `.7z`, `.tar`, `.gz`, `.tgz`, `.bz2`, `.xz`, and `.zst`.
- Automatic two-stage extraction and pre-inspection for compound TAR archives (`.tar.gz`, `.tgz`, `.tar.bz2`, `.tar.xz`, `.tar.zst`, as well as any `.gz`/`.bz2`/`.xz`/`.zst` stream whose inner payload carries a POSIX `ustar` header).
- Smart default output path resolution (`Get-ArchiveDefaultOutputPath`) that strips full compound `.tar.*` suffixes (e.g., `Project.tar.gz` -> `Project.txt`).
- Post-extraction disk size and entry count verification in `Invoke-SevenZipSinglePass` to guard against compressed stream formats that omit uncompressed length metadata in headers.
- Magic binary signatures in `Test-MagicBinarySignature` for 7-Zip (`7z`), XZ (`FD 37 7A 58 5A 00`), Zstandard (`28 B5 2F FD`), BZip2 (`BZh`), and POSIX TAR (`ustar`).

## [0.1.0] - 2026-10-20

### Added

- Initial public release of **ArchiveLens** (`Convert-ArchiveToText` / `ArchiveToText`).
- Safe `.zip` extraction using `System.IO.Compression.ZipFile` with pre-extraction Zip-Slip path traversal validation,
  entry count limits (`-MaxEntryCount`), and cumulative uncompressed byte caps (`-MaxTotalSizeMB`).
- `.rar` archive support via 7-Zip (`7z.exe`) with automatic discovery (`Find-SevenZipExecutable`) and pre-extraction
  `7z l -slt` header inspection.
- Multi-stage text and binary classification engine supporting UTF-8 (with and without BOM), UTF-16 LE/BE, UTF-32 LE/BE,
  magic byte header signatures, NUL-byte rejection, control-character plausibility checks, and configurable legacy
  fallback code pages (`-FallbackEncodingCodePage`).
- Deterministic 5-section self-contained report format (Summary, Full Inventory, Skipped/Excluded/Failed List, Readable
  Contents, and Final Status).
- Atomic staging file report generation and overwrite protection (`-Force`).
- Optional `-ExcludeSensitive` and `-ExcludePattern` filtering.
- Per-user installer (`Install.ps1`), Windows CMD wrapper (`ArchiveToText.cmd`), Pester v5 automated test suite
  (`Tests/ArchiveLens.Tests.ps1`), and GitHub Actions CI workflow (`.github/workflows/ci.yml`).