@{
    RootModule = 'ArchiveLens.psm1'
    ModuleVersion = '0.3.0'
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
            ReleaseNotes = 'Release 0.3.0 introduces the built-in Uninstall-ArchiveLens cmdlet, side-by-side semantic versioned module installation (Modules\ArchiveLens\<Version>\), version-aware installation and uninstallation pruning flags (-CleanInstall, -RemoveOlderVersions, -TargetVersion, -RemoveOlderThan, -RemoveOlderThanOrEqualTo), and automatic CLI/PATH cleanup when zero versions remain.'
        }
    }
}