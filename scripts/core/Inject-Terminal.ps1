function Inject-Terminal {
    [CmdletBinding()]
    param (
        [string]$SettingsPath,
        [string]$BackupDir = (Join-Path $env:USERPROFILE '.winix_backups'),
        [string]$StatePath = (Join-Path $env:USERPROFILE '.winix\state.json')
    )

    Write-WinixLog -Level Info -Message 'Inject-Terminal invoked'
    # TODO: Phase 4 — implement safe settings.json merge
}
