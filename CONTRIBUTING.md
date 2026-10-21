# Contributing to ArchiveLens

Thank you for your interest in contributing to **ArchiveLens**!

## Development Prerequisites

- Windows 10 or Windows 11
- Windows PowerShell 5.1 and PowerShell 7.4+
- [Pester v5.5+](https://pester.dev/) for running automated tests
- [7-Zip](https://www.7-zip.org/) (optional, required for testing `.rar` extraction)

## Testing Guidelines

1. Never write tests that depend on personal files outside `$env:TEMP`.
2. Ensure all tests pass in **both** Windows PowerShell 5.1 (`powershell.exe`) and PowerShell 7 (`pwsh.exe`):
   ```powershell
   Invoke-Pester -Path .\Tests\ArchiveLens.Tests.ps1 -Output Detailed