#Requires -Version 5.1
<#
.SYNOPSIS
Automated Pester test suite for ArchiveLens.
#>

# --- 1. DISCOVERY PHASE (Only used for -Skip conditions) ---
$discoveryRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $discoveryRoot -ChildPath 'ArchiveLens.psd1') -Force
$discovery7z = Find-SevenZipExecutable
$Skip7z = [string]::IsNullOrWhiteSpace($discovery7z)
$SkipZst = $true

if (-not $Skip7z) {
    if ((& $discovery7z i 2>&1 | Out-String) -match '(?i)\bzst\b') {
        $SkipZst = $false
    }
}

# --- 2. RUN PHASE (Full initialization for test execution) ---
BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ManifestPath = Join-Path -Path $script:RepoRoot -ChildPath 'ArchiveLens.psd1'
    $script:CliScriptPath = Join-Path -Path $script:RepoRoot -ChildPath 'ArchiveToText.ps1'
    $script:CmdLauncherPath = Join-Path -Path $script:RepoRoot -ChildPath 'ArchiveToText.cmd'
    $script:InstallScriptPath = Join-Path -Path $script:RepoRoot -ChildPath 'Install.ps1'

    Import-Module -Name $script:ManifestPath -Force -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $script:SevenZipExe = Find-SevenZipExecutable

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

    function New-TestSourceTree
    {
        param(
            [Parameter(Mandatory = $true)]
            [string]$RootDir,

            [Parameter(Mandatory = $true)]
            [array]$Entries
        )
        [void][System.IO.Directory]::CreateDirectory($RootDir)
        foreach ($item in $Entries)
        {
            $fullPath = Join-Path -Path $RootDir -ChildPath ($item.Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            $parentDir = [System.IO.Path]::GetDirectoryName($fullPath)
            if (-not (Test-Path -LiteralPath $parentDir -PathType Container))
            {
                [void][System.IO.Directory]::CreateDirectory($parentDir)
            }
            [System.IO.File]::WriteAllBytes($fullPath, $item.Bytes)
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

            # Verify deterministic ordering (a_folder/first.py < assets/icon.svg < README.md < z_folder/last.txt)
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

    Context '7-Zip Multi-Format Support (.7z, .tar, .gz, .tgz, .bz2, .xz, .zst)' {
        It 'Extracts a .7z archive and reports ArchiveFormat as 7Z' -Skip:$Skip7z {
            $srcDir = Join-Path $script:WorkDir 'src_7z'
            $archivePath = Join-Path $script:WorkDir 'Bundle.7z'
            $utf8 = [System.Text.UTF8Encoding]::new($false)

            New-TestSourceTree -RootDir $srcDir -Entries @(
                @{ Path = 'src/App.java'; Bytes = $utf8.GetBytes("public class App {}`n") },
                @{ Path = 'README.md'; Bytes = $utf8.GetBytes("# 7Z Test`n") }
            )

            & $script:SevenZipExe a -t7z -bd -y -- $archivePath "$srcDir\*" | Out-Null
            $LASTEXITCODE | Should -Be 0

            $res = Convert-ArchiveToText -ArchivePath $archivePath -PassThru
            $res.ExitCode | Should -Be 0
            $res.ArchiveFormat | Should -Be '7Z'
            $res.DiscoveredCount | Should -Be 2
            $res.IncludedCount | Should -Be 2

            $report = [System.IO.File]::ReadAllText($res.OutputPath, $utf8)
            $report | Should -Match 'Archive Format\s*:\s*7Z'
            $report | Should -Match 'public class App \{\}'
        }

        It 'Extracts a standalone .tar archive and reports ArchiveFormat as TAR' -Skip:$Skip7z {
            $srcDir = Join-Path $script:WorkDir 'src_tar'
            $archivePath = Join-Path $script:WorkDir 'Bundle.tar'
            $utf8 = [System.Text.UTF8Encoding]::new($false)

            New-TestSourceTree -RootDir $srcDir -Entries @(
                @{ Path = 'config/settings.json'; Bytes = $utf8.GetBytes("{`"ok`": true}`n") },
                @{ Path = 'notes.txt'; Bytes = $utf8.GetBytes("TAR test file`n") }
            )

            & $script:SevenZipExe a -ttar -bd -y -- $archivePath "$srcDir\*" | Out-Null
            $LASTEXITCODE | Should -Be 0

            $res = Convert-ArchiveToText -ArchivePath $archivePath -PassThru
            $res.ExitCode | Should -Be 0
            $res.ArchiveFormat | Should -Be 'TAR'
            $res.IncludedCount | Should -Be 2
            [System.IO.File]::ReadAllText($res.OutputPath, $utf8) | Should -Match 'TAR test file'
        }

        It 'Extracts compound .tar.gz and .tgz archives via two-stage extraction and strips .tar.gz for default OutputPath' -Skip:$Skip7z {
            $srcDir = Join-Path $script:WorkDir 'src_targz'
            $tarPath = Join-Path $script:WorkDir 'ReleasePkg.tar'
            $tarGzPath = Join-Path $script:WorkDir 'ReleasePkg.tar.gz'
            $tgzPath = Join-Path $script:WorkDir 'ReleaseShort.tgz'
            $expectedTarGzOut = Join-Path $script:WorkDir 'ReleasePkg.txt'
            $utf8 = [System.Text.UTF8Encoding]::new($false)

            New-TestSourceTree -RootDir $srcDir -Entries @(
                @{ Path = 'module/core.ps1'; Bytes = $utf8.GetBytes("Write-Host 'from tar.gz'`n") },
                @{ Path = 'MANIFEST.txt'; Bytes = $utf8.GetBytes("v1.0`n") }
            )

            & $script:SevenZipExe a -ttar -bd -y -- $tarPath "$srcDir\*" | Out-Null
            & $script:SevenZipExe a -tgzip -bd -y -- $tarGzPath $tarPath | Out-Null
            Copy-Item -LiteralPath $tarGzPath -Destination $tgzPath -Force

            # Test .tar.gz
            $resTarGz = Convert-ArchiveToText -ArchivePath $tarGzPath -PassThru
            $resTarGz.ExitCode | Should -Be 0
            $resTarGz.ArchiveFormat | Should -Be 'TAR.GZ'
            $resTarGz.OutputPath | Should -Be $expectedTarGzOut
            $resTarGz.IncludedCount | Should -Be 2
            [System.IO.File]::ReadAllText($expectedTarGzOut, $utf8) | Should -Match "Write-Host 'from tar\.gz'"

            # Test .tgz
            $resTgz = Convert-ArchiveToText -ArchivePath $tgzPath -PassThru
            $resTgz.ExitCode | Should -Be 0
            $resTgz.ArchiveFormat | Should -Be 'TGZ'
            $resTgz.IncludedCount | Should -Be 2
        }

        It 'Extracts a standalone single-file .gz stream (non-TAR)' -Skip:$Skip7z {
            $rawFile = Join-Path $script:WorkDir 'server.log'
            $gzPath = Join-Path $script:WorkDir 'server.log.gz'
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllBytes($rawFile,$utf8.GetBytes("2026-10-22 INFO Server started`n"))

            & $script:SevenZipExe a -tgzip -bd -y -- $gzPath $rawFile | Out-Null
            Remove-Item -LiteralPath $rawFile -Force

            $res = Convert-ArchiveToText -ArchivePath $gzPath -PassThru
            $res.ExitCode | Should -Be 0
            $res.ArchiveFormat | Should -Be 'GZ'
            $res.IncludedCount | Should -Be 1
            [System.IO.File]::ReadAllText($res.OutputPath, $utf8) | Should -Match '2026-10-22 INFO Server started'
        }

        It 'Extracts compound .tar.bz2 and standalone .bz2 archives' -Skip:$Skip7z {
            $srcDir = Join-Path $script:WorkDir 'src_bz2'
            $tarPath = Join-Path $script:WorkDir 'Pkg.tar'
            $tarBz2Path = Join-Path $script:WorkDir 'Pkg.tar.bz2'
            $expectedOut = Join-Path $script:WorkDir 'Pkg.txt'
            $utf8 = [System.Text.UTF8Encoding]::new($false)

            New-TestSourceTree -RootDir $srcDir -Entries @(
                @{ Path = 'bzip_test.txt'; Bytes = $utf8.GetBytes("Hello from BZip2 TAR`n") }
            )

            & $script:SevenZipExe a -ttar -bd -y -- $tarPath "$srcDir\*" | Out-Null
            & $script:SevenZipExe a -tbzip2 -bd -y -- $tarBz2Path $tarPath | Out-Null

            $res = Convert-ArchiveToText -ArchivePath $tarBz2Path -PassThru
            $res.ExitCode | Should -Be 0
            $res.ArchiveFormat | Should -Be 'TAR.BZ2'
            $res.OutputPath | Should -Be $expectedOut
            $res.IncludedCount | Should -Be 1
            [System.IO.File]::ReadAllText($expectedOut, $utf8) | Should -Match 'Hello from BZip2 TAR'
        }

        It 'Extracts compound .tar.xz and standalone .xz archives' -Skip:$Skip7z {
            $srcDir = Join-Path $script:WorkDir 'src_xz'
            $tarPath = Join-Path $script:WorkDir 'XzBundle.tar'
            $tarXzPath = Join-Path $script:WorkDir 'XzBundle.tar.xz'
            $expectedOut = Join-Path $script:WorkDir 'XzBundle.txt'
            $utf8 = [System.Text.UTF8Encoding]::new($false)

            New-TestSourceTree -RootDir $srcDir -Entries @(
                @{ Path = 'xz_note.md'; Bytes = $utf8.GetBytes("# XZ Compression Works`n") }
            )

            & $script:SevenZipExe a -ttar -bd -y -- $tarPath "$srcDir\*" | Out-Null
            & $script:SevenZipExe a -txz -bd -y -- $tarXzPath $tarPath | Out-Null

            $res = Convert-ArchiveToText -ArchivePath $tarXzPath -PassThru
            $res.ExitCode | Should -Be 0
            $res.ArchiveFormat | Should -Be 'TAR.XZ'
            $res.OutputPath | Should -Be $expectedOut
            $res.IncludedCount | Should -Be 1
            [System.IO.File]::ReadAllText($expectedOut, $utf8) | Should -Match '# XZ Compression Works'
        }

        It 'Extracts compound .tar.zst and standalone .zst archives when supported by installed 7-Zip' -Skip:$SkipZst {
            $srcDir = Join-Path $script:WorkDir 'src_zst'
            $tarPath = Join-Path $script:WorkDir 'ZstBundle.tar'
            $tarZstPath = Join-Path $script:WorkDir 'ZstBundle.tar.zst'
            $expectedOut = Join-Path $script:WorkDir 'ZstBundle.txt'
            $utf8 = [System.Text.UTF8Encoding]::new($false)

            New-TestSourceTree -RootDir $srcDir -Entries @(
                @{ Path = 'zst_file.txt'; Bytes = $utf8.GetBytes("Zstandard archive content`n") }
            )

            # 1. Create a standard TAR file using vanilla 7-Zip
            & $script:SevenZipExe a -ttar -bd -y -- $tarPath "$srcDir\*" | Out-Null

            # 2. Package the TAR into a valid, uncompressed Zstandard (ZST) Raw Block frame
            $tarBytes = [System.IO.File]::ReadAllBytes($tarPath)
            $L = $tarBytes.Length

            $zstStream = [System.IO.MemoryStream]::new()
            # Magic: 28 B5 2F FD | FHD: E0 (Single Segment, 8-byte FCS, No Checksum, No Dict)
            $zstStream.Write([byte[]]@(0x28, 0xB5, 0x2F, 0xFD, 0xE0), 0, 5)
            # FCS (8 bytes, Little Endian)
            $zstStream.Write([BitConverter]::GetBytes([long]$L), 0, 8)

            # Block Header: 3 bytes (Last_Block=1, Type=Raw_Block=0, Size=L)
            $blockVal = ($L -shl 3) -bor 1
            $zstStream.Write([byte[]]@(
                [byte]($blockVal -band 0xFF),
                [byte](($blockVal -shr 8) -band 0xFF),
                [byte](($blockVal -shr 16) -band 0xFF)
            ), 0, 3)

            # Block Content
            $zstStream.Write($tarBytes, 0, $L)

            [System.IO.File]::WriteAllBytes($tarZstPath, $zstStream.ToArray())
            $zstStream.Dispose()

            # 3. Test extraction
            $res = Convert-ArchiveToText -ArchivePath $tarZstPath -PassThru
            $res.ExitCode | Should -Be 0
            $res.ArchiveFormat | Should -Be 'TAR.ZST'
            $res.OutputPath | Should -Be $expectedOut
            $res.IncludedCount | Should -Be 1
            [System.IO.File]::ReadAllText($expectedOut, $utf8) | Should -Match 'Zstandard archive content'
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

        It 'Detects disguised 7z, XZ, ZST, and BZip2 magic headers even when given a .txt extension' {
            $zipPath = Join-Path $script:WorkDir 'MagicDisguised.zip'
            New-TestZipFromHashtables -ZipPath $zipPath -Entries @(
                @{ Path = 'fake_7z.txt'; Bytes = [byte[]]@(0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04) },
                @{ Path = 'fake_xz.txt'; Bytes = [byte[]]@(0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00, 0x00, 0x01) },
                @{ Path = 'fake_zst.txt'; Bytes = [byte[]]@(0x28, 0xB5, 0x2F, 0xFD, 0x20, 0x00, 0x00, 0x00) },
                @{ Path = 'fake_bz2.txt'; Bytes = [byte[]]@(0x42, 0x5A, 0x68, 0x39, 0x31, 0x41, 0x59, 0x26) }
            )

            $res = Convert-ArchiveToText -ArchivePath $zipPath -PassThru
            $res.IncludedCount | Should -Be 0
            $res.SkippedCount | Should -Be 4
            $report = [System.IO.File]::ReadAllText($res.OutputPath)
            $report | Should -Match '7-Zip archive signature'
            $report | Should -Match 'XZ compressed signature'
            $report | Should -Match 'Zstandard \(ZST\) compressed signature'
            $report | Should -Match 'BZip2 compressed signature'
        }

        It 'Flags invalid UTF-8 as Failed (Partial Success exit code 2) when fallback encoding is disabled' {
            $zipPath = Join-Path $script:WorkDir 'InvalidUtf8.zip'
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

        It 'Produces a clear actionable error for 7-Zip formats (.rar, .7z, .tar, .gz, .tgz, .bz2, .xz, .zst) when 7-Zip is unavailable' {
            $nonExistent7z = Join-Path $script:WorkDir 'missing_7z.exe'
            foreach ($ext in @('.rar', '.7z', '.tar', '.gz', '.tgz', '.bz2', '.xz', '.zst'))
            {
                $fakeArchive = Join-Path $script:WorkDir ("Sample" + $ext)
                [System.IO.File]::WriteAllBytes($fakeArchive, [byte[]]@(0x00, 0x01, 0x02, 0x03))
                { Convert-ArchiveToText -ArchivePath $fakeArchive -SevenZipPath $nonExistent7z -ErrorAction Stop } | Should -Throw '*7-Zip*'
            }
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

            # Run 1: Should Succeed
            $args1 = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:CliScriptPath`"", "`"$zipPath`"")
            $p1 = Start-Process -FilePath $pwshExe -ArgumentList $args1 -Wait -NoNewWindow -PassThru
            $p1.ExitCode | Should -Be 0

            # Run 2: Should Fail (file already exists, no -Force)
            $args2 = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:CliScriptPath`"", "`"$zipPath`"")
            $p2 = Start-Process -FilePath $pwshExe -ArgumentList $args2 -Wait -NoNewWindow -PassThru
            $p2.ExitCode | Should -Be 1
        }
    }

    Context 'Installer Side-by-Side Versioning and Uninstallation (Install.ps1)' {
        BeforeEach {
            $script:MockModRootPS7 = Join-Path $script:WorkDir 'MockModules\PowerShell\Modules\ArchiveLens'
            $script:MockModRootPS5 = Join-Path $script:WorkDir 'MockModules\WindowsPowerShell\Modules\ArchiveLens'
            $script:MockModuleRoots = @($script:MockModRootPS7, $script:MockModRootPS5)
            $script:MockCliRoot = Join-Path $script:WorkDir 'MockPrograms\ArchiveLens'
            $script:MockCliBin = Join-Path $script:MockCliRoot 'bin'

            function New-MockInstalledVersion
            {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$VersionString
                )
                foreach ($root in $script:MockModuleRoots)
                {
                    $verDir = Join-Path -Path $root -ChildPath $VersionString
                    [void][System.IO.Directory]::CreateDirectory($verDir)
                    $psd1Content = "@{`n    RootModule = 'ArchiveLens.psm1'`n    ModuleVersion = '$VersionString'`n}`n"
                    [System.IO.File]::WriteAllText((Join-Path $verDir 'ArchiveLens.psd1'), $psd1Content)
                    foreach ($f in @('ArchiveLens.psm1', 'ArchiveToText.ps1', 'ArchiveToText.cmd', 'README.md', 'LICENSE.txt'))
                    {
                        Copy-Item -LiteralPath (Join-Path $script:RepoRoot $f) -Destination (Join-Path $verDir $f) -Force
                    }
                }
            }
        }

        It 'Default Install: installs 0.3.0 into <ModuleRoot>\0.3.0 without touching existing version folders' {
            New-MockInstalledVersion -VersionString '0.1.0'
            New-MockInstalledVersion -VersionString '0.2.0'
            New-MockInstalledVersion -VersionString '1.0.0'

            & $script:InstallScriptPath -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath

            foreach ($root in $script:MockModuleRoots)
            {
                (Test-Path -LiteralPath (Join-Path $root '0.1.0\ArchiveLens.psd1')) | Should -BeTrue
                (Test-Path -LiteralPath (Join-Path $root '0.2.0\ArchiveLens.psd1')) | Should -BeTrue
                (Test-Path -LiteralPath (Join-Path $root '0.3.0\ArchiveLens.psd1')) | Should -BeTrue
                (Test-Path -LiteralPath (Join-Path $root '1.0.0\ArchiveLens.psd1')) | Should -BeTrue
            }
            (Test-Path -LiteralPath (Join-Path $script:MockCliBin 'ArchiveToText.cmd')) | Should -BeTrue
        }

        It '-CleanInstall: installs 0.3.0 and deletes all other older and newer version folders' {
            New-MockInstalledVersion -VersionString '0.1.0'
            New-MockInstalledVersion -VersionString '0.2.0'
            New-MockInstalledVersion -VersionString '1.0.0'

            & $script:InstallScriptPath -CleanInstall -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath

            foreach ($root in $script:MockModuleRoots)
            {
                (Test-Path -LiteralPath (Join-Path $root '0.1.0')) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $root '0.2.0')) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $root '1.0.0')) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $root '0.3.0\ArchiveLens.psd1')) | Should -BeTrue
            }
        }

        It '-RemoveOlderVersions: installs 0.3.0, deletes older versions (0.1.0, 0.2.0), and preserves newer versions (1.0.0)' {
            New-MockInstalledVersion -VersionString '0.1.0'
            New-MockInstalledVersion -VersionString '0.2.0'
            New-MockInstalledVersion -VersionString '1.0.0'

            & $script:InstallScriptPath -RemoveOlderVersions -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath

            foreach ($root in $script:MockModuleRoots)
            {
                (Test-Path -LiteralPath (Join-Path $root '0.1.0')) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $root '0.2.0')) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $root '0.3.0\ArchiveLens.psd1')) | Should -BeTrue
                (Test-Path -LiteralPath (Join-Path $root '1.0.0\ArchiveLens.psd1')) | Should -BeTrue
            }
        }

        It '-Uninstall -TargetVersion: accepts v/V prefix and deletes only the exact version while keeping CLI when versions remain' {
            & $script:InstallScriptPath -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath
            New-MockInstalledVersion -VersionString '0.1.0'
            New-MockInstalledVersion -VersionString '0.2.0'

            & $script:InstallScriptPath -Uninstall -TargetVersion 'v0.2.0' -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath

            foreach ($root in $script:MockModuleRoots)
            {
                (Test-Path -LiteralPath (Join-Path $root '0.1.0')) | Should -BeTrue
                (Test-Path -LiteralPath (Join-Path $root '0.2.0')) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $root '0.3.0')) | Should -BeTrue
            }
            (Test-Path -LiteralPath $script:MockCliRoot) | Should -BeTrue
        }

        It '-Uninstall -RemoveOlderThan: compares via [System.Version] (e.g. 0.2.0 < 0.10.0) and strips leading V' {
            & $script:InstallScriptPath -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath
            New-MockInstalledVersion -VersionString '0.1.0'
            New-MockInstalledVersion -VersionString '0.2.0'
            New-MockInstalledVersion -VersionString '0.10.0'

            & $script:InstallScriptPath -Uninstall -RemoveOlderThan 'V0.3.0' -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath

            foreach ($root in $script:MockModuleRoots)
            {
                (Test-Path -LiteralPath (Join-Path $root '0.1.0')) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $root '0.2.0')) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $root '0.3.0')) | Should -BeTrue
                (Test-Path -LiteralPath (Join-Path $root '0.10.0')) | Should -BeTrue
            }
            (Test-Path -LiteralPath $script:MockCliRoot) | Should -BeTrue
        }

        It '-Uninstall -RemoveOlderThanOrEqualTo: deletes versions <= target and automatically removes CLI root when zero versions remain' {
            & $script:InstallScriptPath -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath
            New-MockInstalledVersion -VersionString '0.1.0'
            New-MockInstalledVersion -VersionString '0.2.0'

            # First remove <= 0.2.0 (0.3.0 still remains)
            & $script:InstallScriptPath -Uninstall -RemoveOlderThanOrEqualTo 'v0.2.0' -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath

            foreach ($root in $script:MockModuleRoots)
            {
                (Test-Path -LiteralPath (Join-Path $root '0.1.0')) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $root '0.2.0')) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $root '0.3.0')) | Should -BeTrue
            }
            (Test-Path -LiteralPath $script:MockCliRoot) | Should -BeTrue

            # Now remove target 0.3.0 -> zero versions remain -> CLI root must be automatically removed
            & $script:InstallScriptPath -Uninstall -TargetVersion '0.3.0' -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath

            foreach ($root in $script:MockModuleRoots)
            {
                (Test-Path -LiteralPath $root) | Should -BeFalse
            }
            (Test-Path -LiteralPath $script:MockCliRoot) | Should -BeFalse
        }

        It 'Default -Uninstall: removes all module roots and shared CLI directory immediately' {
            & $script:InstallScriptPath -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath
            New-MockInstalledVersion -VersionString '0.1.0'

            & $script:InstallScriptPath -Uninstall -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath

            foreach ($root in $script:MockModuleRoots)
            {
                (Test-Path -LiteralPath $root) | Should -BeFalse
            }
            (Test-Path -LiteralPath $script:MockCliRoot) | Should -BeFalse
        }

        It 'Throws an ArgumentException when an invalid version string is passed' {
            {
                & $script:InstallScriptPath -Uninstall -TargetVersion 'vNotAVersion' -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath
            } | Should -Throw '*Invalid semantic version*'
        }

        It 'Built-in Uninstall-ArchiveLens cmdlet supports targeted pruning and full teardown without external scripts' {
            & $script:InstallScriptPath -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath
            New-MockInstalledVersion -VersionString '0.1.0'
            New-MockInstalledVersion -VersionString '0.2.0'

            # 1. Remove older than 0.2.0 (deletes 0.1.0, keeps 0.2.0 and 0.3.0)
            Uninstall-ArchiveLens -RemoveOlderThan 'v0.2.0' -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath -KeepLoadedSession -Confirm:$false

            foreach ($root in $script:MockModuleRoots)
            {
                (Test-Path -LiteralPath (Join-Path $root '0.1.0')) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $root '0.2.0')) | Should -BeTrue
                (Test-Path -LiteralPath (Join-Path $root '0.3.0')) | Should -BeTrue
            }
            (Test-Path -LiteralPath $script:MockCliRoot) | Should -BeTrue

            # 2. Remove <= 0.3.0 (deletes remaining 0.2.0 and 0.3.0 -> zero versions remain -> auto-cleans CLI root)
            Uninstall-ArchiveLens -RemoveOlderThanOrEqualTo 'V0.3.0' -ModuleRoots $script:MockModuleRoots -InstallRoot $script:MockCliRoot -SkipEnvironmentPath -KeepLoadedSession -Confirm:$false

            foreach ($root in $script:MockModuleRoots)
            {
                (Test-Path -LiteralPath $root) | Should -BeFalse
            }
            (Test-Path -LiteralPath $script:MockCliRoot) | Should -BeFalse
        }
    }
}