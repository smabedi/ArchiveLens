#Requires -Version 5.1
<#
.SYNOPSIS
Installs or uninstalls ArchiveLens for the current Windows user with side-by-side semantic versioning support.

.DESCRIPTION
Copies the ArchiveLens module to the current user's PowerShell Modules directory under a version-specific
subdirectory (e.g., Documents\PowerShell\Modules\ArchiveLens\0.3.0 and Documents\WindowsPowerShell\Modules\ArchiveLens\0.3.0),
and installs the CMD launcher (ArchiveToText.cmd) into %LOCALAPPDATA%\Programs\ArchiveLens\bin.
Supports side-by-side installations, targeted version pruning, and automatic cleanup of the shared CLI launcher
and User PATH entry when all versions are uninstalled.

.PARAMETER AddToPath
Adds the CMD launcher directory (%LOCALAPPDATA%\Programs\ArchiveLens\bin) to the current user's PATH if not already present.

.PARAMETER CleanInstall
Installs the current version and deletes all other existing version folders.

.PARAMETER RemoveOlderVersions
Installs the current version and deletes only existing version folders strictly older than the current version.

.PARAMETER Uninstall
Switches the script into uninstallation mode. When used alone, deletes the entire ArchiveLens root folder (all versions)
and removes the shared CLI wrapper and User PATH entry.

.PARAMETER TargetVersion
When used with -Uninstall, deletes only the exact specified version folder (e.g., "0.2.0" or "v0.2.0").

.PARAMETER RemoveOlderThan
When used with -Uninstall, deletes existing version folders strictly older than the specified version.

.PARAMETER RemoveOlderThanOrEqualTo
When used with -Uninstall, deletes existing version folders older than or equal to the specified version.

.PARAMETER InstallRoot
Custom installation root for the CMD launcher. Defaults to $env:LOCALAPPDATA\Programs\ArchiveLens.

.PARAMETER ModuleRoots
Optional override for the PowerShell module root directories (e.g., "...\Documents\PowerShell\Modules\ArchiveLens").
Defaults to the current user's PowerShell 7 and Windows PowerShell 5.1 module directories.

.PARAMETER SkipEnvironmentPath
Skips reading or modifying the persistent HKCU User PATH environment variable (useful for isolated automated testing).

.EXAMPLE
.\Install.ps1 -AddToPath

.EXAMPLE
.\Install.ps1 -RemoveOlderVersions -AddToPath

.EXAMPLE
.\Install.ps1 -CleanInstall

.EXAMPLE
.\Install.ps1 -Uninstall -TargetVersion v0.1.0

.EXAMPLE
.\Install.ps1 -Uninstall -RemoveOlderThan 0.3.0

.EXAMPLE
.\Install.ps1 -Uninstall -RemoveOlderThanOrEqualTo v0.2.0

.EXAMPLE
.\Install.ps1 -Uninstall
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [switch]$AddToPath,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$CleanInstall,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$RemoveOlderVersions,

    [Parameter(ParameterSetName = 'Uninstall', Mandatory = $true)]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = 'Uninstall')]
    [string]$TargetVersion,

    [Parameter(ParameterSetName = 'Uninstall')]
    [string]$RemoveOlderThan,

    [Parameter(ParameterSetName = 'Uninstall')]
    [string]$RemoveOlderThanOrEqualTo,

    [Parameter()]
    [string]$InstallRoot = (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\ArchiveLens'),

    [Parameter()]
    [string[]]$ModuleRoots,

    [Parameter()]
    [switch]$SkipEnvironmentPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleName = 'ArchiveLens'
$requiredFiles = @(
    'ArchiveLens.psd1',
    'ArchiveLens.psm1',
    'ArchiveToText.ps1',
    'ArchiveToText.cmd',
    'README.md',
    'LICENSE.txt'
)

#region Helper Functions

function ConvertTo-CleanVersion
{
    <#
    .SYNOPSIS
    Strips any leading 'v' or 'V' and converts a version string into a [System.Version] object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$InputVersion,

        [Parameter()]
        [string]$ParameterName = 'Version'
    )

    if ( [string]::IsNullOrWhiteSpace($InputVersion))
    {
        throw [System.ArgumentException]::new("The version value supplied to -$ParameterName cannot be empty or whitespace.")
    }

    $sanitized = $InputVersion.Trim().Trim('"').Trim("'")
    $sanitized = $sanitized -replace '^[vV]+', ''

    [version]$parsedVersion = $null
    if (-not [version]::TryParse($sanitized, [ref]$parsedVersion))
    {
        throw [System.ArgumentException]::new(
                "Invalid semantic version '$InputVersion' supplied to -$ParameterName. Expected format like '0.3.0' or 'v0.3.0'."
        )
    }

    return $parsedVersion
}

function Get-CurrentPackageVersion
{
    <#
    .SYNOPSIS
    Reads ModuleVersion from ArchiveLens.psd1 in $PSScriptRoot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestDirectory
    )

    $manifestPath = Join-Path -Path $ManifestDirectory -ChildPath 'ArchiveLens.psd1'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf))
    {
        throw [System.IO.FileNotFoundException]::new("Module manifest not found at '$manifestPath'.", $manifestPath)
    }

    $manifestData = Import-PowerShellDataFile -Path $manifestPath -ErrorAction Stop
    if (-not $manifestData.ContainsKey('ModuleVersion') -or [string]::IsNullOrWhiteSpace($manifestData['ModuleVersion']))
    {
        throw [System.InvalidOperationException]::new("ModuleVersion is missing or empty in '$manifestPath'.")
    }

    return (ConvertTo-CleanVersion -InputVersion ([string]$manifestData['ModuleVersion']) -ParameterName 'ManifestModuleVersion')
}

function Get-NormalizedPathEntry
{
    param([string]$Entry)
    if ( [string]::IsNullOrWhiteSpace($Entry))
    {
        return ''
    }
    return $Entry.Trim().Trim('"').TrimEnd('\', '/')
}

function Get-InstalledVersionDirectories
{
    <#
    .SYNOPSIS
    Returns all valid semantic version subdirectories inside a given ArchiveLens module root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleRootPath
    )

    if (-not (Test-Path -LiteralPath $ModuleRootPath -PathType Container))
    {
        return @()
    }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $subDirs = @(Get-ChildItem -LiteralPath $ModuleRootPath -Directory -Force -ErrorAction SilentlyContinue)

    foreach ($dir in $subDirs)
    {
        $cleanName = $dir.Name -replace '^[vV]+', ''
        [version]$ver = $null
        if ( [version]::TryParse($cleanName, [ref]$ver))
        {
            $results.Add([PSCustomObject]@{
                FolderName = $dir.Name
                FullPath = $dir.FullName
                Version = $ver
            })
        }
    }

    return @($results | Sort-Object -Property Version)
}

function Remove-LegacyRootModuleFiles
{
    <#
    .SYNOPSIS
    Removes flat (pre-0.3.0) module files sitting directly in the ArchiveLens module root without touching version subdirectories.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleRootPath,

        [Parameter(Mandatory = $true)]
        [string[]]$FileNames
    )

    if (-not (Test-Path -LiteralPath $ModuleRootPath -PathType Container))
    {
        return
    }

    foreach ($fName in $FileNames)
    {
        $legacyFile = Join-Path -Path $ModuleRootPath -ChildPath $fName
        if (Test-Path -LiteralPath $legacyFile -PathType Leaf)
        {
            if ( $PSCmdlet.ShouldProcess($legacyFile, 'Remove legacy flat module file'))
            {
                Remove-Item -LiteralPath $legacyFile -Force
            }
        }
    }
}

function Invoke-VersionFolderPruning
{
    <#
    .SYNOPSIS
    Generic version pruning method used across both Install and Uninstall modes.
    Evaluates all installed version folders against a predicate and deletes matching folders.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$TargetModuleRoots,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ShouldRemovePredicate,

        [Parameter(Mandatory = $true)]
        [string]$ReasonDescription
    )

    $removedCount = 0

    foreach ($modRoot in $TargetModuleRoots)
    {
        if (-not (Test-Path -LiteralPath $modRoot -PathType Container))
        {
            continue
        }

        $installedVerDirs = @(Get-InstalledVersionDirectories -ModuleRootPath $modRoot)
        foreach ($item in $installedVerDirs)
        {
            [version]$installedVer = $item.Version
            $shouldDelete = & $ShouldRemovePredicate $installedVer

            if ($shouldDelete)
            {
                if ( $PSCmdlet.ShouldProcess($item.FullPath, "Remove version $( $item.FolderName ) ($ReasonDescription)"))
                {
                    Remove-Item -LiteralPath $item.FullPath -Recurse -Force
                    Write-Host "Removed version $( $item.FolderName ): $( $item.FullPath )" -ForegroundColor Green
                    $removedCount++
                }
            }
        }

        # If the module root directory is now completely empty, remove the empty root container
        if (Test-Path -LiteralPath $modRoot -PathType Container)
        {
            $remainingItems = @(Get-ChildItem -LiteralPath $modRoot -Force -ErrorAction SilentlyContinue)
            if ($remainingItems.Count -eq 0)
            {
                if ( $PSCmdlet.ShouldProcess($modRoot, 'Remove empty module root directory'))
                {
                    Remove-Item -LiteralPath $modRoot -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    return $removedCount
}

function Get-RemainingInstalledVersions
{
    <#
    .SYNOPSIS
    Returns all remaining installed version directory objects across all target module roots, sorted descending by Version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$TargetModuleRoots
    )

    $allRemaining = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($modRoot in $TargetModuleRoots)
    {
        $verDirs = @(Get-InstalledVersionDirectories -ModuleRootPath $modRoot)
        foreach ($vd in $verDirs)
        {
            $allRemaining.Add($vd)
        }
    }

    return @($allRemaining | Sort-Object -Property Version -Descending)
}

function Copy-PackageFilesToDirectory
{
    <#
    .SYNOPSIS
    Copies the required ArchiveLens runtime files from SourceDirectory to DestinationDirectory.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [string]$DestinationDirectory,

        [Parameter(Mandatory = $true)]
        [string[]]$FileNames,

        [Parameter(Mandatory = $true)]
        [string]$ActionLabel
    )

    if ( $PSCmdlet.ShouldProcess($DestinationDirectory, $ActionLabel))
    {
        if (Test-Path -LiteralPath $DestinationDirectory -PathType Container)
        {
            Remove-Item -LiteralPath "$DestinationDirectory\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        else
        {
            [void][System.IO.Directory]::CreateDirectory($DestinationDirectory)
        }

        foreach ($file in $FileNames)
        {
            $src = Join-Path -Path $SourceDirectory -ChildPath $file
            $dst = Join-Path -Path $DestinationDirectory -ChildPath $file
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
}

function Add-CliDirectoryToUserPath
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CliBinDirectory,

        [Parameter()]
        [switch]$SkipEnv
    )

    if ($SkipEnv)
    {
        return
    }

    $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ( [string]::IsNullOrWhiteSpace($currentUserPath))
    {
        $currentUserPath = ''
    }

    $normTarget = Get-NormalizedPathEntry -Entry $CliBinDirectory
    $existingEntries = @($currentUserPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $alreadyInPath = $false

    foreach ($entry in $existingEntries)
    {
        if ( [string]::Equals((Get-NormalizedPathEntry -Entry $entry), $normTarget, [System.StringComparison]::OrdinalIgnoreCase))
        {
            $alreadyInPath = $true
            break
        }
    }

    if ($alreadyInPath)
    {
        Write-Host "User PATH already contains '$CliBinDirectory' (no duplicate added)." -ForegroundColor Yellow
    }
    else
    {
        $updatedPath = if ( [string]::IsNullOrWhiteSpace($currentUserPath))
        {
            $CliBinDirectory
        }
        else
        {
            "$($currentUserPath.TrimEnd(';') );$CliBinDirectory"
        }

        if ( $PSCmdlet.ShouldProcess('HKCU\Environment\Path', "Add '$CliBinDirectory' to User PATH"))
        {
            [Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')
            if ($env:PATH -notlike "*$CliBinDirectory*")
            {
                $env:PATH = "$($env:PATH.TrimEnd(';') );$CliBinDirectory"
            }
            Write-Host "Added '$CliBinDirectory' to your User PATH." -ForegroundColor Green
            Write-Host "NOTE: Restart any already-open CMD or PowerShell windows for the updated PATH to take effect." -ForegroundColor Yellow
        }
    }
}

function Remove-SharedCliAndPath
{
    <#
    .SYNOPSIS
    Removes the shared CLI launcher directory ($InstallRoot) and cleans up the User PATH entry.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CliRootDirectory,

        [Parameter(Mandatory = $true)]
        [string]$CliBinDirectory,

        [Parameter()]
        [switch]$SkipEnv
    )

    if (Test-Path -LiteralPath $CliRootDirectory -PathType Container)
    {
        if ( $PSCmdlet.ShouldProcess($CliRootDirectory, 'Remove CLI launcher directory'))
        {
            Remove-Item -LiteralPath $CliRootDirectory -Recurse -Force
            Write-Host "Removed CLI directory: $CliRootDirectory" -ForegroundColor Green
        }
    }

    if (-not $SkipEnv)
    {
        $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not [string]::IsNullOrWhiteSpace($currentUserPath))
        {
            $normTarget = Get-NormalizedPathEntry -Entry $CliBinDirectory
            $entries = @(
            $currentUserPath -split ';' | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                        -not [string]::Equals((Get-NormalizedPathEntry -Entry $_), $normTarget, [System.StringComparison]::OrdinalIgnoreCase)
            }
            )
            $newPath = $entries -join ';'
            if ($newPath -ne $currentUserPath)
            {
                if ( $PSCmdlet.ShouldProcess('HKCU\Environment\Path', "Remove '$CliBinDirectory' from User PATH"))
                {
                    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
                    Write-Host "Removed '$CliBinDirectory' from User PATH." -ForegroundColor Green
                }
            }
        }
    }
}

function Sync-CliLauncherWithHighestRemainingVersion
{
    <#
    .SYNOPSIS
    Ensures the shared CLI launcher ($InstallRoot\bin) matches the highest remaining installed module version.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$HighestVersionDirectory,

        [Parameter(Mandatory = $true)]
        [string]$CliBinDirectory,

        [Parameter(Mandatory = $true)]
        [string[]]$FileNames
    )

    if (-not (Test-Path -LiteralPath $CliBinDirectory -PathType Container))
    {
        return
    }

    $cliManifest = Join-Path -Path $CliBinDirectory -ChildPath 'ArchiveLens.psd1'
    $needsSync = $true

    if (Test-Path -LiteralPath $cliManifest -PathType Leaf)
    {
        try
        {
            $cliData = Import-PowerShellDataFile -Path $cliManifest -ErrorAction Stop
            [version]$cliVer = ConvertTo-CleanVersion -InputVersion ([string]$cliData['ModuleVersion'])
            if ($cliVer -eq $HighestVersionDirectory.Version)
            {
                $needsSync = $false
            }
        }
        catch
        {
            $needsSync = $true
        }
    }

    if ($needsSync)
    {
        Copy-PackageFilesToDirectory `
            -SourceDirectory $HighestVersionDirectory.FullPath `
            -DestinationDirectory $CliBinDirectory `
            -FileNames $FileNames `
            -ActionLabel "Synchronize CLI launcher to highest remaining version ($( $HighestVersionDirectory.FolderName ))"
        Write-Host "Synchronized CLI launcher to highest remaining version ($( $HighestVersionDirectory.FolderName ))." -ForegroundColor Cyan
    }
}

#endregion

# Resolve target module roots
if ($null -ne $ModuleRoots -and $ModuleRoots.Count -gt 0)
{
    $moduleTargets = @($ModuleRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}
else
{
    $documentsDir = [Environment]::GetFolderPath('MyDocuments')
    $moduleTargets = @(
        (Join-Path -Path $documentsDir -ChildPath "PowerShell\Modules\$moduleName"),
        (Join-Path -Path $documentsDir -ChildPath "WindowsPowerShell\Modules\$moduleName")
    ) | Select-Object -Unique
}

$cliBinDir = Join-Path -Path $InstallRoot -ChildPath 'bin'

# ==============================================================================
# UNINSTALLATION MODE
# ==============================================================================
if ($Uninstall)
{
    $uninstallFilterCount = 0
    if ( $PSBoundParameters.ContainsKey('TargetVersion'))
    {
        $uninstallFilterCount++
    }
    if ( $PSBoundParameters.ContainsKey('RemoveOlderThan'))
    {
        $uninstallFilterCount++
    }
    if ( $PSBoundParameters.ContainsKey('RemoveOlderThanOrEqualTo'))
    {
        $uninstallFilterCount++
    }

    if ($uninstallFilterCount -gt 1)
    {
        throw [System.ArgumentException]::new(
                "Specify only one version filter with -Uninstall: -TargetVersion, -RemoveOlderThan, or -RemoveOlderThanOrEqualTo."
        )
    }

    # Case 1: Default Global Uninstall (no version filter parameters supplied)
    if ($uninstallFilterCount -eq 0)
    {
        Write-Host "Uninstalling all versions of ArchiveLens..." -ForegroundColor Cyan

        foreach ($modRoot in $moduleTargets)
        {
            if (Test-Path -LiteralPath $modRoot -PathType Container)
            {
                if ( $PSCmdlet.ShouldProcess($modRoot, 'Remove PowerShell module root directory (all versions)'))
                {
                    Remove-Item -LiteralPath $modRoot -Recurse -Force
                    Write-Host "Removed module directory: $modRoot" -ForegroundColor Green
                }
            }
        }

        Remove-SharedCliAndPath -CliRootDirectory $InstallRoot -CliBinDirectory $cliBinDir -SkipEnv:$SkipEnvironmentPath
        Write-Host "ArchiveLens uninstallation complete." -ForegroundColor Green
        return
    }

    # Cases 2, 3, 4: Targeted Version Uninstallation
    [scriptblock]$predicate = $null
    $reasonText = ''

    if ( $PSBoundParameters.ContainsKey('TargetVersion'))
    {
        [version]$targetVer = ConvertTo-CleanVersion -InputVersion $TargetVersion -ParameterName 'TargetVersion'
        $reasonText = "TargetVersion == $targetVer"
        $predicate = { param([version]$installedVer) $installedVer -eq $targetVer }.GetNewClosure()
        Write-Host "Uninstalling ArchiveLens version $targetVer..." -ForegroundColor Cyan
    }
    elseif ($PSBoundParameters.ContainsKey('RemoveOlderThan'))
    {
        [version]$targetVer = ConvertTo-CleanVersion -InputVersion $RemoveOlderThan -ParameterName 'RemoveOlderThan'
        $reasonText = "Version < $targetVer"
        $predicate = { param([version]$installedVer) $installedVer -lt $targetVer }.GetNewClosure()
        Write-Host "Uninstalling ArchiveLens versions older than $targetVer..." -ForegroundColor Cyan
    }
    elseif ($PSBoundParameters.ContainsKey('RemoveOlderThanOrEqualTo'))
    {
        [version]$targetVer = ConvertTo-CleanVersion -InputVersion $RemoveOlderThanOrEqualTo -ParameterName 'RemoveOlderThanOrEqualTo'
        $reasonText = "Version <= $targetVer"
        $predicate = { param([version]$installedVer) $installedVer -le $targetVer }.GetNewClosure()
        Write-Host "Uninstalling ArchiveLens versions older than or equal to $targetVer..." -ForegroundColor Cyan
    }

    # Also clean up any legacy flat files in the module root before checking remaining versions
    foreach ($modRoot in $moduleTargets)
    {
        Remove-LegacyRootModuleFiles -ModuleRootPath $modRoot -FileNames $requiredFiles
    }

    $removedCount = Invoke-VersionFolderPruning `
        -TargetModuleRoots $moduleTargets `
        -ShouldRemovePredicate $predicate `
        -ReasonDescription $reasonText

    if ($removedCount -eq 0)
    {
        Write-Host "No installed version folders matched filter ($reasonText)." -ForegroundColor Yellow
    }

    # Check if zero versions remain across all module roots
    $remainingVersions = @(Get-RemainingInstalledVersions -TargetModuleRoots $moduleTargets)
    if ($remainingVersions.Count -eq 0)
    {
        Write-Host "No ArchiveLens versions remain on the system. Cleaning up shared CLI launcher and PATH..." -ForegroundColor Cyan
        Remove-SharedCliAndPath -CliRootDirectory $InstallRoot -CliBinDirectory $cliBinDir -SkipEnv:$SkipEnvironmentPath
    }
    else
    {
        Sync-CliLauncherWithHighestRemainingVersion `
            -HighestVersionDirectory $remainingVersions[0] `
            -CliBinDirectory $cliBinDir `
            -FileNames $requiredFiles
    }

    Write-Host "ArchiveLens targeted uninstallation complete." -ForegroundColor Green
    return
}

# ==============================================================================
# INSTALLATION MODE
# ==============================================================================
if ($CleanInstall -and $RemoveOlderVersions)
{
    throw [System.ArgumentException]::new("Cannot specify both -CleanInstall and -RemoveOlderVersions at the same time.")
}

# Verify source files exist in $PSScriptRoot
foreach ($file in $requiredFiles)
{
    $srcFile = Join-Path -Path $PSScriptRoot -ChildPath $file
    if (-not (Test-Path -LiteralPath $srcFile -PathType Leaf))
    {
        throw [System.IO.FileNotFoundException]::new(
                "Installation aborted: Required source file '$srcFile' is missing.",
                $srcFile
        )
    }
}

[version]$currentVersion = Get-CurrentPackageVersion -ManifestDirectory $PSScriptRoot
$versionFolderName = $currentVersion.ToString()

Write-Host "Installing ArchiveLens $versionFolderName (per-user scope)..." -ForegroundColor Cyan

# 1. Install current version into its specific semantic version folder (<ModuleRoot>\<Version>\)
foreach ($modRoot in $moduleTargets)
{
    # Clean up any legacy flat files from 0.1.0/0.2.0 sitting directly in the module root
    Remove-LegacyRootModuleFiles -ModuleRootPath $modRoot -FileNames $requiredFiles

    $versionDir = Join-Path -Path $modRoot -ChildPath $versionFolderName
    Copy-PackageFilesToDirectory `
        -SourceDirectory $PSScriptRoot `
        -DestinationDirectory $versionDir `
        -FileNames $requiredFiles `
        -ActionLabel "Install ArchiveLens $versionFolderName PowerShell Module"

    if (-not $WhatIfPreference)
    {
        Write-Host "Installed PowerShell module ($versionFolderName) to: $versionDir" -ForegroundColor Green
    }
}

# 2. Apply optional post-install pruning rules (-CleanInstall or -RemoveOlderVersions)
if ($CleanInstall)
{
    Write-Host "Applying -CleanInstall: Removing all other version folders..." -ForegroundColor Cyan
    $cleanPredicate = { param([version]$installedVer) $installedVer -ne $currentVersion }.GetNewClosure()
    [void](Invoke-VersionFolderPruning `
        -TargetModuleRoots $moduleTargets `
        -ShouldRemovePredicate $cleanPredicate `
        -ReasonDescription "CleanInstall: Version != $currentVersion")
}
elseif ($RemoveOlderVersions)
{
    Write-Host "Applying -RemoveOlderVersions: Removing version folders older than $currentVersion..." -ForegroundColor Cyan
    $olderPredicate = { param([version]$installedVer) $installedVer -lt $currentVersion }.GetNewClosure()
    [void](Invoke-VersionFolderPruning `
        -TargetModuleRoots $moduleTargets `
        -ShouldRemovePredicate $olderPredicate `
        -ReasonDescription "RemoveOlderVersions: Version < $currentVersion")
}

# 3. Install CMD launcher and runtime files to %LOCALAPPDATA%\Programs\ArchiveLens\bin
Copy-PackageFilesToDirectory `
    -SourceDirectory $PSScriptRoot `
    -DestinationDirectory $cliBinDir `
    -FileNames $requiredFiles `
    -ActionLabel 'Install CMD launcher and scripts'

if (-not $WhatIfPreference)
{
    Write-Host "Installed CMD launcher to: $cliBinDir" -ForegroundColor Green
}

# 4. Optionally add $cliBinDir to User PATH without duplication
if ($AddToPath)
{
    Add-CliDirectoryToUserPath -CliBinDirectory $cliBinDir -SkipEnv:$SkipEnvironmentPath
}
else
{
    Write-Host "Tip: Run '.\Install.ps1 -AddToPath' if you want 'ArchiveToText' available directly in Windows CMD from any folder." -ForegroundColor DarkGray
}

Write-Host "`nInstallation finished! You can now run:" -ForegroundColor Green
Write-Host "  PowerShell : Convert-ArchiveToText `"C:\path\to\archive.zip`""
Write-Host "  CMD        : ArchiveToText `"C:\path\to\archive.zip`""
Write-Host "  Uninstall  : Uninstall-ArchiveLens"