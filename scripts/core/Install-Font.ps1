function Install-Font {
    [CmdletBinding()]
    param (
        [string]$FontName = 'JetBrains Mono',
        [string]$FontUrl = 'https://download.jetbrains.com/fonts/JetBrainsMono-2.304.zip'
    )

    Write-WinixLog -Level Info -Message "Install-Font invoked for $FontName"
    # TODO: Phase 3 — implement user-level JetBrains Mono install
}
