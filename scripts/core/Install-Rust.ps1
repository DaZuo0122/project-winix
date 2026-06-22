function Install-Rust {
    [CmdletBinding()]
    param (
        [string]$Target = 'x86_64-pc-windows-gnu'
    )

    # 1. Check existing rustup/cargo
    $rustc = Get-Command 'rustc.exe' -ErrorAction SilentlyContinue
    $cargo = Get-Command 'cargo.exe' -ErrorAction SilentlyContinue

    if ($rustc -and $cargo) {
        $installedTarget = & rustc.exe --print target-list 2>$null | Where-Object { $_ -eq $Target }
        if ($installedTarget) {
            Write-WinixLog -Level Info -Message "Rust toolchain with target $Target already installed; skipping rustup installation."
            return
        }
        else {
            Write-WinixLog -Level Info -Message 'Rust toolchain found but target not installed; adding target...'
            & rustup.exe target add $Target
            if ($LASTEXITCODE -eq 0) {
                Write-WinixLog -Level Success -Message "Added Rust target $Target."
                return
            }
            else {
                throw "Failed to add Rust target $Target."
            }
        }
    }

    # 2. Download and run rustup-init
    Write-WinixLog -Level Info -Message 'Downloading rustup-init.exe...'
    $rustupUrl = 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe'
    $rustupPath = Join-Path $env:TEMP 'rustup-init.exe'
    Invoke-WebRequest -Uri $rustupUrl -OutFile $rustupPath -UseBasicParsing

    Write-WinixLog -Level Info -Message 'Running rustup-init...'
    $process = Start-Process -FilePath $rustupPath -ArgumentList '-y', "--default-host $Target", '--default-toolchain stable' -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "rustup-init exited with code $($process.ExitCode)."
    }

    # 3. Add cargo to current process PATH
    $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
    if ($env:PATH -notlike "*$cargoBin*") {
        $env:PATH = "$cargoBin;$env:PATH"
    }

    # 4. Verify
    $rustcVersion = & rustc.exe --version 2>$null
    $cargoVersion = & cargo.exe --version 2>$null
    Write-WinixLog -Level Success -Message "Rust installed: $rustcVersion, $cargoVersion"
}
