# Changelog

All notable changes to **ArchiveLens** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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