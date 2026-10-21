# ArchiveLens

**ArchiveLens** (`Convert-ArchiveToText` / `ArchiveToText`) is a security-conscious Windows command-line utility and
PowerShell module that inspects `.zip` and `.rar` archives and consolidates their file inventory, diagnostics, and
readable text contents into a single, deterministic UTF-8 `.txt` report.

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
- **ZIP & RAR Support:** Native `.NET` streaming inspection for `.zip` archives and automated **7-Zip (`7z.exe`)**
  integration for `.rar` archives.
- **Unicode & Multilingual Accuracy:** Strict BOM and byte-stream validation supporting UTF-8 (with/without BOM), UTF-16
  LE/BE, UTF-32 LE/BE, and configurable legacy fallback code pages—preserving Persian (فارسی), Arabic (العربية),
  Chinese, Cyrillic, and source code symbols without silent replacement corruption.
- **Multi-Layered Binary Detection:** Combines known binary extension filtering, magic header byte signatures (`MZ`,
  `ELF`, `PNG`, `PDF`, `SQLite`, `PK`, `Rar!`), NUL-byte scanning, and post-decode control-character plausibility
  checks.
- **Hardened Extraction Security:** Blocks Zip-Slip path traversal (`..\`), symbolic link/reparse escapes, and resource
  exhaustion (configurable entry count, per-file size, and cumulative uncompressed size caps).
- **Atomic Output Protection:** Never overwrites existing reports unless `-Force` is supplied, and writes to a staging
  file first so fatal extraction errors never leave behind a corrupt or misleading report.

---

## Supported Platforms & Dependencies

- **Operating System:** Windows 10 / Windows 11 / Windows Server 2016+
- **Shells:** Windows PowerShell 5.1, PowerShell 7+, and Windows Command Prompt (`cmd.exe`)
- **Dependencies:**
    - `.zip` archives: Zero external dependencies (uses built-in `.NET` `System.IO.Compression`).
    - `.rar` archives: Requires **[7-Zip](https://www.7-zip.org/)** (`7z.exe`) installed in a standard directory
      (`C:\Program Files\7-Zip`), registered in the Windows Registry, on your `PATH`, or supplied via `-SevenZipPath`.

---

## Installation

ArchiveLens installs per-user and **does not require Administrator privileges**.

1. Clone or download this repository and open **PowerShell** in the project folder:
   ```powershell
   .\Install.ps1 -AddToPath