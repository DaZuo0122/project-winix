[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$TargetDir,

    [string]$Version = 'latest',

    [switch]$BuildFromSource
)

# TODO: Phase 5 — implement GitHub release fetch for Zellij
Write-Host "Get-Zellij invoked: TargetDir=$TargetDir Version=$Version BuildFromSource=$BuildFromSource"
