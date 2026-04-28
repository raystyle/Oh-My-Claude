#Requires -Version 5.1

<#
.SYNOPSIS
    Install PowerShellEditorServices (PSES) from GitHub Releases.
.DESCRIPTION
    PSES is a Language Server Protocol server for PowerShell, used by
    editors like VS Code and Claude Code. Not published to PSGallery —
    distributed as a zip from GitHub Releases.
.PARAMETER Command
    Action: check, install, download, uninstall, update.
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

$Repo = "PowerShell/PowerShellEditorServices"
$AssetName = "PowerShellEditorServices.zip"
$script:PsesConfigFile = Join-Path $script:OhmyRoot ".config\pses\config.json"

# ═══════════════════════════════════════════════════════════════════════════
# helpers
# ═══════════════════════════════════════════════════════════════════════════

function Get-PsesInstallDir {
    <#
    .SYNOPSIS
        Return the PSES install root directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path $script:OhmyRoot '.envs\dev\pses'
}

function Get-PsesModuleDir {
    <#
    .SYNOPSIS
        Return the PSES module directory (contains .psd1).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path (Get-PsesInstallDir) "PowerShellEditorServices"
}

function Get-PsesConfig {
    <#
    .SYNOPSIS
        Read PSES config (lock + path).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not (Test-Path $script:PsesConfigFile)) { return @{} }

    try {
        $cfg = Get-Content $script:PsesConfigFile -Raw -Encoding UTF8 -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        $result = @{}
        $cfg.PSObject.Properties | ForEach-Object { $result[$_.Name] = $_.Value }
        $result
    } catch {
        @{}
    }
}

function Set-PsesConfig {
    <#
    .SYNOPSIS
        Write PSES config (lock version + install path).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [string]$Lock = "",
        [string]$Path = ""
    )

    $configDir = Split-Path $script:PsesConfigFile -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $config = Get-PsesConfig
    if ($Lock) { $config['lock'] = $Lock }
    if ($Path) { $config['path'] = $Path }

    $noBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText(
        $script:PsesConfigFile,
        ($config | ConvertTo-Json -Depth 1).Trim(),
        $noBom
    )
}

function Get-PsesInstalledVersion {
    <#
    .SYNOPSIS
        Parse ModuleVersion from the PSES .psd1 manifest.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $manifest = Join-Path (Get-PsesModuleDir) "PowerShellEditorServices.psd1"
    if (-not (Test-Path $manifest)) { return "" }

    try {
        $content = Get-Content $manifest -Raw -Encoding UTF8 -ErrorAction Stop
        if ($content -match "ModuleVersion\s*=\s*'(\d+\.\d+\.\d+)") {
            return $Matches[1]
        }
    } catch { }

    ""
}

function Get-PsesLatestVersion {
    <#
    .SYNOPSIS
        Fetch the latest PSES release version from GitHub.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $release = Get-GitHubRelease -Repo $Repo
    $release.tag_name -replace '^v', ''
}

function Add-PsesModulePath {
    <#
    .SYNOPSIS
        Idempotently add the PSES module parent dir to user PSModulePath.
        Ensures Documents module paths are preserved for PS5/PS7 compatibility.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $moduleParent = Get-PsesInstallDir
    $normalizedDir = $moduleParent.TrimEnd('\')

    $currentPath = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
    if (-not $currentPath) { $currentPath = '' }

    $entries = ($currentPath -split ';') |
        ForEach-Object { $_.TrimEnd('\') } |
        Where-Object { $_ -ne '' }

    if ($entries -contains $normalizedDir) { return }

    # Ensure Documents module paths are present when user-level is first set,
    # otherwise PS5 loses its default module search path.
    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    $requiredDirs = @(
        "$myDocs\WindowsPowerShell\Modules"
        "$myDocs\PowerShell\Modules"
        $normalizedDir
    )

    $pathSet = New-Object System.Collections.Generic.HashSet[string]
    $merged = New-Object System.Collections.Generic.List[string]
    foreach ($dir in $requiredDirs) {
        if ($pathSet.Add($dir)) { $merged.Add($dir) }
    }
    foreach ($dir in $entries) {
        if ($pathSet.Add($dir)) { $merged.Add($dir) }
    }

    $newPath = $merged -join ';'
    [Environment]::SetEnvironmentVariable("PSModulePath", $newPath, "User")
    $env:PSModulePath = "$env:PSModulePath;$normalizedDir"
    Write-Host "[OK] Added $normalizedDir to user PSModulePath" -ForegroundColor Green
}

function Remove-PsesModulePath {
    <#
    .SYNOPSIS
        Remove the PSES module parent dir from user PSModulePath.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $moduleParent = Get-PsesInstallDir
    $normalizedDir = $moduleParent.TrimEnd('\')

    $current = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
    if (-not $current) { return }

    $parts = $current -split ';' |
        Where-Object { $_.TrimEnd('\') -ne $normalizedDir }
    $cleaned = ($parts | Where-Object { $_ -ne '' }) -join ';'

    if ($cleaned -ne $current) {
        [Environment]::SetEnvironmentVariable("PSModulePath", $cleaned, "User")
        Write-Host "[OK] Removed $normalizedDir from PSModulePath" -ForegroundColor Green
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PsesCheck {
    <#
    .SYNOPSIS
        Display PSES installation, PSModulePath, lock, and cache status.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- PowerShellEditorServices ---" -ForegroundColor Cyan

    $moduleDir = Get-PsesModuleDir
    $installedVer = Get-PsesInstalledVersion

    if ($installedVer) {
        Write-Host "[OK] PowerShellEditorServices $installedVer" -ForegroundColor Green
        Write-Host "  Location: $moduleDir" -ForegroundColor DarkGray
    } else {
        Show-NotInstalled -Tool "PowerShellEditorServices" -Expected $moduleDir
    }

    # PSModulePath check
    $currentPath = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
    $installDir = Get-PsesInstallDir
    if ($currentPath -and ($currentPath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -eq $installDir.TrimEnd('\') })) {
        Write-Host "[OK] In PSModulePath" -ForegroundColor DarkGray
    } else {
        Write-Host "[INFO] Not in PSModulePath" -ForegroundColor DarkGray
    }

    # Lock
    $lock = Test-VersionLocked -ToolName "pses"
    if ($lock) {
        if ($installedVer -and $installedVer -eq $lock) {
            Write-Host "[OK] Locked: $lock (current)" -ForegroundColor Green
        } else {
            Write-Host "[LOCK] Locked: $lock" -ForegroundColor Magenta
        }
    } else {
        Write-Host "[INFO] No version lock" -ForegroundColor DarkGray
    }

    # Cache status
    $cacheDir = Join-Path $script:DevSetupRoot "pses"
    if (Test-Path $cacheDir) {
        $cacheFiles = Get-ChildItem "$cacheDir\*.zip" -ErrorAction SilentlyContinue
        if ($cacheFiles) {
            Write-Host "[OK] Cache: $($cacheFiles.Count) file(s) in $cacheDir" -ForegroundColor DarkGray
            foreach ($f in $cacheFiles) {
                Write-Host "  $($f.Name) ($([math]::Round($f.Length / 1MB, 1)) MB)" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "[INFO] Cache dir exists (empty): $cacheDir" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[INFO] No cache: $cacheDir" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# install
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PsesInstall {
    <#
    .SYNOPSIS
        Install or upgrade PowerShellEditorServices from GitHub Releases.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $ErrorActionPreference = 'Stop'

    # ── 0. Idempotent check ──
    $installedVer = Get-PsesInstalledVersion

    if ($Command -eq "install" -and $installedVer -and -not $Force) {
        $lock = Test-VersionLocked -ToolName "pses"
        if (-not $lock) {
            Set-VersionLock -ToolName "pses" -Version $installedVer
            Show-LockWrite -Version $installedVer
        }
        Show-AlreadyInstalled -Tool "PowerShellEditorServices" -Version $installedVer `
            -Location (Get-PsesModuleDir)
        Add-PsesModulePath
        return
    }

    # ── 1. Resolve version (prefer lock over network) ──
    $release = $null
    $tag = ""

    if (-not $Version) {
        $lock = Test-VersionLocked -ToolName "pses"
        if ($lock) {
            $Version = $lock
            $tag = "v$Version"
            Write-Host "[OK] Using locked version: $Version" -ForegroundColor Green
        }
    }

    if (-not $Version) {
        Write-Host "[INFO] Fetching latest release for $Repo..." -ForegroundColor Cyan
        try {
            $release = Get-GitHubRelease -Repo $Repo
            $rawTag  = $release.tag_name
            $Version = $rawTag -replace '^v', ''
            $tag     = $rawTag
            Write-Host "[OK] Latest version: $Version" -ForegroundColor Green
        } catch {
            if ($installedVer) {
                Show-AlreadyInstalled -Tool "PowerShellEditorServices" -Version $installedVer
                Write-Host "[WARN] Could not check for updates: $_" -ForegroundColor Yellow
                return
            }
            Write-Host "[ERROR] Cannot determine version to install: $_" -ForegroundColor Red
            return
        }
    } else {
        $tag = "v$Version"
    }

    # ── 2. Check if upgrade needed ──
    if ($installedVer) {
        $upgradeCheck = Test-UpgradeRequired -Current $installedVer -Target $Version `
            -ToolName "pses" -Force:$Force
        if (-not $upgradeCheck.Required) {
            Show-AlreadyInstalled -Tool "PowerShellEditorServices" -Version $installedVer `
                -Location (Get-PsesModuleDir)
            Write-Host "     $($upgradeCheck.Reason)" -ForegroundColor DarkGray
            $lock = Test-VersionLocked -ToolName "pses"
            if (-not $lock) {
                Set-VersionLock -ToolName "pses" -Version $installedVer
                Show-LockWrite -Version $installedVer
            }
            Add-PsesModulePath
            return
        }

        Write-Host "[UPGRADE] PowerShellEditorServices $installedVer -> $Version" -ForegroundColor Cyan
        Write-Host "     $($upgradeCheck.Reason)" -ForegroundColor DarkGray

        if (-not $Force) {
            $response = Read-Host "  Upgrade? (Y/n)"
            if ($response -and $response -ne 'Y' -and $response -ne 'y') {
                Write-Host "[INFO] Skipped" -ForegroundColor DarkGray
                return
            }
        }
    }

    Show-Installing -Component "PowerShellEditorServices $Version"

    # ── 3. Download zip ──
    $downloadUrl = "https://github.com/$Repo/releases/download/$tag/$AssetName"
    $zipFile     = Join-Path $env:TEMP $AssetName

    Write-Host "[INFO] Downloading $AssetName ..." -ForegroundColor Cyan

    if (-not $release) {
        try { $release = Get-GitHubRelease -Repo $Repo -Tag $tag } catch {
            Write-Host "[WARN] Could not fetch release metadata, hash verification skipped" -ForegroundColor Yellow
            $release = $null
        }
    }

    try {
        Save-WithCache -Url $downloadUrl -OutFile $zipFile -CacheDir "pses" `
            -GhRepo $Repo -GhTag $tag -GhAssetPattern $AssetName
    } catch {
        Write-Host "[ERROR] Failed to download $AssetName : $_" -ForegroundColor Red
        return
    }

    # ── 4. Verify ──
    $attestationOk = Test-GitHubAssetAttestation -Repo $Repo -Tag $tag -FilePath $zipFile
    try {
        if (-not $attestationOk) {
            $null = Test-FileHash -FilePath $zipFile -Release $release -AssetName $AssetName `
                -Repo $Repo -Tag $tag
        }
    } catch {
        Write-Host "[ERROR] Hash verification failed: $($_.Exception.Message)" -ForegroundColor Red
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        return
    }

    # ── 5. Extract ──
    $installDir = Get-PsesInstallDir
    $moduleDir  = Get-PsesModuleDir

    Write-Host "[INFO] Extracting to $moduleDir ..." -ForegroundColor Cyan

    if (Test-Path $moduleDir) {
        Remove-Item $moduleDir -Recurse -Force -ErrorAction Stop
    }
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    Expand-Archive -Path $zipFile -DestinationPath $installDir -Force
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

    # ── 6. Verify extraction ──
    $newVer = Get-PsesInstalledVersion
    if (-not $newVer) {
        Write-Host "[ERROR] Verification failed: could not parse version from .psd1" -ForegroundColor Red
        return
    }
    Write-Host "[OK] Installed: PowerShellEditorServices $newVer" -ForegroundColor Green
    Write-Host "[INFO] Path: $moduleDir" -ForegroundColor Cyan

    # ── 7. Register PSModulePath ──
    Add-PsesModulePath

    # ── 8. Summary ──
    Write-Host ""
    Show-InstallComplete -Tool "PowerShellEditorServices" -Version $newVer

    # ── 9. Write version lock and config ──
    Set-VersionLock -ToolName "pses" -Version $newVer
    Show-LockWrite -Version $newVer

    $relativePath = ".envs\dev\pses\PowerShellEditorServices"
    Set-PsesConfig -Lock $newVer -Path $relativePath
}

# ═══════════════════════════════════════════════════════════════════════════
# download (cache zip, no install)
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PsesDownload {
    <#
    .SYNOPSIS
        Download the locked PSES zip to the local cache without installing.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $ErrorActionPreference = 'Stop'

    # ── 1. Read lock version ──
    $lock = Test-VersionLocked -ToolName "pses"
    if (-not $lock) {
        Write-Host "[INFO] No version lock for pses. Use 'omc install pses' to install and set a lock." -ForegroundColor Cyan
        return
    }
    $Version = $lock
    $tag = "v$Version"

    # ── 2. Check cache ──
    $cacheDir  = Join-Path $script:DevSetupRoot "pses"
    $cacheFile = Join-Path $cacheDir $AssetName
    $hashFile  = "$cacheFile.sha256"

    if ((Test-Path $cacheFile) -and (Test-Path $hashFile)) {
        $cachedHash = (Get-Content $hashFile -Raw).Trim()
        $actualHash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
        if ($cachedHash -eq $actualHash) {
            Write-Host "[OK] pses: cached (locked $Version)" -ForegroundColor Green
            return
        }
    }

    # ── 3. Download ──
    $downloadUrl = "https://github.com/$Repo/releases/download/$tag/$AssetName"
    $zipFile     = Join-Path $env:TEMP $AssetName
    Write-Host "[INFO] Downloading $AssetName ..." -ForegroundColor Cyan

    $release = $null
    try { $release = Get-GitHubRelease -Repo $Repo -Tag $tag } catch { }

    Save-WithCache -Url $downloadUrl -OutFile $zipFile -CacheDir "pses" `
        -GhRepo $Repo -GhTag $tag -GhAssetPattern $AssetName

    $attestationOk = Test-GitHubAssetAttestation -Repo $Repo -Tag $tag -FilePath $zipFile
    try {
        if (-not $attestationOk) {
            $null = Test-FileHash -FilePath $zipFile -Release $release -AssetName $AssetName `
                -Repo $Repo -Tag $tag
        }
    } catch {
        Write-Host "[ERROR] Hash verification failed: $_" -ForegroundColor Red
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        return
    }

    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] pses $Version downloaded and cached" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PsesUninstall {
    <#
    .SYNOPSIS
        Uninstall PowerShellEditorServices by removing install dir, PSModulePath entry, and config.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $installDir = Get-PsesInstallDir
    $configFile = $script:PsesConfigFile

    Show-UninstallHeader -DisplayName "PowerShellEditorServices"

    # Pre-check
    $hasInstall  = Test-Path $installDir
    $hasConfig   = Test-Path $configFile
    if (-not $hasInstall -and -not $hasConfig) {
        Write-Host '[INFO] PowerShellEditorServices not installed, nothing to uninstall' -ForegroundColor Cyan
        return
    }

    # Remove install directory
    if ($hasInstall) {
        Write-Host "[INFO] Removing $installDir ..." -ForegroundColor Cyan
        Remove-Item $installDir -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] Removed $installDir" -ForegroundColor Green
    }

    # Remove PSModulePath entry
    Remove-PsesModulePath

    # Remove config
    if ($hasConfig) {
        Remove-Item $configFile -Force -ErrorAction Stop
        Write-Host "[OK] Removed $configFile" -ForegroundColor Green
    }

    Write-Host ""
    Show-UninstallComplete -Tool "PowerShellEditorServices"
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"     { Invoke-PsesCheck }
    "download"  { Invoke-PsesDownload }
    "install"   { Invoke-PsesInstall }
    "update"    { Invoke-PsesInstall }
    "uninstall" { Invoke-PsesUninstall }
}
