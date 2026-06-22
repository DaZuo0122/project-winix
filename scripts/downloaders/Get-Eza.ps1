[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$TargetDir,

    [string]$Version = 'latest',

    [switch]$BuildFromSource
)

# TODO: Phase 5 — implement GitHub release fetch for Eza
Write-Host "Get-Eza invoked: TargetDir=$TargetDir Version=$Version BuildFromSource=$BuildFromSource"
