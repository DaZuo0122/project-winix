<#
.SYNOPSIS
    Project Winix self-test / validation script.
.DESCRIPTION
    Performs non-destructive checks: syntax validation, required file layout,
    and basic module loading. Does not install or modify anything.
#>

[CmdletBinding()]
param ()

$rootDir = Split-Path $PSScriptRoot -Parent
$errors = [System.Collections.ArrayList]::new()

function Add-Error {
    param ([string]$Message)
    [void]$errors.Add($Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

function Add-Ok {
    param ([string]$Message)
    Write-Host "OK:   $Message" -ForegroundColor Green
}

Write-Host "Project Winix self-test" -ForegroundColor Cyan
Write-Host "Root: $rootDir" -ForegroundColor Cyan
Write-Host ""

# Required files
$requiredFiles = @(
    'Get-Winix.ps1',
    'Uninstall-Winix.ps1',
    'Run.bat',
    'Schemas/gui.xaml',
    'modules/Logging.psm1',
    'modules/Snapshot.psm1',
    'modules/ConsentGate.psm1',
    'modules/UI.psm1',
    'modules/Downloader.psm1',
    'scripts/core/Install-Msys2.ps1',
    'scripts/core/Install-Rust.ps1',
    'scripts/core/Install-Brush.ps1',
    'scripts/core/Install-Font.ps1',
    'scripts/core/Install-Dotfiles.ps1',
    'scripts/core/Inject-Terminal.ps1',
    'scripts/core/Update-UserPath.ps1',
    'scripts/core/Invoke-WinixInstall.ps1',
    'scripts/downloaders/Get-Bat.ps1',
    'scripts/downloaders/Get-Eza.ps1',
    'scripts/downloaders/Get-Fd.ps1',
    'scripts/downloaders/Get-Ripgrep.ps1',
    'scripts/downloaders/Get-Zellij.ps1'
)

foreach ($file in $requiredFiles) {
    $fullPath = Join-Path $rootDir $file
    if (Test-Path $fullPath) {
        Add-Ok "Found $file"
    }
    else {
        Add-Error "Missing $file"
    }
}

# PowerShell syntax validation
$psFiles = Get-ChildItem -Path $rootDir -Recurse -Include '*.ps1', '*.psm1' |
           Where-Object { $_.FullName -notlike '*\.git\*' -and $_.FullName -notlike '*dev-example*' }

foreach ($file in $psFiles) {
    try {
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $file.FullName -Raw), [ref]$null)
        Add-Ok "Syntax OK: $($file.FullName.Substring($rootDir.Length + 1))"
    }
    catch {
        Add-Error "Syntax error in $($file.FullName): $_"
    }
}

# XAML validation
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    [xml]$xaml = Get-Content (Join-Path $rootDir 'Schemas/gui.xaml') -Raw
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    Add-Ok 'WPF XAML loads successfully'
}
catch {
    Add-Error "WPF XAML failed to load: $_"
}

# Deterministic GUID consistency
$guidScript = Join-Path $rootDir 'scripts/core/Inject-Terminal.ps1'
$guid1 = $null
$guid2 = $null
try {
    . $guidScript
    $guid1 = (Get-WinixDeterministicGuid).ToString()
    $guid2 = (Get-WinixDeterministicGuid).ToString()
    if ($guid1 -eq $guid2) {
        Add-Ok "Deterministic GUID is stable: $guid1"
    }
    else {
        Add-Error "Deterministic GUID changed between calls: $guid1 vs $guid2"
    }
}
catch {
    Add-Error "Deterministic GUID check failed: $_"
}

# Summary
Write-Host ""
if ($errors.Count -eq 0) {
    Write-Host "All checks passed." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "$($errors.Count) check(s) failed." -ForegroundColor Red
    exit 1
}
