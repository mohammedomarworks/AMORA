#Requires -Version 7.0
<#
.SYNOPSIS
Exercises release validation with an actual package and deliberately damaged
copies. Does not launch AMORA, modify the inputs, or remove test evidence.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PublishDirectory,
    [Parameter(Mandatory)][string]$ArchivePath,
    [string]$TestDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$publish = (Resolve-Path -LiteralPath $PublishDirectory).Path
$archive = (Resolve-Path -LiteralPath $ArchivePath).Path
if (-not $TestDirectory) {
    # Keep the hard-linked fixtures on the publish payload's volume by default.
    $TestDirectory = Join-Path (Split-Path -Parent $publish) ('amora-validator-tests-' + [Guid]::NewGuid().ToString('N'))
}
$testRoot = [IO.Path]::GetFullPath($TestDirectory)
if (Test-Path -LiteralPath $testRoot) { throw "Test directory already exists: $testRoot" }
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$validator = Join-Path $PSScriptRoot 'Validate-Release.ps1'
$archiveName = [IO.Path]::GetFileName($archive)

function Invoke-ExpectedFailure([string]$Name, [string]$DamagedArchive, [string]$MessagePattern, [string]$PublishFixture = $publish) {
    $reportPath = Join-Path $testRoot "$Name.json"
    try {
        & $validator -PublishDirectory $PublishFixture -ArchivePath $DamagedArchive `
            -ExtractionDirectory (Join-Path $testRoot "$Name-extracted") -ReportPath $reportPath
        throw "Expected $Name validation to fail."
    }
    catch {
        if ($_.Exception.Message -notmatch $MessagePattern) { throw }
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        if ($report.Result -ne 'Failed' -or $report.ProcessSmoke -ne 'Not requested') {
            throw "Incorrect failure evidence for $Name."
        }
        Write-Host "PASS: $Name rejected with expected failure"
    }
}

function New-PublishFixture([string]$Name, [string]$OmittedRelativePath) {
    # Hard links keep these negative fixtures small. Existing links are only read;
    # the one deliberately changed file is a newly created, unlinked file below.
    $fixture = [IO.Directory]::CreateDirectory((Join-Path $testRoot $Name)).FullName
    foreach ($file in Get-ChildItem -LiteralPath $publish -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($publish, $file.FullName).Replace('\', '/')
        if ($relative -ceq $OmittedRelativePath) { continue }
        $target = Join-Path $fixture $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        New-Item -ItemType HardLink -Path $target -Target $file.FullName | Out-Null
    }
    return $fixture
}

& $validator -PublishDirectory $publish -ArchivePath $archive `
    -ExtractionDirectory (Join-Path $testRoot 'valid-extracted') -ReportPath (Join-Path $testRoot 'valid.json')
Write-Host 'PASS: original package accepted'

$withoutHost = New-PublishFixture 'missing-browser-host-publish' 'browser-host/AMORA.BrowserHost.exe'
Invoke-ExpectedFailure 'missing-browser-host' $archive 'Required self-contained browser host file is missing: browser-host/AMORA.BrowserHost.exe' $withoutHost

$changedExtension = New-PublishFixture 'changed-extension-publish' 'browser-extension/content.js'
[IO.File]::WriteAllText((Join-Path $changedExtension 'browser-extension/content.js'), '// Deliberately changed extension fixture')
Invoke-ExpectedFailure 'changed-extension' $archive 'Packaged browser extension differs from shared source: content.js' $changedExtension

$tamperedRoot = [IO.Directory]::CreateDirectory((Join-Path $testRoot 'tampered')).FullName
$tamperedArchive = Join-Path $tamperedRoot $archiveName
Copy-Item -LiteralPath $archive -Destination $tamperedArchive
$zip = [IO.Compression.ZipFile]::Open($tamperedArchive, [IO.Compression.ZipArchiveMode]::Update)
try {
    $entry = $zip.GetEntry('resources.pri')
    if (-not $entry) { throw 'Test input requires root resources.pri.' }
    $entry.Delete()
    $replacement = $zip.CreateEntry('resources.pri')
    $writer = [IO.StreamWriter]::new($replacement.Open())
    try { $writer.Write('Deliberately corrupted resource index for validation regression test') }
    finally { $writer.Dispose() }
}
finally { $zip.Dispose() }
Invoke-ExpectedFailure 'tampered-content' $tamperedArchive 'ZIP content hash differs from publish output: resources.pri'

$traversalRoot = [IO.Directory]::CreateDirectory((Join-Path $testRoot 'traversal')).FullName
$traversalArchive = Join-Path $traversalRoot $archiveName
Copy-Item -LiteralPath $archive -Destination $traversalArchive
$zip = [IO.Compression.ZipFile]::Open($traversalArchive, [IO.Compression.ZipArchiveMode]::Update)
try {
    $entry = $zip.CreateEntry('../must-not-exist.txt')
    $writer = [IO.StreamWriter]::new($entry.Open())
    try { $writer.Write('Traversal must be rejected before extraction') }
    finally { $writer.Dispose() }
}
finally { $zip.Dispose() }
Invoke-ExpectedFailure 'path-traversal' $traversalArchive 'Unsafe archive path'
if (Test-Path -LiteralPath (Join-Path $testRoot 'must-not-exist.txt')) { throw 'Traversal file escaped extraction.' }
if (Test-Path -LiteralPath (Join-Path $testRoot 'path-traversal-extracted')) { throw 'Unsafe ZIP was extracted before validation.' }
Write-Host "All five release-validator cases passed. Evidence retained at: $testRoot"
