#Requires -Version 5.1

<#
.SYNOPSIS
    Manage Rust toolchain installation via rustup.
.PARAMETER Command
    Action: check, install, update, uninstall, download.
.PARAMETER Version
    Toolchain version (default: stable).
.PARAMETER Mirror
    Mirror base URL for rustup (default: rsproxy.cn).
.PARAMETER Force
    Skip upgrade confirmation.
#>

[CmdletBinding()]
param(
    [ValidateSet("check", "install", "update", "uninstall", "download")]
    [string]$Command = "check",

    [AllowEmptyString()]
    [string]$Version = "",

    [string]$Mirror = "https://rsproxy.cn",

    [switch]$Force
)

. "$PSScriptRoot\..\helpers.ps1"

$ohmyRoot       = $script:OhmyRoot
$RustupHome     = Join-Path $ohmyRoot ".envs\dev\.rustup"
$CargoHome      = Join-Path $ohmyRoot ".envs\dev\.cargo"
$CargoBin       = "$CargoHome\bin"
$RustupExe      = "$CargoBin\rustup.exe"
$RustcExe       = "$CargoBin\rustc.exe"
$CargoExe       = "$CargoBin\cargo.exe"
$script:RustConfig = Join-Path $script:OhmyRoot ".config\rust\config.json"

function Get-RustLock {
    <#
    .SYNOPSIS
        Read the locked Rust version from the rust config file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path $script:RustConfig)) { return }
    try {
        $cfg = Get-Content $script:RustConfig -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($cfg.lock) { return $cfg.lock }
    } catch {}
}

function Set-RustLock {
    <#
    .SYNOPSIS
        Write the locked Rust version to the rust config file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $dir = Split-Path $script:RustConfig -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $noBom = New-Object System.Text.UTF8Encoding $false
    $json  = @{ lock = $Version } | ConvertTo-Json
    [System.IO.File]::WriteAllText($script:RustConfig, $json.Trim(), $noBom)
}

function Remove-RustLock {
    <#
    .SYNOPSIS
        Delete the Rust version lock config file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (Test-Path $script:RustConfig) { Remove-Item $script:RustConfig -Force -ErrorAction SilentlyContinue }
}

function Get-InstalledRustVersion {
    <#
    .SYNOPSIS
        Query the locally installed rustc version string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path $RustcExe)) { return }
    $env:RUSTUP_HOME = $RustupHome
    $env:CARGO_HOME  = $CargoHome
    $raw = & $RustcExe --version 2>&1 | Out-String
    if ($raw -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
}

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-RustCheck {
    <#
    .SYNOPSIS
        Display the current Rust installation, lock, cache, and component status.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- Rust ---" -ForegroundColor Cyan

    $installedVer = Get-InstalledRustVersion
    $lock = Get-RustLock

    # ── Install status ──
    if ($installedVer) {
        Write-Host "[OK] Installed: Rust $installedVer ($RustcExe)" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Rust toolchain not installed" -ForegroundColor Cyan
    }

    # ── Lock status ──
    if ($lock) {
        if ($installedVer -and $installedVer -eq $lock) {
            Write-Host "[OK] Locked: $lock (current)" -ForegroundColor Green
        } else {
            Write-Host "[LOCK] Locked: $lock" -ForegroundColor Magenta
        }
    } else {
        Write-Host "[INFO] No version lock" -ForegroundColor DarkGray
    }

    # ── Cache status ──
    $cacheDir = Join-Path $script:DevSetupRoot "rustup"
    if (Test-Path $cacheDir) {
        $cached = Get-ChildItem "$cacheDir\*.exe" -ErrorAction SilentlyContinue
        if ($cached) {
            $names = ($cached | ForEach-Object { $_.Name }) -join ', '
            Write-Host "[CACHE] $cacheDir" -ForegroundColor DarkGray
            Write-Host "        $names" -ForegroundColor DarkGray
        } else {
            Write-Host "[CACHE] No cached downloads in $cacheDir" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[CACHE] No cache directory" -ForegroundColor DarkGray
    }

    # ── rust-analyzer component status ──
    if ($installedVer -and (Test-Path $RustupExe)) {
        $env:RUSTUP_HOME = $RustupHome
        $env:CARGO_HOME = $CargoHome
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        & $RustupExe which rust-analyzer 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Component: rust-analyzer" -ForegroundColor DarkGray
        } else {
            Write-Host "[INFO] Component: rust-analyzer not installed" -ForegroundColor Cyan
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# download
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-RustDownload {
    <#
    .SYNOPSIS
        Download the rustup-init installer and cache it.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $lockVer = Get-RustLock
    if (-not $lockVer) {
        Write-Host "[INFO] No version lock for Rust. Use 'omc install rust' to install and set a lock." -ForegroundColor Cyan
        return
    }

    $archiveName = "rustup-init.exe"
    $cacheDir    = Join-Path $script:DevSetupRoot "rustup"
    $cacheFile   = Join-Path $cacheDir $archiveName

    if (Test-Path $cacheFile) {
        Write-Host "[CACHE] $cacheDir" -ForegroundColor DarkGray
        Write-Host "        $archiveName" -ForegroundColor DarkGray
        return
    }

    $downloadUrl = "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe"
    $destFile    = Join-Path $env:TEMP $archiveName

    Write-Host "[INFO] Downloading rustup-init.exe ..." -ForegroundColor Cyan
    try {
        Save-WithCache -Url $downloadUrl -OutFile $destFile -CacheDir "rustup" -TimeoutSec 120
    } catch {
        Write-Host "[WARN] Direct download failed, trying mirror..." -ForegroundColor Yellow
        try {
            $mirrorUrl = "$Mirror/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe"
            Invoke-WebRequest -Uri $mirrorUrl -OutFile $destFile -TimeoutSec 120 -UseBasicParsing -ErrorAction Stop
            Move-Item $destFile $cacheFile -Force
        } catch {
            Write-Host "[ERROR] Failed to download rustup-init.exe: $_" -ForegroundColor Red
            Remove-Item $destFile -Force -ErrorAction SilentlyContinue
            return
        }
    }

    # Save-WithCache already caches, so just clean up temp
    Remove-Item $destFile -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] rustup-init.exe downloaded" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# install
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-RustInstall {
    <#
    .SYNOPSIS
        Download rustup-init, install the Rust toolchain, and configure mirrors and PATH.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [AllowEmptyString()]
        [string]$ToolchainVersion = ''
    )

    $toolchain = if ($ToolchainVersion) { $ToolchainVersion } elseif ($Version) { $Version } else { 'stable' }

    # ── 0. Check if already installed ──
    $installedVer = Get-InstalledRustVersion

    if ($Command -eq "install" -and $installedVer -and -not $Force) {
        Write-Host "[OK] Installed: Rust $installedVer" -ForegroundColor Green
        if (-not (Get-RustLock)) { Set-RustLock -Version $installedVer; Show-LockWrite -Version $installedVer }
        Write-Host "[INFO] Run 'omc update rust' to check for upgrades" -ForegroundColor Cyan
        return
    }

    # ── Update mode: just rustup update, no re-download ──
    if ($Command -eq "update" -and $installedVer) {
        $lockVer = Get-RustLock
        $env:RUSTUP_HOME = $RustupHome
        $env:CARGO_HOME = $CargoHome

        Write-Host "[INFO] Running rustup update..." -ForegroundColor Cyan
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        & $RustupExe update 2>&1 | ForEach-Object { Write-Host "       $_" }
        $ErrorActionPreference = $prevEAP

        $newVer = Get-InstalledRustVersion
        if ($newVer) {
            Set-RustLock -Version $newVer
            if ($lockVer -and $lockVer -ne $newVer) {
                Write-Host "[OK] Rust $lockVer -> $newVer" -ForegroundColor Green
            } else {
                Write-Host "[OK] Rust $newVer (unchanged)" -ForegroundColor Green
            }
            Show-LockWrite -Version $newVer
        }
        return
    }

    Show-Installing -Component "Rust $toolchain"

    # ── 1. Configure environment variables ──
    Write-Host "[INFO] Configuring environment variables..." -ForegroundColor Cyan

    $env:RUSTUP_HOME = $RustupHome
    $env:CARGO_HOME  = $CargoHome
    [Environment]::SetEnvironmentVariable("RUSTUP_HOME", $RustupHome, "User")
    [Environment]::SetEnvironmentVariable("CARGO_HOME",  $CargoHome,  "User")
    Write-Host "[OK] RUSTUP_HOME = $RustupHome" -ForegroundColor Green
    Write-Host "[OK] CARGO_HOME  = $CargoHome" -ForegroundColor Green

    # Mirror
    $env:RUSTUP_DIST_SERVER = $Mirror
    $env:RUSTUP_UPDATE_ROOT = "$Mirror/rustup"
    [Environment]::SetEnvironmentVariable("RUSTUP_DIST_SERVER", $Mirror, "User")
    [Environment]::SetEnvironmentVariable("RUSTUP_UPDATE_ROOT", "$Mirror/rustup", "User")
    Write-Host "[OK] RUSTUP_DIST_SERVER = $Mirror" -ForegroundColor Green
    Write-Host "[OK] RUSTUP_UPDATE_ROOT = $Mirror/rustup" -ForegroundColor Green

    # ── 2. Ensure directories exist ──
    foreach ($dir in @($RustupHome, $CargoHome)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # ── 3. Configure cargo registry mirror ──
    $configPath = "$CargoHome\config.toml"
    $needWrite = $true
    if (Test-Path $configPath) {
        $existing = Get-Content -Path $configPath -Raw -ErrorAction SilentlyContinue
        if ($existing -match 'rsproxy\.cn') {
            Write-Host "[OK] cargo config.toml already configured with rsproxy.cn" -ForegroundColor Green
            $needWrite = $false
        }
    }
    if ($needWrite) {
        $configContent = @'
[source.crates-io]
replace-with = "rsproxy"

[source.rsproxy]
registry = "sparse+https://rsproxy.cn/index/"

[net]
git-fetch-with-cli = true

[http]
check-revoke = false
multiplexing = true
'@
        $noBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($configPath, $configContent.Trim(), $noBom)
        Write-Host "[OK] cargo config.toml written with rsproxy.cn" -ForegroundColor Green
    }

    # ── 4. Download rustup-init.exe ──
    $archiveName  = "rustup-init.exe"
    $downloadUrl  = "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe"
    $rustupInit   = Join-Path $env:TEMP $archiveName

    Write-Host "[INFO] Downloading rustup-init.exe ..." -ForegroundColor Cyan
    try {
        Save-WithCache -Url $downloadUrl -OutFile $rustupInit -CacheDir "rustup" -TimeoutSec 120
    } catch {
        Write-Host "[WARN] Direct download failed, trying mirror..." -ForegroundColor Yellow
        try {
            $mirrorUrl = "$Mirror/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe"
            Invoke-WebRequest -Uri $mirrorUrl -OutFile $rustupInit -TimeoutSec 120 -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "[ERROR] Failed to download rustup-init.exe: $_" -ForegroundColor Red
            exit 1
        }
    }

    # ── 5. Run rustup-init (silent) ──
    Write-Host "[INFO] Installing Rust $toolchain toolchain..." -ForegroundColor Cyan
    Write-Host "       This may take a few minutes." -ForegroundColor DarkGray

    try {
        $proc = Start-Process -FilePath $rustupInit `
            -ArgumentList '-y', '--default-toolchain', $toolchain, '--default-host', 'x86_64-pc-windows-msvc', '--no-modify-path' `
            -Wait -PassThru -NoNewWindow

        if ($proc.ExitCode -ne 0) {
            throw "rustup-init.exe exited with code $($proc.ExitCode)"
        }
        Write-Host "[OK] rustup-init completed" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Rust installation failed: $_" -ForegroundColor Red
        Remove-Item $rustupInit -Force -ErrorAction SilentlyContinue
        exit 1
    }

    Remove-Item $rustupInit -Force -ErrorAction SilentlyContinue

    # ── 6. PATH ──
    Add-UserPath -Dir $CargoBin
    if ($env:Path -notlike "*$CargoBin*") {
        $env:Path = "$CargoBin;$env:Path"
    }

    # ── 7. Set default toolchain ──
    Write-Host "[INFO] Setting default toolchain..." -ForegroundColor Cyan
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    & $RustupExe default stable 2>$null | Out-Null
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Default toolchain set to stable" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Failed to set default toolchain, run: rustup default stable" -ForegroundColor Yellow
    }

    # ── 8. Install rust-analyzer component ──
    Write-Host "[INFO] Installing rust-analyzer component..." -ForegroundColor Cyan
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    & $RustupExe component add rust-analyzer 2>$null | Out-Null
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] rust-analyzer component installed" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Failed to install rust-analyzer, run: rustup component add rust-analyzer" -ForegroundColor Yellow
    }

    # ── 9. Verify ──
    $result = & $RustcExe --version 2>&1 | Out-String
    if ($result -match '(\d+\.\d+\.\d+)') {
        $ver = $Matches[1]
        Write-Host "[OK] rustc $ver" -ForegroundColor Green
    }

    $result2 = & $CargoExe --version 2>&1 | Out-String
    if ($result2 -match '(\d+\.\d+\.\d+)') {
        Write-Host "[OK] $($result2.Trim())" -ForegroundColor Green
    }

    # ── 10. Lock ──
    if ($ver) {
        Set-RustLock -Version $ver
        Show-LockWrite -Version $ver
    }

    Write-Host ""
    Show-InstallComplete -Tool "Rust" -Version "$ver ($toolchain)"
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-RustUninstall {
    <#
    .SYNOPSIS
        Remove Rust toolchain directories, environment variables, PATH entry, and version lock.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "=== Uninstall Rust ===" -ForegroundColor Cyan

    if (-not (Test-Path $CargoHome) -and -not (Test-Path $RustupHome)) {
        Write-Host '[INFO] Rust not installed, nothing to uninstall' -ForegroundColor Cyan
        return
    }

    # 1. Remove cargo and rustup directories
    foreach ($dir in @($CargoHome, $RustupHome)) {
        if (Test-Path $dir) {
            $removed = $false
            for ($i = 1; $i -le 3; $i++) {
                try {
                    Remove-Item $dir -Recurse -Force -ErrorAction Stop
                    $removed = $true
                    break
                } catch {
                    if ($i -lt 3) { Start-Sleep -Seconds 1 }
                }
            }
            if ($removed) {
                Write-Host "[OK] Removed $dir" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Could not fully remove $dir" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[OK] $dir does not exist" -ForegroundColor DarkGray
        }
    }

    # 2. Remove env vars
    foreach ($var in @("RUSTUP_HOME", "CARGO_HOME", "RUSTUP_DIST_SERVER", "RUSTUP_UPDATE_ROOT")) {
        [Environment]::SetEnvironmentVariable($var, $null, "User")
    }
    Write-Host "[OK] Environment variables removed" -ForegroundColor Green

    # 3. PATH
    Remove-UserPath -Dir $CargoBin
    Write-Host "[OK] PATH entry removed" -ForegroundColor Green

    # 4. Lock
    Remove-RustLock
    Show-LockRemoved

    Write-Host ""
    Write-Host "[OK] Rust uninstalled" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"     { Invoke-RustCheck }
    "download"  { Invoke-RustDownload }
    "install"   { Invoke-RustInstall -ToolchainVersion $Version }
    "update"    { Invoke-RustInstall -ToolchainVersion $Version }
    "uninstall" { Invoke-RustUninstall }
}
