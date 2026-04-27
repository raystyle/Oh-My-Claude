#Requires -Version 5.1

<#
.SYNOPSIS
    Generic PowerShell module manager library.
.DESCRIPTION
    Dot-source this file to get check/install/update/uninstall functions for
    PowerShell Gallery modules. Uses Save-Package for download and
    Install-Module for installation via a local registered repository.
    Caller must define $ModuleDefs hashtable and dot-source helpers.ps1 first.
#>

function Get-LocalRepoPath {
    <#
    .SYNOPSIS
        Return the local PS repository directory path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path $script:DevSetupRoot 'LocalRepo'
}

function Register-OhMyClaudeLocalRepo {
    <#
    .SYNOPSIS
        Ensure the OhMyClaude local PS repository is registered and ready.
    .DESCRIPTION
        Idempotent: skips if already registered with the correct path.
        Creates the directory if needed and registers with Trusted policy.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $repoName = 'OhMyClaude'
    $localRepoPath = Get-LocalRepoPath

    $existing = Get-PSRepository -Name $repoName -ErrorAction SilentlyContinue
    if ($existing -and $existing.SourceLocation -eq $localRepoPath) {
        $repoName
        return
    }

    if (-not (Test-Path $localRepoPath)) {
        New-Item -ItemType Directory -Path $localRepoPath -Force | Out-Null
    }

    if ($existing) {
        Unregister-PSRepository -Name $repoName -ErrorAction SilentlyContinue
    }

    try {
        Register-PSRepository -Name $repoName `
            -SourceLocation $localRepoPath `
            -InstallationPolicy Trusted `
            -ErrorAction Stop
        Write-Host "[OK] Registered local repo: $repoName -> $localRepoPath" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to register local PS repository: $_" -ForegroundColor Red
        throw
    }

    $repoName
}

function Unregister-OhMyClaudeLocalRepo {
    <#
    .SYNOPSIS
        Unregister the OhMyClaude local PS repository.
    .PARAMETER RemoveFiles
        Also remove the local repository directory.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [switch]$RemoveFiles
    )

    $repoName = 'OhMyClaude'

    try {
        Unregister-PSRepository -Name $repoName -ErrorAction Stop
        Write-Host "[OK] Unregistered local repo: $repoName" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Failed to unregister local repo: $_" -ForegroundColor Yellow
    }

    if ($RemoveFiles) {
        $localRepoPath = Get-LocalRepoPath
        if (Test-Path $localRepoPath) {
            Remove-Item $localRepoPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Removed local repo directory: $localRepoPath" -ForegroundColor Green
        }
    }
}

function Get-PSModuleLock {
    <#
    .SYNOPSIS
        Read the locked version for a PowerShell module from its config file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    $configFile = Join-Path $script:OhmyRoot ".config\$ModuleName\config.json"
    if (-not (Test-Path $configFile)) { return }
    try {
        $cfg = Get-Content $configFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($cfg.lock) { return $cfg.lock }
    } catch {}
}

function Set-PSModuleLock {
    <#
    .SYNOPSIS
        Write the locked version for a PowerShell module to its config file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $configDir  = Join-Path $script:OhmyRoot ".config\$ModuleName"
    $configFile = "$configDir\config.json"
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    $noBom = New-Object System.Text.UTF8Encoding $false
    $json  = @{ lock = $Version } | ConvertTo-Json
    [System.IO.File]::WriteAllText($configFile, $json.Trim(), $noBom)
}

function Test-PSModuleValid {
    <#
    .SYNOPSIS
        Validate that a PowerShell module directory contains a valid module.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ModDir,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $psd1 = Join-Path $ModDir "$Name.psd1"
    if (-not (Test-Path $psd1)) { return $false }
    try {
        $content = Get-Content -Path $psd1 -Raw -ErrorAction Stop
        $rootModule = $null
        if ($content -match "RootModule\s*=\s*['`"]([^'`"]+)['`"]") {
            $rootModule = $Matches[1]
        } elseif ($content -match "ModuleToProcess\s*=\s*['`"]([^'`"]+)['`"]") {
            $rootModule = $Matches[1]
        }
        if ($rootModule) {
            $entryPath = Join-Path $ModDir $rootModule
            if (-not (Test-Path $entryPath)) { return $false }
        }
    } catch { return $false }
    $true
}

function Get-PSModuleVersionInstalled {
    <#
    .SYNOPSIS
        Find the latest installed version of a PowerShell module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ModDir,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-Path $ModDir)) { return }
    $versionDirs = Get-ChildItem $ModDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-PSModuleValid -ModDir $_.FullName -Name $Name }
    $latest = $versionDirs | Sort-Object { try { [version]$_.Name } catch { [version]"0.0.0" } } -Descending | Select-Object -First 1
    if (-not $latest) { return }
    $latest.Name
}

function Get-PSModulePaths {
    <#
    .SYNOPSIS
        Get PS5 and PS7 module installation paths for a module.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    @(
        @{ Path = "$myDocs\WindowsPowerShell\Modules\$ModuleName"; Label = 'PS5' }
        @{ Path = "$myDocs\PowerShell\Modules\$ModuleName";         Label = 'PS7' }
    )
}

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PSModuleCheck {
    <#
    .SYNOPSIS
        Display installation and lock status for a PowerShell module.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$ModuleDef,
        [string]$ModuleName
    )

    $dn = $ModuleDef.DisplayName
    Write-Host ''
    Write-Host "--- $dn ---" -ForegroundColor Cyan

    $paths = Get-PSModulePaths -ModuleName $ModuleName
    foreach ($p in $paths) {
        $ver = Get-PSModuleVersionInstalled -ModDir $p.Path -Name $ModuleName
        if ($ver) {
            Write-Host "[OK] $($p.Label) : $ver" -ForegroundColor Green
            Write-Host "  Location: $($p.Path)\$ver" -ForegroundColor DarkGray
        } else {
            Write-Host "[INFO] $($p.Label) : not installed" -ForegroundColor Cyan
            Write-Host "  Expected: $($p.Path)\<version>" -ForegroundColor DarkGray
        }
    }

    # Lock
    $lock = Get-PSModuleLock -ModuleName $ModuleName
    if ($lock) {
        $installedVer = if ($paths) { Get-PSModuleVersionInstalled -ModDir $paths[0].Path -Name $ModuleName }
        if ($installedVer -and $installedVer -eq $lock) {
            Write-Host "[OK] Locked: $lock (current)" -ForegroundColor Green
        } else {
            Write-Host "[LOCK] Locked: $lock" -ForegroundColor Magenta
        }
    } else {
        Write-Host "[INFO] No version lock" -ForegroundColor DarkGray
    }

    # Local repo status
    $localRepoPath = Get-LocalRepoPath
    $registered = Get-PSRepository -Name 'OhMyClaude' -ErrorAction SilentlyContinue
    if ($registered) {
        $nupkgFiles = Get-ChildItem "$localRepoPath\*.nupkg" -ErrorAction SilentlyContinue
        Write-Host "[OK] Local repo: OhMyClaude ($($nupkgFiles.Count) packages)" -ForegroundColor DarkGray
    } else {
        Write-Host "[INFO] Local repo: not registered" -ForegroundColor DarkGray
    }

    # Module-specific nupkg in local repo
    if (Test-Path $localRepoPath) {
        $modulePkgs = Get-ChildItem "$localRepoPath\$ModuleName.*.nupkg" -ErrorAction SilentlyContinue
        if ($modulePkgs) {
            Write-Host "[OK] Cached: $($modulePkgs.Count) package(s) in $localRepoPath" -ForegroundColor DarkGray
            foreach ($pkg in $modulePkgs) {
                Write-Host "  $($pkg.Name) ($([math]::Round($pkg.Length / 1MB, 1)) MB)" -ForegroundColor DarkGray
            }
        }
    }

    # Profile block
    if ($ModuleDef.ProfileBlock) {
        $blockName = $ModuleDef.ProfileBlock.BlockName
        $marker = "# BEGIN ohmywinclaude: $blockName"
        $status = Test-ProfileEntry -Line $marker
        if ($status.All) {
            Write-Host "[OK] Profile: configured (PS5 + PS7)" -ForegroundColor DarkGray
        } elseif ($status.PS5 -or $status.PS7) {
            $partial = if ($status.PS5) { 'PS5' } else { 'PS7' }
            Write-Host "[WARN] Profile: partial ($partial only)" -ForegroundColor Yellow
        } else {
            Write-Host "[INFO] Profile: not configured" -ForegroundColor Cyan
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# download
# ═══════════════════════════════════════════════════════════════════════════

function Save-ModuleNupkg {
    <#
    .SYNOPSIS
        Download a .nupkg file from PSGallery to the local repository.
    .DESCRIPTION
        Downloads the nupkg directly from the PSGallery API. The file is saved
        as <ModuleName>.<Version>.nupkg in the local repo directory.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$LocalRepoPath
    )

    if (-not (Test-Path $LocalRepoPath)) {
        New-Item -ItemType Directory -Path $LocalRepoPath -Force | Out-Null
    }

    $nupkgFile = Join-Path $LocalRepoPath "$ModuleName.$Version.nupkg"
    if ((Test-Path $nupkgFile) -and (Get-Item $nupkgFile).Length -gt 0) {
        return
    }
    if (Test-Path $nupkgFile) {
        Remove-Item $nupkgFile -Force -ErrorAction SilentlyContinue
        Write-Host "[WARN] Cached nupkg is 0 bytes, re-downloading..." -ForegroundColor Yellow
    }

    $downloadUrl = "https://www.powershellgallery.com/api/v2/package/$ModuleName/$Version"
    Write-Host "[INFO] Downloading $ModuleName $Version ..." -ForegroundColor Cyan

    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($downloadUrl, $nupkgFile)
    }
    catch {
        Remove-Item $nupkgFile -Force -ErrorAction SilentlyContinue
        Write-Host "[ERROR] Failed to download $ModuleName $Version : $_" -ForegroundColor Red
        throw
    }

    if ((Get-Item $nupkgFile).Length -eq 0) {
        Remove-Item $nupkgFile -Force -ErrorAction SilentlyContinue
        throw "Downloaded $ModuleName $Version nupkg is 0 bytes (network error?)"
    }

    Write-Host "[OK] $ModuleName $Version downloaded to $LocalRepoPath" -ForegroundColor Green
}

function Invoke-PSModuleDownload {
    <#
    .SYNOPSIS
        Download a PS module .nupkg to the local repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ModuleDef,

        [Parameter(Mandatory)]
        [string]$ModuleName,

        [string]$Version = ''
    )

    $dn = $ModuleDef.DisplayName
    $localRepoPath = Get-LocalRepoPath

    $lockVer = Get-PSModuleLock -ModuleName $ModuleName
    if (-not $lockVer -and -not $Version) {
        Write-Host "[INFO] No version lock for $dn. Use 'omc install $ModuleName' to install and set a lock." -ForegroundColor Cyan
        return
    }
    if ($lockVer) { $Version = $lockVer }

    $nupkgFile = Join-Path $localRepoPath "$ModuleName.$Version.nupkg"
    if (Test-Path $nupkgFile) {
        Write-Host "[OK] ${dn}: cached ($Version)" -ForegroundColor Green
        return
    }

    Save-ModuleNupkg -ModuleName $ModuleName -Version $Version -LocalRepoPath $localRepoPath
}

# ═══════════════════════════════════════════════════════════════════════════
# install
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PSModuleInstall {
    <#
    .SYNOPSIS
        Install a PowerShell module via Save-Package + Install-Module.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$ModuleDef,
        [string]$ModuleName,
        [string]$Version = '',
        [ValidateSet('install', 'update')]
        [string]$Command = 'install',
        [switch]$Force
    )

    $dn = $ModuleDef.DisplayName
    $paths = Get-PSModulePaths -ModuleName $ModuleName

    # ── 0. Install command: skip if all paths already installed ──
    if ($Command -eq 'install' -and -not $Force) {
        $allGood = $true
        foreach ($p in $paths) {
            if (-not (Get-PSModuleVersionInstalled -ModDir $p.Path -Name $ModuleName)) {
                $allGood = $false; break
            }
        }
        if ($allGood) {
            $ver = Get-PSModuleVersionInstalled -ModDir $paths[0].Path -Name $ModuleName
            Write-Host "[OK] Already installed: $dn $ver" -ForegroundColor Green
            foreach ($p in $paths) {
                $v = Get-PSModuleVersionInstalled -ModDir $p.Path -Name $ModuleName
                Write-Host "  $($p.Label): $($p.Path)\$v" -ForegroundColor DarkGray
            }
            $lock = Get-PSModuleLock -ModuleName $ModuleName
            if (-not $lock) {
                Set-PSModuleLock -ModuleName $ModuleName -Version $ver
                Show-LockWrite -Version $ver
            }
            return
        }
    }

    # ── 1. Resolve version ──
    if (-not $Version) {
        Write-Host "[INFO] Fetching latest version from PSGallery..." -ForegroundColor Cyan
        try {
            $psgInfo = Get-PSGalleryModuleInfo -ModuleName $ModuleName
            $Version = $psgInfo.Version
            Write-Host "[OK] PSGallery version: $Version" -ForegroundColor Green
        }
        catch {
            if ($Command -eq 'install') {
                foreach ($p in $paths) {
                    $ver = Get-PSModuleVersionInstalled -ModDir $p.Path -Name $ModuleName
                    if ($ver) {
                        Write-Host "[WARN] Could not check for updates, current: $ver" -ForegroundColor Yellow
                        return
                    }
                }
            }
            Write-Host "[ERROR] Cannot determine version: $_" -ForegroundColor Red
            exit 1
        }
    }

    # ── 2. Update mode: compare with installed version ──
    $currentVer = Get-PSModuleVersionInstalled -ModDir $paths[0].Path -Name $ModuleName
    if ($Command -eq 'update' -and $currentVer) {
        $cmp = Compare-SemanticVersion -Current $currentVer -Latest $Version
        if ($cmp -ge 0) {
            Write-Host "[OK] $dn $currentVer already up to date" -ForegroundColor Green
            $lock = Get-PSModuleLock -ModuleName $ModuleName
            if (-not $lock) {
                Set-PSModuleLock -ModuleName $ModuleName -Version $currentVer
                Show-LockWrite -Version $currentVer
            }
            return
        }
        Write-Host "[UPGRADE] $dn $currentVer -> $Version" -ForegroundColor Cyan
        $response = Read-Host '  Upgrade? (Y/n)'
        if ($response -and $response -ne 'Y' -and $response -ne 'y') {
            Write-Host '[INFO] Skipped' -ForegroundColor DarkGray
            return
        }
    } elseif ($currentVer -and $currentVer -ne $Version) {
        Write-Host "[UPGRADE] $dn $currentVer -> $Version" -ForegroundColor Cyan
        if (-not $Force) {
            $response = Read-Host '  Upgrade? (Y/n)'
            if ($response -and $response -ne 'Y' -and $response -ne 'y') {
                Write-Host '[INFO] Skipped' -ForegroundColor DarkGray
                return
            }
        }
    }

    Show-Installing -Component "$dn $Version"

    # ── 3. Register local repo (lazy) ──
    $repoName = Register-OhMyClaudeLocalRepo

    # ── 4. Ensure nupkg in local repo ──
    $localRepoPath = Get-LocalRepoPath
    try {
        Save-ModuleNupkg -ModuleName $ModuleName -Version $Version -LocalRepoPath $localRepoPath
    }
    catch {
        Write-Host "[ERROR] Failed to download $ModuleName $Version : $_" -ForegroundColor Red
        exit 1
    }

    # ── 5. Install via Install-Module ──
    try {
        Install-Module -Name $ModuleName -Repository $repoName `
            -RequiredVersion $Version -Scope CurrentUser -Force `
            -SkipPublisherCheck -ErrorAction Stop
        Write-Host "[OK] Install-Module succeeded" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Install-Module failed: $_" -ForegroundColor Red
        exit 1
    }

    # ── 6. Cross-install to other PS version ──
    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    $currentModulePath = if ($PSVersionTable.PSVersion.Major -ge 6) {
        "$myDocs\PowerShell\Modules\$ModuleName"
    } else {
        "$myDocs\WindowsPowerShell\Modules\$ModuleName"
    }

    $sourceDir = "$currentModulePath\$Version"
    $failCount = 0

    foreach ($p in $paths) {
        $targetDir = "$($p.Path)\$Version"
        if (Test-PSModuleValid -ModDir $targetDir -Name $ModuleName) {
            Write-Host "[OK] $($p.Label): installed" -ForegroundColor Green
            continue
        }

        if ((Test-Path $sourceDir) -and (Test-PSModuleValid -ModDir $sourceDir -Name $ModuleName)) {
            if (Test-Path $targetDir) {
                Remove-Item -Path $targetDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            try {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                Copy-Item -Path "$sourceDir\*" -Destination $targetDir -Recurse -Force -ErrorAction Stop
                Write-Host "[OK] $($p.Label): cross-installed" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] $($p.Label): cross-install failed - $_" -ForegroundColor Red
                $failCount++
            }
        } else {
            Write-Host "[ERROR] $($p.Label): could not cross-install (source not found)" -ForegroundColor Red
            $failCount++
        }
    }

    if ($failCount -gt 0) {
        Write-Host "[WARN] $failCount target(s) failed. Re-run to retry." -ForegroundColor Yellow
    }

    # ── 7. Write lock ──
    Set-PSModuleLock -ModuleName $ModuleName -Version $Version
    Show-LockWrite -Version $Version

    # ── 8. Configure profile ──
    if ($ModuleDef.ProfileBlock) {
        $pb = $ModuleDef.ProfileBlock
        $profileScript = Join-Path $PSScriptRoot 'profile-line.ps1'
        Write-Host '[INFO] Configuring profile...' -ForegroundColor Cyan
        & $profileScript -Action add -Line $pb.Lines -Comment $pb.Comment -BlockName $pb.BlockName
    }

    Write-Host ''
    Show-InstallComplete -Tool $dn -Version $Version
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PSModuleUninstall {
    <#
    .SYNOPSIS
        Uninstall a PowerShell module via Uninstall-Module from both PS5 and PS7.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [hashtable]$ModuleDef,
        [string]$ModuleName
    )

    $dn = $ModuleDef.DisplayName
    Write-Host ''
    Write-Host "=== Uninstall $dn ===" -ForegroundColor Cyan

    Get-Module -Name $ModuleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    $isCore = $PSVersionTable.PSVersion.Major -ge 6
    $currentLabel = if ($isCore) { 'PS7' } else { 'PS5' }

    # ── Current PS version ──
    try {
        Uninstall-Module -Name $ModuleName -Force -ErrorAction Stop
        Write-Host "[OK] $currentLabel : uninstalled" -ForegroundColor Green
    }
    catch {
        if ($_.FullyQualifiedErrorId -match 'NoModuleFoundForGivenCriteria') {
            Write-Host "[INFO] $currentLabel : not installed" -ForegroundColor Cyan
        } else {
            Write-Host "[WARN] $currentLabel : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # ── Other PS version (cross-installed via copy) ──
    $otherExe = if ($isCore) { 'powershell.exe' } else { 'pwsh.exe' }
    $otherLabel = if ($isCore) { 'PS5' } else { 'PS7' }
    $otherPath = if ($isCore) {
        "$myDocs\WindowsPowerShell\Modules\$ModuleName"
    } else {
        "$myDocs\PowerShell\Modules\$ModuleName"
    }

    if (-not (Test-Path $otherPath)) {
        Write-Host "[INFO] $otherLabel : not installed" -ForegroundColor Cyan
    } elseif (Get-Command $otherExe -ErrorAction SilentlyContinue) {
        & $otherExe -NoLogo -NoProfile -Command `
            "try { Uninstall-Module -Name '$ModuleName' -Force -ErrorAction Stop; exit 0 } catch { exit 1 }" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] $otherLabel : uninstalled" -ForegroundColor Green
        } else {
            Write-Host "[WARN] $otherLabel : Uninstall-Module failed" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[WARN] $otherLabel : $otherExe not available, skipping" -ForegroundColor Yellow
    }

    # Remove lock
    $configFile = Join-Path $script:OhmyRoot ".config\$ModuleName\config.json"
    if (Test-Path $configFile) {
        Remove-Item $configFile -Force -ErrorAction SilentlyContinue
        Show-LockRemoved
    }

    # Remove profile block
    if ($ModuleDef.ProfileBlock) {
        $pb = $ModuleDef.ProfileBlock
        $profileScript = Join-Path $PSScriptRoot 'profile-line.ps1'
        & $profileScript -Action remove -Line $pb.Lines -Comment $pb.Comment -BlockName $pb.BlockName
    }

    Write-Host ''
    Write-Host "[OK] $dn uninstalled" -ForegroundColor Green
}
