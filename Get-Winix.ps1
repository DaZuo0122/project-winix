#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param (
    # Execution modes
    [switch]$Silent,
    [switch]$Force,
    [switch]$Wait,

    # Tiered installation
    [switch]$InstallCore,
    [switch]$InstallAdvanced,
    [switch]$InstallAll,

    # Advanced options
    [switch]$BuildFromSource,
    [switch]$SkipRestorePoint,

    # Maintenance
    [switch]$Uninstall,
    [switch]$RollbackOS
)

# Project Winix — Main orchestrator
# https://github.com/<org>/Project-Winix

$script:Version = "0.1.0"
$script:RootDir = $PSScriptRoot
$script:LogsDir = Join-Path $script:RootDir 'Logs'
$script:SchemasDir = Join-Path $script:RootDir 'Schemas'
$script:AssetsDir = Join-Path $script:RootDir 'assets'
$script:ScriptsDir = Join-Path $script:RootDir 'scripts'
$script:ModulesDir = Join-Path $script:RootDir 'modules'

$script:MainSchema = Join-Path $script:SchemasDir 'gui.xaml'
$script:DefaultLogPath = Join-Path $script:LogsDir 'Winix.log'

$script:ControlParams = @(
    'WhatIf', 'Confirm', 'Verbose', 'Debug',
    'Silent', 'Force', 'Wait',
    'InstallCore', 'InstallAdvanced', 'InstallAll',
    'BuildFromSource', 'SkipRestorePoint',
    'Uninstall', 'RollbackOS'
)

# ---------------------------------------------------------------------------
# Elevation check (redundant with #Requires, but provides graceful fallback)
# ---------------------------------------------------------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Project Winix must be run as Administrator." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Environment validation
# ---------------------------------------------------------------------------
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Error 'Project Winix requires FullLanguage PowerShell execution mode.'
    exit 1
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
if (-not (Test-Path $script:LogsDir)) {
    New-Item -ItemType Directory -Path $script:LogsDir -Force | Out-Null
}

try {
    Start-Transcript -Path $script:DefaultLogPath -Append -IncludeInvocationHeader -Force | Out-Null
}
catch {
    Write-Warning "Unable to start transcript: $_"
}

# ---------------------------------------------------------------------------
# Required files check
# ---------------------------------------------------------------------------
$requiredPaths = @(
    $script:MainSchema,
    $script:AssetsDir,
    $script:ScriptsDir,
    $script:ModulesDir,
    (Join-Path $script:ScriptsDir 'core'),
    (Join-Path $script:ScriptsDir 'downloaders')
)

foreach ($path in $requiredPaths) {
    if (-not (Test-Path $path)) {
        Stop-Transcript | Out-Null
        throw "Required path not found: $path"
    }
}

# ---------------------------------------------------------------------------
# Import modules
# ---------------------------------------------------------------------------
Import-Module (Join-Path $script:ModulesDir 'Logging.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $script:ModulesDir 'Snapshot.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $script:ModulesDir 'ConsentGate.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $script:ModulesDir 'UI.psm1') -Force -ErrorAction Stop

# ---------------------------------------------------------------------------
# Dot-source core scripts
# ---------------------------------------------------------------------------
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
    $scriptPath = Join-Path $script:ScriptsDir "core\$scriptName"
    if (Test-Path $scriptPath) {
        . $scriptPath
    }
    else {
        Write-WinixLog -Level Warning -Message "Core script not found: $scriptPath"
    }
}

# ---------------------------------------------------------------------------
# Parameter normalization
# ---------------------------------------------------------------------------
if ($InstallAll) {
    $InstallCore = $true
    $InstallAdvanced = $true
}

if (-not ($InstallCore -or $InstallAdvanced -or $Uninstall -or $RollbackOS)) {
    $InstallCore = $true
}

if ($Silent -and -not $Force -and -not ($Uninstall -or $RollbackOS)) {
    Stop-Transcript | Out-Null
    throw "Silent mode requires -Force to acknowledge the consent gate."
}

# ---------------------------------------------------------------------------
# Route execution
# ---------------------------------------------------------------------------
try {
    if ($Uninstall) {
        Write-WinixLog -Level Info -Message 'Starting Project Winix uninstallation...'
        & (Join-Path $script:RootDir 'Uninstall-Winix.ps1')
    }
    elseif ($RollbackOS) {
        Write-WinixLog -Level Info -Message 'Launching Windows System Restore UI.'
        Start-Process 'rstrui.exe'
    }
    elseif ($Silent) {
        Write-WinixLog -Level Info -Message 'Starting Project Winix silent installation...'

        # --- Consent gate ---
        $consent = Test-WinixConsentGate
        if ($consent.HasConflicts -and -not $Force) {
            Show-WinixConsentWarning -Conflicts $consent.Conflicts
            Stop-Transcript | Out-Null
            throw "Conflicts detected. Use -Force to acknowledge that existing configs will be backed up and overwritten."
        }

        if ($consent.HasConflicts) {
            Show-WinixConsentWarning -Conflicts $consent.Conflicts
            Write-WinixLog -Level Warning -Message '-Force was specified; proceeding with backups and overwrite.'
        }

        # --- System Restore Point ---
        if (-not $SkipRestorePoint) {
            Write-WinixLog -Level Info -Message 'Creating mandatory System Restore Point...'
            $rp = New-WinixRestorePoint
            if ($rp.Success) {
                Write-WinixLog -Level Success -Message $rp.Message
            }
            else {
                Write-WinixLog -Level Error -Message $rp.Message
                Stop-Transcript | Out-Null
                throw "Failed to create System Restore Point. Use -SkipRestorePoint to bypass (not recommended)."
            }
        }
        else {
            Write-WinixLog -Level Warning -Message 'Skipping System Restore Point creation as requested.'
        }

        # TODO: invoke full installation orchestration (Phase 3+)
        Write-WinixLog -Level Warning -Message 'Silent installation flow partially implemented; core installers will be wired in Phase 3.'
    }
    else {
        Write-WinixLog -Level Info -Message 'Launching Project Winix GUI...'
        Show-WinixMainWindow -SchemaPath $script:MainSchema
    }
}
catch {
    Write-WinixLog -Level Error -Message "Unhandled error: $_"
    throw
}
finally {
    if (-not $Wait) {
        Stop-Transcript | Out-Null
    }
}

if ($Wait) {
    Write-Host ''
    Write-Host 'Press any key to exit...' -ForegroundColor Cyan
    $null = [System.Console]::ReadKey($true)
    Stop-Transcript | Out-Null
}
