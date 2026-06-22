<#
.SYNOPSIS
    Consent gate for Project Winix.
.DESCRIPTION
    Detects existing configurations and tools that may conflict with or be
    overwritten by Winix. Returns the conflicts so the GUI or CLI can obtain
    explicit user consent before proceeding.
#>

function Test-WinixConsentGate {
    <#
    .SYNOPSIS
        Scans for existing configs/tools and determines whether installation
        may proceed.
    .OUTPUTS
        PSCustomObject with properties:
            - Conflicts    : array of detected conflict descriptions
            - HasConflicts : boolean
            - Approved     : boolean (always $false; caller must obtain consent)
    #>
    [CmdletBinding()]
    param ()

    $conflicts = [System.Collections.ArrayList]::new()

    # 1. Existing Unix dotfiles
    $bashrcPath = Join-Path $env:USERPROFILE '.bashrc'
    if (Test-Path $bashrcPath) {
        [void]$conflicts.Add("Existing .bashrc found at $bashrcPath. It will be backed up and overwritten.")
    }

    $bashProfilePath = Join-Path $env:USERPROFILE '.bash_profile'
    if (Test-Path $bashProfilePath) {
        [void]$conflicts.Add("Existing .bash_profile found at $bashProfilePath. It will be backed up and overwritten.")
    }

    # 2. Existing Windows Terminal settings
    $wtPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )

    foreach ($wtPath in $wtPaths) {
        if (Test-Path $wtPath) {
            [void]$conflicts.Add("Existing Windows Terminal settings found at $wtPath. They will be backed up and merged.")
            break
        }
    }

    # 3. Existing MSYS2 / MinGW64 root
    if (Test-Path 'C:\msys64') {
        [void]$conflicts.Add("Existing C:\msys64 directory found. It may be modified or overwritten.")
    }

    # 4. Existing Git outside C:\msys64
    $gitCommand = Get-Command 'git.exe' -ErrorAction SilentlyContinue
    if ($gitCommand -and $gitCommand.Source -notlike 'C:\msys64\*') {
        [void]$conflicts.Add("Existing Git installation found at $($gitCommand.Source). MinGW64 Git will NOT be installed to avoid conflicts.")
    }

    return [PSCustomObject]@{
        Conflicts    = $conflicts.ToArray()
        HasConflicts = $conflicts.Count -gt 0
        Approved     = $false
    }
}

function Show-WinixConsentWarning {
    <#
    .SYNOPSIS
        Prints the consent-gate warnings in the CLI.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [array]$Conflicts
    )

    Write-Host ''
    Write-Host '--------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host '  Project Winix - Pre-Installation Warning' -ForegroundColor Yellow
    Write-Host '--------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'The following existing configurations or tools were detected:' -ForegroundColor Yellow

    foreach ($conflict in $Conflicts) {
        Write-Host "  - $conflict" -ForegroundColor DarkYellow
    }

    Write-Host ''
    Write-Host 'Existing files will be backed up to ~/.winix_backups/ before being overwritten.' -ForegroundColor Cyan
    Write-Host ''
}

Export-ModuleMember -Function Test-WinixConsentGate, Show-WinixConsentWarning
