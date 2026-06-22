<#
.SYNOPSIS
    System Restore Point helpers for Project Winix.
#>

function Test-SystemRestoreEnabled {
    <#
    .SYNOPSIS
        Returns $true if System Protection is enabled for the specified drive.
    #>
    [CmdletBinding()]
    param (
        [string]$Drive = 'C:\'
    )

    try {
        $sr = Get-CimInstance -Namespace 'root\default' -ClassName 'SystemRestoreConfig' -ErrorAction SilentlyContinue |
              Select-Object -First 1

        if (-not $sr) {
            # Fallback: attempt to query a restore point; if this fails, protection is likely off.
            $null = Get-ComputerRestorePoint -ErrorAction Stop | Select-Object -First 1
            return $true
        }

        # RpLifeInterval > 0 generally indicates protection is configured.
        return ($sr.RpLifeInterval -gt 0)
    }
    catch {
        return $false
    }
}

function New-WinixRestorePoint {
    <#
    .SYNOPSIS
        Creates a System Restore Point, bypassing the 24-hour frequency limit.
    .DESCRIPTION
        Temporarily sets SystemRestorePointCreationFrequency to 0, enables
        System Protection on the system drive if necessary, creates the
        restore point, and restores the original registry value.
    #>
    [CmdletBinding()]
    param (
        [string]$Description = 'Project Winix Pre-Install Snapshot',
        [int]$TimeoutSeconds = 120
    )

    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $originalValue = $null
    $valueExisted = $false

    try {
        $prop = Get-ItemProperty -Path $regPath -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
        if ($prop) {
            $originalValue = $prop.SystemRestorePointCreationFrequency
            $valueExisted = $true
        }

        Set-ItemProperty -Path $regPath -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord -Force

        # Ensure System Protection is enabled on the system drive.
        if (-not (Test-SystemRestoreEnabled -Drive $env:SystemDrive)) {
            Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop
        }

        $job = Start-Job -ScriptBlock {
            param($desc)
            Checkpoint-Computer -Description $desc -RestorePointType 'MODIFY_SETTINGS'
        } -ArgumentList $Description

        $completed = $job | Wait-Job -Timeout $TimeoutSeconds

        if (-not $completed) {
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -ErrorAction SilentlyContinue
            return [PSCustomObject]@{
                Success = $false
                Message = "System Restore Point creation timed out after $TimeoutSeconds seconds."
            }
        }

        $jobResult = Receive-Job $job -ErrorAction Stop
        Remove-Job $job -ErrorAction SilentlyContinue

        return [PSCustomObject]@{
            Success = $true
            Message = 'System restore point created successfully.'
            Result  = $jobResult
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Message = "Failed to create system restore point: $_"
        }
    }
    finally {
        if ($valueExisted) {
            Set-ItemProperty -Path $regPath -Name 'SystemRestorePointCreationFrequency' -Value $originalValue -Type DWord -Force -ErrorAction SilentlyContinue
        }
        else {
            Remove-ItemProperty -Path $regPath -Name 'SystemRestorePointCreationFrequency' -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Test-SystemRestoreEnabled, New-WinixRestorePoint
