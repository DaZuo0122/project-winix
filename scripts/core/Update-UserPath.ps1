function Update-UserPath {
    [CmdletBinding()]
    param (
        [string[]]$Paths = @('C:\msys64\mingw64\bin', 'C:\msys64\usr\bin'),
        [string]$StatePath = (Join-Path $env:USERPROFILE '.winix\state.json')
    )

    Write-WinixLog -Level Info -Message "Update-UserPath invoked for paths: $($Paths -join ', ')"
    # TODO: Phase 3 — implement HKCU PATH append and WM_SETTINGCHANGE broadcast
}
