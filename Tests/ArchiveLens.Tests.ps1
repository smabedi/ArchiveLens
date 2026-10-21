#Requires -Version 5.1
<#
.SYNOPSIS
Automated Pester v5 test suite for ArchiveLens.
Uses isolated temporary directories and synthetic archives.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ManifestPath = Join-Path -Path $script:RepoRoot -ChildPath 'ArchiveLens.psd1'
    $script:CliScriptPath = Join-Path -Path $script:RepoRoot -ChildPath 'ArchiveToText.ps1'
    $script:CmdLauncherPath = Join-Path -Path $script:RepoRoot -ChildPath 'ArchiveToText.cmd'

    Import-Module -Name $script:ManifestPath -Force -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function New-TestZipFromHashtables
    {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ZipPath,

            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [array]$Entries
        )

        $fs = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite)
        $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        try
        {
            foreach ($item in $Entries)
            {
                $entry = $archive.CreateEntry($item.Path)
                if ($null -ne $item.Bytes -and $item.Bytes.Length -gt 0)
                {
                    $stream = $entry.Open()
                    try
                    {
                        $stream.Write($item.Bytes, 0, $item.Bytes.Length)
                    }
                    finally
                    {
                        $stream.Dispose()
                    }
                }
            }
        }
        finally
        {
            $archive.Dispose()
            $fs.Dispose()
        }
    }
}

Describe 'ArchiveLens Core Functionality' {
    BeforeEach {
        $script:WorkDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("ArchiveLensTests_" + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($script:WorkDir)
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:WorkDir)
        {
            Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Basic ZIP Behavior and Output Path Resolution' {
        It 'Extracts a ZIP with nested directories, preserves deterministic order, and defaults output to <BaseName>.txt' {
            $zipPath = Join-Path $script:WorkDir 'SampleProject.zip'
            $expectedOut = Join-Path $script:WorkDir 'SampleProject.txt'

            $utf8 = [System.Text.UTF8Encoding]::new($false)
            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = 'z_folder/last.txt'; Bytes = $utf8.GetBytes("Last file content`n") },
                @{ Path = 'a_folder/first.py'; Bytes = $utf8.GetBytes("print('hello')`n") },
                @{ Path = 'README.md'; Bytes = $utf8.GetBytes("# Sample Project`n") },
                @{ Path = 'assets/icon.svg'; Bytes = $utf8.GetBytes("<svg xmlns='http://www.w3.org/2000/svg'></svg>`n") }
            )

            $res = Convert-ArchiveToText -ArchivePath $zipPath -PassThru
            $res | Should -Not -BeNullOrEmpty
            $res.ExitCode | Should -Be 0
            $res.OutputPath | Should -Be $expectedOut
            $res.DiscoveredCount | Should -Be 4
            $res.IncludedCount | Should -Be 4
            $res.SkippedCount | Should -Be 0
            $res.FailedCount | Should -Be 0
            (Test-Path -LiteralPath $expectedOut) | Should -BeTrue

            $reportText = [System.IO.File]::ReadAllText($expectedOut, $utf8)

            $reportText | Should -Match 'SECTION A: REPORT HEADER AND SUMMARY'
            $reportText | Should -Match 'SECTION B: COMPLETE FILE INVENTORY'

            $reportText | Should -Match 'SECTION C: SKIPPED, EXCLUDED, AND FAILED FILES'
            $reportText | Should -Match 'SECTION D: READABLE FILE CONTENTS'

            $reportText | Should -Match 'SECTION E: FINAL STATUS'

            # Verify deterministic ordering (README.md < a_folder/first.py < assets/icon.svg < z_folder/last.txt)
            $idxReadme = $reportText.IndexOf('BEGIN FILE: README.md')
            $idxFirst = $reportText.IndexOf('BEGIN FILE: a_folder/first.py')
            $idxSvg = $reportText.IndexOf('BEGIN FILE: assets/icon.svg')
            $idxLast = $reportText.IndexOf('BEGIN FILE: z_folder/last.txt')

            $idxFirst  | Should -BeGreaterOrEqual 0
            $idxSvg    | Should -BeGreaterThan $idxFirst
            $idxReadme | Should -BeGreaterThan $idxSvg
            $idxLast   | Should -BeGreaterThan $idxReadme
        }

        It 'Handles paths containing spaces and special characters' {
            $subDir = Join-Path $script:WorkDir 'Folder With Spaces & (Symbols)'
            [void][System.IO.Directory]::CreateDirectory($subDir)
            $zipPath = Join-Path $subDir 'My Archive (v1).zip'
            $outPath = Join-Path $subDir 'Custom Report (v1).txt'

            $utf8 = [System.Text.UTF8Encoding]::new($false)
            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = 'sub dir/hello world.txt'; Bytes = $utf8.GetBytes("Space path test`n") }
            )

            $res = Convert-ArchiveToText -ArchivePath $zipPath -OutputPath $outPath -PassThru
            $res.ExitCode | Should -Be 0
            (Test-Path -LiteralPath $outPath) | Should -BeTrue
            $content = [System.IO.File]::ReadAllText($outPath)
            $content | Should -Match 'BEGIN FILE: sub dir/hello world.txt'
        }

        It 'Handles an empty ZIP archive cleanly' {
            $zipPath = Join-Path $script:WorkDir 'Empty.zip'
            New-TestZipFromHashtables -ZipPath $zipPath -Entries @()

            $res = Convert-ArchiveToText -ArchivePath $zipPath -PassThru
            $res.ExitCode | Should -Be 0
            $res.DiscoveredCount | Should -Be 0
            $res.IncludedCount | Should -Be 0
            $content = [System.IO.File]::ReadAllText($res.OutputPath)
            $content | Should -Match '\(Archive contains no files\.\)'
        }

        It 'Handles an archive containing only binary files' {
            $zipPath = Join-Path $script:WorkDir 'OnlyBinaries.zip'
            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = 'logo.png'; Bytes = [byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00) },
                @{ Path = 'app.exe'; Bytes = [byte[]]@(0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00) }
            )

            $res = Convert-ArchiveToText -ArchivePath $zipPath -PassThru
            $res.ExitCode | Should -Be 0
            $res.DiscoveredCount | Should -Be 2
            $res.IncludedCount | Should -Be 0
            $res.SkippedCount | Should -Be 2

            $content = [System.IO.File]::ReadAllText($res.OutputPath)
            $content | Should -Match 'logo\.png \[Skipped\]'
            $content | Should -Match 'app\.exe \[Skipped\]'
            $content | Should -Match '\(No readable text files were included in this report\.\)'
        }
    }

    Context 'Unicode, Persian, Arabic, and Encoding Detection' {
        It 'Correctly decodes UTF-8 (no BOM), UTF-8 (BOM), UTF-16 LE, and UTF-16 BE with Persian and Arabic text' {
            $zipPath = Join-Path $script:WorkDir 'UnicodeSuite.zip'

            $persianText = "سلام دنیا! این یک متن آزمایشی به زبان فارسی است.`n"
            $arabicText = "مرحبا بالعالم! هذا نص تجريبي باللغة العربية.`n"
            $utf16LeText = "UTF-16 Little Endian — فارسی — Русский — 中文`n"
            $utf16BeText = "UTF-16 Big Endian — العربية — Español`n"

            $utf8NoBomBytes = ([System.Text.UTF8Encoding]::new($false)).GetBytes($persianText)
            $utf8BomBytes = [byte[]]@(0xEF, 0xBB, 0xBF) + ([System.Text.UTF8Encoding]::new($false)).GetBytes($arabicText)
            $utf16LeBytes = [byte[]]@(0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes($utf16LeText)
            $utf16BeBytes = [byte[]]@(0xFE, 0xFF) + [System.Text.Encoding]::BigEndianUnicode.GetBytes($utf16BeText)

            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = 'persian_utf8.txt'; Bytes = $utf8NoBomBytes },
                @{ Path = 'arabic_utf8bom.txt'; Bytes = $utf8BomBytes },
                @{ Path = 'multi_utf16le.txt'; Bytes = $utf16LeBytes },
                @{ Path = 'multi_utf16be.txt'; Bytes = $utf16BeBytes }
            )

            $res = Convert-ArchiveToText -ArchivePath $zipPath -PassThru
            $res.ExitCode | Should -Be 0
            $res.IncludedCount | Should -Be 4

            $report = [System.IO.File]::ReadAllText($res.OutputPath,[System.Text.UTF8Encoding]::new($false))
            $report | Should -Match 'سلام دنیا! این یک متن آزمایشی به زبان فارسی است\.'
            $report | Should -Match 'مرحبا بالعالم! هذا نص تجريبي باللغة العربية\.'
            $report | Should -Match 'UTF-16 Little Endian — فارسی — Русский — 中文'
            $report | Should -Match 'UTF-16 Big Endian — العربية — Español'
            $report | Should -Match 'UTF-8 \(BOM\)'
            $report | Should -Match 'UTF-16 LE \(BOM\)'
            $report | Should -Match 'UTF-16 BE \(BOM\)'
        }

        It 'Includes a file with an unfamiliar extension (.customdsl) when it contains valid text' {
            $zipPath = Join-Path $script:WorkDir 'CustomExt.zip'
            $bytes = ([System.Text.UTF8Encoding]::new($false)).GetBytes("rule allow_all { action = permit }`n")

            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = 'policies/firewall.customdsl'; Bytes = $bytes }
            )

            $res = Convert-ArchiveToText -ArchivePath $zipPath -PassThru
            $res.IncludedCount | Should -Be 1
            $report = [System.IO.File]::ReadAllText($res.OutputPath)
            $report | Should -Match 'BEGIN FILE: policies/firewall\.customdsl'

            $report | Should -Match 'rule allow_all'
        }

        It 'Rejects a binary file disguised with a .txt extension (contains NUL or binary control bytes)' {
            $zipPath = Join-Path $script:WorkDir 'DisguisedBinary.zip'
            # Valid ASCII prefix followed by NUL and control characters
            $fakeTxtBytes = [byte[]]@(0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0xFE)

            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = 'notes.txt'; Bytes = $fakeTxtBytes }
            )

            $res = Convert-ArchiveToText -ArchivePath $zipPath -PassThru
            $res.IncludedCount | Should -Be 0
            $res.SkippedCount | Should -Be 1
            $report = [System.IO.File]::ReadAllText($res.OutputPath)
            $report | Should -Match 'notes\.txt \[Skipped\s*\] -- Unrecognized binary data'
        }

        It 'Flags invalid UTF-8 as Failed (Partial Success exit code 2) when fallback encoding is disabled' {
            $zipPath = Join-Path $script:WorkDir 'InvalidUtf8.zip'
            # Invalid UTF-8 continuation bytes without NULs
            $badUtf8 = [byte[]]@(0x41, 0x42, 0xC0, 0xAF, 0xFE, 0xFF, 0x43)

            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = 'broken.txt'; Bytes = $badUtf8 }
            )

            $res = Convert-ArchiveToText -ArchivePath $zipPath -FallbackEncodingCodePage 0 -PassThru
            $res.FailedCount | Should -Be 1
            $res.ExitCode | Should -Be 2
            $report = [System.IO.File]::ReadAllText($res.OutputPath)
            $report | Should -Match 'broken\.txt \[Failed\s*\] -- Text decoding failed'
        }

        It 'Preserves text files without a trailing newline without corrupting the END FILE boundary' {
            $zipPath = Join-Path $script:WorkDir 'NoNewline.zip'
            $bytes = ([System.Text.UTF8Encoding]::new($false)).GetBytes("line without newline at end")

            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = 'no_nl.txt'; Bytes = $bytes }
            )

            $res = Convert-ArchiveToText -ArchivePath $zipPath -PassThru
            $res.ExitCode | Should -Be 0
            $report = [System.IO.File]::ReadAllText($res.OutputPath)
            $report | Should -Match "line without newline at end`n\[ArchiveLens Note: Original file had no trailing newline\]`n--------------------------------------------------------------------------------`nEND FILE: no_nl\.txt"
        }
    }

    Context 'Git Exclusion and Sensitive File Filtering' {
        It 'Excludes .git files by default and includes them when -IncludeGit is specified' {
            $zipPath = Join-Path $script:WorkDir 'RepoWithGit.zip'
            $utf8 = [System.Text.UTF8Encoding]::new($false)

            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = '.git/config'; Bytes = $utf8.GetBytes("[core]`nrepositoryformatversion = 0`n") },
                @{ Path = 'src/main.ps1'; Bytes = $utf8.GetBytes("Write-Output 'ok'`n") }
            )

            $resDefault = Convert-ArchiveToText -ArchivePath $zipPath -PassThru
            $resDefault.IncludedCount | Should -Be 1
            $resDefault.ExcludedCount | Should -Be 1
            $reportDefault = [System.IO.File]::ReadAllText($resDefault.OutputPath)
            $reportDefault | Should -Match '\.git/config \[Excluded\] -- Excluded by default \(\.git directory\)'

            $resWithGit = Convert-ArchiveToText -ArchivePath $zipPath -IncludeGit -Force -PassThru
            $resWithGit.IncludedCount | Should -Be 2
            $resWithGit.ExcludedCount | Should -Be 0
            $reportWithGit = [System.IO.File]::ReadAllText($resWithGit.OutputPath)
            $reportWithGit | Should -Match 'BEGIN FILE: \.git/config'
        }

        It 'Excludes .env and private key files when -ExcludeSensitive is used' {
            $zipPath = Join-Path $script:WorkDir 'Secrets.zip'
            $utf8 = [System.Text.UTF8Encoding]::new($false)

            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = '.env'; Bytes = $utf8.GetBytes("API_KEY=secret123`n") },
                @{ Path = 'id_rsa'; Bytes = $utf8.GetBytes("-----BEGIN RSA PRIVATE KEY-----`n") },
                @{ Path = 'app.py'; Bytes = $utf8.GetBytes("import os`n") }
            )

            $res = Convert-ArchiveToText -ArchivePath $zipPath -ExcludeSensitive -PassThru
            $res.IncludedCount | Should -Be 1
            $res.ExcludedCount | Should -Be 2
            $report = [System.IO.File]::ReadAllText($res.OutputPath)
            $report | Should -Not -Match 'API_KEY=secret123'
            $report | Should -Match '\.env \[Excluded\]'
        }
    }

    Context 'Output Protection, Validation, and Security Safeguards' {
        It 'Refuses to overwrite an existing output file unless -Force is passed' {
            $zipPath = Join-Path $script:WorkDir 'OverwriteTest.zip'
            $outPath = Join-Path $script:WorkDir 'OverwriteTest.txt'
            $utf8 = [System.Text.UTF8Encoding]::new($false)

            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = 'a.txt'; Bytes = $utf8.GetBytes("hello`n") }
            )
            [System.IO.File]::WriteAllText($outPath, 'EXISTING_PROTECTED_CONTENT')

            { Convert-ArchiveToText -ArchivePath $zipPath -OutputPath $outPath -ErrorAction Stop } | Should -Throw '*already exists*'
            [System.IO.File]::ReadAllText($outPath) | Should -Be 'EXISTING_PROTECTED_CONTENT'

            # Now overwrite with -Force
            $res = Convert-ArchiveToText -ArchivePath $zipPath -OutputPath $outPath -Force -PassThru
            $res.ExitCode | Should -Be 0
            [System.IO.File]::ReadAllText($outPath) | Should -Match 'ARCHIVELENS INSPECTION REPORT'
        }

        It 'Rejects OutputPath equal to ArchivePath' {
            $zipPath = Join-Path $script:WorkDir 'SamePath.zip'
            New-TestZipFromHashtables -ZipPath $zipPath -Entries @()

            { Convert-ArchiveToText -ArchivePath $zipPath -OutputPath $zipPath -Force -ErrorAction Stop } | Should -Throw '*cannot be the same*'
        }

        It 'Rejects missing output directory without silently creating arbitrary folder trees' {
            $zipPath = Join-Path $script:WorkDir 'MissingDir.zip'
            $badOut = Join-Path $script:WorkDir 'NonExistentSubfolder\Report.txt'
            New-TestZipFromHashtables -ZipPath $zipPath -Entries @()

            { Convert-ArchiveToText -ArchivePath $zipPath -OutputPath $badOut -ErrorAction Stop } | Should -Throw '*does not exist*'
        }

        It 'Blocks Zip-Slip path traversal entries and leaves no misleading report behind' {
            $zipPath = Join-Path $script:WorkDir 'MaliciousTraversal.zip'
            $outPath = Join-Path $script:WorkDir 'MaliciousTraversal.txt'
            $utf8 = [System.Text.UTF8Encoding]::new($false)

            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = '../../evil_escape.txt'; Bytes = $utf8.GetBytes("pwned`n") }
            )

            { Convert-ArchiveToText -ArchivePath $zipPath -OutputPath $outPath -ErrorAction Stop } | Should -Throw '*Security violation*'
            (Test-Path -LiteralPath $outPath) | Should -BeFalse
        }

        It 'Fails cleanly on a corrupt ZIP archive and cleans up temporary files' {
            $corruptZip = Join-Path $script:WorkDir 'Corrupt.zip'
            $outPath = Join-Path $script:WorkDir 'Corrupt.txt'
            [System.IO.File]::WriteAllBytes($corruptZip, [byte[]]@(0x50, 0x4B, 0x03, 0x04, 0xFF, 0x00, 0x12))

            { Convert-ArchiveToText -ArchivePath $corruptZip -OutputPath $outPath -ErrorAction Stop } | Should -Throw '*Failed to open ZIP archive*'
            (Test-Path -LiteralPath $outPath) | Should -BeFalse
        }

        It 'Enforces -MaxEntryCount safety limit' {
            $zipPath = Join-Path $script:WorkDir 'TooManyEntries.zip'
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = '1.txt'; Bytes = $utf8.GetBytes("1") },
                @{ Path = '2.txt'; Bytes = $utf8.GetBytes("2") },
                @{ Path = '3.txt'; Bytes = $utf8.GetBytes("3") }
            )

            { Convert-ArchiveToText -ArchivePath $zipPath -MaxEntryCount 2 -ErrorAction Stop } | Should -Throw '*exceeds the configured safety limit*'
        }

        It 'Produces a clear actionable error for .rar when 7-Zip is unavailable' {
            $fakeRar = Join-Path $script:WorkDir 'Sample.rar'
            [System.IO.File]::WriteAllBytes($fakeRar, [byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00))
            $nonExistent7z = Join-Path $script:WorkDir 'missing_7z.exe'

            { Convert-ArchiveToText -ArchivePath $fakeRar -SevenZipPath $nonExistent7z -ErrorAction Stop } | Should -Throw '*7-Zip*'
        }
    }

    Context 'CLI Script and CMD Wrapper Exit Code Verification' {
        It 'Returns ExitCode 0 on success and ExitCode 1 on fatal error via ArchiveToText.ps1' {
            $zipPath = Join-Path $script:WorkDir 'CliSuccess.zip'
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = 'hello.txt'; Bytes = $utf8.GetBytes("CLI test`n") }
            )

            $pwshExe = (Get-Process -Id $PID).Path
            & $pwshExe -NoLogo -NoProfile -File $script:CliScriptPath $zipPath | Out-Null
            $LASTEXITCODE | Should -Be 0

            # Second run without -Force should fail with exit code 1 because output file now exists
            & $pwshExe -NoLogo -NoProfile -File $script:CliScriptPath $zipPath 2> $null | Out-Null
            $LASTEXITCODE | Should -Be 1
        }
    }
}