function Install-Dotfiles {
    [CmdletBinding()]
    param (
        [string]$AssetsDir = (Join-Path $script:RootDir 'assets'),
        [string]$BackupDir = (Join-Path $env:USERPROFILE '.winix_backups')
    )

    Write-WinixLog -Level Info -Message 'Install-Dotfiles invoked'
    # TODO: Phase 4 — implement backup & static asset extraction
}
