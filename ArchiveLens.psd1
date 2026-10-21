@{
    RootModule = 'ArchiveLens.psm1'
    ModuleVersion = '0.1.0'
    GUID = '8f9c2d4a-6b1e-4f3a-9c5d-7e2a1b4c8d90'
    Author = 'ArchiveLens Contributors'
    CompanyName = 'Open Source'
    Copyright = '(c) 2026 ArchiveLens Contributors. Licensed under MIT.'
    Description = 'Extracts ZIP and RAR archives safely and consolidates readable text files, file inventory, and diagnostics into a single self-contained UTF-8 report for LLM and human inspection.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Convert-ArchiveToText',
        'Find-SevenZipExecutable'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @(
        'ArchiveToText'
    )

    PrivateData = @{
        PSData = @{
            Tags = @('Archive', 'ZIP', 'RAR', 'LLM', 'Text', 'Flatten', 'Repository', 'UTF8', 'Unicode')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://github.com/smabedi/ArchiveLens'
            ReleaseNotes = 'Initial 0.1.0 release of ArchiveLens with safe ZIP/RAR extraction, strict Unicode decoding, binary signature detection, and comprehensive self-contained reporting.'
        }
    }
}