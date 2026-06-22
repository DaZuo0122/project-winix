<#
.SYNOPSIS
    Centralized logging for Project Winix.
.DESCRIPTION
    Writes timestamped, severity-colored messages to the console and the
    active transcript. When running with a WPF UI, messages can also be
    appended to a bound TextBox via the dispatcher.
#>

$script:LogBuffer = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())

function Write-WinixLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Windows.Controls.TextBox]$LogBox
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $colorMap = @{
        'Info'    = 'White'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
        'Success' = 'Green'
    }

    $line = "[$timestamp] [$Level] $Message"

    # Keep a thread-safe in-memory buffer for UI binding or later inspection.
    [void]$script:LogBuffer.Add($line)

    # Console / transcript output
    if ($Host.Name -eq 'ConsoleHost') {
        Write-Host $line -ForegroundColor $colorMap[$Level]
    }
    else {
        Write-Verbose $line -Verbose
    }

    # UI log console (thread-safe via dispatcher)
    if ($LogBox -and $LogBox.Dispatcher) {
        if ($LogBox.Dispatcher.CheckAccess()) {
            $LogBox.AppendText("$line`r`n")
            $LogBox.ScrollToEnd()
        }
        else {
            $LogBox.Dispatcher.Invoke([action] {
                $LogBox.AppendText("$line`r`n")
                $LogBox.ScrollToEnd()
            })
        }
    }
}

function Get-WinixLogBuffer {
    [CmdletBinding()]
    param ()

    return $script:LogBuffer.ToArray()
}

function Clear-WinixLogBuffer {
    [CmdletBinding()]
    param ()

    $script:LogBuffer.Clear()
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

Export-ModuleMember -Function Write-WinixLog, Get-WinixLogBuffer, Clear-WinixLogBuffer, Initialize-WinixLogging
