#Requires -Version 7.0
<#
.SYNOPSIS
Publishes the unpackaged x64 app, self-contained browser native host and unchanged
shared browser extension into one new local directory. Does not create a release,
register a browser host, install an extension, or change version metadata.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$DotnetPath = 'dotnet',
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw "Publish directory already exists; choose a new directory: $output" }
$appProject = Join-Path $repository 'Windows/AMORA.Orbit/AMORA.Orbit.csproj'
$hostProject = Join-Path $repository 'Windows/AMORA.BrowserHost/AMORA.BrowserHost.csproj'
[xml]$appMetadata = Get-Content -LiteralPath $appProject -Raw
[xml]$hostMetadata = Get-Content -LiteralPath $hostProject -Raw
foreach ($name in @('Version', 'AssemblyVersion', 'FileVersion')) {
    $appNode = $appMetadata.SelectSingleNode("/Project/PropertyGroup/$name")
    $hostNode = $hostMetadata.SelectSingleNode("/Project/PropertyGroup/$name")
    if (-not $appNode -or -not $hostNode -or $appNode.InnerText.Trim() -cne $hostNode.InnerText.Trim()) {
        throw "Browser host and app $name metadata must agree."
    }
}
$extensionSource = Join-Path $repository 'BrowserExtensions/Chrome'
foreach ($name in @('manifest.json', 'service-worker.js', 'content.js')) {
    if (-not (Test-Path -LiteralPath (Join-Path $extensionSource $name) -PathType Leaf)) { throw "Shared browser extension file missing: $name" }
}

& $DotnetPath publish $appProject --configuration Release --runtime win-x64 --self-contained true /p:Platform=x64 /p:WindowsAppSDKSelfContained=true --output $output
if ($LASTEXITCODE -ne 0) { throw "AMORA publish failed with exit code $LASTEXITCODE. Partial output is retained for diagnostics." }
& $DotnetPath publish $hostProject --configuration Release --runtime win-x64 --self-contained true /p:Platform=x64 --output (Join-Path $output 'browser-host')
if ($LASTEXITCODE -ne 0) { throw "Browser native host publish failed with exit code $LASTEXITCODE. Partial output is retained for diagnostics." }
Copy-Item -LiteralPath $extensionSource -Destination (Join-Path $output 'browser-extension') -Recurse
Copy-Item -LiteralPath (Join-Path $repository 'Windows/RELEASE_MANIFEST.md') -Destination (Join-Path $output 'RELEASE_MANIFEST.md')
Write-Host "Published app, browser host and shared extension to: $output"
Write-Host 'Browser registration and extension installation remain explicit user actions inside AMORA.'
