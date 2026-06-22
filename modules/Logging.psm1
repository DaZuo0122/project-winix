function Write-WinixLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $colorMap = @{
        'Info'    = 'White'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
        'Success' = 'Green'
    }

    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line -ForegroundColor $colorMap[$Level]
}

function Initialize-WinixLogging {
    [CmdletBinding()]
    param (
        [string]$LogDir = (Join-Path $PSScriptRoot '..' 'Logs')
    )

    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
}

Export-ModuleMember -Function Write-WinixLog, Initialize-WinixLogging
