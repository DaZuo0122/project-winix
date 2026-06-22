function Install-Brush {
    [CmdletBinding()]
    param ()

    # 1. Check existing Brush in expected locations
    $brushPaths = @(
        'C:\msys64\mingw64\bin\brush.exe',
        (Join-Path $env:USERPROFILE '.cargo\bin\brush.exe')
    )

    foreach ($path in $brushPaths) {
        if (Test-Path $path) {
            $version = & $path --version 2>$null
            Write-WinixLog -Level Info -Message "Brush already installed at $path ($version); skipping."
            return
        }
    }

    # 2. Ensure cargo is available
    $cargo = Get-Command 'cargo.exe' -ErrorAction SilentlyContinue
    if (-not $cargo) {
        $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
        if (Test-Path (Join-Path $cargoBin 'cargo.exe')) {
            $env:PATH = "$cargoBin;$env:PATH"
            $cargo = Get-Command 'cargo.exe' -ErrorAction SilentlyContinue
        }
    }

    if (-not $cargo) {
        throw 'cargo.exe not found. Rust must be installed before Brush.'
    }

    # 3. Build and install Brush from source
    Write-WinixLog -Level Info -Message 'Installing Brush shell from source via cargo...'
    $process = Start-Process -FilePath $cargo.Source -ArgumentList 'install', '--locked', 'brush-shell' -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        throw "cargo install brush-shell exited with code $($process.ExitCode)."
    }

    # 4. Verify
    $brushExe = Join-Path $env:USERPROFILE '.cargo\bin\brush.exe'
    if (-not (Test-Path $brushExe)) {
        throw 'brush.exe was not found after cargo install.'
    }

    $version = & $brushExe --version 2>$null
    Write-WinixLog -Level Success -Message "Brush shell installed: $version"
}
