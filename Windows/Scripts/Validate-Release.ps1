#Requires -Version 7.0
<#
.SYNOPSIS
Validates an unpackaged, self-contained x64 AMORA release and its complete ZIP.
.DESCRIPTION
Never publishes, changes version metadata, overwrites an extraction directory, or
removes files. -ProcessSmokeTest starts the EXTRACTED executable and asks it to
close after the observation period. This is process evidence, not a visual or
functional UI acceptance test. Run in a disposable Windows test user when
existing AMORA settings or automations must not be exercised.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PublishDirectory,
    [Parameter(Mandatory)][string]$ArchivePath,
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),
    [string]$ExtractionDirectory,
    [string]$ReportPath,
    [switch]$ProcessSmokeTest,
    [ValidateRange(3, 60)][int]$ObservationSeconds = 12
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$publishRoot = (Resolve-Path -LiteralPath $PublishDirectory).Path
$archive = (Resolve-Path -LiteralPath $ArchivePath).Path
$repository = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$runId = [Guid]::NewGuid().ToString('N')
if (-not $ExtractionDirectory) {
    $ExtractionDirectory = Join-Path ([IO.Path]::GetTempPath()) "amora-release-$runId"
}
$extraction = [IO.Path]::GetFullPath($ExtractionDirectory)
if (Test-Path -LiteralPath $extraction) {
    throw "Extraction directory already exists; choose a new path: $extraction"
}
if (-not $ReportPath) {
    $ReportPath = Join-Path (Split-Path -Parent $extraction) "amora-validation-$runId.json"
}
$reportFile = [IO.Path]::GetFullPath($ReportPath)
if (Test-Path -LiteralPath $reportFile) { throw "Report already exists: $reportFile" }
$report = [ordered]@{
    SchemaVersion = 1
    StartedUtc = [DateTimeOffset]::UtcNow.ToString('O')
    PublishDirectory = $publishRoot
    ArchivePath = $archive
    ExtractionDirectory = $extraction
    PackageIntegrity = 'Not run'
    ProcessSmoke = 'Not requested'
    VisibleUi = 'Not verified by this script'
    FunctionalInteractions = 'Not verified by this script'
    Shutdown = 'Not tested'
}

function Read-ProjectValue([xml]$Document, [string]$Name) {
    $node = $Document.SelectSingleNode("/Project/PropertyGroup/$Name")
    if (-not $node) { throw "Missing project property: $Name" }
    return $node.InnerText.Trim()
}

function Assert-X64Pe([string]$File) {
    $stream = [IO.File]::OpenRead($File)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) {
            throw "Invalid DOS executable header: $File"
        }
        $stream.Position = 0x3c
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt ($stream.Length - 6)) {
            throw "Invalid PE offset: $File"
        }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "Invalid PE signature: $File" }
        $machine = $reader.ReadUInt16()
        if ($machine -ne 0x8664) { throw ('Expected x64 PE; found 0x{0:X4}: {1}' -f $machine, $File) }
    }
    finally { $reader.Dispose(); $stream.Dispose() }
}

function Get-RelativeFiles([string]$Directory) {
    return @(Get-ChildItem -LiteralPath $Directory -Recurse -File | ForEach-Object {
        [IO.Path]::GetRelativePath($Directory, $_.FullName).Replace('\', '/')
    } | Sort-Object)
}

try {
    [xml]$project = Get-Content -LiteralPath (Join-Path $repository 'Windows/AMORA.Orbit/AMORA.Orbit.csproj') -Raw
    [xml]$tests = Get-Content -LiteralPath (Join-Path $repository 'Windows/AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj') -Raw
    $version = Read-ProjectValue $project 'Version'
    $assemblyVersion = Read-ProjectValue $project 'AssemblyVersion'
    $fileVersion = Read-ProjectValue $project 'FileVersion'
    if ($version -cne (Read-ProjectValue $project 'InformationalVersion') -or
        $version -cne (Read-ProjectValue $tests 'Version')) { throw 'Project, informational and test versions differ.' }
    if ($version -notmatch '^\d+\.\d+\.\d+-beta(?:\.\d+)?$') { throw "Invalid Windows beta version: $version" }
    if ($assemblyVersion -notmatch '^\d+\.\d+\.\d+\.\d+$' -or $assemblyVersion -cne $fileVersion) {
        throw 'Assembly and file versions must be equal four-part numeric versions.'
    }
    $archiveName = "AMORA.Orbit-v$version-win-x64.zip"
    if ([IO.Path]::GetFileName($archive) -cne $archiveName) { throw "Expected archive filename $archiveName" }
    $report.Version = $version
    $report.ArchiveSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $report.ArchiveBytes = (Get-Item -LiteralPath $archive).Length
    if ($report.ArchiveBytes -lt 1000000) { throw 'Archive is too small for a self-contained WinUI package.' }

    $required = @('AMORA.Orbit.exe', 'AMORA.Orbit.dll', 'AMORA.Orbit.deps.json',
        'AMORA.Orbit.runtimeconfig.json', 'resources.pri', 'RELEASE_MANIFEST.md',
        'coreclr.dll', 'hostfxr.dll', 'hostpolicy.dll', 'clrjit.dll')
    foreach ($file in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $publishRoot $file) -PathType Leaf)) {
            throw "Required self-contained publish file is missing: $file"
        }
    }
    $publishFiles = @(Get-ChildItem -LiteralPath $publishRoot -Recurse -File)
    $xamlRuntime = @($publishFiles | Where-Object Name -IEQ 'Microsoft.UI.Xaml.dll')
    if ($xamlRuntime.Count -eq 0) { throw 'WinUI XAML runtime is missing.' }
    if (@($publishFiles | Where-Object Name -Like 'Microsoft.WindowsAppRuntime*.dll').Count -eq 0) {
        throw 'Windows App SDK runtime is missing.'
    }
    foreach ($file in @('AMORA.Orbit.exe', 'coreclr.dll', 'hostfxr.dll', 'hostpolicy.dll', 'clrjit.dll')) {
        Assert-X64Pe (Join-Path $publishRoot $file)
    }
    foreach ($file in $xamlRuntime) { Assert-X64Pe $file.FullName }
    # The browser integration is an actual shipped dependency. A main app ZIP
    # without its native host/runtime or shared extension is incomplete.
    [xml]$hostProject = Get-Content -LiteralPath (Join-Path $repository 'Windows/AMORA.BrowserHost/AMORA.BrowserHost.csproj') -Raw
    foreach ($name in @('Version', 'AssemblyVersion', 'FileVersion')) {
        if ((Read-ProjectValue $hostProject $name) -cne (Read-ProjectValue $project $name)) {
            throw "Browser host and app $name metadata differ."
        }
    }
    $hostRoot = Join-Path $publishRoot 'browser-host'
    foreach ($file in @('AMORA.BrowserHost.exe', 'AMORA.BrowserHost.dll', 'AMORA.BrowserHost.deps.json',
        'AMORA.BrowserHost.runtimeconfig.json', 'coreclr.dll', 'hostfxr.dll', 'hostpolicy.dll', 'clrjit.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $hostRoot $file) -PathType Leaf)) {
            throw "Required self-contained browser host file is missing: browser-host/$file"
        }
    }
    foreach ($file in @('AMORA.BrowserHost.exe', 'coreclr.dll', 'hostfxr.dll', 'hostpolicy.dll', 'clrjit.dll')) {
        Assert-X64Pe (Join-Path $hostRoot $file)
    }
    $hostVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $hostRoot 'AMORA.BrowserHost.dll')).ProductVersion
    if ($hostVersion -cne $version -and -not $hostVersion.StartsWith("$version+", [StringComparison]::Ordinal)) {
        throw "Published browser host version '$hostVersion' differs from source '$version'."
    }
    $extensionSource = Join-Path $repository 'BrowserExtensions/Chrome'
    $extensionRoot = Join-Path $publishRoot 'browser-extension'
    $extensionFiles = @(Get-RelativeFiles $extensionSource)
    foreach ($file in $extensionFiles) {
        $packagedFile = Join-Path $extensionRoot $file
        if (-not (Test-Path -LiteralPath $packagedFile -PathType Leaf) -or
            (Get-FileHash -LiteralPath $packagedFile -Algorithm SHA256).Hash -cne
            (Get-FileHash -LiteralPath (Join-Path $extensionSource $file) -Algorithm SHA256).Hash) {
            throw "Packaged browser extension differs from shared source: $file"
        }
    }
    if (Compare-Object -ReferenceObject $extensionFiles -DifferenceObject @(Get-RelativeFiles $extensionRoot)) {
        throw 'Packaged browser extension file list differs from shared source.'
    }
    $extensionManifest = Get-Content -LiteralPath (Join-Path $extensionRoot 'manifest.json') -Raw | ConvertFrom-Json
    $keyHash = [Security.Cryptography.SHA256]::HashData([Convert]::FromBase64String($extensionManifest.key))
    $extensionIdentity = [Text.StringBuilder]::new()
    foreach ($value in $keyHash[0..15]) {
        [void]$extensionIdentity.Append([char](97 + ($value -shr 4)))
        [void]$extensionIdentity.Append([char](97 + ($value -band 15)))
    }
    if ($extensionIdentity.ToString() -cne 'pcjbhandogggbhkjdfpcngenaaediend') {
        throw 'Shared extension identity does not match the pinned browser native host origin.'
    }
    $report.BrowserHost = 'Passed: self-contained x64 host and matching version present; registration/extension behavior not tested by this script'
    $report.BrowserExtension = "Passed: $($extensionFiles.Count) files match shared source; pinned identity $extensionIdentity"
    $productVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $publishRoot 'AMORA.Orbit.dll')).ProductVersion
    if ($productVersion -cne $version -and -not $productVersion.StartsWith("$version+", [StringComparison]::Ordinal)) {
        throw "Published assembly version '$productVersion' differs from source '$version'."
    }
    $manifest = (Get-Content -LiteralPath (Join-Path $publishRoot 'RELEASE_MANIFEST.md') -Raw).Replace("`r", '')
    foreach ($pattern in @(
        ('(?m)^\*\*Package:\*\*\s+`' + [regex]::Escape($archiveName) + '`$'),
        ('(?m)^\*\*Version:\*\*\s+`' + [regex]::Escape($version) + '`$'))) {
        if ($manifest -notmatch $pattern) { throw 'Published release manifest metadata does not match the package.' }
    }
    if ((Get-FileHash -LiteralPath (Join-Path $publishRoot 'RELEASE_MANIFEST.md')).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $repository 'Windows/RELEASE_MANIFEST.md')).Hash) {
        throw 'Published release manifest differs from the checked-out source manifest.'
    }

    # Reject path traversal, drive-qualified entries, NTFS streams and ambiguous
    # duplicate paths before creating anything from untrusted ZIP entries.
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $entryPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            $relative = $entry.FullName.Replace('\', '/')
            if ($relative.StartsWith('/') -or $relative.Contains(':') -or
                @($relative.Split('/') | Where-Object { $_ -eq '..' -or $_ -eq '.' }).Count -gt 0) {
                throw "Unsafe archive path: $relative"
            }
            $full = [IO.Path]::GetFullPath((Join-Path $extraction $relative))
            if (-not $full.StartsWith($extraction.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar,
                    [StringComparison]::OrdinalIgnoreCase)) { throw "Archive path escapes extraction root: $relative" }
            if (-not $entryPaths.Add($relative.TrimEnd('/'))) { throw "Duplicate archive path: $relative" }
        }
    }
    finally { $zip.Dispose() }
    Expand-Archive -LiteralPath $archive -DestinationPath $extraction
    $published = @(Get-RelativeFiles $publishRoot)
    $archived = @(Get-RelativeFiles $extraction)
    if (Compare-Object -ReferenceObject $published -DifferenceObject $archived) {
        throw 'ZIP file list differs from publish output.'
    }
    foreach ($relative in $published) {
        if ((Get-FileHash -LiteralPath (Join-Path $publishRoot $relative) -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath (Join-Path $extraction $relative) -Algorithm SHA256).Hash) {
            throw "ZIP content hash differs from publish output: $relative"
        }
    }
    $forbidden = @(Get-ChildItem -LiteralPath $extraction -Recurse -File | Where-Object {
        $_.Extension -in @('.apikey', '.key', '.token', '.user') -or $_.Name -match 'secret'
    })
    if ($forbidden.Count -gt 0) { throw 'Prohibited secret or development files found in package.' }
    $report.FileCount = $published.Count
    $report.PackageIntegrity = 'Passed: complete ZIP matches publish output; x64 and metadata validated'

    if ($ProcessSmokeTest) {
        if (-not $IsWindows) { throw 'Process smoke test requires Windows.' }
        if (Get-Process -Name 'AMORA.Orbit' -ErrorAction SilentlyContinue) {
            throw 'AMORA is already running; close it before testing the extracted package.'
        }
        $started = Get-Date
        $crashPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AMORA/Logs/crash.log'
        $priorCrashLength = if (Test-Path -LiteralPath $crashPath) { (Get-Item -LiteralPath $crashPath).Length } else { 0 }
        $process = Start-Process -FilePath (Join-Path $extraction 'AMORA.Orbit.exe') -WorkingDirectory $extraction -WindowStyle Hidden -PassThru
        $report.ProcessId = $process.Id
        try {
            if ($process.WaitForExit($ObservationSeconds * 1000)) {
                throw "Extracted application exited during startup (exit code $($process.ExitCode))."
            }
            $process.Refresh()
            $report.WindowHandleObserved = $process.MainWindowHandle -ne [IntPtr]::Zero
            $report.ObservationSeconds = $ObservationSeconds
            $report.ProcessSmoke = 'Passed: extracted executable remained running; UI still requires inspection'
            $crashChanged = (Test-Path -LiteralPath $crashPath) -and
                ((Get-Item -LiteralPath $crashPath).Length -ne $priorCrashLength)
            $report.NewCrashLogContent = $crashChanged
            if ($crashChanged) { throw "New crash log content appeared during smoke test: $crashPath" }
            # Event contents are not copied into the report: they may contain private data.
            try {
                $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $started; Level = @(1, 2) } -ErrorAction Stop |
                    Where-Object { $_.Message -match 'AMORA\.Orbit' })
                $report.ApplicationErrorEvents = @($events | Select-Object Id, ProviderName, TimeCreated)
                if ($events.Count -gt 0) { throw 'Windows Application log contains AMORA errors from this run.' }
            }
            catch {
                if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { $report.ApplicationErrorEvents = @() }
                elseif ($_.Exception.Message -eq 'Windows Application log contains AMORA errors from this run.') { throw }
                else { $report.EventLogCheck = 'Unavailable; inspect Event Viewer manually' }
            }
        }
        finally {
            if (-not $process.HasExited) {
                $closeRequested = $process.CloseMainWindow()
                if ($closeRequested -and $process.WaitForExit(5000)) { $report.Shutdown = 'Closed through window close request' }
                else {
                    # Only terminate the exact process created above. This is recorded
                    # as forced cleanup and never reported as clean lifecycle evidence.
                    Stop-Process -InputObject $process -Force
                    $report.Shutdown = 'Forced cleanup; graceful shutdown NOT verified'
                }
            }
            else { $report.Shutdown = "Process exited with code $($process.ExitCode)" }
            $process.Dispose()
        }
    }
    $report.Result = 'Passed for the checks requested; manual UI acceptance remains required'
}
catch {
    $report.Result = 'Failed'
    $report.Failure = $_.Exception.Message
    throw
}
finally {
    $report.FinishedUtc = [DateTimeOffset]::UtcNow.ToString('O')
    $reportParent = Split-Path -Parent $reportFile
    [IO.Directory]::CreateDirectory($reportParent) | Out-Null
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportFile -Encoding utf8
    Write-Host "Validation report: $reportFile"
    Write-Host "Extracted package (retained for UI testing): $extraction"
}
