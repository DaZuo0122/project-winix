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

# TODO: Phase 7 — implement full teardown logic
# 1. Load state file (best-effort if missing)
# 2. Remove WT profile by GUID
# 3. Remove / restore dotfiles
# 4. Remove PATH entries
# 5. Optionally remove JetBrains Mono font
# 6. Optionally purge C:\msys64 and Cargo bins
# 7. Offer rstrui.exe

Write-WinixLog -Level Warning -Message 'Uninstall logic is a stub; no changes were made.'

if ($Wait) {
    Write-Host ''
    Write-Host 'Press any key to exit...' -ForegroundColor Cyan
    $null = [System.Console]::ReadKey($true)
}
