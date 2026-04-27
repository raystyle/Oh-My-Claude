#Requires -Version 5.1

# Shared test infrastructure for OhMyClaude Pester tests.
# Dot-source this file in BeforeAll — it loads production scripts,
# defines helper factories, and sets up TestDrive for isolated file tests.

# ── Resolve project paths ──
$_testProjectRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
$_testScriptsDir  = Join-Path $_testProjectRoot '.scripts'

# ── Load production scripts ──
. "$_testScriptsDir\helpers.ps1"
. "$_testScriptsDir\core.ps1"
. "$_testScriptsDir\dev\psmodule.ps1"

# ── Set global root for tool lifecycle functions ──
$global:Tool_RootDir = $script:OhmyRoot

# ── Helper factories ──

function New-TestToolDefinition {
    <#
    .SYNOPSIS
        Create a synthetic tool definition hashtable for testing.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$ToolName = 'testtool',
        [hashtable]$Override = @{}
    )
    $default = @{
        ToolName           = $ToolName
        DisplayName        = $ToolName
        ExeName            = "$ToolName.exe"
        Source             = 'github-release'
        Repo               = 'testowner/testrepo'
        TagPrefix          = 'v'
        ExtractType        = 'standalone'
        GetSetupDir        = { param($r) "$r\.config\$ToolName" }
        GetBinDir          = { param($r) "$r\.envs\tools\bin" }
        VersionCommand     = '--version'
        VersionPattern     = '(\d+\.\d+\.\d+)'
        AssetPlatform      = 'windows'
        AssetArch          = 'x86_64'
        AssetExtPreference = @('.zip', '.tar.gz', '.exe')
    }
    foreach ($key in $Override.Keys) {
        $default[$key] = $Override[$key]
    }
    $default
}

function New-SyntheticRelease {
    <#
    .SYNOPSIS
        Create a synthetic GitHub release object for testing.
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [string]$TagName = 'v1.2.3',
        [array]$Assets = @()
    )
    [PSCustomObject]@{
        tag_name = $TagName
        assets   = $Assets
    }
}

function New-SyntheticAsset {
    <#
    .SYNOPSIS
        Create a synthetic release asset for testing.
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [string]$Name = 'tool-v1.0.0-windows-x86_64.zip',
        [long]$Size = 1048576,
        [string]$BrowserDownloadUrl = "https://github.com/owner/repo/releases/download/v1.0.0/$Name",
        [string]$Digest = $null
    )
    [PSCustomObject]@{
        name                 = $Name
        size                 = $Size
        browser_download_url = $BrowserDownloadUrl
        digest               = $Digest
    }
}

function New-TestConfig {
    <#
    .SYNOPSIS
        Create a test config directory and return its path.
        Uses $script:OhmyRoot (real project root) with a unique suffix.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName
    )
    $configDir = Join-Path $script:OhmyRoot ".config\$ToolName"
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    $configDir
}

function Remove-TestConfig {
    <#
    .SYNOPSIS
        Remove a test config directory created by New-TestConfig.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName
    )
    $configDir = Join-Path $script:OhmyRoot ".config\$ToolName"
    if (Test-Path $configDir) {
        Remove-Item $configDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
