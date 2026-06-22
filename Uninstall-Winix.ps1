#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param (
    [switch]$PurgeMsys2,
    [switch]$PurgeCargoBins,
    [switch]$RestoreBackups,
    [switch]$Wait
)

<#
.SYNOPSIS
    Project Winix uninstaller / rollback helper.
.DESCRIPTION
    Removes the Windows Terminal profile, extracted dotfiles, PATH entries,
    and optionally purges MSYS2 / Cargo binaries installed by Winix.
#>

$script:Version = "0.1.0"
$script:RootDir = $PSScriptRoot
$script:ModulesDir = Join-Path $script:RootDir 'modules'
$script:StateDir = Join-Path $env:USERPROFILE '.winix'
$script:StateFile = Join-Path $script:StateDir 'state.json'

Import-Module (Join-Path $script:ModulesDir 'Logging.psm1') -Force -ErrorAction Stop

Write-WinixLog -Level Info -Message 'Project Winix uninstaller started.'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-WinixTerminalSettingsPath {
    $candidatePaths = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($path in $candidatePaths) {
        if (Test-Path $path) { return $path }
    }
    return $candidatePaths[0]
}

function Get-WinixDeterministicGuid {
    $namespaceBytes = [Guid]::Parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8').ToByteArray()
    $nameBytes = [System.Text.Encoding]::UTF8.GetBytes('Project Winix')
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $hash = $sha1.ComputeHash($namespaceBytes + $nameBytes)
    $hash[7] = ($hash[7] -band 0x0F) -bor 0x50
    $hash[8] = ($hash[8] -band 0x3F) -bor 0x80
    [byte[]]$guidBytes = $hash[0..15]
    return [Guid]::new($guidBytes)
}

function Remove-WinixTerminalProfile {
    param (
        [string]$SettingsPath,
        [string]$Guid
    )

    if (-not (Test-Path $SettingsPath)) {
        Write-WinixLog -Level Warning -Message "Windows Terminal settings not found at $SettingsPath; skipping profile removal."
        return
    }

    $settings = Get-Content -Path $SettingsPath -Raw | ConvertFrom-Json -AsHashtable
    if (-not $settings -or -not $settings.ContainsKey('profiles') -or -not $settings['profiles'].ContainsKey('list')) {
        Write-WinixLog -Level Warning -Message 'No profiles list found in Windows Terminal settings; skipping.'
        return
    }

    $originalCount = $settings['profiles']['list'].Count
    $settings['profiles']['list'] = [System.Collections.ArrayList]::new(
        ($settings['profiles']['list'] | Where-Object { $_.guid -ne $Guid -and $_.guid -ne ($Guid -replace '\{', '') })
    )

    if ($settings['profiles']['list'].Count -lt $originalCount) {
        $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $SettingsPath -Encoding UTF8
        Write-WinixLog -Level Success -Message "Removed Winix profile ($Guid) from Windows Terminal settings."
    }
    else {
        Write-WinixLog -Level Info -Message 'Winix profile was not found in Windows Terminal settings; nothing to remove.'
    }
}

function Restore-WinixBackup {
    param (
        [string]$BackupDir,
        [string]$FileName
    )

    $backup = Get-ChildItem -Path $BackupDir -Filter "$FileName_*" -File |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1

    if (-not $backup) {
        Write-WinixLog -Level Warning -Message "No backup found for $FileName in $BackupDir."
        return $false
    }

    $destPath = Join-Path $env:USERPROFILE $FileName
    Copy-Item -Path $backup.FullName -Destination $destPath -Force
    Write-WinixLog -Level Success -Message "Restored $FileName from $($backup.FullName)."
    return $true
}

function Remove-WinixUserPathEntries {
    param (
        [string[]]$Paths
    )

    $regPath = 'HKCU:\Environment'
    $currentPath = (Get-ItemProperty -Path $regPath -Name 'Path' -ErrorAction SilentlyContinue).Path
    if ([string]::IsNullOrWhiteSpace($currentPath)) { return }

    $segments = $currentPath -split ';' | Where-Object { $_ -ne '' }
    $remaining = [System.Collections.ArrayList]::new()
    $removed = [System.Collections.ArrayList]::new()

    foreach ($segment in $segments) {
        $normalizedSegment = $segment.TrimEnd('\')
        $match = $false
        foreach ($path in $Paths) {
            if ($normalizedSegment -eq $path.TrimEnd('\')) {
                $match = $true
                [void]$removed.Add($segment)
                break
            }
        }
        if (-not $match) {
            [void]$remaining.Add($segment)
        }
    }

    if ($removed.Count -gt 0) {
        $newPath = $remaining -join ';'
        Set-ItemProperty -Path $regPath -Name 'Path' -Value $newPath -Type ExpandString -Force
        Write-WinixLog -Level Success -Message "Removed PATH entries: $($removed -join '; ')"

        # Broadcast change
        $code = @'
using System;
using System.Runtime.InteropServices;
public class EnvChange {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
'@
        try {
            Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
            $HWND_BROADCAST = [IntPtr]::Zero -bor 0xFFFF
            $result = [UIntPtr]::Zero
            [void][EnvChange]::SendMessageTimeout($HWND_BROADCAST, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
        }
        catch {
            Write-WinixLog -Level Warning -Message "Failed to broadcast PATH change: $_"
        }
    }
    else {
        Write-WinixLog -Level Info -Message 'No Winix PATH entries found to remove.'
    }
}

function Remove-WinixFont {
    param (
        [hashtable]$FontState
    )

    if (-not $FontState -or -not $FontState.ContainsKey('Files')) {
        Write-WinixLog -Level Info -Message 'No font state recorded; skipping font removal.'
        return
    }

    $regPath = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    foreach ($fontFile in $FontState.Files) {
        if (Test-Path $fontFile) {
            Remove-Item -Path $fontFile -Force -ErrorAction SilentlyContinue
            Write-WinixLog -Level Info -Message "Removed font file $fontFile"
        }

        # Find and remove the registry entry pointing to this file
        $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if ($props) {
            foreach ($propName in $props.PSObject.Properties.Name) {
                if ($props.$propName -eq $fontFile) {
                    Remove-ItemProperty -Path $regPath -Name $propName -Force -ErrorAction SilentlyContinue
                    Write-WinixLog -Level Info -Message "Removed font registry entry $propName"
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Load state
# ---------------------------------------------------------------------------
$state = @{}
if (Test-Path $script:StateFile) {
    try {
        $state = Get-Content $script:StateFile -Raw | ConvertFrom-Json -AsHashtable
        Write-WinixLog -Level Info -Message "Loaded state file: $script:StateFile"
    }
    catch {
        Write-WinixLog -Level Warning -Message "Failed to parse state file: $_. Using best-effort detection."
    }
}
else {
    Write-WinixLog -Level Warning -Message 'State file not found; using best-effort detection.'
}

$guid = if ($state.ContainsKey('Guid')) { $state.Guid } else { "{$(Get-WinixDeterministicGuid)}" }
$settingsPath = if ($state.ContainsKey('TerminalSettingsPath')) { $state.TerminalSettingsPath } else { Get-WinixTerminalSettingsPath }
$backupDir = if ($state.ContainsKey('BackupDir')) { $state.BackupDir } else { Join-Path $env:USERPROFILE '.winix_backups' }
$addedPaths = if ($state.ContainsKey('AddedPaths')) { $state.AddedPaths } else { @('C:\msys64\mingw64\bin', 'C:\msys64\usr\bin') }
$deployedAssets = if ($state.ContainsKey('DeployedAssets')) { $state.DeployedAssets } else { @('.bashrc', '.bash_profile') }
$fontState = if ($state.ContainsKey('InstalledFont')) { $state.InstalledFont } else { $null }

Write-WinixLog -Level Info -Message "Using GUID: $guid"
Write-WinixLog -Level Info -Message "Using Windows Terminal settings: $settingsPath"

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($settingsPath, 'Remove Winix Windows Terminal profile')) {
    Remove-WinixTerminalProfile -SettingsPath $settingsPath -Guid $guid
}

# Dotfiles
foreach ($asset in $deployedAssets) {
    $destPath = Join-Path $env:USERPROFILE $asset
    if (Test-Path $destPath) {
        if ($RestoreBackups -and (Test-Path $backupDir)) {
            $restored = Restore-WinixBackup -BackupDir $backupDir -FileName $asset
            if (-not $restored) {
                Remove-Item -Path $destPath -Force -ErrorAction SilentlyContinue
                Write-WinixLog -Level Info -Message "Removed $destPath (no backup to restore)."
            }
        }
        else {
            Remove-Item -Path $destPath -Force -ErrorAction SilentlyContinue
            Write-WinixLog -Level Info -Message "Removed $destPath."
        }
    }
    else {
        Write-WinixLog -Level Info -Message "Asset file not found, skipping: $destPath"
    }
}

# PATH
if ($PSCmdlet.ShouldProcess('user PATH', 'Remove Winix PATH entries')) {
    Remove-WinixUserPathEntries -Paths $addedPaths
}

# Font
if ($PSCmdlet.ShouldProcess('JetBrains Mono', 'Remove Winix-installed font')) {
    Remove-WinixFont -FontState $fontState
}

# Optional: purge MSYS2
if ($PurgeMsys2) {
    if ($PSCmdlet.ShouldProcess('C:\msys64', 'Delete MSYS2 installation')) {
        if (Test-Path 'C:\msys64') {
            Remove-Item -Path 'C:\msys64' -Recurse -Force -ErrorAction SilentlyContinue
            Write-WinixLog -Level Success -Message 'Removed C:\msys64.'
        }
        else {
            Write-WinixLog -Level Info -Message 'C:\msys64 not found; nothing to purge.'
        }
    }
}

# Optional: purge Cargo binaries
if ($PurgeCargoBins) {
    if ($PSCmdlet.ShouldProcess('~/.cargo/bin', 'Delete Cargo binaries')) {
        $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
        $winixBins = @('brush.exe', 'bat.exe', 'eza.exe', 'fd.exe', 'rg.exe', 'zellij.exe')
        foreach ($bin in $winixBins) {
            $binPath = Join-Path $cargoBin $bin
            if (Test-Path $binPath) {
                Remove-Item -Path $binPath -Force -ErrorAction SilentlyContinue
                Write-WinixLog -Level Info -Message "Removed $binPath"
            }
        }
    }
}

# Remove state file last
if ($PSCmdlet.ShouldProcess($script:StateFile, 'Remove Winix state file')) {
    if (Test-Path $script:StateFile) {
        Remove-Item -Path $script:StateFile -Force -ErrorAction SilentlyContinue
        Write-WinixLog -Level Info -Message "Removed state file $script:StateFile"
    }
}

Write-WinixLog -Level Success -Message 'Project Winix uninstallation completed.'

# Offer OS rollback
$choice = Read-Host 'Launch Windows System Restore to revert OS state? (y/N)'
if ($choice -eq 'y' -or $choice -eq 'Y') {
    Start-Process 'rstrui.exe'
}

if ($Wait) {
    Write-Host ''
    Write-Host 'Press any key to exit...' -ForegroundColor Cyan
    $null = [System.Console]::ReadKey($true)
}
