#Requires -Version 5.1

# Project root (one level up from .scripts/)
$script:OhmyRoot = Split-Path $PSScriptRoot -Parent

# Unified cache root and shared paths
$script:DevSetupRoot = Join-Path $script:OhmyRoot '.cache\dev'

$script:VSBuildTools_LayoutDir    = Join-Path $script:DevSetupRoot "vsbuildtools\Layout"
$script:VSBuildTools_Bootstrapper = Join-Path $script:DevSetupRoot "vsbuildtools\vs_buildtools.exe"
$script:VSBuildTools_CacheDir     = Join-Path $script:DevSetupRoot "vsbuildtools\cache"
$script:VSBuildTools_InstallPath  = Join-Path $script:OhmyRoot '.envs\dev\VSBuildTools'

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Check if the current process is running with administrator privileges.
    .OUTPUTS
        [bool] $true if running as admin, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-AdminRequiredPopup {
    <#
    .SYNOPSIS
        Show a popup dialog explaining admin rights are needed.
    .DESCRIPTION
        Loads System.Windows.Forms and displays a message box. Returns $true
        if the user clicks Retry (to attempt re-launch), $false on Cancel.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $result = [System.Windows.Forms.MessageBox]::Show(
            "BITS job cleanup requires administrator privileges.`n`n" +
            "Please run as administrator, then try again.",
            "Admin Rights Required",
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        ($result -eq [System.Windows.Forms.DialogResult]::OK)
    } catch {
        Write-Host "[INFO] Admin rights needed. Run PowerShell as Administrator." -ForegroundColor Cyan
        $false
    }
}

# Ensure external CLI output displays UTF-8 correctly (emoji/Unicode)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Set-ConsoleUtf8 {
    <#
    .SYNOPSIS
        Set console encoding to UTF-8 for correct emoji/Unicode output from external tools.
        Call before running npm, uv, claude, playwright-cli or other Node.js/Rust CLIs.
    #>
    [CmdletBinding()]
    param()

    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

function Update-Environment {
    <#
    .SYNOPSIS
        Reload PATH from Machine and User registry into current process.
        Use at the start of scripts that depend on tools installed by previous steps.
    #>
    [CmdletBinding()]
    param()
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")

    # Merge with deduplication while preserving order (Machine -> User)
    $pathSet = New-Object System.Collections.Generic.HashSet[string]
    $mergedPaths = New-Object System.Collections.Generic.List[string]

    foreach ($path in $machinePath -split ';') {
        if (-not [string]::IsNullOrWhiteSpace($path) -and $pathSet.Add($path)) {
            $mergedPaths.Add($path)
        }
    }
    foreach ($path in $userPath -split ';') {
        if (-not [string]::IsNullOrWhiteSpace($path) -and $pathSet.Add($path)) {
            $mergedPaths.Add($path)
        }
    }

    $env:Path = $mergedPaths -join ';'
}

$script:ghAuthenticated = $null

function Test-GhAuthenticated {
    <#
    .SYNOPSIS
        Check if gh CLI is available and authenticated.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($null -ne $script:ghAuthenticated) { return $script:ghAuthenticated }

    $ghExe = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $ghExe) {
        $script:ghAuthenticated = $false
        return $false
    }

    try {
        & $ghExe auth status 2>$null | Out-Null
        $script:ghAuthenticated = ($LASTEXITCODE -eq 0)
    } catch {
        $script:ghAuthenticated = $false
    }
    $script:ghAuthenticated
}

function Invoke-DownloadWithProgress {
    <#
    .SYNOPSIS
        Download a file with byte-level progress display.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$OutFile,

        [int]$TimeoutSec = 300
    )

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.AllowAutoRedirect = $true
    $request.Timeout = $TimeoutSec * 1000
    $response = $request.GetResponse()
    $total = $response.ContentLength
    $stream = $response.GetResponseStream()
    $fs = [System.IO.File]::Create($OutFile)
    $buffer = New-Object byte[] 65536
    $totalRead = 0

    try {
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fs.Write($buffer, 0, $read)
            $totalRead += $read
            if ($total -gt 0) {
                $pct = [math]::Floor($totalRead / $total * 100)
            } else {
                $pct = 0
            }
            $mb = "{0:N1}" -f ($totalRead / 1MB)
            $totalMB = "{0:N1}" -f ($total / 1MB)
            Write-Host "`r  [$pct%] $mb / $totalMB MB" -NoNewline -ForegroundColor DarkGray
        }
        Write-Host ''
    } finally {
        $fs.Close()
        $stream.Close()
        $response.Close()
    }
}

function Save-GitHubReleaseAsset {
    <#
    .SYNOPSIS
        Download a GitHub release asset using gh CLI.
    .PARAMETER Repo
        GitHub repo in "owner/repo" format.
    .PARAMETER Tag
        Release tag (e.g. "v2.54.0").
    .PARAMETER AssetPattern
        Glob pattern to match the asset name (e.g. "ripgrep-*-x86_64-pc-windows-msvc.zip").
    .PARAMETER OutFile
        Destination file path.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Repo,

        [Parameter(Mandatory)]
        [string]$Tag,

        [Parameter(Mandatory)]
        [string]$AssetPattern,

        [Parameter(Mandatory)]
        [string]$OutFile
    )

    if (-not (Test-GhAuthenticated)) {
        throw "gh CLI not available or not authenticated. Run: gh auth login"
    }

    $outDir = Split-Path $OutFile -Parent
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    & gh release download $Tag -R $Repo -p $AssetPattern --clobber -D $outDir
    if ($LASTEXITCODE -ne 0) {
        throw "gh release download failed for $Repo $Tag"
    }

    # gh downloads with original asset name; rename if OutFile differs
    if (-not (Test-Path $OutFile)) {
        $escaped = [regex]::Escape($AssetPattern)
        $downloaded = Get-ChildItem $outDir | Where-Object { $_.Name -match $escaped } | Select-Object -First 1
        if ($downloaded) {
            Move-Item -Path $downloaded.FullName -Destination $OutFile -Force
        }
    }
    if (-not (Test-Path $OutFile)) {
        throw "gh release download completed but file not found: $OutFile"
    }

    Write-Host "[OK] Downloaded via gh release download ($Repo $Tag)" -ForegroundColor Green
}

function Test-GitHubAssetAttestation {
    <#
    .SYNOPSIS
        Verify a downloaded asset using GitHub's cryptographically signed attestation.
    .PARAMETER Repo
        GitHub repo in "owner/repo" format.
    .PARAMETER Tag
        Release tag.
    .PARAMETER FilePath
        Path to the downloaded asset file.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Repo,

        [Parameter(Mandatory)]
        [string]$Tag,

        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (-not (Test-GhAuthenticated)) { return $false }
    if (-not (Test-Path $FilePath)) { return $false }

    try {
        & gh release verify-asset $Tag $FilePath -R $Repo 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Verified via GitHub attestation" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Debug "Attestation verification failed: $_"
    }
    $false
}

function Save-WithCache {
    <#
    .SYNOPSIS
        Download with caching. Supports GitHub release via gh CLI or direct URL.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CacheDir,

        [string]$UserAgent = "",

        [string]$GhRepo = "",

        [string]$GhTag = "",

        [string]$GhAssetPattern = ""
    )

    $fullCacheDir = Join-Path $script:DevSetupRoot $CacheDir
    $cacheFile = Join-Path $fullCacheDir (Split-Path $OutFile -Leaf)
    $cacheConfig = Join-Path $fullCacheDir 'config.json'

    $outParent = Split-Path $OutFile -Parent
    if ($outParent -and -not (Test-Path $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }

    # Cache hit: verify hash from config
    if (Test-Path $cacheFile) {
        try {
            if (Test-Path $cacheConfig) {
                $cfg = Get-Content $cacheConfig -Raw -Encoding UTF8 | ConvertFrom-Json
                $cacheName = Split-Path $cacheFile -Leaf
                $storedHash = $cfg.$cacheName
                if ($storedHash) {
                    $actualHash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
                    if ($actualHash -eq $storedHash) {
                        $cacheSize = (Get-Item $cacheFile).Length
                        if ($cacheSize -ge 1MB) {
                            $sizeStr = "{0:N1} MB" -f ($cacheSize / 1MB)
                        } else {
                            $sizeStr = "{0:N0} KB" -f ($cacheSize / 1KB)
                        }
                        Write-Host "[OK] Using cached: $(Split-Path $cacheFile -Leaf) ($sizeStr)" -ForegroundColor Green
                        Copy-Item -Path $cacheFile -Destination $OutFile -Force
                        return
                    }
                    Write-Host "[WARN] Cache hash mismatch, re-downloading" -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host "[WARN] Cache verification failed, re-downloading: $_" -ForegroundColor Yellow
        }
    }

    if (-not (Test-Path $fullCacheDir)) {
        New-Item -ItemType Directory -Path $fullCacheDir -Force | Out-Null
    }

    if ($GhRepo -and $GhTag -and $GhAssetPattern) {
        Save-GitHubReleaseAsset -Repo $GhRepo -Tag $GhTag -AssetPattern $GhAssetPattern -OutFile $cacheFile
        Copy-Item -Path $cacheFile -Destination $OutFile -Force
    } else {
        $webParams = @{ Uri = $Url; OutFile = $OutFile; MaximumRedirection = 5 }
        if ($UserAgent) { $webParams['UserAgent'] = $UserAgent }
        Invoke-WebRequest @webParams -ErrorAction Stop
        Copy-Item -Path $OutFile -Destination $cacheFile -Force
    }

    try {
        $hash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
        $cfg = @{}
        if (Test-Path $cacheConfig) {
            try {
                $json = Get-Content $cacheConfig -Raw -Encoding UTF8 | ConvertFrom-Json
                $json.PSObject.Properties | ForEach-Object { $cfg[$_.Name] = $_.Value }
            } catch { }
        }
        $cacheName = Split-Path $cacheFile -Leaf
        $cfg[$cacheName] = $hash
        $cfg | ConvertTo-Json -Depth 1 | Set-Content -Path $cacheConfig -Encoding UTF8 -Force
        Write-Host "[OK] Cached: $(Split-Path $cacheFile -Leaf) -> $fullCacheDir" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "[WARN] Failed to cache file: $_" -ForegroundColor Yellow
    }
}

function Get-GitHubRelease {
    <#
    .SYNOPSIS
        Fetch a GitHub release object (latest or by tag) via gh CLI.
    .PARAMETER Repo
        GitHub repo in "owner/repo" format.
    .PARAMETER Tag
        Specific tag to fetch. If omitted, fetches latest.
    .OUTPUTS
        PSObject — release object with tag_name and assets[].
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Repo,
        [string]$Tag
    )

    if (-not (Test-GhAuthenticated)) {
        Write-Host "[INFO] gh CLI unavailable, using GitHub API for $Repo" -ForegroundColor DarkGray
        return Get-GitHubReleaseViaApi -Repo $Repo -Tag $Tag
    }

    try {
        if ($Tag) {
            $ghJson = gh release view $Tag --repo $Repo --json tagName,assets 2>$null | Out-String
        } else {
            $ghJson = gh release view --repo $Repo --json tagName,assets 2>$null | Out-String
        }
        if ($ghJson) {
            $ghObj = $ghJson | ConvertFrom-Json
            $release = [PSCustomObject]@{
                tag_name = $ghObj.tagName
                assets   = $ghObj.assets | ForEach-Object {
                    [PSCustomObject]@{
                        name                 = $_.name
                        size                 = $_.size
                        browser_download_url = $_.url
                        digest               = $_.digest
                    }
                }
            }
            $release
            return
        }
    } catch {
        throw "gh CLI failed to fetch release for ${Repo}: $_"
    }

    throw "Failed to fetch release for ${Repo}"
}

function Get-GitHubReleaseViaApi {
    <#
    .SYNOPSIS
        Fetch a GitHub release object via the REST API (no gh CLI required).
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Repo,
        [string]$Tag
    )

    $url = if ($Tag) {
        "https://api.github.com/repos/$Repo/releases/tags/$Tag"
    } else {
        "https://api.github.com/repos/$Repo/releases/latest"
    }

    try {
        $headers = @{ 'User-Agent' = 'ohmyclaude' }
        $response = Invoke-RestMethod -Uri $url -Headers $headers -MaximumRedirection 5 -ErrorAction Stop
    } catch {
        throw "GitHub API failed for ${Repo}: $_"
    }

    $release = [PSCustomObject]@{
        tag_name = $response.tag_name
        assets   = $response.assets | ForEach-Object {
            [PSCustomObject]@{
                name                 = $_.name
                size                 = $_.size
                browser_download_url = $_.browser_download_url
                digest               = $null
            }
        }
    }
    $release
}

function Get-LatestGitHubVersion {
    <#
    .SYNOPSIS
        Convenience wrapper: returns version info from latest release.
    .OUTPUTS
        PSCustomObject with Tag (original) and Version (prefix-stripped).
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Repo,
        [string]$PrefixPattern = '^v'
    )

    $release = Get-GitHubRelease -Repo $Repo
    $rawTag = $release.tag_name
    $ver = $rawTag -replace $PrefixPattern, ''

    [PSCustomObject]@{
        Tag     = $rawTag
        Version = $ver
    }
}

function Convert-PSGalleryEntry {
    <#
    .SYNOPSIS
        Convert a PowerShell Gallery OData entry to a normalized PSObject.
    .PARAMETER Properties
        The properties node from an OData feed entry.
    .OUTPUTS
        PSCustomObject with Version, IsPrerelease, PackageHashHex, HashAlgorithm.
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory)]
        [object]$Properties
    )
    $ver  = $Properties.NormalizedVersion

    # IsPrerelease has m:type="Edm.Boolean" attribute → XmlElement, not string
    $preRaw = if ($Properties.IsPrerelease -is [System.Xml.XmlElement]) {
        $Properties.IsPrerelease.InnerText
    } else {
        $Properties.IsPrerelease
    }
    $pre = $preRaw -eq 'true'

    $hashRaw = if ($Properties.PackageHash -is [System.Xml.XmlElement]) {
        $Properties.PackageHash.InnerText
    } else {
        $Properties.PackageHash
    }
    $algoRaw = if ($Properties.PackageHashAlgorithm -is [System.Xml.XmlElement]) {
        $Properties.PackageHashAlgorithm.InnerText
    } else {
        $Properties.PackageHashAlgorithm
    }

    $hash = if ($hashRaw) { $hashRaw } else { '' }
    $algo = if ($algoRaw) { $algoRaw } else { 'SHA512' }

    $hashHex = ''
    if ($hash) {
        $hashBytes = [Convert]::FromBase64String($hash)
        $hashHex = -join ($hashBytes | ForEach-Object { '{0:X2}' -f $_ })
    }

    [PSCustomObject]@{
        Version        = $ver
        IsPrerelease   = $pre
        PackageHashHex = $hashHex
        HashAlgorithm  = $algo
    }
}

function Get-PSGalleryModuleInfo {
    <#
    .SYNOPSIS
        Query PowerShell Gallery OData API for module version and package hash.
    .DESCRIPTION
        Returns the latest stable (or specified) version, download URL, and SHA hash
        for a PowerShell Gallery module. When querying latest, fetches the full
        version feed sorted by NormalizedVersion desc and scans for the first
        non-prerelease entry. Hash is converted from base64 to hex for Get-FileHash.
    .PARAMETER ModuleName
        Module name (e.g. 'PSFzf').
    .PARAMETER Version
        Specific version to query. If omitted, analyzes the version feed to find
        the latest non-prerelease release.
    .OUTPUTS
        PSCustomObject with Version, DownloadUrl, PackageHashHex, HashAlgorithm.
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        [string]$Version = ""
    )

    if ($Version) {
        $url = "https://www.powershellgallery.com/api/v2/Packages(Id='$ModuleName',Version='$Version')"
    } else {
        $url = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id=%27$ModuleName%27&`$orderby=NormalizedVersion%20desc"
    }

    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        $xml = [xml]$response.Content

        if (-not $Version) {
            # ── Latest stable: fetch all, filter prerelease, semantic sort desc ──
            $entries = $xml.feed.entry
            if (-not $entries -or $entries.Count -eq 0) {
                throw "No entries found in PSGallery feed for $ModuleName"
            }
            # PSGallery's $orderby=NormalizedVersion desc uses string sort,
            # so "2.7.9" > "2.7.10". We must sort semantically client-side.
            Write-Debug "PSGallery: sorting $($entries.Count) entries for $ModuleName"
            $selected = $entries | ForEach-Object {
                Convert-PSGalleryEntry -Properties $_.properties
            } | Where-Object { -not $_.IsPrerelease } |
                Sort-Object { [version]$_.Version } -Descending |
                Select-Object -First 1
            if (-not $selected) { throw "No stable release found for $ModuleName" }
            Write-Debug "PSGallery: selected $ModuleName v$($selected.Version)"
            $selected
        } else {
            # ── Specific version: root is entry ──
            $entry = $xml.entry
            if (-not $entry) { throw "No package entry found for $ModuleName $Version" }
            Convert-PSGalleryEntry -Properties $entry.properties
        }
    }
    catch {
        throw "PSGallery API query failed for $ModuleName : $_"
    }
}

function Find-GitHubReleaseAsset {
    <#
    .SYNOPSIS
        Find the best-matching asset from a GitHub release for the target platform.
    .DESCRIPTION
        Filters release.assets[] by platform, architecture, and extension preference.
        Used when a tool definition does not hardcode GetArchiveName — the actual
        asset format (zip, tar.gz, bare exe) is discovered from the GitHub API.
    .PARAMETER Release
        GitHub release object from Get-GitHubRelease.
    .PARAMETER Platform
        Target platform: 'windows', 'linux', 'macos'. Mapped to name-matching regex.
    .PARAMETER Arch
        Target architecture: 'x86_64', 'aarch64'. Mapped to name-matching regex.
    .PARAMETER ExtPreference
        Ordered list of preferred file extensions. First match wins.
    .PARAMETER NamePattern
        Optional secondary regex to further filter asset names.
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory)]
        $Release,

        [string]$Platform = 'windows',

        [string]$Arch = 'x86_64',

        [string[]]$ExtPreference = @('.zip', '.tar.gz', '.exe'),

        [string]$NamePattern = $null
    )

    if (-not $Release.assets -or $Release.assets.Count -eq 0) {
        $url = if ($Release.html_url) { $Release.html_url } else { 'unknown' }
        throw "Release has no assets: $url"
    }

    $platformPattern = switch ($Platform) {
        'windows' { 'windows|msvc|pc-windows|(?<!dar)win(dows|32|64)?' }
        'linux'   { 'linux|ubuntu|debian|musl|gnu' }
        'macos'   { 'macos|darwin|mac|apple' }
        default   { $Platform }
    }

    $archPattern = switch ($Arch) {
        'x86_64'  { 'x86[_-]?64|amd64|x64' }
        'aarch64' { 'aarch64|arm64' }
        default   { $Arch }
    }

    $escapedExts = $ExtPreference | ForEach-Object { [regex]::Escape($_) }

    $candidates = $Release.assets | Where-Object {
        $asset = $_
        $asset.name -match $platformPattern -and
        $asset.name -match $archPattern -and
        ($escapedExts | Where-Object { $asset.name -match "$_$" })
    }

    if ($NamePattern) {
        $candidates = $candidates | Where-Object { $_.name -match $NamePattern }
    }

    if (-not $candidates -or $candidates.Count -eq 0) {
        $allNames = ($Release.assets | ForEach-Object { "  - $($_.name)" }) -join "`n"
        throw "No asset matching platform='$Platform' arch='$Arch' in release. Available assets:`n$allNames"
    }

    $candidates = $candidates | Sort-Object {
        $matchedExt = $null
        foreach ($e in $ExtPreference) {
            if ($_.name -match "$([regex]::Escape($e))$") {
                $matchedExt = $e
                break
            }
        }
        if ($matchedExt) { [array]::IndexOf($ExtPreference, $matchedExt) } else { 999 }
    }, 'name'

    $selected = $candidates | Select-Object -First 1
    Write-Host "[INFO] Matched asset: $($selected.name)" -ForegroundColor DarkGray
    $selected
}

function Test-FileHash {
    <#
    .SYNOPSIS
        Verify SHA256 hash of a downloaded file against GitHub sources.
    .PARAMETER FilePath
        Path to the downloaded file.
    .PARAMETER Release
        GitHub release object from Get-GitHubRelease.
    .PARAMETER AssetName
        Exact file name of the asset to match in release.assets[] / checksums.txt.
    .PARAMETER Repo
        GitHub repo "owner/repo", used for checksums.txt URL fallback.
    .PARAMETER Tag
        Release tag, used for checksums.txt URL fallback.
    .RETURNS
        $true if verified or skipped (no digest available).
        Throws on mismatch.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Release,

        [Parameter(Mandatory)]
        [string]$AssetName,

        [string]$Repo = '',

        [string]$Tag = ''
    )

    $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash

    # ---- Method 1: GitHub API digest field ----
    $expectedDigest = $null
    if ($Release -and $Release.assets) {
        $asset = $Release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
        if ($asset -and $asset.digest -and $asset.digest -match '^sha256:(.+)$') {
            $expectedDigest = $Matches[1].ToUpper()
        }
    }

    if ($expectedDigest) {
        if ($actualHash -eq $expectedDigest) {
            Write-Host "[OK] SHA256 verified via GitHub digest" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "[ERROR] SHA256 mismatch" -ForegroundColor Red
            Write-Host "       Expected (GitHub digest): $expectedDigest" -ForegroundColor Red
            Write-Host "       Actual:   $actualHash" -ForegroundColor Red
            throw "Integrity check failed for $AssetName"
        }
    }

    # ---- Method 2: checksums.txt / SHA256SUMS from release assets ----
    if ($Repo -and $Tag -and $Release -and $Release.assets) {
        # Find checksum file assets by naming convention
        $checksumCandidates = $Release.assets | Where-Object {
            $n = $_.name
            $n -ne $AssetName -and (  # exclude the asset itself
                $n -eq 'checksums.txt' -or
                $n -match '(?i)(checksum|sha256)' -or
                $n -match "\.SHA256SUMS$"
            )
        } | Sort-Object {
            if ($_.name -eq 'checksums.txt') { 0 }
            elseif ($_.name -match [regex]::Escape($AssetName)) { 1 }
            else { 2 }
        }

        if ($checksumCandidates) {
            $csAsset = $checksumCandidates | Where-Object { $_.browser_download_url } | Select-Object -First 1
            if (-not $csAsset) {
                Write-Host "[WARN] Checksum asset found but has no download URL" -ForegroundColor Yellow
                return $true
            }
            Write-Host "[INFO] Verifying via $($csAsset.name) ..." -ForegroundColor DarkGray
            $csContent = $null
            try {
                $csContent = Invoke-RestMethod -Uri $csAsset.browser_download_url -TimeoutSec 10 -ErrorAction Stop
            } catch {
                Write-Host "[WARN] Checksum download failed: $_" -ForegroundColor Yellow
                return $true
            }
            $lines = $csContent -split "`n" | ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and $_ -notmatch '^#' }

            foreach ($line in $lines) {
                if ($line -match '^([0-9a-fA-F]{64})\s+[\* ](.+)$') {
                    $expectedHash  = $Matches[1].ToUpper()
                    $entryFilename = Split-Path $Matches[2] -Leaf
                    if ($entryFilename -eq $AssetName) {
                        if ($actualHash -eq $expectedHash) {
                            Write-Host "[OK] SHA256 verified via $($csAsset.name)" -ForegroundColor Green
                            return $true
                        }
                        else {
                            Write-Host "[ERROR] SHA256 mismatch" -ForegroundColor Red
                            Write-Host "       Expected ($($csAsset.name)): $expectedHash" -ForegroundColor Red
                            Write-Host "       Actual:   $actualHash" -ForegroundColor Red
                            throw "Integrity check failed for $AssetName"
                        }
                    }
                }
            }
            Write-Host "[WARN] No matching entry for $AssetName in $($csAsset.name)" -ForegroundColor Yellow
        }
    }

    # ---- Fallback: no verification source available ----
    Write-Host "[WARN] No digest from GitHub API, hash verification skipped" -ForegroundColor Yellow
    Write-Host "       SHA256: $actualHash" -ForegroundColor DarkGray
    $true
}

function Add-UserPath {
    <#
    .SYNOPSIS
        Idempotently add a directory to user-level PATH
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Dir
    )
    $normalizedDir = $Dir.TrimEnd('\')
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $currentPath) { $currentPath = '' }
    $entries = ($currentPath -split ';') |
        ForEach-Object { $_.TrimEnd('\') } |
        Where-Object { $_ -ne '' }
    if ($entries -contains $normalizedDir) {
        return
    }
    else {
        # Avoid double semicolons
        $separator = if ($currentPath -and -not $currentPath.EndsWith(';')) { ';' } else { '' }
        $newPath = "$currentPath$separator$normalizedDir"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$env:Path;$normalizedDir"
        Write-Host "[OK] Added $Dir to user PATH" -ForegroundColor Green
    }
}

function Remove-UserPath {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Dir
    )
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $current) { return }

    $parts   = $current -split ';' | Where-Object { $_.TrimEnd('\') -ne $Dir.TrimEnd('\') }
    $cleaned = ($parts | Where-Object { $_ -ne '' }) -join ';'

    if ($cleaned -ne $current) {
        [Environment]::SetEnvironmentVariable("Path", $cleaned, "User")
        Write-Host "[OK] Removed from PATH: $Dir" -ForegroundColor Green
    }
}

function Test-ProfileEntry {
    <#
    .SYNOPSIS
        Check if a specific line exists in PowerShell profiles
    .PARAMETER Line
        The exact line to search for in profile files
    .OUTPUTS
        Hashtable with PS5 and PS7 status
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Line
    )

    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    $profiles = @(
        @{ Path = "$myDocs\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"; Label = "PS5" }
        @{ Path = "$myDocs\PowerShell\Microsoft.PowerShell_profile.ps1";        Label = "PS7" }
    )

    $result = @{
        PS5 = $false
        PS7 = $false
        All = $false
    }

    foreach ($p in $profiles) {
        if (Test-Path $p.Path) {
            $content = Get-Content $p.Path -Raw -ErrorAction SilentlyContinue
            if ($content -match [regex]::Escape($Line)) {
                $result[$p.Label] = $true
            }
        }
    }

    $result.All = $result.PS5 -and $result.PS7
    $result
}

function Show-ProfileStatus {
    <#
    .SYNOPSIS
        Display profile status in a formatted way
    .PARAMETER Line
        The line that should be in profile
    .PARAMETER Label
        Optional label for the line being checked
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line,
        [string]$Label = "Profile entry"
    )

    $status = Test-ProfileEntry -Line $Line

    if ($status.All) {
        Write-Host "  Profile ($Label): OK (PS5 + PS7)" -ForegroundColor DarkGray
    }
    elseif ($status.PS5 -or $status.PS7) {
        $partial = if ($status.PS5) { "PS5" } else { "PS7" }
        Write-Host "  Profile ($Label): Partial ($partial only)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  Profile ($Label): NOT configured" -ForegroundColor DarkGray
    }
}

#region Version Management Functions

function Compare-SemanticVersion {
    <#
    .SYNOPSIS
        Compare two semantic version strings
    .DESCRIPTION
        Uses .NET [version] type for proper semantic version comparison.
        Handles cases like "1.2.10" > "1.2.3" correctly.
    .PARAMETER Current
        Current version string
    .PARAMETER Latest
        Latest/target version string
    .EXAMPLE
        Compare-SemanticVersion "1.2.3" "1.2.10"  # Returns -1 (upgrade available)
        Compare-SemanticVersion "1.2.3" "1.2.3"  # Returns 0 (equal)
        Compare-SemanticVersion "1.2.10" "1.2.3" # Returns 1 (current newer)
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Current,

        [Parameter(Mandatory)]
        [string]$Latest
    )

    try {
        $currentVer = [version]$Current
        $latestVer = [version]$Latest

        if ($currentVer -lt $latestVer) {
            -1  # Current < Latest, upgrade needed
        }
        elseif ($currentVer -gt $latestVer) {
            1   # Current > Latest, already have newer version
        }
        else {
            0   # Versions are equal
        }
    }
    catch {
        # If version parsing fails, fall back to string comparison
        if ($Current -eq $Latest) {
            0
        }
        elseif ($Current -lt $Latest) {
            -1
        }
        else {
            1
        }
    }
}

function Test-VersionLocked {
    <#
    .SYNOPSIS
        Check if a tool version is locked
    .DESCRIPTION
        Reads the tool's per-tool config (.config\<ToolName>\config.json)
        and returns the locked version string or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName
    )

    $configPath = Join-Path $script:OhmyRoot ".config\$ToolName\config.json"
    if (-not (Test-Path $configPath)) { return }

    try {
        $config = Get-Content -Path $configPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($config.lock) { return $config.lock }
    }
    catch {
        Write-Debug "Version lock config read error: $_"
    }
}

function Set-VersionLock {
    <#
    .SYNOPSIS
        Set or remove a version lock for a tool
    .DESCRIPTION
        Writes/removes the 'lock' field in the tool's per-tool config
        (.config\<ToolName>\config.json).
    .PARAMETER ToolName
        Tool identifier (e.g. "just", "ripgrep")
    .PARAMETER Version
        Version to lock. Pass empty string or $null to remove lock.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [AllowEmptyString()]
        [string]$Version = ""
    )

    $configPath = Join-Path $script:OhmyRoot ".config\$ToolName\config.json"
    $configDir  = Split-Path $configPath -Parent

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $config = @{}
    if (Test-Path $configPath) {
        try {
            $obj = Get-Content -Path $configPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $obj.PSObject.Properties | ForEach-Object { $config[$_.Name] = $_.Value }
        }
        catch {
            $config = @{}
        }
    }

    if ($Version) {
        $config['lock'] = $Version
    }
    else {
        $config.Remove('lock')
    }

    $config | ConvertTo-Json -Depth 1 | Set-Content -Path $configPath -Encoding UTF8 -Force
}

function Test-UpgradeRequired {
    <#
    .SYNOPSIS
        Test if a tool upgrade is required
    .DESCRIPTION
        Checks version lock, then semantic version comparison.
        Locked tools return Required=false unless -Force is used.
    .PARAMETER Current
        Current installed version
    .PARAMETER Target
        Target version to install
    .PARAMETER ToolName
        Tool identifier for version lock lookup
    .PARAMETER Force
        If set, always returns true (skip lock and version check)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Current,

        [Parameter(Mandatory)]
        [string]$Target,

        [string]$ToolName = "",

        [switch]$Force
    )

    # Check version lock (unless Force)
    if (-not $Force -and $ToolName) {
        $lockedVersion = Test-VersionLocked -ToolName $ToolName
        if ($lockedVersion) {
            return @{
                Required = $false
                Reason = "Version locked to $lockedVersion (use -Force to override)"
            }
        }
    }

    if ($Force) {
        return @{
            Required = $true
            Reason = "Force mode enabled"
        }
    }

    $comparison = Compare-SemanticVersion -Current $Current -Latest $Target

    if ($comparison -eq -1) {
        @{
            Required = $true
            Reason = "Upgrade available: $Current -> $Target"
        }
    }
    elseif ($comparison -eq 1) {
        @{
            Required = $false
            Reason = "Current version ($Current) is newer than target ($Target)"
        }
    }
    else {
        @{
            Required = $false
            Reason = "Already up to date: $Current"
        }
    }
}

function Backup-ToolVersion {
    <#
    .SYNOPSIS
        Backup current tool executable file
    .DESCRIPTION
        Creates a backup of the tool executable to a temporary directory.
        Backup is named with timestamp for rollback capability.
    .PARAMETER ToolName
        Name of the tool (used in backup directory name)
    .PARAMETER ExePath
        Full path to the executable to backup
    .EXAMPLE
        Backup-ToolVersion -ToolName "fzf" -ExePath "C:\Users\ray\.local\bin\fzf.exe"
        # Returns: C:\Users\ray\AppData\Local\Temp\fzf-backup-20250410-143000\fzf.exe
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$ExePath
    )

    if (-not (Test-Path $ExePath)) {
        throw "Executable not found: $ExePath"
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $env:TEMP "$ToolName-backup-$timestamp"
    $backupFile = Join-Path $backupDir (Split-Path $ExePath -Leaf)

    # Create backup directory
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    # Copy executable to backup
    Copy-Item -Path $ExePath -Destination $backupFile -Force

    $backupFile
}

function Restore-ToolVersion {
    <#
    .SYNOPSIS
        Restore tool from backup
    .DESCRIPTION
        Restores a tool executable from backup location.
        Used when upgrade fails and rollback is needed.
    .PARAMETER ToolName
        Name of the tool
    .PARAMETER BackupPath
        Full path to the backup file
    .PARAMETER TargetPath
        Target location where executable should be restored
    .EXAMPLE
        Restore-ToolVersion -ToolName "fzf" -BackupPath "C:\...\fzf.exe" -TargetPath "C:\Users\ray\.local\bin\fzf.exe"
    # Restores fzf.exe from backup
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$BackupPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path $BackupPath)) {
        throw "Backup file not found: $BackupPath"
    }

    try {
        # Ensure target directory exists
        $targetDir = Split-Path $TargetPath -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        # Restore from backup
        Copy-Item -Path $BackupPath -Destination $TargetPath -Force
        Write-Host "[INFO] Restored $ToolName from backup" -ForegroundColor Cyan
    }
    catch {
        throw "Failed to restore $ToolName from backup: $_"
    }
}

#endregion Version Management Functions

#region Unified Output Functions

function Show-AlreadyInstalled {
    <#
    .SYNOPSIS
        Display unified "already installed" message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,
        [string]$Version = "",
        [string]$Location = ""
    )

    $versionInfo = if ($Version) { " $Version" } else { "" }
    Write-Host "[OK] Already installed: $Tool$versionInfo" -ForegroundColor Green

    if ($Location) {
        Write-Host "  Location: $Location" -ForegroundColor DarkGray
    }
}

function Show-Installing {
    <#
    .SYNOPSIS
        Display unified "installing" message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component
    )

    Write-Host "[INFO] Installing $Component..." -ForegroundColor Cyan
}

function Show-InstallComplete {
    <#
    .SYNOPSIS
        Display unified "installation completed" message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,
        [string]$Version = "",
        [string]$NextSteps = ""
    )

    $versionInfo = if ($Version) { " $Version" } else { "" }
    Write-Host "[OK] $Tool installation completed!$versionInfo" -ForegroundColor Green

    if ($NextSteps) {
        Write-Host "  $NextSteps" -ForegroundColor DarkGray
    }
}

function Show-InstallSuccess {
    <#
    .SYNOPSIS
        Display unified "installed" message for components
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,
        [string]$Location = ""
    )

    Write-Host "[OK] $Component installed" -ForegroundColor Green

    if ($Location) {
        Write-Host "  Location: $Location" -ForegroundColor DarkGray
    }
}

function Show-NotInstalled {
    <#
    .SYNOPSIS
        Display unified "not installed" message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,
        [string]$Expected = ""
    )
    Write-Host "[INFO] $Tool not installed" -ForegroundColor Cyan
    if ($Expected) {
        Write-Host "  Expected: $Expected" -ForegroundColor DarkGray
    }
}

function Show-UninstallHeader {
    <#
    .SYNOPSIS
        Display unified uninstall section header
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )
    Write-Host ""
    Write-Host "=== Uninstall $DisplayName ===" -ForegroundColor Cyan
}

function Show-UninstallComplete {
    <#
    .SYNOPSIS
        Display unified uninstall completion message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool
    )
    Write-Host "[OK] $Tool uninstalled" -ForegroundColor Green
}

function Show-LockWrite {
    <#
    .SYNOPSIS
        Display lock write success message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )
    Write-Host "[OK] Locked: $Version" -ForegroundColor Green
}

function Show-LockRemoved {
    <#
    .SYNOPSIS
        Display lock removal success message
    #>
    [CmdletBinding()]
    param()
    Write-Host "[OK] Lock removed" -ForegroundColor Green
}

function Show-LockMismatch {
    <#
    .SYNOPSIS
        Display version lock mismatch warning (installed differs from locked)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LockedVersion
    )
    Write-Host "[LOCK] Locked: $LockedVersion" -ForegroundColor Magenta
}

#endregion Unified Output Functions

#region Shim Deployment Functions

function Install-ShimExe {
    <#
    .SYNOPSIS
        Deploy a scoop-better-shimexe shim next to an existing script/cmd.
    .DESCRIPTION
        Downloads scoop-better-shimexe (with caching), extracts shim.exe,
        copies it as <TargetExePath>, and creates a companion .shim config
        file that points to the real script. Idempotent.
    .PARAMETER TargetExePath
        Full path where the shim .exe should be placed.
        Example: D:\DevEnvs\node\typescript-language-server.exe
    .PARAMETER ShimTargetPath
        Full path to the real script/cmd that the shim should invoke.
        Example: D:\DevEnvs\node\typescript-language-server.cmd
    .PARAMETER ShimArgs
        Optional additional arguments passed via the 'args = ' line in the .shim config.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetExePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ShimTargetPath,

        [string]$ShimArgs = ""
    )

    # ---- Idempotent check ----
    $shimConfigPath = [System.IO.Path]::ChangeExtension($TargetExePath, ".shim")
    if ((Test-Path $TargetExePath) -and (Test-Path $shimConfigPath)) {
        $existingContent = (Get-Content $shimConfigPath -Raw -ErrorAction SilentlyContinue).Trim()
        if ($existingContent -match [regex]::Escape("path = $ShimTargetPath")) {
            Show-AlreadyInstalled -Tool "shim: $(Split-Path $TargetExePath -Leaf)" -Location $TargetExePath
            return
        }
    }

    # ---- Validate target script exists ----
    if (-not (Test-Path $ShimTargetPath)) {
        throw "Shim target not found: $ShimTargetPath"
    }

    # ---- Download shimexe ----
    $ShimExeVersion = "3.2.1"
    $ShimExeUrl     = "https://github.com/kiennq/scoop-better-shimexe/releases/download/v$ShimExeVersion/shimexe-x86_64.zip"
    $ShimExeZipName = "shimexe-x86_64.zip"
    $tempZip        = Join-Path $env:TEMP $ShimExeZipName

    try {
        Write-Host "[INFO] Downloading shimexe v$ShimExeVersion..." -ForegroundColor Cyan
        Save-WithCache -Url $ShimExeUrl -OutFile $tempZip -CacheDir "shimexe" `
            -GhRepo "kiennq/scoop-better-shimexe" -GhTag "v$ShimExeVersion" -GhAssetPattern "shimexe-x86_64.zip"
    }
    catch {
        Write-Host "[ERROR] Failed to download shimexe: $_" -ForegroundColor Red
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        return
    }

    # ---- Extract ----
    $extractDir    = Join-Path $env:TEMP "shimexe-extract"
    $shimExeSource = Join-Path $extractDir "shim.exe"

    try {
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Expand-Archive -Path $tempZip -DestinationPath $extractDir -Force -ErrorAction Stop

        if (-not (Test-Path $shimExeSource)) {
            throw "shim.exe not found in extracted archive"
        }
    }
    catch {
        throw "Failed to extract shimexe: $_"
    }

    # ---- Deploy shim exe ----
    $targetDir = Split-Path $TargetExePath -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    Copy-Item -Path $shimExeSource -Destination $TargetExePath -Force

    # ---- Create .shim config ----
    $shimLines = @("path = $ShimTargetPath")
    if ($ShimArgs) {
        $shimLines += "args = $ShimArgs"
    }
    Set-Content -Path $shimConfigPath -Value ($shimLines -join "`n") -NoNewline -Encoding UTF8

    # ---- Cleanup ----
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

    Show-InstallSuccess -Component "shim: $(Split-Path $TargetExePath -Leaf)" -Location $TargetExePath
}

function Remove-ShimExe {
    <#
    .SYNOPSIS
        Remove a shim exe and its companion .shim config file.
    .PARAMETER TargetExePath
        Full path to the shim .exe to remove.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetExePath
    )

    $shimConfigPath = [System.IO.Path]::ChangeExtension($TargetExePath, ".shim")
    foreach ($file in @($TargetExePath, $shimConfigPath)) {
        if (Test-Path $file) {
            try {
                Remove-Item $file -Force -ErrorAction Stop
                Write-Host "[OK] Removed: $file" -ForegroundColor Green
            }
            catch {
                Write-Host "[WARN] Could not remove $file : $_" -ForegroundColor Yellow
            }
        }
    }
}

#endregion Shim Deployment Functions

function Remove-PendingDeleteDirs {
    <#
    .SYNOPSIS
        Clean up any .pending-delete directories from previous uninstalls.
        Automatically removes stale *.pending-delete folders in PowerShell module paths.
        Falls back to child process if direct delete fails.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    $moduleDirs = @(
        "$myDocs\WindowsPowerShell\Modules\"
        "$myDocs\PowerShell\Modules\"
    )

    $childShell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
    $cleaned = 0

    foreach ($dir in $moduleDirs) {
        if (-not (Test-Path $dir)) { continue }

        Get-ChildItem -Path $dir -Directory -Filter "*.pending-delete" -ErrorAction SilentlyContinue | ForEach-Object {
            $pendingPath = $_.FullName
            Write-Host "[INFO] Cleaning up stale .pending-delete: $($pendingPath)" -ForegroundColor DarkGray

            # Try direct delete first
            try {
                Remove-Item -Path $pendingPath -Recurse -Force -ErrorAction Stop
                Write-Host "[OK] Removed .pending-delete: $pendingPath" -ForegroundColor Green
                $cleaned++
                return
            }
            catch {
                Write-Host "[INFO] Direct delete failed, trying child process..." -ForegroundColor DarkGray
            }

            # Try child process delete
            $deleteScript = "Remove-Item -Path '$($pendingPath -replace "'","''")' -Recurse -Force -ErrorAction SilentlyContinue"
            $null = Start-Process -FilePath $childShell -ArgumentList @(
                '-NoProfile', '-NonInteractive', '-Command', $deleteScript
            ) -Wait -NoNewWindow

            if (-not (Test-Path $pendingPath)) {
                Write-Host "[OK] Removed .pending-delete (via child): $pendingPath" -ForegroundColor Green
                $cleaned++
            }
            else {
                Write-Host "[WARN] .pending-delete still locked: $pendingPath" -ForegroundColor Yellow
            }
        }
    }

    if ($cleaned -eq 0) {
        Write-Host "[INFO] No .pending-delete directories found" -ForegroundColor DarkGray
    }
}
