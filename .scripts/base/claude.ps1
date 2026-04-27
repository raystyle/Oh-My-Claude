#Requires -Version 5.1

<#
.SYNOPSIS
    Manage Claude Code installation via claude-agent-sdk.
.PARAMETER Command
    Action: check, download, install, update, uninstall, setup.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("check", "download", "install", "update", "uninstall", "setup")]
    [string]$Command = "check",

    [switch]$Force
)

. "$PSScriptRoot\..\helpers.ps1"

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

# ── Resolve ohmyclaude root from script location ──
$script:OhmyRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# ── Constants ──
$UvExe           = Join-Path $script:OhmyRoot '.envs\base\bin\uv.exe'
$CacheDir        = Join-Path $script:OhmyRoot '.cache\base\claude'
$BinDir          = "$env:USERPROFILE\.local\bin"
$TargetExe       = "$BinDir\claude.exe"
$script:ClaudeLockPath = Join-Path $script:OhmyRoot '.config\claude\config.json'
$SdkPackage      = 'claude-agent-sdk'

function Get-ClaudeExeVersion {
    <#
    .SYNOPSIS
        Get the Claude Code version string from a given executable path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) { return }
    try {
        $output = & $Path --version 2>&1 | Out-String
        if ($output -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    } catch {}
}

function Get-InstalledVersion {
    <#
    .SYNOPSIS
        Get the currently installed Claude Code version string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Get-ClaudeExeVersion -Path $TargetExe
}

function Get-ClaudeLock {
    <#
    .SYNOPSIS
        Read the locked Claude Code and SDK versions from config.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not (Test-Path $script:ClaudeLockPath)) { return }
    try {
        $cfg = Get-Content $script:ClaudeLockPath -Raw -ErrorAction SilentlyContinue |
            ConvertFrom-Json
        if ($cfg.lock) {
            return @{
                Lock          = $cfg.lock
                ClaudeVersion = if ($cfg.claude_version) { $cfg.claude_version } else { $cfg.lock }
                SdkVersion    = $cfg.sdk_version
                SHA256        = $cfg.sha256
            }
        }
    } catch {}
}

function Set-ClaudeLock {
    <#
    .SYNOPSIS
        Write the locked Claude Code version, SDK version, and SHA256 to config.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$ClaudeVersion,

        [Parameter(Mandatory)]
        [string]$SdkVersion,

        [string]$SHA256
    )

    $dir = Split-Path $script:ClaudeLockPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $noBom = New-Object System.Text.UTF8Encoding $false
    $lockStr = "$ClaudeVersion/$SdkVersion"
    $json = @{
        lock           = $lockStr
        claude_version = $ClaudeVersion
        sdk_version    = $SdkVersion
        sha256         = $SHA256
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($script:ClaudeLockPath, $json.Trim(), $noBom)
}

function Get-SdkLatestVersion {
    <#
    .SYNOPSIS
        Query PyPI for the latest claude-agent-sdk version.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path $UvExe)) { return }

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $UvExe run python -m pip index versions $SdkPackage 2>$null | Out-String
    $ErrorActionPreference = $prevEAP

    if ($output -match "$SdkPackage\s*\((\d+\.\d+\.\d+)\)") { return $Matches[1] }
}

function Remove-ClaudeLock {
    <#
    .SYNOPSIS
        Delete the Claude Code lock config file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (Test-Path $script:ClaudeLockPath) {
        Remove-Item $script:ClaudeLockPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ClaudeExtract {
    <#
    .SYNOPSIS
        Extract claude.exe from claude-agent-sdk via uv run --with.
    .PARAMETER Destination
        Target file path for the extracted claude.exe.
    .PARAMETER SdkVersion
        Specific SDK version to use. If omitted, uses latest.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Destination,

        [string]$SdkVersion
    )

    if (-not (Test-Path $UvExe)) {
        Write-Host "[ERROR] uv not found at $UvExe - run 'omc install uv' first" -ForegroundColor Red
        exit 1
    }

    $destDir = Split-Path $Destination -Parent
    if ($destDir -and -not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $pyScript = @"
import claude_agent_sdk, shutil, os, sys
src = os.path.join(os.path.dirname(claude_agent_sdk.__file__), '_bundled', 'claude.exe')
if not os.path.isfile(src):
    print(f'[ERROR] claude.exe not found in sdk: {src}')
    sys.exit(1)
dst = os.environ.get('CLAUDE_TARGET_EXE', 'claude.exe')
os.makedirs(os.path.dirname(dst) or '.', exist_ok=True)
shutil.copy2(src, dst)
size_mb = os.path.getsize(dst) // (1024*1024)
print(f'Extracted: {dst} ({size_mb} MB)')
"@

    $withSpec = if ($SdkVersion) { "$SdkPackage==$SdkVersion" } else { $SdkPackage }
    $sdkLabel = if ($SdkVersion) { "$SdkPackage $SdkVersion" } else { "$SdkPackage (latest)" }
    Write-Host "[INFO] Extracting claude.exe via $sdkLabel ..." -ForegroundColor Cyan

    $env:CLAUDE_TARGET_EXE = $Destination
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $UvExe run --with $withSpec python -c $pyScript 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    if ($exitCode -ne 0) {
        Write-Host "[ERROR] claude.exe is in use - close Claude Code and try again" -ForegroundColor Red
        exit 1
    }

    if (-not (Test-Path $Destination)) {
        Write-Host "[ERROR] claude.exe not found at $Destination after extraction" -ForegroundColor Red
        exit 1
    }

    # Clean up temporary uv cache
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $UvExe cache prune 2>$null
    $ErrorActionPreference = $prevEAP
}

# ═══════════════════════════════════════════════════════════════════════════
# Configuration System
# ═══════════════════════════════════════════════════════════════════════════

$script:ClaudeDefaultBaseUrl = "https://open.bigmodel.cn/api/anthropic"
$script:ClaudeJsonPath = Join-Path $env:USERPROFILE ".claude.json"

$script:ConfigItems = @{
    # ── API ──
    API_TIMEOUT_MS = @{
        Default = "3000000"
        Description = "API request timeout (ms)"
        Type = "env"
    }
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = @{
        Default = "1"
        Description = "Disable telemetry and non-essential traffic"
        Type = "env"
    }
    ENABLE_LSP_TOOL = @{
        Default = "1"
        Description = "Enable LSP-based code intelligence"
        Type = "env"
    }
    CLAUDE_CODE_USE_POWERSHELL_TOOL = @{
        Default = "1"
        Description = "Use PowerShell as the shell tool on Windows"
        Type = "env"
    }
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = @{
        Default = "1"
        Description = "Enable experimental agent teams"
        Type = "env"
    }
    CLAUDE_CODE_GIT_BASH_PATH = @{
        Default = { Join-Path $script:OhmyRoot ".envs\base\git\bin\bash.exe" }
        Description = "Path to Git Bash executable"
        Type = "env"
        Dynamic = $true
    }
    # ── Bash timeouts (aligned with API_TIMEOUT_MS) ──
    BASH_DEFAULT_TIMEOUT_MS = @{
        Default = "300000"
        Description = "Default Bash command timeout (ms)"
        Type = "env"
    }
    BASH_MAX_TIMEOUT_MS = @{
        Default = "600000"
        Description = "Maximum Bash command timeout (ms)"
        Type = "env"
    }
    # ── Disable flags ──
    DISABLE_TELEMETRY = @{
        Default = "1"
        Description = "Disable telemetry"
        Type = "env"
    }
    DISABLE_AUTOUPDATER = @{
        Default = "1"
        Description = "Disable auto-updater"
        Type = "env"
    }
    DISABLE_AUTO_COMPACT = @{
        Default = "1"
        Description = "Disable automatic context compaction"
        Type = "env"
    }
    DISABLE_FEEDBACK_SURVEY = @{
        Default = "1"
        Description = "Disable feedback survey prompts"
        Type = "env"
    }
    CLAUDE_CODE_DISABLE_1M_CONTEXT = @{
        Default = "1"
        Description = "Disable 1M context window (unsupported by GLM)"
        Type = "env"
    }
    MCP_TIMEOUT = @{
        Default = "60000"
        Description = "MCP server communication timeout (ms)"
        Type = "env"
    }
    # ── Python encoding ──
    PYTHONUTF8 = @{
        Default = "1"
        Description = "Force Python UTF-8 mode"
        Type = "env"
    }
    PYTHONIOENCODING = @{
        Default = "utf-8"
        Description = "Python stdin/stdout/stderr encoding"
        Type = "env"
    }
    # ── Locale ──
    LANG = @{
        Default = "en_US.UTF-8"
        Description = "Locale setting"
        Type = "env"
    }
    LC_ALL = @{
        Default = "en_US.UTF-8"
        Description = "Locale override"
        Type = "env"
    }
    # ── API credentials ──
    ANTHROPIC_AUTH_TOKEN = @{
        Default = ""
        Description = "API authentication token"
        Type = "api"
        Required = $true
        Sensitive = $true
    }
    ANTHROPIC_BASE_URL = @{
        Default = $script:ClaudeDefaultBaseUrl
        Description = "API base URL"
        Type = "api"
        Required = $true
    }
    # ── Default models ──
    ANTHROPIC_DEFAULT_HAIKU_MODEL = @{
        Default = "glm-4.5-air"
        Description = "Default Haiku model"
        Type = "model"
    }
    ANTHROPIC_DEFAULT_SONNET_MODEL = @{
        Default = "glm-5-turbo"
        Description = "Default Sonnet model"
        Type = "model"
    }
    ANTHROPIC_DEFAULT_OPUS_MODEL = @{
        Default = "glm-5.1"
        Description = "Default Opus model"
        Type = "model"
    }
}

function Get-ConfigValue {
    <#
    .SYNOPSIS
        Get current value of a configuration item
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $item = $script:ConfigItems[$Name]
    if (-not $item) { $null; return }

    $current = [Environment]::GetEnvironmentVariable($Name, "User")

    if ($current) {
        @{
            Name = $Name
            Value = $current
            IsSet = $true
            Source = "env"
        }
    } else {
        @{
            Name = $Name
            Value = $null
            IsSet = $false
            Source = "default"
        }
    }
}

function Show-ConfigItemStatus {
    <#
    .SYNOPSIS
        Display status of a single config item
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $item = $script:ConfigItems[$Name]
    if (-not $item) { return }

    $config = Get-ConfigValue -Name $Name
    $defaultValue = if ($item.Dynamic) { & $item.Default } else { $item.Default }

    if ($config.IsSet) {
        $displayValue = if ($item.Sensitive) {
            if ($config.Value.Length -gt 8) {
                $config.Value.Substring(0, 8) + "..." + $config.Value.Substring($config.Value.Length - 4)
            } else {
                "***"
            }
        } else {
            $config.Value
        }
        Write-Host "  [OK] $Name = $displayValue" -ForegroundColor Green
    } else {
        $defaultDisplay = if ($defaultValue) { $defaultValue } else { "(not set)" }
        Write-Host "  [INFO] $Name = (not set, default: $defaultDisplay)" -ForegroundColor Yellow
    }
}

function Show-ConfigStatus {
    <#
    .SYNOPSIS
        Display status of all configuration items
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- Claude Code Configuration ---" -ForegroundColor Cyan

    # Environment config
    Write-Host "`n  Environment:" -ForegroundColor Cyan
    foreach ($key in $script:ConfigItems.Keys) {
        if ($script:ConfigItems[$key].Type -eq "env") {
            Show-ConfigItemStatus -Name $key
        }
    }

    # API config
    Write-Host "`n  API Credentials:" -ForegroundColor Cyan
    foreach ($key in $script:ConfigItems.Keys) {
        if ($script:ConfigItems[$key].Type -eq "api") {
            Show-ConfigItemStatus -Name $key
        }
    }

    # Model config
    Write-Host "`n  Default Models:" -ForegroundColor Cyan
    foreach ($key in $script:ConfigItems.Keys) {
        if ($script:ConfigItems[$key].Type -eq "model") {
            Show-ConfigItemStatus -Name $key
        }
    }

    # Onboarding
    $onboarded = $false
    if (Test-Path $script:ClaudeJsonPath) {
        try {
            $claudeJson = Get-Content $script:ClaudeJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($claudeJson.hasCompletedOnboarding -eq $true) { $onboarded = $true }
        } catch {}
    }
    Write-Host "`n  Onboarding:" -ForegroundColor Cyan
    if ($onboarded) {
        Write-Host "  [OK] Completed" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Not completed" -ForegroundColor Yellow
    }
}

function Set-ConfigItem {
    <#
    .SYNOPSIS
        Set a configuration item value
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Value
    )

    $item = $script:ConfigItems[$Name]
    if (-not $item) {
        Write-Host "[WARN] Unknown config item: $Name" -ForegroundColor Yellow
        return
    }

    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "env:$Name" -Value $Value

    $displayValue = if ($item.Sensitive) { "***" } else { $Value }
    Write-Host "  [OK] $Name = $displayValue" -ForegroundColor Green

    $true
}

function Set-DefaultConfig {
    <#
    .SYNOPSIS
        Apply default values to all config items
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "[INFO] Applying default configuration..." -ForegroundColor Cyan

    $changed = $false

    foreach ($key in $script:ConfigItems.Keys) {
        $item = $script:ConfigItems[$key]
        if ($item.Required -and -not $item.Default) { continue }

        $current = [Environment]::GetEnvironmentVariable($key, "User")
        $defaultValue = if ($item.Dynamic) { & $item.Default } else { $item.Default }

        if (-not $defaultValue) { continue }

        if ($current -ne $defaultValue) {
            [Environment]::SetEnvironmentVariable($key, $defaultValue, "User")
            Set-Item -Path "env:$key" -Value $defaultValue
            Write-Host "  [OK] $key = $defaultValue" -ForegroundColor Green
            $changed = $true
        } else {
            Write-Host "  [OK] $key = $defaultValue" -ForegroundColor DarkGray
        }
    }

    # Onboarding
    $onboarded = $false
    if (Test-Path $script:ClaudeJsonPath) {
        try {
            $claudeJson = Get-Content $script:ClaudeJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($claudeJson.hasCompletedOnboarding -eq $true) { $onboarded = $true }
        } catch {}
    }
    if (-not $onboarded) {
        $claudeConfig = @{}
        if (Test-Path $script:ClaudeJsonPath) {
            try {
                $existing = Get-Content $script:ClaudeJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $existing.PSObject.Properties | ForEach-Object { $claudeConfig[$_.Name] = $_.Value }
            } catch {}
        }
        $claudeConfig['hasCompletedOnboarding'] = $true
        $noBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($script:ClaudeJsonPath, ($claudeConfig | ConvertTo-Json), $noBom)
        Write-Host "  [OK] Onboarding: hasCompletedOnboarding = true" -ForegroundColor Green
        $changed = $true
    } else {
        Write-Host "  [OK] Onboarding: completed" -ForegroundColor DarkGray
    }

    if (-not $changed) {
        Write-Host "  [OK] All defaults up to date" -ForegroundColor Green
    }
}

function Read-CustomConfig {
    <#
    .SYNOPSIS
        Open a GUI dialog to edit Claude Code interactive configuration.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $interactiveKeys = @(
        'ANTHROPIC_AUTH_TOKEN'
        'ANTHROPIC_BASE_URL'
        'ANTHROPIC_DEFAULT_HAIKU_MODEL'
        'ANTHROPIC_DEFAULT_SONNET_MODEL'
        'ANTHROPIC_DEFAULT_OPUS_MODEL'
    )

    $table = New-Object System.Data.DataTable
    $null = $table.Columns.Add("Variable")
    $null = $table.Columns.Add("Value")
    $null = $table.Columns.Add("Description")

    foreach ($key in $interactiveKeys) {
        $item = $script:ConfigItems[$key]
        $current = [Environment]::GetEnvironmentVariable($key, "User")
        if (-not $current) {
            $current = if ($item.Dynamic) { & $item.Default } else { $item.Default }
        }
        $row = $table.NewRow()
        $row["Variable"] = $key
        $row["Value"] = $current
        $row["Description"] = $item.Description
        $table.Rows.Add($row) | Out-Null
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Claude Code Configuration"
    $form.ClientSize = New-Object System.Drawing.Size(720, 300)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = "Fill"
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.MultiSelect = $false
    $grid.SelectionMode = "CellSelect"
    $grid.RowHeadersVisible = $false
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.BorderStyle = "None"
    $grid.CellBorderStyle = "SingleHorizontal"
    $grid.GridColor = [System.Drawing.Color]::LightGray
    $grid.AutoGenerateColumns = $false

    $colVar = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colVar.HeaderText = "Variable"
    $colVar.ReadOnly = $true
    $colVar.Width = 260
    $colVar.DataPropertyName = "Variable"
    $colVar.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Gray

    $colVal = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colVal.HeaderText = "Value"
    $colVal.Width = 300
    $colVal.DataPropertyName = "Value"

    $colDesc = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colDesc.HeaderText = "Description"
    $colDesc.ReadOnly = $true
    $colDesc.AutoSizeMode = "Fill"
    $colDesc.DataPropertyName = "Description"
    $colDesc.DefaultCellStyle.ForeColor = [System.Drawing.Color]::DarkGray

    $grid.Columns.Clear()
    $grid.Columns.Add($colVar)
    $grid.Columns.Add($colVal)
    $grid.Columns.Add($colDesc)
    $grid.DataSource = $table

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Bottom"
    $panel.Height = 50

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Size = New-Object System.Drawing.Size(100, 32)
    $btnCancel.Location = New-Object System.Drawing.Point(500, 8)
    $btnCancel.DialogResult = "Cancel"

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Size = New-Object System.Drawing.Size(100, 32)
    $btnSave.Location = New-Object System.Drawing.Point(610, 8)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(200, 230, 200)
    $btnSave.DialogResult = "OK"

    $panel.Controls.AddRange(@($btnCancel, $btnSave))
    $form.Controls.Add($panel)
    $form.Controls.Add($grid)

    $form.AcceptButton = $btnSave
    $form.CancelButton = $btnCancel

    $result = $form.ShowDialog()

    if ($result -ne "OK") { return $false }

    $grid.EndEdit()

    $tokenValue = $grid.Rows[0].Cells[1].Value
    if (-not $tokenValue -or [string]::IsNullOrWhiteSpace($tokenValue.ToString())) {
        [System.Windows.Forms.MessageBox]::Show(
            "API Key cannot be empty.", "Validation Error",
            "OK", "Error")
        return $false
    }

    for ($i = 0; $i -lt $interactiveKeys.Count; $i++) {
        $name = $interactiveKeys[$i]
        $value = $grid.Rows[$i].Cells[1].Value.ToString()
        Set-ConfigItem -Name $name -Value $value
    }

    return $true
}

function Invoke-ClaudeConfig {
    <#
    .SYNOPSIS
        Unified configuration handler for install/update/setup

    .PARAMETER Scope
        Configuration scope:
        - "install": Silent, apply defaults if not configured
        - "update": Check and apply defaults, no interaction
        - "setup": Interactive, offer configuration options

    .PARAMETER Force
        Force reconfiguration even if already set
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("install", "update", "setup")]
        [string]$Scope,

        [switch]$Force
    )

    Write-Host ""
    Write-Host "--- Claude Code Configuration ($Scope) ---" -ForegroundColor Cyan

    # Check existing configuration (only interactive items; env vars are idempotent)
    $hasApiConfig = [Environment]::GetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "User") -and
                    [Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")
    $hasModelConfig = [Environment]::GetEnvironmentVariable("ANTHROPIC_DEFAULT_HAIKU_MODEL", "User") -and
                      [Environment]::GetEnvironmentVariable("ANTHROPIC_DEFAULT_SONNET_MODEL", "User") -and
                      [Environment]::GetEnvironmentVariable("ANTHROPIC_DEFAULT_OPUS_MODEL", "User")

    $isFullyConfigured = $hasApiConfig -and $hasModelConfig

    # Env vars are always idempotent — apply defaults silently
    Set-DefaultConfig

    # Handle based on scope
    switch ($Scope) {
        "install" {
            if (-not $isFullyConfigured -or $Force) {
                Write-Host "[INFO] Configuration applied (env vars set to defaults)" -ForegroundColor Cyan
            } else {
                Write-Host "[OK] Configuration already present" -ForegroundColor Green
            }
        }

        "update" {
            Write-Host "[INFO] Configuration checked (env vars up to date)" -ForegroundColor Cyan
        }

        "setup" {
            Show-ConfigStatus

            if ($isFullyConfigured -and -not $Force) {
                Write-Host "`n[INFO] Configuration already present" -ForegroundColor Cyan
                $response = Read-Host "  Options: (K)eep / (R)eplace (default: K)"

                if ($response -in 'R', 'r') {
                    Write-Host "[INFO] Opening configuration editor..." -ForegroundColor Cyan
                    $success = Read-CustomConfig
                    if ($success) {
                        Write-Host "[OK] Configuration updated" -ForegroundColor Green
                        Show-ConfigStatus
                    }
                } else {
                    Write-Host "[INFO] Keeping existing configuration" -ForegroundColor Green
                }
                return
            }

            Write-Host "`n[INFO] Opening configuration editor..." -ForegroundColor Cyan
            $success = Read-CustomConfig
            if ($success) {
                Write-Host "[OK] Configuration saved" -ForegroundColor Green
                Show-ConfigStatus
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ClaudeCheck {
    <#
    .SYNOPSIS
        Display Claude Code installation and configuration status.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- Claude Code ---" -ForegroundColor Cyan

    $installed = Get-InstalledVersion
    $binFound = Test-Path $TargetExe

    if ($binFound -and $installed) {
        Write-Host "[OK] Installed: Claude Code $installed" -ForegroundColor Green
    } elseif ($binFound) {
        Write-Host "[OK] Installed (version unknown)" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Claude Code not installed" -ForegroundColor Cyan
        Write-Host "  Run 'omc install claude' to install" -ForegroundColor DarkGray
    }
    if ($binFound) {
        Write-Host "  Location: $TargetExe" -ForegroundColor DarkGray
    }

    # PATH check
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -split ';' -contains $BinDir) {
        Write-Host "  PATH:      $BinDir" -ForegroundColor DarkGray
    } else {
        Write-Host "  PATH:      not set" -ForegroundColor DarkGray
    }

    # uv check
    if (Test-Path $UvExe) {
        Write-Host "  uv:        $UvExe" -ForegroundColor DarkGray
    } else {
        Write-Host "  uv:        not installed (required for install/update)" -ForegroundColor Yellow
    }

    # Lock status
    $lock = Get-ClaudeLock
    if ($lock) {
        if ($installed -and $installed -eq $lock.ClaudeVersion) {
            Write-Host "  Lock:      $($lock.Lock) (current)" -ForegroundColor Green
        } else {
            Write-Host "  Lock:      $($lock.Lock)" -ForegroundColor Magenta
        }
        if ($lock.SdkVersion) {
            Write-Host "  SDK:       $($lock.SdkVersion)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  Lock:      none" -ForegroundColor DarkGray
    }

    Show-ConfigStatus
}

# ═══════════════════════════════════════════════════════════════════════════
# download — cache the Claude Code binary as Claude-<version>.exe
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ClaudeDownload {
    <#
    .SYNOPSIS
        Download Claude Code binary to cache via claude-agent-sdk extraction.
        Cache file named Claude-<version>.exe. Lock stores claude/sdk version pair.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }

    $lock = Get-ClaudeLock

    # If locked (with SDK version), check cache first
    if ($lock -and $lock.SdkVersion) {
        $cacheFile = Join-Path $CacheDir "Claude-$($lock.ClaudeVersion).exe"
        if ((Test-Path $cacheFile) -and $lock.SHA256) {
            $actualHash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash.ToLower()
            if ($actualHash -eq $lock.SHA256) {
                $size = (Get-Item $cacheFile).Length
                $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
                Write-Host "[OK] Claude Code $($lock.Lock) cached: $sizeStr" -ForegroundColor Green
                return
            }
            Write-Host "[WARN] Cache hash mismatch, re-extracting" -ForegroundColor Yellow
        }

        # Re-extract with locked SDK version
        $tempFile = Join-Path $CacheDir "claude-temp-$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
        try {
            Invoke-ClaudeExtract -Destination $tempFile -SdkVersion $lock.SdkVersion

            $claudeVersion = Get-ClaudeExeVersion -Path $tempFile
            if (-not $claudeVersion) {
                Write-Host "[ERROR] Could not determine version from extracted binary" -ForegroundColor Red
                return
            }

            $cacheFile = Join-Path $CacheDir "Claude-$claudeVersion.exe"
            Copy-Item -Path $tempFile -Destination $cacheFile -Force

            $hash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash.ToLower()
            Set-ClaudeLock -ClaudeVersion $claudeVersion -SdkVersion $lock.SdkVersion -SHA256 $hash
            Show-LockWrite -Version "$claudeVersion/$($lock.SdkVersion)"

            $size = (Get-Item $cacheFile).Length
            $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
            Write-Host "[OK] Cached: Claude-$claudeVersion.exe ($sizeStr)" -ForegroundColor Green
        } finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        }
        return
    }

    # No lock — query latest SDK and extract
    Write-Host "[INFO] Querying latest $SdkPackage version ..." -ForegroundColor Cyan
    $sdkVersion = Get-SdkLatestVersion
    if (-not $sdkVersion) {
        Write-Host "[ERROR] Could not determine latest SDK version" -ForegroundColor Red
        return
    }
    Write-Host "[INFO] Latest SDK: $sdkVersion" -ForegroundColor Cyan

    $tempFile = Join-Path $CacheDir "claude-temp-$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    try {
        Invoke-ClaudeExtract -Destination $tempFile -SdkVersion $sdkVersion

        $claudeVersion = Get-ClaudeExeVersion -Path $tempFile
        if (-not $claudeVersion) {
            Write-Host "[ERROR] Could not determine version from extracted binary" -ForegroundColor Red
            return
        }

        $cacheFile = Join-Path $CacheDir "Claude-$claudeVersion.exe"
        Copy-Item -Path $tempFile -Destination $cacheFile -Force

        $hash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash.ToLower()
        Set-ClaudeLock -ClaudeVersion $claudeVersion -SdkVersion $sdkVersion -SHA256 $hash
        Show-LockWrite -Version "$claudeVersion/$sdkVersion"

        $size = (Get-Item $cacheFile).Length
        $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
        Write-Host "[OK] Cached: Claude-$claudeVersion.exe ($sizeStr)" -ForegroundColor Green
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# install — download to cache, then copy to bin
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ClaudeInstall {
    <#
    .SYNOPSIS
        Install Claude Code by extracting from claude-agent-sdk to cache, then copying to bin.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # ── 1. Check existing ──
    $installedVersion = Get-InstalledVersion
    $lock = Get-ClaudeLock

    if ($installedVersion) {
        if ($lock -and $installedVersion -eq $lock.ClaudeVersion) {
            Write-Host "[OK] Claude Code $installedVersion already installed (locked: $($lock.Lock))" -ForegroundColor Green
            return
        }
        # Installed but lock mismatch — repair lock
        $hash = (Get-FileHash -Path $TargetExe -Algorithm SHA256).Hash.ToLower()
        $sdkVersion = if ($lock) { $lock.SdkVersion } else { Get-SdkLatestVersion }
        if ($sdkVersion) {
            Set-ClaudeLock -ClaudeVersion $installedVersion -SdkVersion $sdkVersion -SHA256 $hash
            Write-Host "[OK] Lock repaired: $installedVersion/$sdkVersion" -ForegroundColor Green
        }
        Write-Host "[OK] Claude Code $installedVersion already installed" -ForegroundColor Green
        return
    }

    # ── 2. Download to cache ──
    Write-Host "[INFO] Installing Claude Code ..." -ForegroundColor Cyan
    Invoke-ClaudeDownload

    # ── 3. Copy from cache to bin ──
    $lock = Get-ClaudeLock
    if (-not $lock) {
        Write-Host "[ERROR] Download failed — no lock file created" -ForegroundColor Red
        return
    }

    $cacheFile = Join-Path $CacheDir "Claude-$($lock.ClaudeVersion).exe"
    if (-not (Test-Path $cacheFile)) {
        Write-Host "[ERROR] Cache file not found: $cacheFile" -ForegroundColor Red
        return
    }

    if (-not (Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    }

    Copy-Item -Path $cacheFile -Destination $TargetExe -Force
    Add-UserPath -Dir $BinDir

    # ── 4. Verify ──
    $currentPath = $env:Path -split ';'
    if ($BinDir -notin $currentPath) {
        $env:Path = "$BinDir;$env:PATH"
    }

    $verifyVersion = Get-InstalledVersion
    if ($verifyVersion) {
        Show-InstallComplete -Tool "Claude Code" -Version "$verifyVersion/$($lock.SdkVersion)"
    } else {
        Write-Host "[OK] Claude Code installed" -ForegroundColor Green
        Write-Host "  Location: $TargetExe" -ForegroundColor DarkGray
        Write-Host "  Restart terminal if 'claude' command is not found" -ForegroundColor DarkGray
    }

    # ── 5. Configuration ──
    Invoke-ClaudeConfig -Scope "install"

    $hasCreds = [Environment]::GetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "User") -and
                 [Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")
    if (-not $hasCreds) {
        Write-Host "`n[INFO] API credentials not configured" -ForegroundColor Cyan
        Write-Host "  Run 'omc setup claude' to configure" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# update — check SDK version, extract if newer, prompt upgrade
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ClaudeUpdate {
    <#
    .SYNOPSIS
        Check for new claude-agent-sdk version and upgrade Claude Code if available.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $installedVersion = Get-InstalledVersion

    if (-not $installedVersion) {
        Invoke-ClaudeInstall
        return
    }

    $lock = Get-ClaudeLock
    Write-Host "[INFO] Claude Code: $installedVersion" -ForegroundColor Cyan
    if ($lock) {
        Write-Host "[INFO] SDK: $($lock.SdkVersion)" -ForegroundColor DarkGray
    }

    # Query latest SDK version
    Write-Host "[INFO] Querying latest $SdkPackage version ..." -ForegroundColor Cyan
    $latestSdk = Get-SdkLatestVersion
    if (-not $latestSdk) {
        Write-Host "[WARN] Could not determine latest SDK version — skipping update check" -ForegroundColor Yellow
        return
    }

    $lockedSdk = if ($lock) { $lock.SdkVersion } else { $null }

    if (-not $lockedSdk) {
        $hash = (Get-FileHash -Path $TargetExe -Algorithm SHA256).Hash.ToLower()
        Set-ClaudeLock -ClaudeVersion $installedVersion -SdkVersion $latestSdk -SHA256 $hash
        Write-Host "[OK] Already installed: Claude Code $installedVersion" -ForegroundColor Green
        Write-Host "[OK] Lock restored: $installedVersion/$latestSdk" -ForegroundColor Green
        return
    }

    if ($latestSdk -eq $lockedSdk) {
        Write-Host "[OK] Already up to date: $($lock.Lock)" -ForegroundColor Green
        return
    }

    Write-Host "[UPGRADE] SDK: $lockedSdk -> $latestSdk" -ForegroundColor Cyan

    # Extract latest
    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }

    $tempFile = Join-Path $CacheDir "claude-new-$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    try {
        Invoke-ClaudeExtract -Destination $tempFile -SdkVersion $latestSdk

        $newClaudeVersion = Get-ClaudeExeVersion -Path $tempFile
        if (-not $newClaudeVersion) {
            Write-Host "[ERROR] Could not determine version from extracted binary" -ForegroundColor Red
            return
        }

        # Cache the new version
        $newCacheFile = Join-Path $CacheDir "Claude-$newClaudeVersion.exe"
        Copy-Item -Path $tempFile -Destination $newCacheFile -Force
        $hash = (Get-FileHash -Path $newCacheFile -Algorithm SHA256).Hash.ToLower()
        Set-ClaudeLock -ClaudeVersion $newClaudeVersion -SdkVersion $latestSdk -SHA256 $hash

        if ($newClaudeVersion -eq $installedVersion) {
            Write-Host "[OK] Claude Code $newClaudeVersion unchanged (SDK updated to $latestSdk)" -ForegroundColor Green
            Write-Host "[OK] Lock updated: $newClaudeVersion/$latestSdk" -ForegroundColor Green
            return
        }

        Write-Host "[UPGRADE] Claude Code: $installedVersion -> $newClaudeVersion" -ForegroundColor Cyan
        $response = Read-Host "  Upgrade? (Y/n)"
        if ($response -and $response -ne 'Y' -and $response -ne 'y') {
            Write-Host "[INFO] Skipped (new version cached: Claude-$newClaudeVersion.exe)" -ForegroundColor DarkGray
            return
        }

        Copy-Item -Path $tempFile -Destination $TargetExe -Force
        Write-Host "[OK] Updated: $installedVersion -> $newClaudeVersion" -ForegroundColor Green
        Write-Host "[OK] Locked: $newClaudeVersion/$latestSdk" -ForegroundColor Green
    } finally {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    Invoke-ClaudeConfig -Scope "update"
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ClaudeUninstall {
    <#
    .SYNOPSIS
        Uninstall Claude Code by removing the binary from the bin directory.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $TargetExe)) {
        Write-Host "[INFO] Claude Code not installed" -ForegroundColor Cyan
        return
    }

    $version = Get-InstalledVersion
    $label = if ($version) { "Claude Code $version" } else { "Claude Code" }

    Write-Host "[INFO] Uninstalling $label ..." -ForegroundColor Cyan

    try {
        Remove-Item $TargetExe -Force -ErrorAction Stop
        Write-Host "[OK] Removed: $TargetExe" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Could not remove: $_" -ForegroundColor Yellow
    }

    Write-Host "[OK] $label uninstalled" -ForegroundColor Green

    Write-Host "[INFO] Lock and download cache preserved:" -ForegroundColor DarkGray
    Write-Host "  Lock:  $script:ClaudeLockPath" -ForegroundColor DarkGray
    Write-Host "  Cache: $CacheDir" -ForegroundColor DarkGray
    Write-Host "  Config: $script:ClaudeJsonPath" -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"     { Invoke-ClaudeCheck }
    "download"  { Invoke-ClaudeDownload }
    "install"   { Invoke-ClaudeInstall }
    "update"    { Invoke-ClaudeUpdate }
    "uninstall" { Invoke-ClaudeUninstall }
    "setup"     { Invoke-ClaudeConfig -Scope "setup" -Force:$Force }
}
