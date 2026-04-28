#Requires -Version 5.1

<#
.SYNOPSIS
    Manage .NET SDK installation using aria2c for downloading.
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
$DotnetDir       = "$script:OhmyRoot\.envs\dev\dotnet"
$DotnetExe       = "$DotnetDir\dotnet.exe"
$DotnetConfigFile = Join-Path $script:OhmyRoot ".config\dotnet\config.json"
$CacheDir        = Join-Path $script:DevSetupRoot "dotnet"
$DefaultChannel  = "LTS"
$FeedBase        = "https://builds.dotnet.microsoft.com/dotnet"
$NoBom           = New-Object System.Text.UTF8Encoding $false

function Get-DotnetLock {
    <#
    .SYNOPSIS
        Read the locked version from the dotnet config file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path $DotnetConfigFile)) { return }
    try {
        $cfg = Get-Content $DotnetConfigFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($cfg.lock) { return $cfg.lock }
    } catch {}
}

function Set-DotnetLock {
    <#
    .SYNOPSIS
        Write the locked version to the dotnet config file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Ver
    )

    $dir = Split-Path $DotnetConfigFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = @{ lock = $Ver } | ConvertTo-Json
    [System.IO.File]::WriteAllText($DotnetConfigFile, $json.Trim(), $NoBom)
}

function Get-InstalledDotnetVersion {
    <#
    .SYNOPSIS
        Query the locally installed .NET SDK version string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path $DotnetExe)) { return $null }
    try {
        $raw = & $DotnetExe --version 2>$null | Out-String
        $raw = $raw.Trim()
        if ($raw -match '\d+\.\d+\.\d+') { return $raw }
    } catch {}
    $null
}

function Get-LatestDotnetVersion {
    <#
    .SYNOPSIS
        Fetch the latest SDK version from the official builds feed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Channel = $DefaultChannel
    )

    $url = "$FeedBase/Sdk/$Channel/latest.version"
    try {
        $content = Invoke-RestMethod -Uri $url -TimeoutSec 15 -ErrorAction Stop
        $parts = $content -split '\s+'
        return $parts[-1]
    } catch {
        throw "Failed to fetch latest .NET $Channel version: $_"
    }
}

function Resolve-DotnetDownloadInfo {
    <#
    .SYNOPSIS
        Resolve version and construct the SDK download URL from the official feed.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$Ver,
        [string]$Channel = $DefaultChannel
    )

    if (-not $Ver) {
        $Ver = Get-LatestDotnetVersion -Channel $Channel
    }

    $pvUrl = "$FeedBase/Sdk/$Ver/sdk-productVersion.txt"
    try {
        $productVersion = (Invoke-RestMethod -Uri $pvUrl -TimeoutSec 15 -ErrorAction Stop).Trim()
    } catch {
        $productVersion = $Ver
    }

    $url     = "$FeedBase/Sdk/$Ver/dotnet-sdk-$productVersion-win-x64.zip"
    $zipName = "dotnet-sdk-$productVersion-win-x64.zip"

    return @{
        Version        = $Ver
        ProductVersion = $productVersion
        Url            = $url
        ZipName        = $zipName
    }
}

function Find-Aria2c {
    <#
    .SYNOPSIS
        Locate the aria2c executable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $aria2c = Get-Command aria2c.exe -ErrorAction SilentlyContinue
    if ($aria2c) { return $aria2c.Source }

    $fallback = "$script:OhmyRoot\.envs\base\bin\aria2c.exe"
    if (Test-Path $fallback) { return $fallback }

    throw "aria2c not found. Run 'omc install aria2' first."
}

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DotnetCheck {
    <#
    .SYNOPSIS
        Display the current .NET SDK installation, lock, cache, and PATH status.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- .NET SDK ---" -ForegroundColor Cyan

    $installed = Get-InstalledDotnetVersion

    if ($installed) {
        Write-Host "[OK] Installed: .NET SDK $installed ($DotnetDir)" -ForegroundColor Green
    } else {
        Write-Host "[INFO] .NET SDK not installed" -ForegroundColor Cyan
        Write-Host "  Expected: $DotnetDir" -ForegroundColor DarkGray
    }

    $lock = Get-DotnetLock
    if ($lock) {
        if ($installed -and $installed -eq $lock) {
            Write-Host "[OK] Locked: $lock (current)" -ForegroundColor Green
        } else {
            Write-Host "[LOCK] Locked: $lock" -ForegroundColor Magenta
        }
    } else {
        Write-Host "[INFO] No version lock" -ForegroundColor DarkGray
    }

    if (Test-Path $CacheDir) {
        $cached = Get-ChildItem -Path $CacheDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -eq '.zip' } |
            Sort-Object LastWriteTime -Descending
        if ($cached) {
            $names = ($cached | ForEach-Object { $_.Name }) -join ', '
            Write-Host "[CACHE] $CacheDir" -ForegroundColor DarkGray
            Write-Host "        $names" -ForegroundColor DarkGray
        } else {
            Write-Host "[CACHE] No cached downloads in $CacheDir" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[CACHE] No cache directory" -ForegroundColor DarkGray
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -split ';' -contains $DotnetDir) {
        Write-Host "[OK] PATH: $DotnetDir" -ForegroundColor DarkGray
    } else {
        Write-Host "[INFO] PATH: not set" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# download
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DotnetDownload {
    <#
    .SYNOPSIS
        Download the .NET SDK zip to cache using aria2c.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $lockVer = Get-DotnetLock
    if ($Version) {
        $targetVer = $Version
    } elseif ($lockVer) {
        $targetVer = $lockVer
    } else {
        try {
            $targetVer = Get-LatestDotnetVersion -Channel $DefaultChannel
            Write-Host "[OK] .NET SDK latest $DefaultChannel`: $targetVer" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Cannot resolve latest version: $_" -ForegroundColor Yellow
            return
        }
    }

    $info = Resolve-DotnetDownloadInfo -Ver $targetVer
    Write-Host "[INFO] .NET SDK $($info.ProductVersion)" -ForegroundColor Cyan

    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }

    $cacheFile = Join-Path $CacheDir $info.ZipName
    if (Test-Path $cacheFile) {
        $size = (Get-Item $cacheFile).Length
        $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
        Write-Host "[OK] Cached: $sizeStr" -ForegroundColor Green
        Write-Host "      $cacheFile" -ForegroundColor DarkGray
        Set-DotnetLock -Ver $info.ProductVersion
        return
    }

    $aria2c = Find-Aria2c
    Write-Host "[INFO] Downloading $($info.ZipName) ..." -ForegroundColor Cyan

    & $aria2c -x 16 -s 16 -k 1M -d $CacheDir -o $info.ZipName $info.Url
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] aria2c download failed" -ForegroundColor Red
        exit 1
    }

    $size = (Get-Item $cacheFile).Length
    $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
    Write-Host "[OK] Downloaded: $sizeStr" -ForegroundColor Green
    Write-Host "      $cacheFile" -ForegroundColor DarkGray

    Set-DotnetLock -Ver $info.ProductVersion
    Write-Host "[OK] Locked: $($info.ProductVersion)" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# install
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DotnetInstall {
    <#
    .SYNOPSIS
        Download .NET SDK with aria2c, extract, and configure PATH.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $installed = Get-InstalledDotnetVersion

    # ── Determine version ──
    if ($Version) {
        $targetVer = $Version
    } else {
        $lockVer = Get-DotnetLock
        if ($lockVer) {
            $targetVer = $lockVer
        } else {
            try {
                $targetVer = Get-LatestDotnetVersion -Channel $DefaultChannel
                Write-Host "[OK] .NET SDK latest $DefaultChannel`: $targetVer" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Cannot resolve latest version: $_" -ForegroundColor Yellow
                return
            }
        }
    }

    # ── Idempotent check ──
    if ($installed -and $targetVer -and $installed -eq $targetVer -and -not $Force) {
        Show-AlreadyInstalled -Tool ".NET SDK" -Version $installed -Location $DotnetDir
        if (-not (Get-DotnetLock)) { Set-DotnetLock -Ver $installed }
        return
    }
    if ($installed -and $targetVer) {
        Write-Host "[UPGRADE] .NET SDK $installed -> $targetVer" -ForegroundColor Cyan
    }

    # ── Resolve download info ──
    $info = Resolve-DotnetDownloadInfo -Ver $targetVer

    # ── Download ──
    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }

    $cacheFile = Join-Path $CacheDir $info.ZipName
    if (-not (Test-Path $cacheFile)) {
        $aria2c = Find-Aria2c
        Write-Host "[INFO] Downloading $($info.ZipName) ..." -ForegroundColor Cyan
        & $aria2c -x 16 -s 16 -k 1M -d $CacheDir -o $info.ZipName $info.Url
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] aria2c download failed" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "[OK] Using cached $($info.ZipName)" -ForegroundColor Green
    }

    # ── Extract ──
    Write-Host "[INFO] Extracting to $DotnetDir ..." -ForegroundColor Cyan

    if (Test-Path $DotnetDir) {
        Remove-Item $DotnetDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $DotnetDir -Force | Out-Null

    $7z = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($7z) {
        & $7z.Source x $cacheFile "-o$DotnetDir" -y
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] 7z extraction failed" -ForegroundColor Red
            exit 1
        }
    } else {
        try {
            Expand-Archive -Path $cacheFile -DestinationPath $DotnetDir -Force -ErrorAction Stop
        } catch {
            Write-Host "[ERROR] Extraction failed: $_" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "[OK] Extracted to $DotnetDir" -ForegroundColor Green

    # ── PATH ──
    Add-UserPath -Dir $DotnetDir

    # ── Verify ──
    Update-Environment
    $verifyVer = Get-InstalledDotnetVersion
    if ($verifyVer) {
        Show-InstallComplete -Tool ".NET SDK" -Version $verifyVer
        Set-DotnetLock -Ver $verifyVer
        Write-Host "[OK] Locked: $verifyVer" -ForegroundColor Green
    } else {
        Write-Host "[OK] .NET SDK installed" -ForegroundColor Green
        Write-Host "  Location: $DotnetDir" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# update
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DotnetUpdate {
    <#
    .SYNOPSIS
        Check for a newer .NET SDK version and prompt for upgrade.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $installed = Get-InstalledDotnetVersion
    $installed = if ($installed) { $installed } else { "not installed" }

    Write-Host "[INFO] .NET SDK: $installed" -ForegroundColor Cyan

    try {
        $latest = Get-LatestDotnetVersion -Channel $DefaultChannel
        Write-Host "[OK] Latest $DefaultChannel`: $latest" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Cannot check latest version: $_" -ForegroundColor Yellow
        return
    }

    if (-not $installed -or $installed -eq "not installed") {
        Write-Host "[INFO] Not installed, installing $latest ..." -ForegroundColor Cyan
        Invoke-DotnetInstall
        return
    }

    if (-not (Get-DotnetLock)) { Set-DotnetLock -Ver $installed }

    $cmp = Compare-SemanticVersion -Current $installed -Latest $latest
    if ($cmp -ge 0) {
        Show-AlreadyInstalled -Tool ".NET SDK" -Version $installed
        return
    }

    Write-Host "[UPGRADE] $installed -> $latest" -ForegroundColor Cyan
    $response = Read-Host "  Upgrade? (Y/n)"
    if ($response -and $response -ne 'Y' -and $response -ne 'y') {
        Write-Host "[INFO] Skipped" -ForegroundColor DarkGray
        return
    }

    Invoke-DotnetInstall
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DotnetUninstall {
    <#
    .SYNOPSIS
        Remove the installed .NET SDK directory, PATH entry, and version lock.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $DotnetDir) -and -not (Test-Path $DotnetConfigFile)) {
        Write-Host '[INFO] .NET SDK not installed, nothing to uninstall' -ForegroundColor Cyan
        return
    }

    Write-Host "[INFO] Uninstalling .NET SDK from $DotnetDir ..." -ForegroundColor Cyan

    if (Test-Path $DotnetDir) {
        try {
            Remove-Item $DotnetDir -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Removed: $DotnetDir" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Could not fully remove $DotnetDir : $_" -ForegroundColor Yellow
        }
    }

    Remove-UserPath -Dir $DotnetDir

    if (Test-Path $DotnetConfigFile) {
        Remove-Item $DotnetConfigFile -Force -ErrorAction SilentlyContinue
        Show-LockRemoved
    }

    Write-Host "[OK] .NET SDK uninstalled" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"     { Invoke-DotnetCheck }
    "download"  { Invoke-DotnetDownload }
    "install"   { Invoke-DotnetInstall }
    "update"    { Invoke-DotnetUpdate }
    "uninstall" { Invoke-DotnetUninstall }
}
