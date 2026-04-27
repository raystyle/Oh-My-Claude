#Requires -Version 5.1

<#
.SYNOPSIS
    Install PowerShell 7 (pwsh) from GitHub Releases via MSI installer.
.PARAMETER Command
    Action: check, install, uninstall.
.PARAMETER Version
    Specific version to install (default: latest).
.PARAMETER Force
    Skip upgrade confirmation prompt.
#>

[CmdletBinding()]
param(
    [ValidateSet("check", "install", "uninstall", "update", "download")]
    [string]$Command = "check",

    [AllowEmptyString()]
    [string]$Version = "",

    [switch]$Force
)

. "$PSScriptRoot\..\helpers.ps1"

$Repo    = "PowerShell/PowerShell"
$PwshDir = "$Env:ProgramFiles\PowerShell\7"
$PwshExe = "$PwshDir\pwsh.exe"
$script:PwshConfigFile = Join-Path $script:OhmyRoot ".config\pwsh\config.json"

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PwshCheck {
    <#
    .SYNOPSIS
        Display PowerShell 7 installation, PATH, lock, and cache status.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- PowerShell ---" -ForegroundColor Cyan

    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd) { $pwshCmd = Get-Command $PwshExe -ErrorAction SilentlyContinue }

    $installedVer = ""
    if ($pwshCmd) {
        $raw = & $pwshCmd.Source --version 2>&1 | Out-String
        if ($raw -match 'PowerShell\s+(\d+\.\d+\.\d+)') {
            $installedVer = $Matches[1]
            Write-Host "[OK] PowerShell $installedVer" -ForegroundColor Green
            Write-Host "  Location: $($pwshCmd.Source)" -ForegroundColor DarkGray
        } else {
            Write-Host "[OK] pwsh found at $($pwshCmd.Source)" -ForegroundColor Green
        }
    } else {
        Write-Host "[INFO] PowerShell 7 (pwsh) not installed" -ForegroundColor Cyan
        Write-Host "  Expected: $PwshDir" -ForegroundColor DarkGray
    }

    # PATH check
    $pwshInPath = $null -ne (Get-Command pwsh -ErrorAction SilentlyContinue)
    if ($pwshInPath) {
        Write-Host "[OK] pwsh in PATH" -ForegroundColor DarkGray
    } else {
        Write-Host "[INFO] pwsh not in PATH" -ForegroundColor DarkGray
    }

    # Lock
    $pwshLock = $null
    if (Test-Path $script:PwshConfigFile) {
        $cfg = Get-Content $script:PwshConfigFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($cfg.lock) { $pwshLock = $cfg.lock }
    }
    if ($pwshLock) {
        if ($installedVer -and $installedVer -eq $pwshLock) {
            Write-Host "[OK] Locked: $pwshLock (current)" -ForegroundColor Green
        } else {
            Write-Host "[LOCK] Locked: $pwshLock" -ForegroundColor Magenta
        }
    } else {
        Write-Host "[INFO] No version lock" -ForegroundColor DarkGray
    }

    # Cache status
    $pwshCacheDir = Join-Path $script:DevSetupRoot "pwsh"
    if (Test-Path $pwshCacheDir) {
        $cacheFiles = Get-ChildItem "$pwshCacheDir\*.msi" -ErrorAction SilentlyContinue
        if ($cacheFiles) {
            Write-Host "[OK] Cache: $($cacheFiles.Count) MSI(s) in $pwshCacheDir" -ForegroundColor DarkGray
            foreach ($f in $cacheFiles) {
                Write-Host "  $($f.Name) ($([math]::Round($f.Length / 1MB, 1)) MB)" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "[INFO] Cache dir exists (empty): $pwshCacheDir" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[INFO] No cache: $pwshCacheDir" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# install
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PwshInstall {
    <#
    .SYNOPSIS
        Install or upgrade PowerShell 7 via MSI installer with elevation.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # ── Self-elevation (MSI per-machine install requires admin) ──
    $shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "[INFO] Elevating to admin..." -ForegroundColor Yellow
        $logFile = Join-Path $env:TEMP "pwsh7_install.log"
        Remove-Item $logFile -Force -ErrorAction SilentlyContinue

        $elevArgs = [System.Collections.ArrayList]@(
            "-NoLogo", "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`"",
            $Command,
            "-Version", "`"$Version`""
        )
        if ($Force) { $null = $elevArgs.Add("-Force") }
        $proc = Start-Process $shell -Verb RunAs -ArgumentList $elevArgs -Wait -PassThru
        Remove-Item $logFile -Force -ErrorAction SilentlyContinue
        exit $proc.ExitCode
    }

    # ── Elevated: capture output via transcript ──
    $logFile = Join-Path $env:TEMP "pwsh7_install.log"
    Start-Transcript -Path $logFile -Force 6>$null

    try {
        $ErrorActionPreference = 'Stop'
        $script:exitCode = 0

        # ── 0. Idempotent check ──
        $installed = $false
        $installedVersion = ""

        $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwshCmd) { $PwshExe = $pwshCmd.Source }

        if ($pwshCmd -or (Test-Path $PwshExe)) {
            $raw = & $PwshExe --version 2>&1 | Out-String
            if ($raw -match 'PowerShell\s+(\d+\.\d+\.\d+)') {
                $installedVersion = $Matches[1]
                $installed = $true
            }
        }

        # Install command: skip if already installed (no API call)
        if ($Command -eq "install" -and $installed -and -not $Force) {
            Show-AlreadyInstalled -Tool "PowerShell 7" -Version $installedVersion -Location (Split-Path $PwshExe -Parent)
            $pwshLock = $null
            if (Test-Path $script:PwshConfigFile) {
                $cfg = Get-Content $script:PwshConfigFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
                if ($cfg.lock) { $pwshLock = $cfg.lock }
            }
            if (-not $pwshLock) {
                $configDir = Split-Path $script:PwshConfigFile -Parent
                if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
                $lockJson = @{ lock = $installedVersion } | ConvertTo-Json
                [System.IO.File]::WriteAllText($script:PwshConfigFile, $lockJson.Trim(), (New-Object System.Text.UTF8Encoding $false))
                Write-Host "[OK] Lock restored: $installedVersion" -ForegroundColor Green
            }
            $pwshCacheDir = Join-Path $script:DevSetupRoot "pwsh"
            if (Test-Path $pwshCacheDir) {
                $cacheFiles = Get-ChildItem "$pwshCacheDir\*.msi" -ErrorAction SilentlyContinue
                if ($cacheFiles) {
                    Write-Host "[OK] Cache: $($cacheFiles.Count) MSI(s) in $pwshCacheDir" -ForegroundColor DarkGray
                }
            }
            return
        }

        # ── 1. Resolve version ──
        $release = $null
        $tag = ""

        if (-not $Version) {
            Write-Host "[INFO] Fetching latest release for $Repo..." -ForegroundColor Cyan
            try {
                $release = Get-GitHubRelease -Repo $Repo
                $rawTag  = $release.tag_name
                $Version = $rawTag -replace '^v', ''
                $tag     = $rawTag
                Write-Host "[OK] Latest version: $Version" -ForegroundColor Green
            } catch {
                if ($installed) {
                    Show-AlreadyInstalled -Tool "PowerShell 7" -Version $installedVersion -Location (Split-Path $PwshExe -Parent)
                    Write-Host "[WARN] Could not check for updates: $_" -ForegroundColor Yellow
                    return
                }
                Write-Host "[ERROR] Cannot determine version to install: $_" -ForegroundColor Red
                $script:exitCode = 1; return
            }
        } else {
            $tag = "v$Version"
        }

        # ── 2. Check if already installed and up to date ──
        if ($installed) {
            $upgradeCheck = Test-UpgradeRequired -Current $installedVersion -Target $Version -ToolName "powershell7" -Force:$Force
            if (-not $upgradeCheck.Required) {
                Show-AlreadyInstalled -Tool "PowerShell 7" -Version $installedVersion -Location (Split-Path $PwshExe -Parent)
                Write-Host "     $($upgradeCheck.Reason)" -ForegroundColor DarkGray
                $pwshLock = $null
                if (Test-Path $script:PwshConfigFile) {
                    $cfg = Get-Content $script:PwshConfigFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
                    if ($cfg.lock) { $pwshLock = $cfg.lock }
                }
                if (-not $pwshLock) {
                    $configDir = Split-Path $script:PwshConfigFile -Parent
                    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
                    $lockJson = @{ lock = $installedVersion } | ConvertTo-Json
                    [System.IO.File]::WriteAllText($script:PwshConfigFile, $lockJson.Trim(), (New-Object System.Text.UTF8Encoding $false))
                    Write-Host "[OK] Lock restored: $installedVersion" -ForegroundColor Green
                }
                return
            }

            Write-Host "[UPGRADE] PowerShell $installedVersion -> $Version" -ForegroundColor Cyan
            Write-Host "     $($upgradeCheck.Reason)" -ForegroundColor DarkGray

            if (-not $Force) {
                $response = Read-Host "  Upgrade? (Y/n)"
                if ($response -and $response -ne 'Y' -and $response -ne 'y') {
                    Write-Host "[INFO] Skipped" -ForegroundColor DarkGray
                    return
                }
            }
        }

        Show-Installing -Component "PowerShell 7 $Version"

        # ── 3. Download MSI ──
        $msiName     = "PowerShell-${Version}-win-x64.msi"
        $downloadUrl = "https://github.com/$Repo/releases/download/$tag/$msiName"
        $msiFile     = "$env:TEMP\$msiName"

        Write-Host "[INFO] Downloading $msiName ..." -ForegroundColor Cyan

        if (-not $release) {
            try {
                $release = Get-GitHubRelease -Repo $Repo -Tag $tag
            } catch {
                Write-Host "[WARN] Could not fetch release metadata, hash verification skipped" -ForegroundColor Yellow
                $release = $null
            }
        }

        try {
            Save-WithCache -Url $downloadUrl -OutFile $msiFile -CacheDir "pwsh" -TimeoutSec 300 `
                -GhRepo $Repo -GhTag $tag -GhAssetPattern $msiName
        } catch {
            Write-Host "[ERROR] Failed to download $msiName : $_" -ForegroundColor Red
            $script:exitCode = 1; return
        }

        # ── 4. Verify ──
        $attestationOk = Test-GitHubAssetAttestation -Repo $Repo -Tag $tag -FilePath $msiFile
        try {
            if (-not $attestationOk) {
                Test-FileHash -FilePath $msiFile -Release $release -AssetName $msiName -Repo $Repo -Tag $tag
            }
        } catch {
            Write-Host "[ERROR] Hash verification failed: $($_.Exception.Message)" -ForegroundColor Red
            Remove-Item $msiFile -Force -ErrorAction SilentlyContinue
            $script:exitCode = 1; return
        }

        # ── 5. Run msiexec ──
        Write-Host "[INFO] Installing PowerShell $Version ..." -ForegroundColor Cyan
        Write-Host "[INFO] msiexec /package $msiName /passive ADD_PATH=1 ..." -ForegroundColor DarkGray

        $msiexecArgs = @(
            "/package", $msiFile,
            "/passive",
            "ADD_PATH=1",
            "ENABLE_PSREMOTING=1",
            "REGISTER_MANIFEST=1",
            "USE_MU=0",
            "ENABLE_MU=0",
            "/norestart"
        )

        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiexecArgs -Wait -PassThru -NoNewWindow
        Remove-Item $msiFile -Force -ErrorAction SilentlyContinue

        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
            if ($proc.ExitCode -eq 3010) {
                Write-Host "[WARN] Reboot required before pwsh is fully usable" -ForegroundColor Yellow
            }
            Write-Host "[OK] msiexec completed (exit code: $($proc.ExitCode))" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] msiexec failed with exit code: $($proc.ExitCode)" -ForegroundColor Red
            $script:exitCode = 1; return
        }

        # ── 6. Refresh environment and verify ──
        Update-Environment

        $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
        if (-not $pwshCmd) { $pwshCmd = Get-Command $PwshExe -ErrorAction SilentlyContinue }

        if (-not $pwshCmd) {
            Write-Host "[WARN] pwsh not found in PATH after install (reboot may be needed)" -ForegroundColor Yellow
            if (Test-Path $PwshExe) {
                $pwshCmd = @{ Source = $PwshExe }
            } else {
                Write-Host "[ERROR] pwsh.exe not found at expected location" -ForegroundColor Red
                $script:exitCode = 1; return
            }
        }

        $raw = & $pwshCmd.Source --version 2>&1 | Out-String
        if ($raw -match 'PowerShell\s+(\d+\.\d+\.\d+)') {
            $installedVersion = $Matches[1]
            Write-Host "[OK] Installed: $($raw.Trim())" -ForegroundColor Green
            Write-Host "[INFO] Path: $($pwshCmd.Source)" -ForegroundColor Cyan
        } else {
            Write-Host "[ERROR] Verification failed: could not parse version from pwsh --version" -ForegroundColor Red
            $script:exitCode = 1; return
        }

        # ── 7. Summary ──
        Write-Host ""
        Show-InstallComplete -Tool "PowerShell 7" -Version $installedVersion

        # ── 8. Write version lock ──
        $configDir = Split-Path $script:PwshConfigFile -Parent
        if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
        $lockJson = @{ lock = $installedVersion } | ConvertTo-Json
        [System.IO.File]::WriteAllText($script:PwshConfigFile, $lockJson.Trim(), (New-Object System.Text.UTF8Encoding $false))
        Show-LockWrite -Version $installedVersion

    } finally {
        Stop-Transcript -ErrorAction SilentlyContinue 6>$null
        if ($script:exitCode) { exit $script:exitCode }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# download (cache MSI, no install)
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PwshDownload {
    <#
    .SYNOPSIS
        Download the locked PowerShell 7 MSI to the local cache without installing.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $ErrorActionPreference = 'Stop'
    $release = $null
    $tag = ""

    # ── 1. Read lock version ──
    $pwshLock = $null
    if (Test-Path $script:PwshConfigFile) {
        $cfg = Get-Content $script:PwshConfigFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($cfg.lock) { $pwshLock = $cfg.lock }
    }
    if (-not $pwshLock) {
        Write-Host "[INFO] No version lock for pwsh. Use 'omc install pwsh' to install and set a lock." -ForegroundColor Cyan
        return
    }
    $Version = $pwshLock
    $tag = "v$Version"

    # ── 2. Check cache for locked version ──
    $msiName   = "PowerShell-${Version}-win-x64.msi"
    $cacheDir  = Join-Path $script:DevSetupRoot "pwsh"
    $cacheFile = Join-Path $cacheDir $msiName
    $hashFile  = "$cacheFile.sha256"

    if ((Test-Path $cacheFile) -and (Test-Path $hashFile)) {
        $cachedHash = (Get-Content $hashFile -Raw).Trim()
        $actualHash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
        if ($cachedHash -eq $actualHash) {
            Write-Host "[OK] pwsh: cached (locked $Version)" -ForegroundColor Green
            return
        }
    }

    # ── 3. Download ──
    $downloadUrl = "https://github.com/$Repo/releases/download/$tag/$msiName"
    $msiFile     = "$env:TEMP\$msiName"
    Write-Host "[INFO] Downloading $msiName ..." -ForegroundColor Cyan

    try { $release = Get-GitHubRelease -Repo $Repo -Tag $tag } catch { }

    Save-WithCache -Url $downloadUrl -OutFile $msiFile -CacheDir "pwsh" -TimeoutSec 300 `
        -GhRepo $Repo -GhTag $tag -GhAssetPattern $msiName

    $attestationOk = Test-GitHubAssetAttestation -Repo $Repo -Tag $tag -FilePath $msiFile

    try {
        if (-not $attestationOk) {
            Test-FileHash -FilePath $msiFile -Release $release -AssetName $msiName -Repo $Repo -Tag $tag
        }
    } catch {
        Write-Host "[ERROR] Hash verification failed: $_" -ForegroundColor Red
        Remove-Item $msiFile -Force -ErrorAction SilentlyContinue
        return
    }

    Remove-Item $msiFile -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] pwsh $Version downloaded and cached" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PwshUninstall {
    <#
    .SYNOPSIS
        Uninstall PowerShell 7 by removing the MSI product and install directory.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "=== Uninstall PowerShell 7 ===" -ForegroundColor Cyan

    # ── Pre-check: see if anything is installed before elevating ──
    $productCode = $null
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($path in $uninstallPaths) {
        $entry = Get-ItemProperty $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*PowerShell 7*' -and $_.PSChildName -match '^\{' } |
            Select-Object -First 1
        if ($entry) {
            $productCode = $entry.PSChildName
            break
        }
    }

    if (-not $productCode -and -not (Test-Path $PwshDir)) {
        Write-Host '[INFO] PowerShell 7 not installed, nothing to uninstall' -ForegroundColor Cyan
        return
    }

    # ── Self-elevation (MSI uninstall + Program Files requires admin) ──
    $shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "[INFO] Elevating to admin..." -ForegroundColor Yellow
        $proc = Start-Process $shell -Verb RunAs -ArgumentList @(
            "-NoLogo", "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`"",
            "uninstall"
        ) -Wait -PassThru
        exit $proc.ExitCode
    }

    # Admin path
    $ErrorActionPreference = 'Stop'

    # $productCode was already resolved in the pre-check above
    if ($productCode) {
        $displayName = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$productCode" -ErrorAction SilentlyContinue).DisplayName
        Write-Host "[INFO] Found: $displayName (code: $productCode)" -ForegroundColor Cyan

        # ── 2. Run msiexec /x ──
        Write-Host "[INFO] Running msiexec /x $productCode /quiet /norestart ..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList @(
            "/x", $productCode, "/passive", "/norestart"
        ) -Wait -PassThru -NoNewWindow

        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010 -or $proc.ExitCode -eq 1605) {
            Write-Host "[OK] MSI uninstall completed (exit code: $($proc.ExitCode))" -ForegroundColor Green
        } else {
            Write-Host "[WARN] msiexec exit code: $($proc.ExitCode)" -ForegroundColor Yellow
        }
    }

    # ── 3. Remove install directory (if MSI left files) ──
    if (Test-Path $PwshDir) {
        Write-Host "[INFO] Cleaning up $PwshDir ..." -ForegroundColor Cyan

        # Tier 1: PowerShell Remove-Item
        $removed = $false
        try {
            Remove-Item -Path $PwshDir -Recurse -Force -ErrorAction Stop
            $removed = $true
        } catch {
            Write-Host "[WARN] Direct removal failed: $_" -ForegroundColor Yellow
        }

        # Tier 2: cmd rd /s /q
        if (-not $removed -and (Test-Path $PwshDir)) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "rd /s /q `"$PwshDir`"" `
                -NoNewWindow -PassThru -Wait | Out-Null
            if (-not (Test-Path $PwshDir)) { $removed = $true }
        }

        # Tier 3: rename and defer
        if (-not $removed -and (Test-Path $PwshDir)) {
            $pendingName = "$PwshDir.pending-delete.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            try {
                Rename-Item -Path $PwshDir -NewName (Split-Path $pendingName -Leaf) -Force -ErrorAction Stop
                Write-Host "[WARN] Renamed to: $pendingName" -ForegroundColor Yellow
                $removed = $true
            } catch {
                Write-Host "[ERROR] Could not remove or rename: $PwshDir" -ForegroundColor Red
            }
        }

        if ($removed -and -not (Test-Path $PwshDir)) {
            Write-Host "[OK] Removed $PwshDir" -ForegroundColor Green
        }
    } else {
        Write-Host "[OK] $PwshDir does not exist (already clean)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "[OK] PowerShell 7 uninstalled" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"     { Invoke-PwshCheck }
    "download"  { Invoke-PwshDownload }
    "install"   { Invoke-PwshInstall }
    "update"    { Invoke-PwshInstall }
    "uninstall" { Invoke-PwshUninstall }
}
