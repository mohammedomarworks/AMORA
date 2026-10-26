# Windows verification

The Windows app and test projects target .NET 8 and Windows SDK 19041. CI uses
the .NET 8 SDK and MSBuild. The test project selects the NuGet-supplied Windows
App SDK build tasks so non-UI xUnit tests also build with `dotnet` on Windows
without Visual Studio. Tests inspect XAML source fixtures; they do not load a
WinUI window. The application still compiles its XAML and generates its normal
`resources.pri`.

From the repository root, with .NET 8 available:

```powershell
dotnet restore Windows/AMORA.sln /p:Configuration=Release /p:Platform=x64
dotnet build Windows/AMORA.sln --configuration Release /p:Platform=x64 --no-restore
dotnet test Windows/AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj --configuration Release --no-build --no-restore /p:Platform=x64 --logger 'trx;LogFileName=windows-release.trx'
./Windows/Scripts/Publish-Release.ps1 -OutputDirectory ./publish/win-x64
[xml]$amoraProject = Get-Content Windows/AMORA.Orbit/AMORA.Orbit.csproj
$amoraVersion = $amoraProject.Project.PropertyGroup.Version
$amoraArchive = "AMORA.Orbit-v$amoraVersion-win-x64.zip"
Compress-Archive -Path ./publish/win-x64/* -DestinationPath $amoraArchive
./Windows/Scripts/Validate-Release.ps1 -PublishDirectory ./publish/win-x64 -ArchivePath $amoraArchive -ExtractionDirectory ./work/zip-acceptance -ReportPath ./work/package-validation.json
```

Choose fresh extraction/report paths on each validation. The validator refuses
to overwrite them and retains the extracted application for interactive testing.
It checks version agreement, actual assembly metadata, required self-contained
runtimes, native x64 PE headers, full ZIP file lists and SHA-256 hashes, unsafe
ZIP paths, and prohibited secret/development filenames. It does not publish or
change tags. The release workflow's existing validations remain in force.

`Publish-Release.ps1` also publishes the actual `AMORA.BrowserHost` executable
and its self-contained .NET runtime under `browser-host/`, and copies the
unchanged shared `BrowserExtensions/Chrome` files under `browser-extension/`.
Choose a fresh output directory; partial failed output is retained for diagnosis,
never silently reused. Pass `-DotnetPath` when the SDK is installed at a task-local
path. The validator requires the host payload, matching host/app version and x64
architecture, complete extension/source hash agreement and the pinned extension
identity. A package missing these is incomplete even if the main app launches.

Packaging does not register the native host or install an extension. Registration
is an explicit per-user action in AMORA; actual Chrome/Edge extension connection,
request acknowledgement, media capability and permission behavior still require
separate native end-to-end acceptance. The Windows CI publish step uses the same
helper and retains all previous version/runtime/archive/security checks.

To exercise the validator itself against a valid package:

```powershell
./Windows/Scripts/Test-ReleaseValidation.ps1 -PublishDirectory ./publish/win-x64 -ArchivePath $amoraArchive
```

This accepts the original package and rejects four negative fixtures: a missing
browser host, a changed extension script, a damaged resource index, and a path
traversal entry. The two publish fixtures use read-only hard links to conserve
space; deliberately changed content is written only to a new unlinked file.
It never executes these copies or modifies original publish/archive files.
The default test directory is a new sibling of the publish directory so hard
links stay on the same volume. A custom `-TestDirectory` must use that volume.

An optional `-ProcessSmokeTest` on `Validate-Release.ps1` runs the **extracted**
executable, observes it for 12 seconds, checks for new crash-log content and
AMORA Application-log errors, and requests window closure. It refuses to run
while another AMORA process exists. It records forced cleanup as a lifecycle
failure to verify, rather than claiming graceful shutdown. Existing AMORA
settings and user-enabled automations may load; use a disposable Windows user
for isolated acceptance. The smoke process is started hidden and the report
explicitly marks visible UI and functional behavior as unverified.

## Required interactive acceptance

Launch the executable from the validated extraction directory. Inspect the
collapsed capsule and expanded interface and capture both. Exercise expansion,
Escape, keyboard focus, a local command, timer pause/resume/cancel, settings and
automation panels, tray access, and Ctrl+Alt+O. Confirm media only with a real
active Windows media session; an empty player is not playback acceptance.
Check battery/no-battery and unavailable telemetry displays against the machine.
Exercise multi-monitor disconnect, DPI changes, fullscreen avoidance, reduced
motion, and shutdown where suitable hardware/settings are available.

Record exact commands, source revision/working-tree changes, test results,
screenshots, package hash, process startup, visible UI, and each tested
interaction separately. Inspect `%LOCALAPPDATA%\AMORA\Logs\crash.log` and the
Windows Application event log for the same launch interval. A passing build,
unit suite, package validator, or process smoke does **not** establish visual or
functional parity, nor does it authorize a public release.
