@{
    RootModule = 'ArchiveLens.psm1'
    ModuleVersion = '0.4.0'
    GUID = '8f9c2d4a-6b1e-4f3a-9c5d-7e2a1b4c8d90'
    Author = 'ArchiveLens Contributors'
    CompanyName = 'Open Source'
    Copyright = '(c) 2026 ArchiveLens Contributors. Licensed under MIT.'
    Description = 'Extracts ZIP, RAR, 7Z, TAR, GZ, TGZ, BZ2, XZ, and ZST archives safely and consolidates readable text files, file inventory, and diagnostics into a single self-contained UTF-8 report for LLM and human inspection.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Convert-ArchiveToText',
        'Find-SevenZipExecutable',
        'Uninstall-ArchiveLens'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @(
        'ArchiveToText'
    )

    PrivateData = @{
        PSData = @{
            Tags = @('Archive', 'ZIP', 'RAR', '7Z', 'TAR', 'GZ', 'TGZ', 'BZ2', 'XZ', 'ZST', 'Zstandard', 'LLM', 'Text', 'Flatten', 'Repository', 'UTF8', 'Unicode')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://github.com/smabedi/ArchiveLens'
            ReleaseNotes = 'Release 0.4.0 introduces the -ListOnly dry-run mode for memory-efficient archive scanning, the -DeepScan modifier for temporary extraction and strict byte-level binary/encoding classification, and the -SaveReport switch for disk generation without embedding contents.'        }
    }
}