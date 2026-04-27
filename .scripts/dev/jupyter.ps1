#Requires -Version 5.1

<#
.SYNOPSIS
    Install Jupyter (jupyter-core + jupyterlab + collaboration) via uv tool.
.PARAMETER Command
    Action: check, install, uninstall.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Version', Justification = 'Reserved for future pinning')]
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("check", "download", "install", "update", "uninstall")]
    [string]$Command = "check",

    [Parameter(Position = 1)]
    [AllowEmptyString()]
    [string]$Version = ""
)

. "$PSScriptRoot\..\helpers.ps1"

Update-Environment

$ErrorActionPreference = "Stop"

$jupyterlabVersion = "4.4.1"
$jupyterCollabVersion = "4.0.2"
$pycrdtVersion = "0.12.17"

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-JupyterCheck {
    <#
    .SYNOPSIS
        Display Jupyter installation status including jupyter-core, jupyterlab, and extensions.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- Jupyter ---" -ForegroundColor Cyan

    if (-not (Get-Command "uv.exe" -ErrorAction SilentlyContinue)) {
        Write-Host "[WARN] uv not found, cannot check Jupyter status" -ForegroundColor Yellow
        return
    }

    $uvList = cmd /c "uv tool list 2>NUL" | Out-String
    if ($uvList -match "jupyter-core") {
        $uvToolDir = & uv tool dir 2>$null
        # Extract version
        if ($uvList -match "jupyter-core\s*v?(\S+)") {
            Write-Host "[OK] jupyter-core $($Matches[1])" -ForegroundColor Green
            if ($uvToolDir) {
                Write-Host "  Location: $uvToolDir\jupyter-core" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "[OK] jupyter-core installed" -ForegroundColor Green
            if ($uvToolDir) {
                Write-Host "  Location: $uvToolDir\jupyter-core" -ForegroundColor DarkGray
            }
        }

        # Show included packages
        if ($uvList -match "jupyterlab\s*v?(\S+)") {
            Write-Host "  jupyterlab:      $($Matches[1])" -ForegroundColor DarkGray
        }
        if ($uvList -match "ipykernel\s*v?(\S+)") {
            Write-Host "  ipykernel:       $($Matches[1])" -ForegroundColor DarkGray
        }
        if ($uvList -match "jupyter-collaboration") {
            Write-Host "  collaboration:   yes" -ForegroundColor DarkGray
        }
        if ($uvList -match "pycrdt") {
            Write-Host "  datalayer_pycrdt: yes" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[INFO] Jupyter not installed" -ForegroundColor Cyan
        Write-Host "  Run 'omc install jupyter' to install" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# install
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-JupyterInstall {
    <#
    .SYNOPSIS
        Install jupyter-core and dependencies via uv tool install.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # ---- 1. Check uv ----
    if (-not (Get-Command "uv.exe" -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] uv not found" -ForegroundColor Red
        Write-Host "  Install Python + uv first: omc install python" -ForegroundColor DarkGray
        exit 1
    }

    # ---- 2. Define packages ----
    $packages = @(
        "jupyter-core",
        "jupyterlab==$jupyterlabVersion",
        "jupyter-collaboration==$jupyterCollabVersion",
        "ipykernel",
        "datalayer_pycrdt==$pycrdtVersion"
    )

    # ---- 3. Build uv tool install command ----
    $uvArgs = @("tool", "install", "--force", "jupyter-core")
    foreach ($pkg in $packages[1..($packages.Length - 1)]) {
        $uvArgs += "--with", $pkg
    }

    # ---- 4. Check if already installed ----
    $uvList = cmd /c "uv tool list 2>NUL" | Out-String
    if ($uvList -match "jupyter-core") {
        Show-AlreadyInstalled -Tool "jupyter-core"
        return
    }

    # ---- 5. Ensure Rust default toolchain (needed by datalayer-pycrdt) ----
    $cargoHome = $env:CARGO_HOME
    if (-not $cargoHome) {
        $cargoHome = [Environment]::GetEnvironmentVariable("CARGO_HOME", "User")
    }
    if (-not $cargoHome) {
        $cargoHome = "$env:USERPROFILE\.cargo"
    }
    $rustup = Join-Path $cargoHome "bin\rustup.exe"

    if (Test-Path $rustup) {
        $env:RUSTUP_HOME = if ($env:RUSTUP_HOME) { $env:RUSTUP_HOME } else { [Environment]::GetEnvironmentVariable("RUSTUP_HOME", "User") }
        $env:CARGO_HOME  = $cargoHome
        $rustupOutput = & $rustup show 2>&1 | Out-String
        if ($rustupOutput -match 'no.*toolchain' -or $rustupOutput -match 'no default') {
            Write-Host "[INFO] Setting Rust default toolchain to stable (required by datalayer-pycrdt)..." -ForegroundColor Cyan
            & $rustup default stable 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Rust default toolchain set to stable" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Failed to set Rust default toolchain" -ForegroundColor Yellow
            }
        }
    }

    # ---- 6. Install via uv ----
    Show-Installing -Component "jupyter-core"

    $env:UV_NO_PROMPT = "1"
    & uv @uvArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Installation failed" -ForegroundColor Red
        exit 1
    }

    # ---- 7. Verify ----
    $uvList = cmd /c "uv tool list 2>NUL" | Out-String
    if ($uvList -match "jupyter-core") {
        Show-InstallComplete -Tool "jupyter-core" -NextSteps "Run 'jupyter lab' to start"
    } else {
        Write-Host "[WARN] jupyter-core not showing in uv tool list" -ForegroundColor Yellow
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# download — Jupyter uses uv tool install, no separate download
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-JupyterDownload {
    <#
    .SYNOPSIS
        Display download status info; Jupyter is managed by uv tool install with no separate download step.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "[INFO] Jupyter uses 'uv tool install' -- no separate download." -ForegroundColor Cyan

    if (-not (Get-Command "uv.exe" -ErrorAction SilentlyContinue)) {
        Write-Host "[WARN] uv not found" -ForegroundColor Yellow
        return
    }

    $uvList = cmd /c "uv tool list 2>NUL" | Out-String
    if ($uvList -match "jupyter-core") {
        Write-Host "[OK] Already installed" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Jupyter not installed" -ForegroundColor Cyan
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-JupyterUninstall {
    <#
    .SYNOPSIS
        Uninstall jupyter-core via uv tool uninstall.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Get-Command "uv.exe" -ErrorAction SilentlyContinue)) {
        Write-Host "[INFO] uv not found, nothing to uninstall" -ForegroundColor Cyan
        return
    }

    $uvList = cmd /c "uv tool list 2>NUL" | Out-String
    if ($uvList -notmatch "jupyter-core") {
        Write-Host "[INFO] jupyter-core not installed" -ForegroundColor Cyan
        return
    }

    Write-Host "[INFO] Uninstalling jupyter-core ..." -ForegroundColor Cyan
    & uv tool uninstall jupyter-core
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] jupyter-core uninstalled" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Uninstall failed" -ForegroundColor Red
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"     { Invoke-JupyterCheck }
    "download"  { Write-Host "[INFO] Jupyter is managed by uv, skipping download" -ForegroundColor DarkGray }
    "install"   { Invoke-JupyterInstall }
    "update"    { Write-Host "[INFO] Jupyter is managed by uv, skipping update" -ForegroundColor DarkGray }
    "uninstall" { Invoke-JupyterUninstall }
}
