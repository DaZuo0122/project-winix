function Get-WinixTerminalSettingsPath {
    [CmdletBinding()]
    param ()

    $candidatePaths = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )

    foreach ($path in $candidatePaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    # Default to the Microsoft Store path if neither exists
    return $candidatePaths[0]
}

function Get-WinixDeterministicGuid {
    [CmdletBinding()]
    param ()

    $namespaceBytes = [Guid]::Parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8').ToByteArray()
    $nameBytes = [System.Text.Encoding]::UTF8.GetBytes('Project Winix')

    # Simple v5-like GUID using SHA1
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $hash = $sha1.ComputeHash($namespaceBytes + $nameBytes)

    # .NET Guid constructor treats the first 8 bytes as little-endian integers,
    # so the version nibble lands in byte 7 and the variant bits in byte 8.
    $hash[7] = ($hash[7] -band 0x0F) -bor 0x50  # version 5
    $hash[8] = ($hash[8] -band 0x3F) -bor 0x80  # variant RFC 4122

    [byte[]]$guidBytes = $hash[0..15]
    return [Guid]::new($guidBytes)
}

function Inject-Terminal {
    [CmdletBinding()]
    param (
        [string]$SettingsPath = (Get-WinixTerminalSettingsPath),
        [string]$BackupDir = (Join-Path $env:USERPROFILE '.winix_backups'),
        [string]$StatePath = (Join-Path $env:USERPROFILE '.winix\state.json')
    )

    $brushExe = 'C:\msys64\mingw64\bin\brush.exe'
    if (-not (Test-Path $brushExe)) {
        $brushExe = Join-Path $env:USERPROFILE '.cargo\bin\brush.exe'
    }

    # 1. Ensure settings file exists
    $settingsDir = Split-Path $SettingsPath -Parent
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    if (-not (Test-Path $SettingsPath)) {
        @{ profiles = @{ list = @() } } | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsPath -Encoding UTF8
    }

    # 2. Backup
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupPath = Join-Path $BackupDir "WindowsTerminal_settings_$timestamp.json"
    Copy-Item -Path $SettingsPath -Destination $backupPath -Force
    Write-WinixLog -Level Info -Message "Backed up Windows Terminal settings to $backupPath"

    # 3. Parse JSON
    $settings = Get-Content -Path $SettingsPath -Raw | ConvertFrom-Json -AsHashtable
    if (-not $settings) {
        $settings = @{}
    }

    if (-not $settings.ContainsKey('profiles')) {
        $settings['profiles'] = @{}
    }
    if (-not $settings['profiles'].ContainsKey('list')) {
        $settings['profiles']['list'] = [System.Collections.ArrayList]::new()
    }

    # 4. Generate deterministic GUID and build profile
    $guid = (Get-WinixDeterministicGuid).ToString()

    $winixProfile = @{
        name              = 'Winix (Brush)'
        guid              = "{$guid}"
        commandline       = "$brushExe -i -l --enable-highlighting --input-backend reedline"
        startingDirectory = '%USERPROFILE%'
        icon              = '%USERPROFILE%\.winix\brush.ico'
        font              = @{
            face = 'JetBrains Mono'
            size = 11
        }
        colorScheme       = 'Campbell'
        useAcrylic        = $true
        acrylicOpacity    = 0.85
    }

    # 5. Remove any existing Winix profile by GUID, then add new one
    $settings['profiles']['list'] = [System.Collections.ArrayList]::new(
        ($settings['profiles']['list'] | Where-Object { $_.guid -ne "{$guid}" })
    )
    [void]$settings['profiles']['list'].Add($winixProfile)

    # 6. Optionally set as default if no defaultProfile exists
    if (-not $settings['profiles'].ContainsKey('defaults')) {
        $settings['profiles']['defaults'] = @{}
    }

    # 7. Write JSON back
    $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $SettingsPath -Encoding UTF8

    Write-WinixLog -Level Success -Message "Injected 'Winix (Brush)' profile into $SettingsPath"

    # 8. Persist state
    $state = @{}
    if (Test-Path $StatePath) {
        $state = Get-Content $StatePath -Raw | ConvertFrom-Json -AsHashtable
    }
    $state['Guid'] = "{$guid}"
    $state['TerminalSettingsPath'] = $SettingsPath

    if (-not (Test-Path (Split-Path $StatePath -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $StatePath -Parent) -Force | Out-Null
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -Path $StatePath -Encoding UTF8
}
