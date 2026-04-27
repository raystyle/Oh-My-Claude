# 独立脚本工具 — 自管理生命周期

适用于：`$BaseScripts`（uv、claude）、`$ToolScripts`（duckdb）、`$DevTools`（node、rust、font、pwsh、jupyter、vsbuild）、`$PsModules`（psanalyzer、psfzf）。

与数据驱动工具不同，独立脚本自行定义 `param()`、命令分发（`switch $Command`）、lock 管理和下载逻辑。由 `omc.ps1` 通过 dot-source 调用。

## 选择分类

| 分类 | 注册位置 | 分发方式 | 安装到 |
|------|----------|----------|--------|
| `$BaseScripts` | `$BaseScripts` 数组 | Dot-source + 运行函数 | `.envs\base\bin` |
| `$ToolScripts` | `$ToolScripts` 数组 | `Invoke-ToolCommand` | `.envs\tools\bin`（或自定义） |
| `$DevTools` | `$DevTools` 哈希表 | `Invoke-DevTool` | `.envs\dev\bin` 或自定义 |
| `$PsModules` | `$PsModules` 哈希表 | `Invoke-DevTool`（经由 psanalyzer.ps1） | PS module 路径 |

## 运行流程（通用模式）

```
omc install <tool>
  └─ .scripts/<category>/<name>.ps1 -Command install
       ├─ Dot-source helpers.ps1
       ├─ 检测已安装版本
       ├─ 确定目标版本（lock → latest）
       ├─ 幂等检查：已安装 == 目标 && !Force → 修复 lock，return
       ├─ 提前写入 lock
       ├─ 下载（带回退）
       │    ├─ Save-GitHubReleaseAsset (gh CLI)
       │    └─ Invoke-WebRequest / Invoke-DownloadWithProgress (直连 URL)
       ├─ SHA256 校验
       ├─ 解压 / 安装
       ├─ 再次写入 lock
       └─ 验证
```

## 最小模板

```powershell
#Requires -Version 5.1

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

$ConfigFile = Join-Path $script:OhmyRoot ".config\mytool\config.json"
$NoBom      = New-Object System.Text.UTF8Encoding $false

# ── Lock 辅助函数 ──

function Get-MyToolLock {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if (-not (Test-Path $ConfigFile)) { return }
    try {
        $cfg = Get-Content $ConfigFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($cfg.lock) { return $cfg.lock }
    } catch {}
}

function Set-MyToolLock {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )
    $dir = Split-Path $ConfigFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = @{ lock = $Version } | ConvertTo-Json
    [System.IO.File]::WriteAllText($ConfigFile, $json.Trim(), $NoBom)
}

# ── 版本检测 ──

function Get-InstalledMyToolVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $exe = "$script:OhmyRoot\.envs\tools\bin\mytool.exe"
    if (-not (Test-Path $exe)) { return }
    try {
        $raw = & $exe --version 2>$null | Out-String
        if ($raw -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    } catch {}
}

# ── check ──

function Invoke-MyToolCheck {
    [CmdletBinding()]
    [OutputType([void])]
    param()
    Write-Host ""
    Write-Host "--- MyTool ---" -ForegroundColor Cyan
    $installed = Get-InstalledMyToolVersion
    if ($installed) {
        Write-Host "[OK] Installed: MyTool $installed" -ForegroundColor Green
    } else {
        Write-Host "[INFO] MyTool not installed" -ForegroundColor Cyan
    }
    $lock = Get-MyToolLock
    if ($lock) {
        if ($installed -and $installed -eq $lock) {
            Write-Host "[OK] Locked: $lock (current)" -ForegroundColor Green
        } else {
            Write-Host "[LOCK] Locked: $lock" -ForegroundColor Magenta
        }
    } else {
        Write-Host "[INFO] No version lock" -ForegroundColor DarkGray
    }
}

# ── download ──

function Invoke-MyToolDownload {
    [CmdletBinding()]
    [OutputType([void)]
    param()
    $lockVer = Get-MyToolLock
    $ver = if ($lockVer) { $lockVer } else { <获取最新版> }
    # 下载到 .cache/tools/mytool/ 并做 SHA256 校验
    # 写入 lock：Set-MyToolLock -Version $ver
    # Show-LockWrite -Version $ver
}

# ── install ──

function Invoke-MyToolInstall {
    [CmdletBinding()]
    [OutputType([void)]
    param()
    $installed = Get-InstalledMyToolVersion
    $targetVer = <解析：lock → 最新>

    # *** 必须：跳过路径修复 lock ***
    if ($installed -and $installed -eq $targetVer -and -not $Force) {
        Show-AlreadyInstalled -Tool "MyTool" -Version $installed -Location $exePath
        if (-not (Get-MyToolLock)) { Set-MyToolLock -Version $installed }
        return
    }

    Set-MyToolLock -Version $targetVer
    Invoke-MyToolDownload
    # 解压、安装、验证
    Set-MyToolLock -Version $targetVer
    Show-LockWrite -Version $targetVer
}

# ── update ──

function Invoke-MyToolUpdate {
    [CmdletBinding()]
    [OutputType([void)]
    param()
    $installed = Get-InstalledMyToolVersion
    if (-not $installed) { Invoke-MyToolInstall; return }

    # *** 必须：版本比较前修复 lock ***
    if (-not (Get-MyToolLock)) { Set-MyToolLock -Version $installed }

    $latest = <获取最新版>
    $cmp = Compare-SemanticVersion -Current $installed -Latest $latest
    if ($cmp -ge 0) {
        Show-AlreadyInstalled -Tool "MyTool" -Version $installed
        return
    }
    # 提示升级，然后 Invoke-MyToolInstall
}

# ── uninstall ──

function Invoke-MyToolUninstall {
    [CmdletBinding()]
    [OutputType([void)]
    param()
    # 前置检查：是否已安装
    if (-not (Test-Path $exePath) -and -not (Test-Path $ConfigFile)) {
        Write-Host '[INFO] MyTool not installed, nothing to uninstall' -ForegroundColor Cyan
        return
    }
    # 移除二进制文件
    # 不移除 lock 和缓存
    Write-Host "[OK] MyTool uninstalled" -ForegroundColor Green
}

# ── 分发 ──

switch ($Command) {
    "check"     { Invoke-MyToolCheck }
    "download"  { Invoke-MyToolDownload }
    "install"   { Invoke-MyToolInstall }
    "update"    { Invoke-MyToolUpdate }
    "uninstall" { Invoke-MyToolUninstall }
}
```

## Lock 幂等 — 强制模式

每个独立脚本**必须**在 install 和 update 两条跳过路径中修复缺失的 lock。

### install 跳过（已安装且版本匹配目标版本）

```powershell
if ($installed -and $installed -eq $targetVer -and -not $Force) {
    Show-AlreadyInstalled -Tool "MyTool" -Version $installed -Location $exePath
    if (-not (Get-MyToolLock)) { Set-MyToolLock -Version $installed }
    return
}
```

### update 跳过（已安装且为最新版本）

```powershell
if (-not (Get-MyToolLock)) { Set-MyToolLock -Version $installed }

$cmp = Compare-SemanticVersion -Current $installed -Latest $latest
if ($cmp -ge 0) {
    Show-AlreadyInstalled -Tool "MyTool" -Version $installed
    return
}
```

**为什么两条路径都要？** `install` 由 `omc install <tool>` 调用，`update` 由 `omc update <tool>` 调用。两条路径都可能遇到工具已安装但 config 被删除的情况。

## 下载策略 — 回退链

所有下载必须实现回退模式以适应中国网络环境：

```powershell
# 方式 1：gh CLI（已认证，无限速）
try {
    Save-GitHubReleaseAsset -Repo $Repo -Tag $tag -AssetPattern $archiveName -OutFile $zipFile
    $downloaded = $true
} catch {
    Write-Host "[WARN] gh download unavailable, trying direct URL..." -ForegroundColor Yellow
}

# 方式 2：直连 URL
if (-not $downloaded) {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -UseBasicParsing -ErrorAction Stop
}

# SHA256 校验
$actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
```

非 GitHub 源（镜像站）使用 `Invoke-WebRequest` 或 `Invoke-DownloadWithProgress`。

## 配置文件结构

配置文件位于 `.config\<tool>\config.json`。最小形式：

```json
{ "lock": "1.50.0" }
```

扩展形式（含缓存元数据）：

```json
{
    "prefix": "D:\\ohmyclaude",
    "lock": "1.50.0",
    "sha256": "5DC713F0...",
    "asset": "just-1.50.0-x86_64-pc-windows-msvc.zip"
}
```

**Lock 字段名：** 除 font（使用 `version`）和 claude（使用组合键 `claude_version/sdk_version`）外，所有工具统一使用 `lock`。

**uninstall 不删除 config。** Lock 和缓存保留，以便重新安装时加速。

## 特殊场景

### Base Scripts（uv、claude）

- 在 bootstrap 早期运行，此时 gh/git 可能尚未安装
- uv 通过 `uv python install` 管理 Python，claude 从 SDK 包提取二进制
- 配置结构更复杂（uv 存储 asset + sha256 + lock；claude 存储 claude_version + sdk_version + sha256）
- install 路径的 lock 修复：uv 从已安装版本 + 缓存文件重建；claude 从已安装二进制 + 查询 SDK 版本重建

### 交互式升级确认

需要用户确认升级的工具：

```powershell
Write-Host "[UPGRADE] $installed -> $latest" -ForegroundColor Cyan
$response = Read-Host "  Upgrade? (Y/n)"
if ($response -and $response -ne 'Y' -and $response -ne 'y') {
    Write-Host "[INFO] Skipped" -ForegroundColor DarkGray
    return
}
```

### 无版本比较的 update（rust）

`rust` update 始终执行 `rustup update` 然后写入 lock — 不需要 API 版本比较，因为 `rustup update` 自行处理。

### 自提升安装（pwsh、vsbuild）

MSI 按机器安装需要管理员权限。模式：

```powershell
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Start-Process $shell -Verb RunAs -ArgumentList @(...) -Wait -PassThru
    exit $proc.ExitCode
}
# 管理员路径从这里继续
```

**通过 `Start-Transcript` 捕获提升后的输出**，`-Wait` 后读取日志文件。

### 提升前先做前置检查

始终在提升权限**之前**检查是否已安装。前置检查（注册表、`Test-Path`）通常不需要管理员权限。无条件提升会导致每次运行都弹 UAC。

### 无 lock 系统（jupyter、vsbuild）

`jupyter` 由 `uv tool install` 管理（uv 处理版本）。`vsbuild` 是离线 MSI 布局（版本由布局内容决定）。两者不需要 lock 文件。

### PS Modules（psanalyzer、psfzf）

通过 `Register-PSRepository` + `Install-Module` 从本地 `.nupkg` 缓存安装。Lock 存储 module 版本字符串。Lock 修复遵循与其他独立工具相同的模式。

## 常见错误

### 用 `$null` 作为语句代替 `return`

`{ $null }` 在 `if` 块中会向管道发送 `$null` 并且**继续执行后续语句**。提前退出必须用 bare `return`。

### 函数中间的裸值不会导致提前返回

`$cfg.lock` 或 `$Matches[1]` 作为独立语句只是向管道发送值，**不会停止函数执行**。需要提前返回时用 `return $cfg.lock`。

### `return ,@($array)` 会多余包装

逗号操作符 `,@($arr)` 创建单元素数组包装。不要用 `return` 发送对象；让值作为函数最后一条语句自然落下。

### PS 5.1 `Invoke-WebRequest` 对二进制内容返回 `byte[]`

检查 `$response.Content -is [byte[]]`，手动用 `[System.Text.Encoding]::UTF8.GetString()` 解码。

### `Write-Log ""` 在 Mandatory String 参数下崩溃

PS 5.1 拒绝 `[Parameter(Mandatory)] [string]` 接收空字符串。空行用 `Write-Host ""`。

### `[string[]]` Mandatory 参数拒绝 `Get-Content` 返回的空数组

`Get-Content` 返回 `$null` 或空数组时，PS 5.1 抛出 `ParameterArgumentValidationErrorEmptyStringNotAllowed`。对可能接收空数组的集合类型参数移除 `[Mandatory]`。

### `Register-ObjectEvent` 在 PS 5.1 中不可靠

异步事件回调在另一个 runspace 中执行，变量赋值不会传播到主线程。改用同步 `HttpWebRequest.GetResponseStream` + 分块读取循环。

### PS 5.1 原生命令的 stderr 在 `Stop` 模式下触发 `NativeCommandError`

向 stderr 输出的工具（如 DuckDB 的 `-- Loading resources from ~/.duckdbrc`）会导致 `NativeCommandError` 异常。版本检测不要用子进程运行；改用 `Test-Path` + lock 文件。

### PS 5.1 `Save-Package` 不保存 `.nupkg` 文件

它保存的是展开的模块目录。用 `Invoke-WebRequest` 从 PSGallery API（`/api/v2/package/<name>/<version>`）获取实际的 `.nupkg` 文件。

### `Install-Module` 只安装到当前 PS 版本路径

PS 5.1 → `Documents\WindowsPowerShell\Modules\`，PS 7+ → `Documents\PowerShell\Modules\`。跨版本安装需要启动另一个 PS 可执行文件运行 `Uninstall-Module`。
