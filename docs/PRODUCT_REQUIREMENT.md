# Product Requirements Document (PRD): Project Winix

## 1. Executive Summary & Project Goal
**Project Winix** (Windows + Unix) is an automated, open-source environment bootstrapper featuring a premium WPF GUI and robust CLI automation. It provisions a native, high-performance Unix-like command-line environment on Windows.

**The Goal:** To provide developers with the exact muscle-memory and UX of Linux/FreeBSD (using the Rust-based, bash-compatible **Brush** shell, MinGW64 toolchains, and modern Rust CLI tools) **without** the I/O overhead of WSL, and **without** the POSIX-emulation weirdness of Cygwin or the MSYS2 interactive terminal.

**The Philosophy:** 
1. **"GUI for Humans, CLI for Automation."** 
2. **"Native Execution, Unix Workflow."** 
3. **"Safety First."** (Mandatory System Restore Points and static asset deployment).

---

## 2. Core Architectural Principles
1. **System-Level Safety Net:** Before modifying the environment, the tool **must** trigger a native Windows System Restore Point.
2. **Modular Downloaders:** To ensure long-term maintainability, the fetching and extraction of every third-party pre-built binary is isolated into its own dedicated PowerShell script.
3. **Static Asset Deployment:** Configuration files (`.bashrc`, Zellij `config.kdl`) are never generated via PowerShell string manipulation. They are maintained as static files in the repository, bundled into the release `.zip`, and extracted directly to guarantee perfect Unix `LF` encoding.
4. **The "Space-less" Path Rule:** All downloaded CLI binaries are deployed strictly to `C:\msys64\mingw64\bin` to prevent path-resolution bugs in experimental native shells.
5. **Dual-Mode Interface:** A modern WPF dashboard for interactive users, and a comprehensive `param()` block for headless CI/CD or sysadmin deployment.

---

## 3. Functional Requirements (FR)

### FR1: Dual-Mode Interface & Consent Gate
* **FR1.1 WPF GUI:** If launched without parameters, the script loads a XAML-based WPF window featuring a dashboard, real-time log console, progress bars, and tier-selection checkboxes.
* **FR1.2 Consent Gate:** Both GUI and CLI modes must scan for existing `.bashrc` and Windows Terminal profiles and existing C:\msys2\ path. If found, a prominent warning is displayed. The user must explicitly consent (via GUI checkbox or CLI `-Force` flag) to acknowledge that existing configs will be backed up and overwritten.
* **FR1.3 CLI Parameters:** Headless execution flags including `-Silent`, `-InstallCore`, `-InstallAdvanced`, `-BuildFromSource`, `-Force`, and `-Uninstall`.

### FR2: System Restore Point Engine (Mandatory Snapshot)
* **FR2.1 Pre-Flight Check:** The script must verify that System Protection is enabled on the `C:` drive. If not, it prompts the user to enable it.
* **FR2.2 Checkpoint Creation:** Before installing *any* toolchain or modifying `$env:PATH`, the script invokes the Windows WMI/CIM API to create a System Restore Point named `"Project Winix Pre-Install Snapshot"`.
* **FR2.3 Bypass 24h Limit:** Windows natively limits restore points to one per 24 hours. The script must temporarily modify the `SystemRestorePointCreationFrequency` registry key to force the snapshot, then revert the registry key immediately after.

### FR3: Tiered Installation Modules
* **FR3.1 Tier 1: Winix Core (Default / Mandatory)**
  * MSYS2 MinGW64 Base (`gcc`, `make`, `cmake`, `coreutils`).
  * Git & Git-LFS (via `winget`).
  * Rust Toolchain (`rustup` targeting `x86_64-pc-windows-gnu`).
  * **Brush Shell** (The bash-compatible Rust shell, installed via `cargo`).
  * Base Static Dotfiles & Windows Terminal Profile injection.
* **FR3.2 Tier 2: Winix Advanced Arsenal (Optional / Opt-in)**
  * **Multiplexer:** Zellij.
  * **Modern Coreutils:** Bat (cat), Eza (ls), Ripgrep (grep), Fd (find).
  * **Languages:** Python (via `winget`).

### FR4: Modular Binary Downloaders (Maintainability)
* **FR4.1 Isolated Scripts:** The project must not contain one monolithic download function. Instead, every advanced tool must have a dedicated script in the `scripts/downloaders/` directory (e.g., `Get-Zellij.ps1`, `Get-Bat.ps1`).
* **FR4.2 Standardized Interface:** Each downloader script must accept standard parameters (e.g., `-TargetDir`, `-Version`) and handle its own GitHub API querying, `.zip` extraction, and `.exe` deployment to `C:\msys64\mingw64\bin`.
* **FR4.3 Source-Build Fallback:** If the user selects the "Build from Source" option in the GUI/CLI, the orchestrator bypasses the downloader scripts and invokes `cargo install --locked <tool>` using the newly provisioned Rust/MinGW toolchain.

### FR5: Static Dotfiles Extraction
* **FR5.1 Asset Bundling:** The release `.zip` contains an `assets/` folder with pre-configured, syntax-highlighted Unix files (`bashrc`, `bash_profile`, `zellij_config.kdl`).
* **FR5.2 Safe Extraction:** The script uses `System.IO.Compression` to extract these files directly to `$env:USERPROFILE`.
* **FR5.3 Backup & Comment:** If an existing `.bashrc` is overwritten, the script moves the old file to `~/.winix_backups/` and appends a commented header to the new `.bashrc` indicating where the backup is stored.

### FR6: Windows Terminal Integration
* **FR6.1 Safe-Merge JSON:** Safely parse `settings.json` using `ConvertFrom-Json`.
* **FR6.2 Profile Injection:** Inject the **"Winix (Brush)"** profile (`brush.exe -i -l --enable-highlighting --input-backend reedline` with a Nerd Font).
* **FR6.3 Backup:** Create a timestamped backup of `settings.json` in `~/.winix_backups/` before writing changes.

### FR7: Uninstallation & Rollback
* **FR7.1 Teardown:** Remove the WT profile GUID, delete extracted dotfiles, and optionally purge `C:\msys64` and Cargo bins.
* **FR7.2 System Restore UI:** Provide a dedicated GUI/CLI option to list available "Project Winix" System Restore Points and trigger the Windows `rstrui.exe` or WMI rollback sequence to revert the entire OS registry and PATH state.

---

## 4. Technical Implementation Details

### A. The System Restore Point Logic (PowerShell)
```powershell
function New-WinixRestorePoint {
    # Bypass the 24-hour limit
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    Set-ItemProperty -Path $regPath -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord
    
    # Enable System Protection on C: if disabled
    Enable-ComputerRestore -Drive "C:\"
    
    # Create the Checkpoint
    Checkpoint-Computer -Description "Project Winix Pre-Install Snapshot" -RestorePointType "MODIFY_SETTINGS"
    
    # Revert the 24-hour limit
    Remove-ItemProperty -Path $regPath -Name "SystemRestorePointCreationFrequency"
}
```

### B. The Modular Downloader Invocation
The main orchestrator simply dot-sources or executes the isolated scripts, keeping the main codebase clean:
```powershell
if ($InstallAdvanced) {
    Write-Host "[Winix] Fetching Zellij..." -ForegroundColor Cyan
    & "$PSScriptRoot\scripts\downloaders\Get-Zellij.ps1" -TargetDir "C:\msys64\mingw64\bin"
    
    Write-Host "[Winix] Fetching Bat..." -ForegroundColor Cyan
    & "$PSScriptRoot\scripts\downloaders\Get-Bat.ps1" -TargetDir "C:\msys64\mingw64\bin"
}
```

---

## 5. Repository & Release Architecture

To support the modular downloaders and static assets, the GitHub repository and Release `.zip` will follow this strict structure:

```text
Project-Winix/
├── Get-Winix.ps1                 # Main Orchestrator (WPF GUI & CLI Param routing)
├── Uninstall-Winix.ps1           # Standalone rollback & Restore Point trigger
├── assets/
│   ├── gui.xaml                  # WPF UI layout (Dark mode, Consent Gate, Tiers)
│   ├── bashrc                    # Static, LF-encoded bash config
│   ├── bash_profile              # Static, LF-encoded profile config
│   └── zellij_config.kdl         # Static Zellij layout
├── scripts/
│   ├── core/
│   │   ├── Install-Msys2.ps1     # Headless MSYS2 & MinGW64 provisioning
│   │   ├── Install-Rust.ps1      # Rustup & GNU target configuration
│   │   └── Inject-Terminal.ps1   # Safe JSON merge for Windows Terminal
│   └── downloaders/              # ISOLATED BINARY FETCHERS (Easy to maintain/add)
│       ├── Get-Zellij.ps1        # Queries GH API, extracts .exe to TargetDir
│       ├── Get-Bat.ps1
│       ├── Get-Eza.ps1
│       ├── Get-Ripgrep.ps1
│       └── Get-Brush.ps1         # Fallback cargo installer wrapper
└── modules/
    ├── Snapshot.psm1             # WMI/CIM System Restore Point logic
    └── UI.psm1                   # WPF XAML loading and event binding
```

---

## 6. Updated CLI Parameter Matrix

```powershell
param(
    # Execution Modes
    [switch]$Silent,       # Suppresses WPF GUI
    [switch]$Force,        # REQUIRED for Silent mode. Bypasses the Wipe/Restore Warning.
    [switch]$Wait,         # Keeps console open after completion
    
    # Tiered Installation
    [switch]$InstallCore,      # Default if no flags are passed
    [switch]$InstallAdvanced,  # Installs Zellij, Bat, Eza, Rg via modular downloaders
    [switch]$InstallAll,       # Shorthand for Core + Advanced
    
    # Advanced Options
    [switch]$BuildFromSource,  # Bypasses downloaders, uses 'cargo install'
    [switch]$SkipRestorePoint, # DANGEROUS: Skips the WMI System Restore Point creation
    
    # Maintenance
    [switch]$Uninstall,        # Triggers the teardown sequence
    [switch]$RollbackOS        # Launches Windows System Restore UI to revert OS state
)
```

---

## 7. Non-Functional Requirements (NFR) & Out of Scope

### NFRs
* **Maintainability:** Adding a new tool (e.g., `fzf` or `helix`) must only require adding a new `Get-Tool.ps1` script to the `downloaders/` folder and adding a single checkbox to the `gui.xaml` file. No core orchestrator logic should need rewriting.
* **Resilience:** If a GitHub API rate-limit is hit during binary downloading, the modular downloader must catch the HTTP 403 error, log it to the WPF console, and gracefully skip the tool without crashing the entire installation sequence.
* **Telemetry:** 100% telemetry-free. No external network calls other than Microsoft's `winget` CDNs and GitHub Release APIs.

### Out of Scope
* **WSL Integration:** Project Winix explicitly rejects WSL 1 and WSL 2.
* **GUI Applications:** Strictly focused on the CLI/TUI experience. No X11/Wayland servers.
* **Dynamic Dotfile Generation:** PowerShell will never be used to `Out-File` or `Set-Content` complex bash scripts. Static ZIP extraction is the only approved method for dotfile deployment to guarantee LF encoding.