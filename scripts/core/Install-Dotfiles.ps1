function Install-Dotfiles {
    [CmdletBinding()]
    param (
        [string]$AssetsDir = (Join-Path $script:RootDir 'assets'),
        [string]$BackupDir = (Join-Path $env:USERPROFILE '.winix_backups'),
        [string]$StatePath = (Join-Path $env:USERPROFILE '.winix\state.json')
    )

    # Asset source -> destination mapping
    # NOTE: zellij_config.kdl is excluded because Zellij is optional/advanced and not installed yet.
    $assetMap = @{
        '.bashrc'       = (Join-Path $env:USERPROFILE '.bashrc')
        '.bash_profile' = (Join-Path $env:USERPROFILE '.bash_profile')
    }

    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }

    $deployedAssets = [System.Collections.ArrayList]::new()
    $skippedAssets = [System.Collections.ArrayList]::new()
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    foreach ($assetName in $assetMap.Keys) {
        $sourcePath = Join-Path $AssetsDir $assetName
        $destPath = $assetMap[$assetName]

        if (-not (Test-Path $sourcePath)) {
            Write-WinixLog -Level Warning -Message "Asset not found, skipping: $sourcePath"
            [void]$skippedAssets.Add($assetName)
            continue
        }

        # Conflict check: if destination already exists, back it up first.
        if (Test-Path $destPath) {
            $backupName = "{0}_{1}" -f (Split-Path $destPath -Leaf), $timestamp
            $backupPath = Join-Path $BackupDir $backupName

            try {
                Copy-Item -Path $destPath -Destination $backupPath -Force -ErrorAction Stop
                Write-WinixLog -Level Info -Message "Backed up existing $(Split-Path $destPath -Leaf) to $backupPath"
            }
            catch {
                Write-WinixLog -Level Error -Message "Failed to backup existing $(Split-Path $destPath -Leaf): $_. Skipping deployment to avoid conflict."
                [void]$skippedAssets.Add($assetName)
                continue
            }
        }

        # Ensure parent directory exists
        $destParent = Split-Path $destPath -Parent
        if (-not (Test-Path $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }

        # Copy byte-for-byte to preserve LF encoding
        try {
            Copy-Item -Path $sourcePath -Destination $destPath -Force -ErrorAction Stop
        }
        catch {
            Write-WinixLog -Level Error -Message "Failed to deploy $assetName -> $destPath : $_. Skipping."
            [void]$skippedAssets.Add($assetName)
            continue
        }

        # Append backup comment to .bashrc
        if ((Split-Path $destPath -Leaf) -eq '.bashrc') {
            $comment = @"

# ---------------------------------------------------------------------------
# Project Winix deployed this .bashrc on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss').
# Original file backed up to: $BackupDir
# ---------------------------------------------------------------------------
"@
            Add-Content -Path $destPath -Value $comment -NoNewline -Encoding UTF8
        }

        [void]$deployedAssets.Add((Split-Path $destPath -Leaf))
        Write-WinixLog -Level Success -Message "Deployed $assetName -> $destPath"
    }

    if ($skippedAssets.Count -gt 0) {
        Write-WinixLog -Level Warning -Message "Skipped assets due to conflicts or missing files: $($skippedAssets -join ', ')"
    }

    # Persist to state file
    $state = @{}
    if (Test-Path $StatePath) {
        $state = Get-Content $StatePath -Raw | ConvertFrom-Json -AsHashtable
    }

    $state['DeployedAssets'] = $deployedAssets.ToArray()
    $state['BackupDir'] = $BackupDir

    if (-not (Test-Path (Split-Path $StatePath -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $StatePath -Parent) -Force | Out-Null
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -Path $StatePath -Encoding UTF8
}
