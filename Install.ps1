<#
.SYNOPSIS
Installs or uninstalls ArchiveLens for the current Windows user without requiring administrator privileges.

.DESCRIPTION
Copies the ArchiveLens module to the current user's PowerShell Modules directory for both
Windows PowerShell 5.1 (Documents\WindowsPowerShell\Modules) and PowerShell 7 (Documents\PowerShell\Modules),
and installs the CMD launcher (ArchiveToText.cmd) into %LOCALAPPDATA%\Programs\ArchiveLens\bin.
Optionally adds the launcher directory to the user's PATH environment variable.

.PARAMETER AddToPath
Adds the CMD launcher directory (%LOCALAPPDATA%\Programs\ArchiveLens\bin) to the current user's PATH if not already present.

.PARAMETER Uninstall
Removes the installed ArchiveLens module directories, CMD launcher directory, and user PATH entry.

.PARAMETER InstallRoot
Custom installation root for the CMD launcher. Defaults to $env:LOCALAPPDATA\Programs\ArchiveLens.

.EXAMPLE
.\Install.ps1 -AddToPath

.EXAMPLE
.\Install.ps1 -Uninstall
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [switch]$AddToPath,

    [Parameter()]
    [switch]$Uninstall,

    [Parameter()]
    [string]$InstallRoot = (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\ArchiveLens')
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

# Determine user module roots for both Windows PowerShell 5.1 and PowerShell 7+
$documentsDir = [Environment]::GetFolderPath('MyDocuments')
$moduleTargets = @(
    (Join-Path -Path $documentsDir -ChildPath "PowerShell\Modules\$moduleName"),
    (Join-Path -Path $documentsDir -ChildPath "WindowsPowerShell\Modules\$moduleName")
) | Select-Object -Unique

$cliBinDir = Join-Path -Path $InstallRoot -ChildPath 'bin'

function Get-NormalizedPathEntry
{
    param([string]$Entry)
    if ( [string]::IsNullOrWhiteSpace($Entry))
    {
        return ''
    }
    return $Entry.Trim().Trim('"').TrimEnd('\', '/')
}

if ($Uninstall)
{
    Write-Host "Uninstalling ArchiveLens..." -ForegroundColor Cyan

    foreach ($modDir in $moduleTargets)
    {
        if (Test-Path -LiteralPath $modDir -PathType Container)
        {
            if ( $PSCmdlet.ShouldProcess($modDir, 'Remove PowerShell module directory'))
            {
                Remove-Item -LiteralPath $modDir -Recurse -Force
                Write-Host "Removed module directory: $modDir" -ForegroundColor Green
            }
        }
    }

    if (Test-Path -LiteralPath $InstallRoot -PathType Container)
    {
        if ( $PSCmdlet.ShouldProcess($InstallRoot, 'Remove CLI launcher directory'))
        {
            Remove-Item -LiteralPath $InstallRoot -Recurse -Force
            Write-Host "Removed CLI directory: $InstallRoot" -ForegroundColor Green
        }
    }

    # Remove from User PATH if present
    $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not [string]::IsNullOrWhiteSpace($currentUserPath))
    {
        $normTarget = Get-NormalizedPathEntry -Entry $cliBinDir
        $entries = $currentUserPath -split ';' | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
                    -not [string]::Equals((Get-NormalizedPathEntry -Entry $_), $normTarget, [System.StringComparison]::OrdinalIgnoreCase)
        }
        $newPath = $entries -join ';'
        if ($newPath -ne $currentUserPath)
        {
            if ( $PSCmdlet.ShouldProcess('HKCU\Environment\Path', "Remove '$cliBinDir' from User PATH"))
            {
                [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
                Write-Host "Removed '$cliBinDir' from User PATH." -ForegroundColor Green
            }
        }
    }

    Write-Host "ArchiveLens uninstallation complete." -ForegroundColor Green
    return
}

# Verify source files exist in $PSScriptRoot
foreach ($file in $requiredFiles)
{
    $srcFile = Join-Path -Path $PSScriptRoot -ChildPath $file
    if (-not (Test-Path -LiteralPath $srcFile -PathType Leaf))
    {
        throw "Installation aborted: Required source file '$srcFile' is missing."
    }
}

Write-Host "Installing ArchiveLens v0.2.0 (per-user scope)..." -ForegroundColor Cyan

# 1. Install to PowerShell 7 and Windows PowerShell 5.1 user module directories
foreach ($modDir in $moduleTargets)
{
    if ( $PSCmdlet.ShouldProcess($modDir, 'Install ArchiveLens PowerShell Module'))
    {
        if (Test-Path -LiteralPath $modDir -PathType Container)
        {
            Remove-Item -LiteralPath "$modDir\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        else
        {
            [void][System.IO.Directory]::CreateDirectory($modDir)
        }
        foreach ($file in $requiredFiles)
        {
            $src = Join-Path -Path $PSScriptRoot -ChildPath $file
            $dst = Join-Path -Path $modDir -ChildPath $file
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
        Write-Host "Installed PowerShell module to: $modDir" -ForegroundColor Green
    }
}

# 2. Install CMD launcher and runtime files to %LOCALAPPDATA%\Programs\ArchiveLens\bin
if ( $PSCmdlet.ShouldProcess($cliBinDir, 'Install CMD launcher and scripts'))
{
    if (Test-Path -LiteralPath $cliBinDir -PathType Container)
    {
        Remove-Item -LiteralPath "$cliBinDir\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
    else
    {
        [void][System.IO.Directory]::CreateDirectory($cliBinDir)
    }
    foreach ($file in $requiredFiles)
    {
        $src = Join-Path -Path $PSScriptRoot -ChildPath $file
        $dst = Join-Path -Path $cliBinDir -ChildPath $file
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
    Write-Host "Installed CMD launcher to: $cliBinDir" -ForegroundColor Green
}

# 3. Optionally add $cliBinDir to User PATH without duplication
if ($AddToPath)
{
    $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ( [string]::IsNullOrWhiteSpace($currentUserPath))
    {
        $currentUserPath = ''
    }

    $normTarget = Get-NormalizedPathEntry -Entry $cliBinDir
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
        Write-Host "User PATH already contains '$cliBinDir' (no duplicate added)." -ForegroundColor Yellow
    }
    else
    {
        $updatedPath = if ( [string]::IsNullOrWhiteSpace($currentUserPath))
        {
            $cliBinDir
        }
        else
        {
            "$($currentUserPath.TrimEnd(';') );$cliBinDir"
        }

        if ( $PSCmdlet.ShouldProcess('HKCU\Environment\Path', "Add '$cliBinDir' to User PATH"))
        {
            [Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')
            # Also update current session PATH for immediate usability
            if ($env:PATH -notlike "*$cliBinDir*")
            {
                $env:PATH = "$($env:PATH.TrimEnd(';') );$cliBinDir"
            }
            Write-Host "Added '$cliBinDir' to your User PATH." -ForegroundColor Green
            Write-Host "NOTE: Restart any already-open CMD or PowerShell windows for the updated PATH to take effect." -ForegroundColor Yellow
        }
    }
}
else
{
    Write-Host "Tip: Run '.\Install.ps1 -AddToPath' if you want 'ArchiveToText' available directly in Windows CMD from any folder." -ForegroundColor DarkGray
}

Write-Host "`nInstallation finished! You can now run:" -ForegroundColor Green
Write-Host "  PowerShell : Convert-ArchiveToText `"C:\path\to\archive.zip`""
Write-Host "  CMD        : ArchiveToText `"C:\path\to\archive.zip`""