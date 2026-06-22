function Update-UserPath {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string[]]$Paths = @('C:\msys64\mingw64\bin'),
        [string]$StatePath = (Join-Path $env:USERPROFILE '.winix\state.json')
    )

    $regPath = 'HKCU:\Environment'
    $currentPath = (Get-ItemProperty -Path $regPath -Name 'Path' -ErrorAction SilentlyContinue).Path

    if ([string]::IsNullOrWhiteSpace($currentPath)) {
        $currentPath = ''
    }

    $addedPaths = [System.Collections.ArrayList]::new()

    foreach ($path in $Paths) {
        # Normalize trailing backslash for comparison
        $normalizedPath = $path.TrimEnd('\')
        $pattern = '(^|;)' + [regex]::Escape($normalizedPath) + '(;|$)'

        if ($currentPath -notmatch $pattern) {
            Write-WinixLog -Level Info -Message "Adding $normalizedPath to user PATH."
            $currentPath = if ($currentPath) { "$currentPath;$normalizedPath" } else { $normalizedPath }
            [void]$addedPaths.Add($normalizedPath)
        }
        else {
            Write-WinixLog -Level Info -Message "$normalizedPath is already in user PATH; skipping."
        }
    }

    if ($addedPaths.Count -gt 0) {
        if ($PSCmdlet.ShouldProcess('HKCU:\Environment\Path', "Append $($addedPaths -join '; ')")) {
            Set-ItemProperty -Path $regPath -Name 'Path' -Value $currentPath -Type ExpandString -Force

            # Broadcast WM_SETTINGCHANGE so Explorer and new consoles pick up the change
            $code = @'
using System;
using System.Runtime.InteropServices;
public class EnvChange {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
'@
            try {
                Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
                $HWND_BROADCAST = [IntPtr]::Zero -bor 0xFFFF
                $WM_SETTINGCHANGE = 0x1A
                $result = [UIntPtr]::Zero
                [void][EnvChange]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
                Write-WinixLog -Level Success -Message 'User PATH updated and environment change broadcast.'
            }
            catch {
                Write-WinixLog -Level Warning -Message "PATH updated, but failed to broadcast environment change: $_"
            }
        }
    }
    else {
        Write-WinixLog -Level Info -Message 'No PATH changes were necessary.'
    }

    # Persist added paths to state file for uninstall
    if (-not (Test-Path (Split-Path $StatePath -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $StatePath -Parent) -Force | Out-Null
    }

    $state = @{}
    if (Test-Path $StatePath) {
        $state = Get-Content $StatePath -Raw | ConvertFrom-Json -AsHashtable
    }

    $state['AddedPaths'] = $addedPaths.ToArray()
    $state | ConvertTo-Json -Depth 5 | Set-Content -Path $StatePath -Encoding UTF8
}
