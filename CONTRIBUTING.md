# Contributing to ArchiveLens

Thank you for your interest in contributing to **ArchiveLens**!

## Development Prerequisites

- Windows 10 or Windows 11
- Windows PowerShell 5.1 and PowerShell 7.4+
- [Pester v5.5+](https://pester.dev/) for running automated tests
- [7-Zip](https://www.7-zip.org/) (`7z.exe` v21.07+ recommended; required for testing `.rar`, `.7z`, `.tar`, `.gz`, `.tgz`, `.bz2`, `.xz`, and `.zst` extraction)

## Testing Guidelines

1. Never write tests that depend on personal files outside `$env:TEMP`.
2. Ensure all tests pass in **both** Windows PowerShell 5.1 (`powershell.exe`) and PowerShell 7 (`pwsh.exe`):
   ```powershell
   Invoke-Pester -Path .\Tests\ArchiveLens.Tests.ps1 -Output Detailed
   ```
3. Maintain `.ps1` / `.psm1` files with `UTF-8 with BOM` encoding (as configured in `.editorconfig`) so Windows PowerShell 5.1 parses non-ASCII string literals accurately.

## Pull Request Checklist

- [ ] New features or archive behaviors include corresponding Pester v5 tests in `Tests/ArchiveLens.Tests.ps1`.
- [ ] `ArchiveLens.psd1` and `CHANGELOG.md` are updated when adding user-facing changes.
- [ ] Temporary directories created during extraction or testing are deterministically cleaned up in `finally` / `AfterEach` blocks.