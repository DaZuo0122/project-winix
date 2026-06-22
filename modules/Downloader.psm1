<#
.SYNOPSIS
    Shared helpers for Project Winix binary downloaders.
#>

function Invoke-WinixGitHubApi {
    <#
    .SYNOPSIS
        Queries the GitHub Releases API and returns the release object.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Repo
    )

    $uri = "https://api.github.com/repos/$Repo/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 30
        return $release
    }
    catch {
        $status = $_.Exception.Response.StatusCode.Value__
        if ($status -eq 403) {
            Write-WinixLog -Level Warning -Message "GitHub API rate limit hit for $Repo. Skipping binary download."
        }
        else {
            Write-WinixLog -Level Warning -Message "GitHub API request failed for ${Repo}: $_"
        }
        return $null
    }
}

function Find-WinixReleaseAsset {
    <#
    .SYNOPSIS
        Selects the first asset whose name matches any of the provided patterns.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Release,

        [Parameter(Mandatory)]
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        $asset = $Release.assets | Where-Object { $_.name -like $pattern } | Select-Object -First 1
        if ($asset) {
            return $asset
        }
    }
    return $null
}

function Expand-WinixArchiveToTarget {
    <#
    .SYNOPSIS
        Extracts .zip/.tar.gz archives to a temp directory and copies matching
        .exe files to the target directory.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [Parameter(Mandatory)]
        [string]$TargetDir,

        [string]$ExePattern = '*.exe'
    )

    $tempDir = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        if ($ArchivePath -like '*.zip') {
            Expand-Archive -Path $ArchivePath -DestinationPath $tempDir -Force
        }
        elseif ($ArchivePath -like '*.tar.gz' -or $ArchivePath -like '*.tgz') {
            # Prefer tar if available (Windows 10 1803+ and PS 5.1+)
            & tar -xzf $ArchivePath -C $tempDir 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "tar extraction failed for $ArchivePath"
            }
        }
        else {
            throw "Unsupported archive type: $ArchivePath"
        }

        $exeFiles = Get-ChildItem -Path $tempDir -Filter $ExePattern -Recurse
        foreach ($exe in $exeFiles) {
            $dest = Join-Path $TargetDir $exe.Name
            Copy-Item -Path $exe.FullName -Destination $dest -Force
            Write-WinixLog -Level Success -Message "Deployed $($exe.Name) -> $dest"
        }
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-WinixToolFromSource {
    <#
    .SYNOPSIS
        Installs a Rust tool via cargo install --locked.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$CrateName
    )

    $cargo = Get-Command 'cargo.exe' -ErrorAction SilentlyContinue
    if (-not $cargo) {
        Write-WinixLog -Level Warning -Message "cargo.exe not found; cannot build $CrateName from source."
        return $false
    }

    Write-WinixLog -Level Info -Message "Building $CrateName from source with cargo..."
    $process = Start-Process -FilePath $cargo.Source -ArgumentList 'install', '--locked', $CrateName -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        Write-WinixLog -Level Warning -Message "cargo install $CrateName exited with code $($process.ExitCode)."
        return $false
    }

    Write-WinixLog -Level Success -Message "$CrateName built from source successfully."
    return $true
}

Export-ModuleMember -Function Invoke-WinixGitHubApi, Find-WinixReleaseAsset, Expand-WinixArchiveToTarget, Install-WinixToolFromSource
