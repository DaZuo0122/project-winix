function Invoke-WinixInstallation {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [switch]$InstallCore,
        [switch]$InstallAdvanced,
        [switch]$InstallAll,
        [switch]$InstallBat,
        [switch]$InstallEza,
        [switch]$InstallFd,
        [switch]$InstallRipgrep,
        [switch]$InstallZellij,
        [switch]$BuildFromSource,
        [switch]$SkipRestorePoint,
        [switch]$Force,
        [switch]$DryRun,
        [string]$ScriptsDir = (Join-Path $PSScriptRoot '..'),
        [object]$LogBox
    )

    # Normalize
    if ($InstallAll) {
        $InstallCore = $true
        $InstallAdvanced = $true
    }

    if ($InstallAdvanced) {
        $InstallBat = $true
        $InstallEza = $true
        $InstallFd = $true
        $InstallRipgrep = $true
        $InstallZellij = $true
    }

    if ($DryRun) {
        Write-WinixLog -Level Warning -Message '==================== DRY RUN MODE ====================' -LogBox $LogBox
        Write-WinixLog -Level Warning -Message 'No system changes will be made. Logging planned actions only.' -LogBox $LogBox
        Write-WinixLog -Level Warning -Message '======================================================' -LogBox $LogBox
    }

    $commonParams = @{}
    if ($WhatIfPreference -or $DryRun) {
        $commonParams['WhatIf'] = $true
    }

    # Consent gate
    Import-Module (Join-Path $PSScriptRoot '..\..\modules\ConsentGate.psm1') -Force
    $consent = Test-WinixConsentGate
    if ($consent.HasConflicts -and -not $Force) {
        Show-WinixConsentWarning -Conflicts $consent.Conflicts
        throw 'Conflicts detected. Check the consent box to acknowledge that existing configs will be backed up and overwritten.'
    }

    if ($consent.HasConflicts) {
        Show-WinixConsentWarning -Conflicts $consent.Conflicts
        Write-WinixLog -Level Warning -Message 'Consent acknowledged; proceeding with backups and overwrite.' -LogBox $LogBox
    }

    # System Restore Point
    if ($DryRun) {
        Write-WinixLog -Level Info -Message '[DRY RUN] Would create a System Restore Point.' -LogBox $LogBox
    }
    else {
        Import-Module (Join-Path $PSScriptRoot '..\..\modules\Snapshot.psm1') -Force
        if (-not $SkipRestorePoint) {
            Write-WinixLog -Level Info -Message 'Creating mandatory System Restore Point...' -LogBox $LogBox
            $rp = New-WinixRestorePoint
            if ($rp.Success) {
                Write-WinixLog -Level Success -Message $rp.Message -LogBox $LogBox
            }
            else {
                throw $rp.Message
            }
        }
        else {
            Write-WinixLog -Level Warning -Message 'Skipping System Restore Point creation as requested.' -LogBox $LogBox
        }
    }

    # Dot-source core installers
    $coreScripts = @(
        'Install-Msys2.ps1',
        'Install-Rust.ps1',
        'Install-Brush.ps1',
        'Install-Font.ps1',
        'Install-Dotfiles.ps1',
        'Inject-Terminal.ps1',
        'Update-UserPath.ps1'
    )

    foreach ($scriptName in $coreScripts) {
        $scriptPath = Join-Path $ScriptsDir "core\$scriptName"
        if (Test-Path $scriptPath) {
            . $scriptPath
        }
    }

    # Core installation
    if ($InstallCore -or $InstallAll) {
        if ($DryRun) {
            Write-WinixLog -Level Info -Message '[DRY RUN] Would install Winix Core:' -LogBox $LogBox
            Write-WinixLog -Level Info -Message '  - MSYS2 / MinGW64 base environment' -LogBox $LogBox
            Write-WinixLog -Level Info -Message '  - Rust toolchain (x86_64-pc-windows-gnu)' -LogBox $LogBox
            Write-WinixLog -Level Info -Message '  - Brush shell (cargo install --locked brush-shell)' -LogBox $LogBox
            Write-WinixLog -Level Info -Message '  - JetBrains Mono font (user-level)' -LogBox $LogBox
            Write-WinixLog -Level Info -Message '  - Dotfiles (.bashrc, .bash_profile)' -LogBox $LogBox
            Write-WinixLog -Level Info -Message '  - Windows Terminal "Winix (Brush)" profile' -LogBox $LogBox
            Write-WinixLog -Level Info -Message '  - User PATH update (C:\msys64\mingw64\bin)' -LogBox $LogBox
        }
        else {
            Write-WinixLog -Level Info -Message 'Installing Winix Core...' -LogBox $LogBox
            try {
                Install-Msys2 @commonParams
                Install-Rust @commonParams
                Install-Brush @commonParams
                Install-Font @commonParams
                Install-Dotfiles @commonParams
                Inject-Terminal @commonParams
                Update-UserPath @commonParams
                Write-WinixLog -Level Success -Message 'Winix Core installed.' -LogBox $LogBox
            }
            catch {
                Write-WinixLog -Level Error -Message "Core installation failed: $_" -LogBox $LogBox
                throw
            }
        }
    }

    # Advanced tools
    if ($InstallBat -or $InstallEza -or $InstallFd -or $InstallRipgrep -or $InstallZellij) {
        $targetDir = 'C:\msys64\mingw64\bin'
        $downloaderArgs = @{ TargetDir = $targetDir }
        if ($BuildFromSource) {
            $downloaderArgs['BuildFromSource'] = $true
        }
        if ($WhatIfPreference) {
            $downloaderArgs['WhatIf'] = $true
        }

        if ($DryRun) {
            Write-WinixLog -Level Info -Message '[DRY RUN] Would install selected advanced tools to C:\msys64\mingw64\bin:' -LogBox $LogBox
            if ($InstallBat)     { Write-WinixLog -Level Info -Message '  - bat' -LogBox $LogBox }
            if ($InstallEza)     { Write-WinixLog -Level Info -Message '  - eza' -LogBox $LogBox }
            if ($InstallFd)      { Write-WinixLog -Level Info -Message '  - fd' -LogBox $LogBox }
            if ($InstallRipgrep) { Write-WinixLog -Level Info -Message '  - ripgrep' -LogBox $LogBox }
            if ($InstallZellij)  { Write-WinixLog -Level Info -Message '  - zellij' -LogBox $LogBox }
            if ($BuildFromSource){ Write-WinixLog -Level Info -Message '  (all tools built from source via cargo)' -LogBox $LogBox }
        }
        else {
            Write-WinixLog -Level Info -Message 'Installing selected advanced tools...' -LogBox $LogBox
            try {
                if ($InstallBat)     { & (Join-Path $ScriptsDir 'downloaders\Get-Bat.ps1') @downloaderArgs }
                if ($InstallEza)     { & (Join-Path $ScriptsDir 'downloaders\Get-Eza.ps1') @downloaderArgs }
                if ($InstallFd)      { & (Join-Path $ScriptsDir 'downloaders\Get-Fd.ps1') @downloaderArgs }
                if ($InstallRipgrep) { & (Join-Path $ScriptsDir 'downloaders\Get-Ripgrep.ps1') @downloaderArgs }
                if ($InstallZellij)  { & (Join-Path $ScriptsDir 'downloaders\Get-Zellij.ps1') @downloaderArgs }
                Write-WinixLog -Level Success -Message 'Advanced tools installation completed.' -LogBox $LogBox
            }
            catch {
                Write-WinixLog -Level Error -Message "Advanced tools installation failed: $_" -LogBox $LogBox
                throw
            }
        }
    }

    if ($DryRun) {
        Write-WinixLog -Level Warning -Message '==================== DRY RUN COMPLETE ====================' -LogBox $LogBox
    }

    Write-WinixLog -Level Success -Message 'Project Winix installation flow completed.' -LogBox $LogBox
}
