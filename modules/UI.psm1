function Show-WinixMainWindow {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SchemaPath
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    if (-not (Test-Path $SchemaPath)) {
        throw "GUI schema not found: $SchemaPath"
    }

    [xml]$xaml = Get-Content -Path $SchemaPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # TODO: Phase 6 — wire controls, consent gate, background job orchestration

    $window.ShowDialog() | Out-Null
}

function Add-WinixLogLine {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox]$LogBox,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($LogBox.Dispatcher.CheckAccess()) {
        $LogBox.AppendText("$Message`r`n")
        $LogBox.ScrollToEnd()
    }
    else {
        $LogBox.Dispatcher.Invoke([action] {
            $LogBox.AppendText("$Message`r`n")
            $LogBox.ScrollToEnd()
        })
    }
}

Export-ModuleMember -Function Show-WinixMainWindow, Add-WinixLogLine
