#Requires -Version 5.1

<#
.SYNOPSIS
    Manage Nerd Font installation.
.PARAMETER Command
    Action: check, install, update, uninstall, download.
.PARAMETER Name
    Font name (default: all fonts).
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("check", "install", "update", "uninstall", "download")]
    [string]$Command = "check",

    [Parameter(Position = 1)]
    [string]$Name = ""
)

. "$PSScriptRoot\..\helpers.ps1"
Add-Type -AssemblyName System.Drawing

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = "Stop"

$script:OhmyRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$UserFontDir    = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$RegPath        = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
$NoBom          = New-Object System.Text.UTF8Encoding $false

$FontRegistry = @{
    '0xProto' = @{
        DisplayName  = '0xProto Nerd Font'
        FilePattern  = '0xProto'
        ArchiveName  = '0xProto.zip'
    }
}

$NerdFontsRepo = 'ryanoasis/nerd-fonts'

function Get-FontDef {
    <#
    .SYNOPSIS
        Look up the font definition entry from the registry by name.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$fontName
    )

    if (-not $fontName) { return }
    $FontRegistry[$fontName]
}

function Get-FontConfigFile {
    <#
    .SYNOPSIS
        Build the config file path for a given font name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$fontName
    )

    Join-Path $script:OhmyRoot ".config\fonts\$fontName\config.json"
}

function Get-FontLock {
    <#
    .SYNOPSIS
        Read the locked version for a given font from its config file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$fontName
    )

    $configFile = Get-FontConfigFile $fontName
    if (-not (Test-Path $configFile)) { return }
    try {
        $cfg = Get-Content $configFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($cfg.version) { return $cfg.version }
    } catch {}
}

function Set-FontLock {
    <#
    .SYNOPSIS
        Write the locked version for a given font to its config file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$fontName,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $configFile = Get-FontConfigFile $fontName
    $dir = Split-Path $configFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = @{ version = $Version } | ConvertTo-Json
    [System.IO.File]::WriteAllText($configFile, $json.Trim(), $NoBom)
}

function Get-CacheDir {
    <#
    .SYNOPSIS
        Resolve the cache directory path for a given font.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$fontName
    )

    Join-Path $script:DevSetupRoot "fonts\$fontName"
}

function Get-FontCacheFile {
    <#
    .SYNOPSIS
        Locate the cached archive file for a given font.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$fontName
    )

    $def = Get-FontDef $fontName
    $lock = Get-FontLock $fontName
    if ($lock -and $def) { Join-Path (Get-CacheDir $fontName) $def.ArchiveName }
}

function Get-InstalledFontEntries {
    <#
    .SYNOPSIS
        Query the Windows font registry for entries matching a file pattern.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$filePattern
    )

    $regEntries = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
    if (-not $regEntries) { return @() }
    @($regEntries.PSObject.Properties |
        Where-Object { $_.Name -match $filePattern -or $_.Value -match $filePattern })
}

function Get-FontFamilyName {
    <#
    .SYNOPSIS
        Extract the font family name from a font file using System.Drawing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$FontPath
    )

    try {
        $fc = New-Object System.Drawing.Text.PrivateFontCollection
        $fc.AddFontFile($FontPath)
        $fc.Families[0].Name
    } catch {}
}

function Set-NestedProperty {
    <#
    .SYNOPSIS
        Set a nested property on a PSObject using dot-notation key path.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [object]$Obj,

        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [object]$Value
    )

    $parts = $Key -split '\.'
    $current = $Obj
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $propName = $parts[$i]
        if (-not ($current.PSObject.Properties.Name -contains $propName)) {
            $current | Add-Member -NotePropertyName $propName -NotePropertyValue (New-Object PSObject) -Force
        }
        $current = $current.$propName
    }
    $current | Add-Member -NotePropertyName $parts[-1] -NotePropertyValue $Value -Force
}

function Invoke-VscodeFontConfig {
    <#
    .SYNOPSIS
        Configure VS Code terminal and editor font settings to use the installed Nerd Font.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $vscodeSettingsDir = Join-Path $env:APPDATA 'Code\User'
    $settingsFile = Join-Path $vscodeSettingsDir 'settings.json'

    if (-not (Test-Path $settingsFile)) {
        Write-Host "[INFO] VS Code settings not found, skipping font config" -ForegroundColor DarkGray
        return
    }

    Write-Host "[INFO] Configuring VS Code font settings..." -ForegroundColor Cyan

    try {
        $content = [System.IO.File]::ReadAllText($settingsFile, [System.Text.Encoding]::UTF8)
        $settings = $content | ConvertFrom-Json

        Set-NestedProperty -Obj $settings -Key "terminal.integrated.fontFamily" -Value "'0xProto Nerd Font', monospace"
        Set-NestedProperty -Obj $settings -Key "editor.fontFamily" -Value "'0xProto Nerd Font', Consolas, 'Courier New', monospace"
        Set-NestedProperty -Obj $settings -Key "editor.fontLigatures" -Value $true

        $noBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($settingsFile, ($settings | ConvertTo-Json -Depth 10), $noBom)
        Write-Host "[OK] VS Code font configured (terminal + editor)" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] VS Code font config failed: $_" -ForegroundColor Yellow
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# per-font operations
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-SingleFontCheck {
    <#
    .SYNOPSIS
        Display installation status, lock, and cache info for a single font.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$fontName
    )

    $def = Get-FontDef $fontName
    Write-Host ""
    Write-Host "--- $($def.DisplayName) ---" -ForegroundColor Cyan

    $found = Get-InstalledFontEntries $def.FilePattern
    if ($found.Count -gt 0) {
        Write-Host "[OK] $($def.DisplayName) installed ($($found.Count) files)" -ForegroundColor Green
    } else {
        Write-Host "[INFO] $($def.DisplayName) not installed" -ForegroundColor Cyan
    }

    $lock = Get-FontLock $fontName
    if ($lock) {
        Write-Host "[OK] Locked: $lock" -ForegroundColor Green
    } else {
        Write-Host "[INFO] No version lock" -ForegroundColor DarkGray
    }

    $cacheFile = Get-FontCacheFile $fontName
    if ($cacheFile -and (Test-Path $cacheFile)) {
        $size = (Get-Item $cacheFile).Length
        $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
        Write-Host "[CACHE] $cacheFile ($sizeStr)" -ForegroundColor DarkGray
    } else {
        Write-Host "[CACHE] No cache" -ForegroundColor DarkGray
    }
}

function Invoke-SingleFontDownload {
    <#
    .SYNOPSIS
        Download and cache the archive for a single Nerd Font.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$fontName
    )

    $def = Get-FontDef $fontName
    $lock = Get-FontLock $fontName

    if ($lock) {
        $tag = "v$lock"
    } else {
        try {
            $release = Get-GitHubRelease -Repo $NerdFontsRepo
            $tag = $release.tag_name
            if ($tag -match 'v(\d+\.\d+(?:\.\d+)?)') { $lock = $Matches[1] }
        } catch {
            Write-Host "[WARN] Cannot fetch latest version: $_" -ForegroundColor Yellow
            return
        }
    }

    $archiveName = $def.ArchiveName
    $cacheDir = Get-CacheDir $fontName
    $cacheFile = Join-Path $cacheDir $archiveName
    $hashFile  = "$cacheFile.sha256"

    if ((Test-Path $cacheFile) -and (Test-Path $hashFile)) {
        $expectedHash = (Get-Content $hashFile -Raw).Trim()
        $actualHash   = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
        if ($actualHash -eq $expectedHash) {
            $size = (Get-Item $cacheFile).Length
            $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
            Write-Host "[OK] $($def.DisplayName) $lock cached ($sizeStr)" -ForegroundColor Green
            return
        }
        Write-Host "[WARN] Cache hash mismatch, re-downloading" -ForegroundColor Yellow
        Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
        Remove-Item $hashFile -Force -ErrorAction SilentlyContinue
    }

    Write-Host "[INFO] Downloading $($def.DisplayName) $lock ..." -ForegroundColor Cyan

    $zipFile = "$env:TEMP\$archiveName"

    try {
        Save-GitHubReleaseAsset -Repo $NerdFontsRepo -Tag $tag -AssetPattern $archiveName -OutFile $zipFile
    } catch {
        Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
        exit 1
    }

    $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
    Set-Content -Path $hashFile -Value $actualHash -NoNewline -Encoding UTF8
    Copy-Item -Path $zipFile -Destination $cacheFile -Force
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

    $size = (Get-Item $cacheFile).Length
    $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
    Write-Host "[OK] $($def.DisplayName) $lock downloaded ($sizeStr)" -ForegroundColor Green

    Set-FontLock -fontName $fontName -Version $lock
    Show-LockWrite -Version $lock
}

function Invoke-SingleFontInstall {
    <#
    .SYNOPSIS
        Install a single Nerd Font from the cached archive into the user font directory.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$fontName
    )

    $def = Get-FontDef $fontName
    $found = Get-InstalledFontEntries $def.FilePattern

    if ($found.Count -gt 0 -and -not $Force) {
        Write-Host "[OK] $($def.DisplayName) already installed ($($found.Count) files)" -ForegroundColor Green
        if (-not (Get-FontLock $fontName)) {
            try {
                $release = Get-GitHubRelease -Repo $NerdFontsRepo
                $latestTag = $release.tag_name
                if ($latestTag -match 'v(\d+\.\d+(?:\.\d+)?)') { Set-FontLock -fontName $fontName -Version $Matches[1] }
            } catch {}
        }
        return
    }

    Invoke-SingleFontDownload $fontName

    $cacheDir = Get-CacheDir $fontName
    $cachedZip = Get-ChildItem -Path $cacheDir -Filter "$($def.FilePattern)*.zip" |
        Where-Object { $_.Extension -eq '.zip' } | Select-Object -First 1
    if (-not $cachedZip -or -not (Test-Path $cachedZip.FullName)) {
        Write-Host "[ERROR] Cache not found" -ForegroundColor Red
        exit 1
    }

    $extractDir = "$env:TEMP\$($fontName)-extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Host "[INFO] Installing $($def.DisplayName) ..." -ForegroundColor Cyan
    try {
        Expand-Archive -Path $cachedZip.FullName -DestinationPath $extractDir -Force -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Extract failed: $_" -ForegroundColor Red
        exit 1
    }

    $fontFiles = @(Get-ChildItem -Path $extractDir -Recurse -Include '*.ttf', '*.otf' |
        Where-Object { $_.BaseName -match $def.FilePattern })

    if ($fontFiles.Count -eq 0) {
        Write-Host "[ERROR] No font files found in archive" -ForegroundColor Red
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }

    $regEntries = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
    if ($regEntries) {
        $regEntries.PSObject.Properties |
            Where-Object { $_.Name -match $def.FilePattern -or $_.Value -match $def.FilePattern } |
            ForEach-Object { Remove-ItemProperty -Path $RegPath -Name $_.Name -ErrorAction SilentlyContinue -Force }
    }

    if (-not (Test-Path $UserFontDir)) { New-Item -ItemType Directory -Path $UserFontDir -Force | Out-Null }

    $count = 0
    foreach ($font in $fontFiles) {
        $dest = Join-Path $UserFontDir $font.Name
        Copy-Item -Path $font.FullName -Destination $dest -Force -ErrorAction Stop

        $title = Get-FontFamilyName -FontPath $dest
        if (-not $title) {
            $title = $font.BaseName -replace '[-_]', ' ' -replace '([a-z])([A-Z])', '$1 $2'
        }

        $ext = $font.Extension.ToLower()
        $suffix = if ($ext -eq '.otf') { '(OpenType)' } else { '(TrueType)' }
        $regName = "$title $suffix"

        New-ItemProperty -Path $RegPath -Name $regName -Value $dest -PropertyType String -Force | Out-Null
        $count++
    }

    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

    if ($count -gt 0) {
        Write-Host "[OK] Installed $count font files" -ForegroundColor Green
        Write-Host "  Location: $UserFontDir" -ForegroundColor DarkGray
        Write-Host "  Restart your terminal to use the new fonts" -ForegroundColor DarkGray
    } else {
        Write-Host "[WARN] No font files were installed" -ForegroundColor Yellow
    }

    $lock = Get-FontLock $fontName
    if ($lock -and $lock -ne "installed") {
        Set-FontLock -fontName $fontName -Version $lock
        Show-LockWrite -Version $lock
    }
}

function Invoke-SingleFontUninstall {
    <#
    .SYNOPSIS
        Remove a single Nerd Font from the user font directory and registry.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$fontName
    )

    $def = Get-FontDef $fontName
    Write-Host "[INFO] Uninstalling $($def.DisplayName) ..." -ForegroundColor Cyan

    $found = Get-InstalledFontEntries $def.FilePattern
    $count = 0

    foreach ($entry in $found) {
        $fontFile = $entry.Value
        if (Test-Path $fontFile) { Remove-Item $fontFile -Force -ErrorAction SilentlyContinue }
        Remove-ItemProperty -Path $RegPath -Name $entry.Name -ErrorAction SilentlyContinue -Force | Out-Null
        $count++
    }

    if ($count -gt 0) {
        Write-Host "[OK] Removed $count font entries" -ForegroundColor Green
    } else {
        Write-Host "[INFO] $($def.DisplayName) not found" -ForegroundColor Cyan
    }

    $configFile = Get-FontConfigFile $fontName
    if (Test-Path $configFile) {
        Remove-Item $configFile -Force -ErrorAction SilentlyContinue
        Show-LockRemoved
    }

    Write-Host "[OK] $($def.DisplayName) uninstalled" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

$targets = if ($Name) { @($Name) } else { @($FontRegistry.Keys) }

foreach ($fn in $targets) {
    $def = Get-FontDef $fn
    if (-not $def) {
        Write-Host "[ERROR] Unknown font: $fn" -ForegroundColor Red
        Write-Host "  Available: $($FontRegistry.Keys -join ', ')" -ForegroundColor DarkGray
        continue
    }

    switch ($Command) {
        "check"     { Invoke-SingleFontCheck $fn }
        "download"  { Invoke-SingleFontDownload $fn }
        "install"   { Invoke-SingleFontInstall $fn }
        "uninstall" { Invoke-SingleFontUninstall $fn }
        "update"    {
            Write-Host ""
            Write-Host "--- $($def.DisplayName) ---" -ForegroundColor Cyan
            $found = Get-InstalledFontEntries $def.FilePattern
            $lock = Get-FontLock $fn
            if ($found.Count -eq 0) {
                Invoke-SingleFontInstall $fn
                continue
            }
            Write-Host "[INFO] Current lock: $lock" -ForegroundColor Cyan
            try {
                $release = Get-GitHubRelease -Repo $NerdFontsRepo
                $latestTag = $release.tag_name
                if ($latestTag -match 'v(\d+\.\d+(?:\.\d+)?)') { $latestVer = $Matches[1] } else { $latestVer = $latestTag }
            } catch {
                Write-Host "[WARN] Cannot check latest version: $_" -ForegroundColor Yellow
                continue
            }
            Write-Host "[OK] Latest: $latestVer" -ForegroundColor Green
            if (-not $lock) {
                Set-FontLock -fontName $fn -Version $latestVer
                Write-Host "[OK] Lock restored: $latestVer" -ForegroundColor Green
                continue
            }
            if ($lock -eq $latestVer) {
                Write-Host "[OK] $($def.DisplayName) $lock already up to date" -ForegroundColor Green
                continue
            }
            Write-Host "[UPGRADE] $lock -> $latestVer" -ForegroundColor Cyan
            $response = Read-Host "  Upgrade? (Y/n)"
            if ($response -and $response -ne 'Y' -and $response -ne 'y') {
                Write-Host "[INFO] Skipped" -ForegroundColor DarkGray
                continue
            }
            Invoke-SingleFontInstall $fn
        }
    }
}

if ($Command -eq "install" -and -not $Name) { Invoke-VscodeFontConfig }
