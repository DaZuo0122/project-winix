<#
.SYNOPSIS
    WPF GUI helpers for Project Winix.
#>

function Show-WinixMainWindow {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SchemaPath,

        [Parameter(Mandatory)]
        [string]$ScriptsDir
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    if (-not (Test-Path $SchemaPath)) {
        throw "GUI schema not found: $SchemaPath"
    }

    [xml]$xaml = Get-Content -Path $SchemaPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # -----------------------------------------------------------------------
    # Resolve controls
    # -----------------------------------------------------------------------
    $controls = @{}
    $controlNames = @(
        'InstallCoreCheckBox',
        'InstallAdvancedCheckBox',
        'InstallAllCheckBox',
        'InstallBatCheckBox',
        'InstallEzaCheckBox',
        'InstallFdCheckBox',
        'InstallRipgrepCheckBox',
        'InstallZellijCheckBox',
        'WaitCheckBox',
        'BuildFromSourceCheckBox',
        'SkipRestorePointCheckBox',
        'UninstallCheckBox',
        'RollbackOSCheckBox',
        'ConsentCheckBox',
        'InstallButton',
        'UninstallButton',
        'CancelButton',
        'InstallProgressBar',
        'LogTextBox'
    )

    foreach ($name in $controlNames) {
        $controls[$name] = $window.FindName($name)
    }

    $logBox = $controls['LogTextBox']

    function Add-LogLine {
        param ([string]$Message)
        Add-WinixLogLine -LogBox $logBox -Message $Message
    }

    # -----------------------------------------------------------------------
    # Tier checkbox logic
    # -----------------------------------------------------------------------
    $controls['InstallAllCheckBox'].Add_Checked({
        $controls['InstallCoreCheckBox'].IsChecked = $true
        $controls['InstallAdvancedCheckBox'].IsChecked = $true
    })
    $controls['InstallAllCheckBox'].Add_Unchecked({
        $controls['InstallCoreCheckBox'].IsChecked = $false
        $controls['InstallAdvancedCheckBox'].IsChecked = $false
    })

    $controls['InstallAdvancedCheckBox'].Add_Checked({
        $controls['InstallBatCheckBox'].IsChecked = $true
        $controls['InstallEzaCheckBox'].IsChecked = $true
        $controls['InstallFdCheckBox'].IsChecked = $true
        $controls['InstallRipgrepCheckBox'].IsChecked = $true
        $controls['InstallZellijCheckBox'].IsChecked = $true
    })
    $controls['InstallAdvancedCheckBox'].Add_Unchecked({
        $controls['InstallBatCheckBox'].IsChecked = $false
        $controls['InstallEzaCheckBox'].IsChecked = $false
        $controls['InstallFdCheckBox'].IsChecked = $false
        $controls['InstallRipgrepCheckBox'].IsChecked = $false
        $controls['InstallZellijCheckBox'].IsChecked = $false
    })

    # When all advanced tools are checked manually, tick InstallAdvanced too.
    $updateAdvancedState = {
        $allChecked = ($controls['InstallBatCheckBox'].IsChecked -eq $true) -and
                      ($controls['InstallEzaCheckBox'].IsChecked -eq $true) -and
                      ($controls['InstallFdCheckBox'].IsChecked -eq $true) -and
                      ($controls['InstallRipgrepCheckBox'].IsChecked -eq $true) -and
                      ($controls['InstallZellijCheckBox'].IsChecked -eq $true)
        $controls['InstallAdvancedCheckBox'].IsChecked = $allChecked
    }

    foreach ($name in @('InstallBatCheckBox', 'InstallEzaCheckBox', 'InstallFdCheckBox', 'InstallRipgrepCheckBox', 'InstallZellijCheckBox')) {
        $controls[$name].Add_Checked($updateAdvancedState)
        $controls[$name].Add_Unchecked($updateAdvancedState)
    }

    # -----------------------------------------------------------------------
    # Consent gate enables Install button
    # -----------------------------------------------------------------------
    $refreshInstallState = {
        $needsConsent = -not ($controls['UninstallCheckBox'].IsChecked -eq $true -or $controls['RollbackOSCheckBox'].IsChecked -eq $true)
        $consented = $controls['ConsentCheckBox'].IsChecked -eq $true
        $controls['InstallButton'].IsEnabled = (-not $needsConsent) -or $consented
    }

    $controls['ConsentCheckBox'].Add_Checked($refreshInstallState)
    $controls['ConsentCheckBox'].Add_Unchecked($refreshInstallState)
    $controls['UninstallCheckBox'].Add_Checked($refreshInstallState)
    $controls['UninstallCheckBox'].Add_Unchecked($refreshInstallState)
    $controls['RollbackOSCheckBox'].Add_Checked($refreshInstallState)
    $controls['RollbackOSCheckBox'].Add_Unchecked($refreshInstallState)

    # Initial state
    & $refreshInstallState

    # -----------------------------------------------------------------------
    # Cancel
    # -----------------------------------------------------------------------
    $controls['CancelButton'].Add_Click({ $window.Close() })

    # -----------------------------------------------------------------------
    # Uninstall
    # -----------------------------------------------------------------------
    $controls['UninstallButton'].Add_Click({
        Add-LogLine -Message 'Starting uninstallation...'
        $controls['InstallProgressBar'].IsIndeterminate = $true
        try {
            & (Join-Path (Split-Path $ScriptsDir -Parent) 'Uninstall-Winix.ps1')
            Add-LogLine -Message 'Uninstallation completed.'
        }
        catch {
            Add-LogLine -Message "Uninstallation failed: $_"
        }
        finally {
            $controls['InstallProgressBar'].IsIndeterminate = $false
        }
    })

    # -----------------------------------------------------------------------
    # Install
    # -----------------------------------------------------------------------
    $controls['InstallButton'].Add_Click({
        if ($controls['RollbackOSCheckBox'].IsChecked -eq $true) {
            Add-LogLine -Message 'Launching Windows System Restore UI.'
            Start-Process 'rstrui.exe'
            return
        }

        $controls['InstallButton'].IsEnabled = $false
        $controls['InstallProgressBar'].IsIndeterminate = $true
        Add-LogLine -Message 'Starting installation...'

        $installParams = @{
            InstallCore        = $controls['InstallCoreCheckBox'].IsChecked -eq $true
            InstallAdvanced    = $controls['InstallAdvancedCheckBox'].IsChecked -eq $true
            InstallAll         = $controls['InstallAllCheckBox'].IsChecked -eq $true
            InstallBat         = $controls['InstallBatCheckBox'].IsChecked -eq $true
            InstallEza         = $controls['InstallEzaCheckBox'].IsChecked -eq $true
            InstallFd          = $controls['InstallFdCheckBox'].IsChecked -eq $true
            InstallRipgrep     = $controls['InstallRipgrepCheckBox'].IsChecked -eq $true
            InstallZellij      = $controls['InstallZellijCheckBox'].IsChecked -eq $true
            BuildFromSource    = $controls['BuildFromSourceCheckBox'].IsChecked -eq $true
            SkipRestorePoint   = $controls['SkipRestorePointCheckBox'].IsChecked -eq $true
            Force              = $true  # Consent checkbox already acknowledges
            ScriptsDir         = $ScriptsDir
            LogBox             = $logBox
        }

        # Run installation in a background runspace so the UI stays responsive.
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()

        # Pass variables into the runspace
        $runspace.SessionStateProxy.SetVariable('InstallParams', $installParams)
        $runspace.SessionStateProxy.SetVariable('PSScriptRoot', $PSScriptRoot)

        $powershell = [powershell]::Create()
        $powershell.Runspace = $runspace

        [void]$powershell.AddScript({
            # Re-import modules in the runspace
            Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'Logging.psm1') -Force
            Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'Snapshot.psm1') -Force
            Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'ConsentGate.psm1') -Force

            . (Join-Path $InstallParams.ScriptsDir 'core\Invoke-WinixInstall.ps1')

            try {
                Invoke-WinixInstallation @InstallParams
            }
            catch {
                Write-WinixLog -Level Error -Message "Installation failed: $_" -LogBox $InstallParams.LogBox
            }
        })

        $handle = $powershell.BeginInvoke()

        # Poll for completion and keep UI responsive
        while (-not $handle.IsCompleted) {
            Start-Sleep -Milliseconds 100
            [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action] { }, 'Render')
        }

        $powershell.EndInvoke($handle) | Out-Null
        $powershell.Dispose()
        $runspace.Close()
        $runspace.Dispose()

        $controls['InstallProgressBar'].IsIndeterminate = $false
        $controls['InstallButton'].IsEnabled = $true
        Add-LogLine -Message 'Installation thread finished.'
    })

    # -----------------------------------------------------------------------
    # Show window
    # -----------------------------------------------------------------------
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
