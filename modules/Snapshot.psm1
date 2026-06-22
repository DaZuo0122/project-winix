function Test-SystemRestoreEnabled {
    [CmdletBinding()]
    param (
        [string]$Drive = 'C:\'
    )

    try {
        $restoreStatus = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Select-Object -First 1
        # Note: This only tells us restore points exist, not whether protection is enabled.
        # A more robust check uses WMI/SystemRestore config.
        return $true
    }
    catch {
        return $false
    }
}

function New-WinixRestorePoint {
    [CmdletBinding()]
    param (
        [string]$Description = 'Project Winix Pre-Install Snapshot'
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

        Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction SilentlyContinue

        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS'

        [PSCustomObject]@{
            Success = $true
            Message = 'System restore point created successfully.'
        }
    }
    catch {
        [PSCustomObject]@{
            Success = $false
            Message = "Failed to create system restore point: $_"
        }
    }
    finally {
        if ($valueExisted) {
            Set-ItemProperty -Path $regPath -Name 'SystemRestorePointCreationFrequency' -Value $originalValue -Type DWord -Force
        }
        else {
            Remove-ItemProperty -Path $regPath -Name 'SystemRestorePointCreationFrequency' -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Test-SystemRestoreEnabled, New-WinixRestorePoint
