#Requires -Version 5.1

<#
.SYNOPSIS
    Manage Node.js installation from USTC mirror with SHA256 verification.
.PARAMETER Command
    Action: check, install, update, uninstall, download.
.PARAMETER Version
    Specific version to install (default: latest LTS).
.PARAMETER Force
    Skip upgrade confirmation.
#>

[CmdletBinding()]
param(
    [ValidateSet("check", "install", "update", "uninstall", "download")]
    [string]$Command = "check",

    [AllowEmptyString()]
    [string]$Version = "",

    [switch]$Force
)

. "$PSScriptRoot\..\helpers.ps1"

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = "Stop"

$script:OhmyRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$DefaultVersion  = "24.14.1"
$Mirror          = "https://mirrors.ustc.edu.cn"
$NodeDir         = "$script:OhmyRoot\.envs\dev\node"
$NodeExe         = "$NodeDir\node.exe"
$NpmExe          = "$NodeDir\npm"
$NpxExe          = "$NodeDir\npx"
$NodeConfigFile  = Join-Path $script:OhmyRoot ".config\node\config.json"
$NoBom           = New-Object System.Text.UTF8Encoding $false

function Get-NodeLock {
    <#
    .SYNOPSIS
        Read the locked version from the node config file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path $NodeConfigFile)) { return }
    try {
        $cfg = Get-Content $NodeConfigFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($cfg.lock) { return $cfg.lock }
    } catch {}
}

function Set-NodeLock {
    <#
    .SYNOPSIS
        Write the locked version to the node config file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $dir = Split-Path $NodeConfigFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = @{ lock = $Version } | ConvertTo-Json
    [System.IO.File]::WriteAllText($NodeConfigFile, $json.Trim(), $NoBom)
}

function Get-InstalledNodeVersion {
    <#
    .SYNOPSIS
        Query the locally installed Node.js version string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path $NodeExe)) { return $null }
    try {
        $raw = & $NodeExe --version 2>$null | Out-String
        if ($raw -match 'v(\d+\.\d+\.\d+)') { return $Matches[1] }
    } catch {}
    $null
}

function Get-LatestNodeVersion {
    <#
    .SYNOPSIS
        Fetch the latest LTS version string from the Node.js release index.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $releases = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -TimeoutSec 10 -ErrorAction Stop
        $lts = $releases | Where-Object { $_.lts -ne $false } | Select-Object -First 1
        if ($lts -and $lts.version -match 'v(\d+\.\d+\.\d+)') { return $Matches[1] }
        throw "No LTS version found"
    } catch {
        throw "Failed to fetch latest Node.js version: $_"
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-NodeCheck {
    <#
    .SYNOPSIS
        Display the current Node.js installation, lock, cache, and PATH status.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- Node.js ---" -ForegroundColor Cyan

    $installed = Get-InstalledNodeVersion

    # ── Install status ──
    if ($installed) {
        Write-Host "[OK] Installed: Node.js $installed ($NodeExe)" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Node.js not installed" -ForegroundColor Cyan
        Write-Host "  Expected: $NodeDir" -ForegroundColor DarkGray
    }

    # npm / npx
    if (Test-Path "$NpmExe.cmd") {
        $npmVer = (& "$NpmExe.cmd" --version 2>$null | Out-String).Trim()
        Write-Host "[OK] npm: $npmVer" -ForegroundColor Green
    }
    if (Test-Path "$NpxExe.cmd") {
        $npxVer = (& "$NpxExe.cmd" --version 2>$null | Out-String).Trim()
        Write-Host "[OK] npx: $npxVer" -ForegroundColor Green
    }

    # ── Lock status ──
    $lock = Get-NodeLock
    if ($lock) {
        if ($installed -and $installed -eq $lock) {
            Write-Host "[OK] Locked: $lock (current)" -ForegroundColor Green
        } else {
            Write-Host "[LOCK] Locked: $lock" -ForegroundColor Magenta
        }
    } else {
        Write-Host "[INFO] No version lock" -ForegroundColor DarkGray
    }

    # ── Cache status ──
    $cacheDir = Join-Path $script:DevSetupRoot "node"
    if (Test-Path $cacheDir) {
        $cached = Get-ChildItem -Path $cacheDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -ne '.sha256' } |
            Sort-Object LastWriteTime -Descending
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

    # ── PATH ──
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -split ';' -contains $NodeDir) {
        Write-Host "[OK] PATH: $NodeDir" -ForegroundColor DarkGray
    } else {
        Write-Host "[INFO] PATH: not set" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# download
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-NodeDownload {
    <#
    .SYNOPSIS
        Download the Node.js zip archive and cache it with SHA256 verification.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $lockVer = Get-NodeLock
    if ($lockVer) {
        $Version = $lockVer
    } else {
        try {
            $Version = Get-LatestNodeVersion
            Write-Host "[OK] Node.js latest LTS: $Version" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Cannot fetch latest version, using default: $DefaultVersion" -ForegroundColor Yellow
            $Version = $DefaultVersion
        }
    }

    $ZipName   = "node-v$Version-win-x64.zip"
    $cacheDir  = Join-Path $script:DevSetupRoot "node"
    $cacheFile = Join-Path $cacheDir $ZipName
    $hashFile  = "$cacheFile.sha256"

    # ── Cache hit ──
    if ((Test-Path $cacheFile) -and (Test-Path $hashFile)) {
        $expectedHash = (Get-Content $hashFile -Raw).Trim()
        $actualHash   = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
        if ($actualHash -eq $expectedHash) {
            $size = (Get-Item $cacheFile).Length
            $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
            Write-Host "[OK] Node.js v$Version cached: $sizeStr" -ForegroundColor Green
            Write-Host "      $cacheFile" -ForegroundColor DarkGray
            return
        }
        Write-Host "[WARN] Cache hash mismatch, re-downloading" -ForegroundColor Yellow
        Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
        Remove-Item $hashFile -Force -ErrorAction SilentlyContinue
    }

    # ── Download ──
    $DownloadUrl = "$Mirror/node/v$Version/$ZipName"
    $ShasumsUrl  = "$Mirror/node/v$Version/SHASUMS256.txt"
    $zipFile     = "$env:TEMP\$ZipName"
    $NodeUA      = "node/$Version (Windows; x64)"

    Write-Host "[INFO] Downloading Node.js v$Version ..." -ForegroundColor Cyan

    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipFile -UserAgent $NodeUA -MaximumRedirection 5 -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
        exit 1
    }

    # ── SHA256 verification ──
    $expectedHash = $null
    try {
        $shasums = Invoke-RestMethod -Uri $ShasumsUrl -UserAgent $NodeUA -ErrorAction Stop
        if ($shasums -match "([a-fA-F0-9]{64})\s{2}\*?$([Regex]::Escape($ZipName))") {
            $expectedHash = $Matches[1].ToUpper()
        }
    } catch {
        Write-Host "[WARN] Could not fetch SHASUMS256.txt: $_" -ForegroundColor Yellow
    }

    $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash

    if ($expectedHash) {
        if ($actualHash -eq $expectedHash) {
            Write-Host "[OK] SHA256 verified" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] SHA256 mismatch!" -ForegroundColor Red
            Write-Host "       Expected: $expectedHash" -ForegroundColor Red
            Write-Host "       Actual:   $actualHash" -ForegroundColor Red
            Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
            exit 1
        }
    } else {
        Write-Host "[WARN] SHA256 verification skipped (no SHASUMS256.txt)" -ForegroundColor Yellow
    }

    # ── Cache ──
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    Copy-Item -Path $zipFile -Destination $cacheFile -Force
    Set-Content -Path $hashFile -Value $actualHash -NoNewline -Encoding UTF8
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

    $size = (Get-Item $cacheFile).Length
    $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
    Write-Host "[OK] Node.js v$Version downloaded and cached: $sizeStr" -ForegroundColor Green
    Write-Host "      $cacheFile" -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════════════
# install
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-NodeInstall {
    <#
    .SYNOPSIS
        Download, extract, and configure Node.js on the system PATH.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $installed = Get-InstalledNodeVersion

    # ── Determine version ──
    if ($Version) {
        $targetVer = $Version
    } else {
        $lockVer = Get-NodeLock
        if ($lockVer) {
            $targetVer = $lockVer
        } else {
            try {
                $targetVer = Get-LatestNodeVersion
                Write-Host "[OK] Node.js latest LTS: $targetVer" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Cannot fetch latest version, using default: $DefaultVersion" -ForegroundColor Yellow
                $targetVer = $DefaultVersion
            }
        }
    }

    # ── Idempotent check ──
    if ($installed -and $installed -eq $targetVer -and -not $Force) {
        Show-AlreadyInstalled -Tool "Node.js" -Version $installed -Location $NodeDir
        if (-not (Get-NodeLock)) { Set-NodeLock -Version $installed }
        return
    }
    if ($installed) {
        Write-Host "[UPGRADE] Node.js $installed -> $targetVer" -ForegroundColor Cyan
    }

    # ── Download if needed ──
    Set-NodeLock -Version $targetVer
    Invoke-NodeDownload

    # ── Extract ──
    $ZipName   = "node-v$targetVer-win-x64.zip"
    $cacheDir  = Join-Path $script:DevSetupRoot "node"
    $cacheFile = Join-Path $cacheDir $ZipName
    $zipFile   = "$env:TEMP\$ZipName"

    if (-not (Test-Path $cacheFile)) {
        Write-Host "[ERROR] Cache not found: $cacheFile" -ForegroundColor Red
        exit 1
    }

    if (Test-Path $NodeDir) {
        Remove-Item $NodeDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "[INFO] Installing Node.js $targetVer ..." -ForegroundColor Cyan
    Copy-Item -Path $cacheFile -Destination $zipFile -Force

    try {
        Expand-Archive -Path $zipFile -DestinationPath "$env:TEMP\node-extract" -Force -ErrorAction Stop
        # node zip extracts to node-v$Version-win-x64/ subdirectory
        $extracted = Get-ChildItem "$env:TEMP\node-extract" -Directory | Select-Object -First 1
        if ($extracted) {
            Move-Item -Path $extracted.FullName -Destination $NodeDir -Force
        } else {
            Write-Host "[ERROR] Unexpected archive structure" -ForegroundColor Red
            Remove-Item "$env:TEMP\node-extract" -Recurse -Force -ErrorAction SilentlyContinue
            exit 1
        }
        Remove-Item "$env:TEMP\node-extract" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Extracted to $NodeDir" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Extract failed: $_" -ForegroundColor Red
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        exit 1
    }

    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

    # ── PATH ──
    Add-UserPath -Dir $NodeDir

    # ── Verify ──
    Update-Environment
    $verifyVer = Get-InstalledNodeVersion
    if ($verifyVer) {
        Show-InstallComplete -Tool "Node.js" -Version $verifyVer
    } else {
        Write-Host "[OK] Node.js installed" -ForegroundColor Green
        Write-Host "  Location: $NodeDir" -ForegroundColor DarkGray
    }

    Set-NodeLock -Version $targetVer
    Write-Host "[OK] Locked: $targetVer" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# update
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-NodeUpdate {
    <#
    .SYNOPSIS
        Check for a newer Node.js LTS version and prompt for upgrade.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $installed = Get-InstalledNodeVersion
    $installed = if ($installed) { $installed } else { "not installed" }

    Write-Host "[INFO] Node.js: $installed" -ForegroundColor Cyan

    try {
        $latest = Get-LatestNodeVersion
        Write-Host "[OK] Latest LTS: $latest" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Cannot check latest version: $_" -ForegroundColor Yellow
        return
    }

    if (-not $installed -or $installed -eq "not installed") {
        Write-Host "[INFO] Not installed, installing $latest ..." -ForegroundColor Cyan
        Invoke-NodeInstall
        return
    }

    if (-not (Get-NodeLock)) { Set-NodeLock -Version $installed }

    $cmp = Compare-SemanticVersion -Current $installed -Latest $latest
    if ($cmp -ge 0) {
        Show-AlreadyInstalled -Tool "Node.js" -Version $installed
        return
    }

    Write-Host "[UPGRADE] $installed -> $latest" -ForegroundColor Cyan
    $response = Read-Host "  Upgrade? (Y/n)"
    if ($response -and $response -ne 'Y' -and $response -ne 'y') {
        Write-Host "[INFO] Skipped" -ForegroundColor DarkGray
        return
    }

    Invoke-NodeInstall
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-NodeUninstall {
    <#
    .SYNOPSIS
        Remove the installed Node.js directory, PATH entry, and version lock.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $NodeDir) -and -not (Test-Path $NodeConfigFile)) {
        Write-Host '[INFO] Node.js not installed, nothing to uninstall' -ForegroundColor Cyan
        return
    }

    Write-Host "[INFO] Uninstalling Node.js from $NodeDir ..." -ForegroundColor Cyan

    if (Test-Path $NodeDir) {
        try {
            Remove-Item $NodeDir -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Removed: $NodeDir" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Could not fully remove $NodeDir : $_" -ForegroundColor Yellow
        }
    }

    Remove-UserPath -Dir $NodeDir

    if (Test-Path $NodeConfigFile) {
        Remove-Item $NodeConfigFile -Force -ErrorAction SilentlyContinue
        Show-LockRemoved
    }

    Write-Host "[OK] Node.js uninstalled" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"     { Invoke-NodeCheck }
    "download"  { Invoke-NodeDownload }
    "install"   { Invoke-NodeInstall }
    "update"    { Invoke-NodeUpdate }
    "uninstall" { Invoke-NodeUninstall }
}
