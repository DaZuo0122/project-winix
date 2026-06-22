function Test-FontInstalled {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$FontName
    )

    $userFontsReg = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    $machineFontsReg = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

    $userFonts = Get-ItemProperty -Path $userFontsReg -ErrorAction SilentlyContinue
    $machineFonts = Get-ItemProperty -Path $machineFontsReg -ErrorAction SilentlyContinue

    $allFonts = @()
    if ($userFonts) { $allFonts += ($userFonts.PSObject.Properties.Name -join '|') }
    if ($machineFonts) { $allFonts += ($machineFonts.PSObject.Properties.Name -join '|') }

    return ($allFonts -join '|') -like "*$FontName*"
}

function Install-Font {
    [CmdletBinding()]
    param (
        [string]$FontName = 'JetBrains Mono',
        [string]$FontVersion = '2.304',
        [string]$FontUrl = 'https://download.jetbrains.com/fonts/JetBrainsMono-2.304.zip'
    )

    # 1. Check existing font
    if (Test-FontInstalled -FontName $FontName) {
        Write-WinixLog -Level Info -Message "Font '$FontName' is already installed; skipping."
        return
    }

    # 2. Download font archive
    Write-WinixLog -Level Info -Message "Downloading $FontName $FontVersion..."
    $archivePath = Join-Path $env:TEMP "JetBrainsMono-$FontVersion.zip"
    try {
        Invoke-WebRequest -Uri $FontUrl -OutFile $archivePath -UseBasicParsing -MaximumRedirection 5
    }
    catch {
        Write-WinixLog -Level Warning -Message "Failed to download font: $_. The Windows Terminal profile will reference '$FontName'; install it manually if needed."
        return
    }

    # 3. Extract TTF files
    $extractDir = Join-Path $env:TEMP "JetBrainsMono-$FontVersion"
    if (Test-Path $extractDir) {
        Remove-Item -Path $extractDir -Recurse -Force
    }
    Expand-Archive -Path $archivePath -DestinationPath $extractDir -Force

    $ttfFiles = Get-ChildItem -Path $extractDir -Filter '*.ttf' -Recurse
    if (-not $ttfFiles) {
        Write-WinixLog -Level Warning -Message "No .ttf files found in the downloaded font archive."
        return
    }

    # 4. Install at user level
    $userFontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    if (-not (Test-Path $userFontDir)) {
        New-Item -ItemType Directory -Path $userFontDir -Force | Out-Null
    }

    $installedFiles = [System.Collections.ArrayList]::new()
    $userFontsReg = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

    foreach ($ttf in $ttfFiles) {
        # Skip variable fonts and italic/bold variants if the regular face is enough;
        # install all faces so the Terminal can use the exact named font.
        $destPath = Join-Path $userFontDir $ttf.Name
        Copy-Item -Path $ttf.FullName -Destination $destPath -Force
        [void]$installedFiles.Add($destPath)

        $regName = "$FontName $($ttf.BaseName) (TrueType)"
        Set-ItemProperty -Path $userFontsReg -Name $regName -Value $destPath -Type String -Force
    }

    Write-WinixLog -Level Success -Message "Font '$FontName' installed at user level ($($installedFiles.Count) files)."
}
