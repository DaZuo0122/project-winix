function Install-Msys2 {
    [CmdletBinding()]
    param (
        [string]$TargetDir = 'C:\msys64'
    )

    $mingwBin = Join-Path $TargetDir 'mingw64\bin'
    $gccExe = Join-Path $mingwBin 'gcc.exe'

    # 1. Check existing MinGW64 GCC
    if (Test-Path $gccExe) {
        Write-WinixLog -Level Info -Message "MSYS2 MinGW64 GCC already present at $gccExe; skipping MSYS2 installation."
        return
    }

    if (Test-Path $TargetDir) {
        Write-WinixLog -Level Warning -Message "Directory $TargetDir exists but gcc.exe was not found; continuing with toolchain install."
    }

    # 2. Install MSYS2
    Write-WinixLog -Level Info -Message 'Installing MSYS2 MinGW64 base environment...'

    $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    $installedByWinget = $false

    if ($winget) {
        try {
            Write-WinixLog -Level Info -Message 'Attempting MSYS2 installation via winget...'
            & $winget.Source install --id MSYS2.MSYS2 --location $TargetDir --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0) {
                $installedByWinget = $true
                Write-WinixLog -Level Success -Message 'MSYS2 installed via winget.'
            }
            else {
                Write-WinixLog -Level Warning -Message "winget install returned exit code $LASTEXITCODE; falling back to offline installer."
            }
        }
        catch {
            Write-WinixLog -Level Warning -Message "winget install failed: $_; falling back to offline installer."
        }
    }
    else {
        Write-WinixLog -Level Warning -Message 'winget not found; falling back to offline installer.'
    }

    if (-not $installedByWinget) {
        $installerUrl = 'https://github.com/msys2/msys2-installer/releases/download/2024-07-27/msys2-x86_64-20240727.exe'
        $installerPath = Join-Path $env:TEMP 'msys2-installer.exe'

        Write-WinixLog -Level Info -Message "Downloading MSYS2 installer from $installerUrl..."
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

        Write-WinixLog -Level Info -Message 'Running MSYS2 installer silently...'
        $process = Start-Process -FilePath $installerPath -ArgumentList "install", "--root", $TargetDir, "--confirm-command" -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            throw "MSYS2 installer exited with code $($process.ExitCode)."
        }
    }

    # 3. Update MSYS2 base and install MinGW64 toolchain
    $msysShell = Join-Path $TargetDir 'usr\bin\bash.exe'
    if (-not (Test-Path $msysShell)) {
        throw "MSYS2 shell not found at $msysShell."
    }

    Write-WinixLog -Level Info -Message 'Updating MSYS2 package database...'
    & $msysShell -lc "pacman -Syu --noconfirm" | ForEach-Object { Write-WinixLog -Level Info -Message $_ }

    Write-WinixLog -Level Info -Message 'Installing MinGW64 toolchain...'
    $toolchainPackages = @(
        'mingw-w64-x86_64-gcc',
        'mingw-w64-x86_64-make',
        'mingw-w64-x86_64-cmake',
        'mingw-w64-x86_64-coreutils'
    )
    & $msysShell -lc "pacman -S --noconfirm $($toolchainPackages -join ' ')" | ForEach-Object { Write-WinixLog -Level Info -Message $_ }

    # 4. Existing Git check
    $gitCommand = Get-Command 'git.exe' -ErrorAction SilentlyContinue
    $existingGit = $gitCommand -and $gitCommand.Source -notlike "$TargetDir\*"

    if ($existingGit) {
        Write-WinixLog -Level Warning -Message "Existing Git detected at $($gitCommand.Source). Skipping MinGW64 Git/Git-LFS installation to avoid conflicts."
    }
    else {
        Write-WinixLog -Level Info -Message 'Installing Git and Git-LFS from MinGW64 source...'
        & $msysShell -lc "pacman -S --noconfirm mingw-w64-x86_64-git mingw-w64-x86_64-git-lfs" | ForEach-Object { Write-WinixLog -Level Info -Message $_ }
    }

    # 5. Verify
    if (-not (Test-Path $gccExe)) {
        throw "gcc.exe was not found after installation at $gccExe."
    }

    Write-WinixLog -Level Success -Message "MSYS2 MinGW64 environment ready at $TargetDir."
}
