[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$TargetDir,

    [string]$Version = 'latest',

    [switch]$BuildFromSource
)

Import-Module (Join-Path $PSScriptRoot '..' '..' 'modules' 'Logging.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '..' 'modules' 'Downloader.psm1') -Force

$toolName = 'fd-find'
$exePath = Join-Path $TargetDir 'fd.exe'

# 1. Check existing
if (Test-Path $exePath) {
    $v = & $exePath --version 2>$null
    Write-WinixLog -Level Info -Message "fd already present at $exePath ($v); skipping."
    return
}

# 2. Source build
if ($BuildFromSource) {
    Install-WinixToolFromSource -CrateName $toolName
    return
}

# 3. GitHub release download
Write-WinixLog -Level Info -Message 'Fetching fd release from GitHub...'
$release = Invoke-WinixGitHubApi -Repo 'sharkdp/fd'
if (-not $release) {
    Write-WinixLog -Level Warning -Message 'Falling back to source build for fd.'
    Install-WinixToolFromSource -CrateName $toolName
    return
}

$asset = Find-WinixReleaseAsset -Release $release -Patterns @("fd-$($release.tag_name)-x86_64-pc-windows-msvc.zip", "fd-$($release.tag_name)-x86_64-pc-windows-gnu.zip")
if (-not $asset) {
    Write-WinixLog -Level Warning -Message "No compatible fd binary found in release $($release.tag_name); falling back to source build."
    Install-WinixToolFromSource -CrateName $toolName
    return
}

$archivePath = Join-Path $env:TEMP $asset.name
Write-WinixLog -Level Info -Message "Downloading $($asset.browser_download_url)..."
try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath -UseBasicParsing
}
catch {
    Write-WinixLog -Level Warning -Message "Failed to download fd binary: $_. Falling back to source build."
    Install-WinixToolFromSource -CrateName $toolName
    return
}

Expand-WinixArchiveToTarget -ArchivePath $archivePath -TargetDir $TargetDir -ExePattern 'fd.exe'

# 4. Verify
if (Test-Path $exePath) {
    $v = & $exePath --version 2>$null
    Write-WinixLog -Level Success -Message "fd ready: $v"
}
else {
    Write-WinixLog -Level Warning -Message 'fd binary was not found after extraction; falling back to source build.'
    Install-WinixToolFromSource -CrateName $toolName
}
