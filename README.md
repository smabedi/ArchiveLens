# ArchiveLens

**ArchiveLens** (`Convert-ArchiveToText` / `ArchiveToText`) is a security-conscious Windows command-line utility and
PowerShell module that inspects `.zip`, `.rar`, `.7z`, `.tar`, `.gz`, `.tgz`, `.bz2`, `.xz`, and `.zst` archives (including
compound `.tar.gz`, `.tar.bz2`, `.tar.xz`, and `.tar.zst` bundles) and consolidates their file inventory, diagnostics,
and readable text contents into a single, deterministic UTF-8 `.txt` report.

## Purpose & Use Cases

Modern Large Language Models (LLMs) and code analysis workflows frequently need to inspect an entire software
repository, configuration bundle, or documentation archive at once. Uploading raw archives is often unsupported or
opaque.

ArchiveLens solves this by producing a **self-contained inspection report** that allows both humans and LLMs to
immediately see:

- Which archive was processed, when, and whether any errors occurred.
- A complete, deterministically sorted inventory of every file inside the archive.
- Explicit reasons for every skipped binary file, excluded path (`.git`, sensitive files), or failed decode.
- The exact relative path and text contents of every readable file.

---

## Key Features

- **Cross-Shell Usability:** Use `Convert-ArchiveToText` (or alias `ArchiveToText`) in **PowerShell 7** and **Windows
  PowerShell 5.1**, or `ArchiveToText` directly in **Windows CMD**.
- **Comprehensive Archive & Stream Support:**
    - `.zip`: Native `.NET` streaming inspection (`System.IO.Compression`).
    - `.rar`, `.7z`, `.tar`: Automated **7-Zip (`7z.exe`)** container inspection and extraction.
    - `.gz`, `.tgz`, `.bz2`, `.xz`, `.zst`: Automated single-stream decompression **and** automatic two-stage TAR extraction
      for `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.zst`, and `.tgz` archives.
- **Unicode & Multilingual Accuracy:** Strict BOM and byte-stream validation supporting UTF-8 (with/without BOM), UTF-16
  LE/BE, UTF-32 LE/BE, and configurable legacy fallback code pages—preserving Persian (فارسی), Arabic (العربية),
  Chinese, Cyrillic, and source code symbols without silent replacement corruption.
- **Multi-Layered Binary Detection:** Combines known binary extension filtering, magic header byte signatures (`MZ`,
  `ELF`, `PNG`, `PDF`, `SQLite`, `PK`, `Rar!`, `7z`, `XZ`, `ZST`, `BZh`, `GZIP`, `ustar`), NUL-byte scanning, and
  post-decode control-character plausibility checks.
- **Hardened Extraction Security:** Blocks Zip-Slip path traversal (`..\`), symbolic link/reparse escapes, and resource
  exhaustion (configurable entry count, per-file size, and cumulative uncompressed size caps verified both pre- and
  post-extraction).
- **Atomic Output Protection:** Never overwrites existing reports unless `-Force` is supplied, and writes to a staging
  file first so fatal extraction errors never leave behind a corrupt or misleading report.

---

## Supported Platforms & Dependencies

- **Operating System:** Windows 10 / Windows 11 / Windows Server 2016+
- **Shells:** Windows PowerShell 5.1, PowerShell 7+, and Windows Command Prompt (`cmd.exe`)
- **Dependencies:**
    - `.zip` archives: Zero external dependencies (uses built-in `.NET` `System.IO.Compression`).
    - `.rar`, `.7z`, `.tar`, `.gz`, `.tgz`, `.bz2`, `.xz`, `.zst` archives: Requires **[7-Zip](https://www.7-zip.org/)**
      (`7z.exe`, v21.07+ recommended for `.zst` support) installed in a standard directory (`C:\Program Files\7-Zip`),
      registered in the Windows Registry, on your `PATH`, or supplied via `-SevenZipPath`.

---

## Installation

ArchiveLens installs per-user and **does not require Administrator privileges**.

Clone or download this repository and open **PowerShell** in the project folder:

```powershell
.\Install.ps1 -AddToPath
```

This script:
1. Copies the `ArchiveLens` module to your user PowerShell module directories for both **PowerShell 7** (`Documents\PowerShell\Modules\ArchiveLens`) and **Windows PowerShell 5.1** (`Documents\WindowsPowerShell\Modules\ArchiveLens`).
2. Installs the command-line wrapper (`ArchiveToText.cmd` and runtime scripts) to `%LOCALAPPDATA%\Programs\ArchiveLens\bin`.
3. Adds `%LOCALAPPDATA%\Programs\ArchiveLens\bin` to your user `PATH` (when `-AddToPath` is specified).

To uninstall at any time:

```powershell
.\Install.ps1 -Uninstall
```

---

## Usage Examples

### PowerShell (5.1 & 7+)

```powershell
# Basic usage (outputs C:\Projects\MyRepo.txt)
Convert-ArchiveToText "C:\Projects\MyRepo.zip"

# Extract a compound .tar.gz archive (outputs C:\Releases\Source.txt)
Convert-ArchiveToText "C:\Releases\Source.tar.gz"

# Specify a custom output path, filter sensitive files (.env, keys), and overwrite existing report
Convert-ArchiveToText "C:\Backups\App.7z" -OutputPath "C:\Reports\AppReport.txt" -ExcludeSensitive -Force

# Exclude specific glob patterns and return a summary object for scripting
$result = Convert-ArchiveToText "C:\Projects\Web.tar.zst" -ExcludePattern '*.min.js', 'dist/*' -PassThru
```

### Windows Command Prompt (`cmd.exe`)

```cmd
ArchiveToText "C:\Projects\MyRepo.zip"
ArchiveToText "C:\Releases\Source.tar.xz" "C:\Reports\SourceReport.txt" -ExcludeSensitive -Force
```

---

## Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `-ArchivePath` | `string` | *(Prompted)* | Path to input archive (`.zip`, `.rar`, `.7z`, `.tar`, `.gz`, `.tgz`, `.bz2`, `.xz`, `.zst`). |
| `-OutputPath` | `string` | `<BaseName>.txt` | Destination path for the UTF-8 report (strips `.tar.*` suffixes automatically). |
| `-SevenZipPath` | `string` | Auto-detected | Explicit path to `7z.exe` for non-ZIP formats. |
| `-IncludeGit` | `switch` | `$false` | Includes files inside `.git/` directories (excluded by default). |
| `-ExcludeSensitive` | `switch` | `$false` | Excludes common credential files (`.env*`, `*.pem`, `*.key`, `id_rsa*`, `*.pfx`, `*.kdbx`, etc.). |
| `-ExcludePattern` | `string[]` | `@()` | Wildcard patterns (e.g., `'*.min.js'`, `'node_modules/*'`) to exclude. |
| `-MaxFileSizeMB` | `int` | `10` | Maximum size (MB) for an individual file to be decoded as text (`1`–`500`). |
| `-MaxTotalSizeMB` | `int` | `250` | Maximum cumulative uncompressed archive size (MB) allowed (`1`–`10000`). |
| `-MaxEntryCount` | `int` | `10000` | Maximum archive entries allowed before aborting extraction (`1`–`500000`). |
| `-FallbackEncodingCodePage` | `int` | `1252` | Fallback code page when strict UTF-8 fails (e.g., `1256` for Persian/Arabic; `0` to disable). |
| `-NoInteractive` | `switch` | `$false` | Disables interactive `Read-Host` prompts when `-ArchivePath` is omitted. |
| `-PassThru` | `switch` | `$false` | Emits a `PSCustomObject` with run counts, timestamps, status, and exit code. |
| `-Force` | `switch` | `$false` | Overwrites `-OutputPath` if the file already exists. |

---

## Report Structure & Exit Codes

Every generated report is encoded in **UTF-8 (no BOM)** with normalized LF (`\n`) line endings and contains five sections:
1. **Section A — Report Header and Summary:** Archive metadata, UTC timestamps, file counts, total bytes scanned, and overall status.
2. **Section B — Complete File Inventory:** Deterministically sorted table of every file (`[Text]`, `[Skipped]`, `[Excluded]`, or `[Failed]`), byte size, detected encoding, and classification reason.
3. **Section C — Skipped, Excluded, and Failed Files:** Focused diagnostic list of all non-included files.
4. **Section D — Readable File Contents:** Verbatim text contents enclosed between `BEGIN FILE: <path>` and `END FILE: <path>` delimiters.
5. **Section E — Final Status:** Verification footer and summary counts.

### Exit Codes

| Exit Code | Meaning |
| :--- | :--- |
| `0` | **Success:** Archive extracted and all candidate text files decoded cleanly. |
| `1` | **Fatal Error:** Missing archive, unsupported format, safety limit exceeded, Zip-Slip attempt, or I/O error. |
| `2` | **Partial Success:** Report generated, but one or more files failed text decoding (`FailedCount > 0`). |

---

## License

Licensed under the [MIT License](LICENSE.txt).