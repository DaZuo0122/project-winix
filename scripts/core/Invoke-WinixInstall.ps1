function Invoke-WinixInstallation {
    [CmdletBinding()]
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
        [string]$ScriptsDir = (Join-Path $PSScriptRoot '..'),
        [System.Windows.Controls.TextBox]$LogBox
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

    # Consent gate
    Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'ConsentGate.psm1') -Force
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
    Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'Snapshot.psm1') -Force
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
        Write-WinixLog -Level Info -Message 'Installing Winix Core...' -LogBox $LogBox
        Install-Msys2
        Install-Rust
        Install-Brush
        Install-Font
        Install-Dotfiles
        Inject-Terminal
        Update-UserPath
        Write-WinixLog -Level Success -Message 'Winix Core installed.' -LogBox $LogBox
    }

    # Advanced tools
    if ($InstallBat -or $InstallEza -or $InstallFd -or $InstallRipgrep -or $InstallZellij) {
        $targetDir = 'C:\msys64\mingw64\bin'
        $downloaderArgs = @{ TargetDir = $targetDir }
        if ($BuildFromSource) {
            $downloaderArgs['BuildFromSource'] = $true
        }

        Write-WinixLog -Level Info -Message 'Installing selected advanced tools...' -LogBox $LogBox
        if ($InstallBat)     { & (Join-Path $ScriptsDir 'downloaders\Get-Bat.ps1') @downloaderArgs }
        if ($InstallEza)     { & (Join-Path $ScriptsDir 'downloaders\Get-Eza.ps1') @downloaderArgs }
        if ($InstallFd)      { & (Join-Path $ScriptsDir 'downloaders\Get-Fd.ps1') @downloaderArgs }
        if ($InstallRipgrep) { & (Join-Path $ScriptsDir 'downloaders\Get-Ripgrep.ps1') @downloaderArgs }
        if ($InstallZellij)  { & (Join-Path $ScriptsDir 'downloaders\Get-Zellij.ps1') @downloaderArgs }
        Write-WinixLog -Level Success -Message 'Advanced tools installation completed.' -LogBox $LogBox
    }

    Write-WinixLog -Level Success -Message 'Project Winix installation flow completed.' -LogBox $LogBox
}
