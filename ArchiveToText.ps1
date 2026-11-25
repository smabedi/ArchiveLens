<#
.SYNOPSIS
Command-line script wrapper for ArchiveLens (Convert-ArchiveToText).
Used by the CMD launcher (ArchiveToText.cmd) and direct script execution.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [AllowEmptyString()]
    [string]$ArchivePath,

    [Parameter(Position = 1)]
    [AllowEmptyString()]
    [string]$OutputPath,

    [Parameter()]
    [string]$SevenZipPath,

    [Parameter()]
    [switch]$IncludeGit,

    [Parameter()]
    [switch]$ExcludeSensitive,

    [Parameter()]
    [string[]]$ExcludePattern = @(),

    [Parameter()]
    [int]$MaxFileSizeMB,

    [Parameter()]
    [int]$MaxTotalSizeMB,

    [Parameter()]
    [int]$MaxEntryCount,

    [Parameter()]
    [int]$FallbackEncodingCodePage,

    [Parameter()]
    [switch]$NoInteractive,

    [Parameter()]
    [switch]$ListOnly,

    [Parameter()]
    [switch]$DeepScan,

    [Parameter()]
    [switch]$SaveReport,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'ArchiveLens.psd1'
if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf))
{
    [Console]::Error.WriteLine("ERROR: ArchiveLens.psd1 not found next to ArchiveToText.ps1 at '$PSScriptRoot'.")
    exit 1
}

try
{
    Import-Module -Name $moduleManifest -Force -ErrorAction Stop

    $invokeParams = @{
        PassThru = $true
    }`

    if ( $PSBoundParameters.ContainsKey('MaxFileSizeMB')) { $invokeParams['MaxFileSizeMB'] = $MaxFileSizeMB }
    if ( $PSBoundParameters.ContainsKey('MaxTotalSizeMB')) { $invokeParams['MaxTotalSizeMB'] = $MaxTotalSizeMB }
    if ( $PSBoundParameters.ContainsKey('MaxEntryCount')) { $invokeParams['MaxEntryCount'] = $MaxEntryCount }
    if ( $PSBoundParameters.ContainsKey('FallbackEncodingCodePage')) { $invokeParams['FallbackEncodingCodePage'] = $FallbackEncodingCodePage }

    if ( $PSBoundParameters.ContainsKey('ArchivePath'))
    {
        $invokeParams['ArchivePath'] = $ArchivePath
    }
    if ( $PSBoundParameters.ContainsKey('OutputPath'))
    {
        $invokeParams['OutputPath'] = $OutputPath
    }
    if ( $PSBoundParameters.ContainsKey('SevenZipPath'))
    {
        $invokeParams['SevenZipPath'] = $SevenZipPath
    }
    if ( $PSBoundParameters.ContainsKey('ExcludePattern'))
    {
        $invokeParams['ExcludePattern'] = $ExcludePattern
    }
    if ($IncludeGit.IsPresent)
    {
        $invokeParams['IncludeGit'] = $true
    }
    if ($ExcludeSensitive.IsPresent)
    {
        $invokeParams['ExcludeSensitive'] = $true
    }
    if ($NoInteractive.IsPresent)
    {
        $invokeParams['NoInteractive'] = $true
    }
    if ($Force.IsPresent)
    {
        $invokeParams['Force'] = $true
    }
    if ($ListOnly.IsPresent)
    {
        $invokeParams['ListOnly'] = $true
    }
    if ($DeepScan.IsPresent)
    {
        $invokeParams['DeepScan'] = $true
    }
    if ($SaveReport.IsPresent)
    {
        $invokeParams['SaveReport'] = $true
    }
    if ( $PSBoundParameters.ContainsKey('Verbose'))
    {
        $invokeParams['Verbose'] = $PSBoundParameters['Verbose']
    }
    if ( $PSBoundParameters.ContainsKey('WhatIf'))
    {
        $invokeParams['WhatIf'] = $PSBoundParameters['WhatIf']
    }
    if ( $PSBoundParameters.ContainsKey('Confirm'))
    {
        $invokeParams['Confirm'] = $PSBoundParameters['Confirm']
    }

    $summary = Convert-ArchiveToText @invokeParams

    if ($null -ne $summary)
    {
        Write-Host ("ArchiveLens v{0}: {1}" -f $summary.Version, $summary.Status)
        Write-Host ("Output Report : {0}" -f $summary.OutputPath)
        Write-Host ("Summary Counts: Discovered={0} | Included={1} | Skipped={2} | Excluded={3} | Failed={4}" -f `
            $summary.DiscoveredCount, $summary.IncludedCount, $summary.SkippedCount, $summary.ExcludedCount, $summary.FailedCount)
        exit $summary.ExitCode
    }

    # If -WhatIf was used, $summary is null and operation succeeded
    exit 0
}
catch
{
    [Console]::Error.WriteLine("ArchiveLens Fatal Error: $( $_.Exception.Message )")
    exit 1
}