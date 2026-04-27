# 数据驱动工具 — core.ps1 生命周期

适用于：`$ToolDefs`（ripgrep、jq、yq、fzf、just、starship、mq、markdown-oxide）和 `$BaseTools`（7z、git、gh）。

## 工作原理

工具脚本（`.scripts/tools/<name>.ps1` 或 `.scripts/base/<name>.ps1`）返回一个 hashtable。`core.ps1` 通过 `Import-ToolDefinition` 导入并接管完整生命周期：check、install、update、uninstall、download、lock。

`omc.ps1` 通过 `Invoke-BaseTool`（`$BaseTools`）或 `Invoke-ToolCommand`（`$ToolDefs`）分发。

## 运行流程

```
omc install <tool>
  └─ Invoke-ToolInstall (core.ps1)
       ├─ 读取配置 → Get-ToolConfig
       ├─ 检测已安装版本 → Get-ToolInstalledVersion (运行 exe --version)
       ├─ 已安装 == 目标版本 && !Force → 跳过（修复缺失的 lock）
       ├─ 下载 → Invoke-ToolDownload
       │    ├─ 解析归档名 + 下载 URL
       │    ├─ 下载附属 assets（在主文件缓存检查之前）
       │    ├─ 缓存命中？验证 SHA256 → 跳过下载
       │    ├─ Save-GitHubReleaseAsset (gh CLI) → Invoke-WebRequest (直连 URL)
       │    ├─ 校验：Test-GitHubAssetAttestation → Test-FileHash
       │    └─ Set-ToolConfig (lock, asset, sha256)
       ├─ 按 ExtractType 解压 (standalone/zip/tar/none/7z-sfx)
       ├─ Set-ToolConfig (lock)
       ├─ 复制 companion assets 到 bin
       ├─ PostInstall 钩子
       └─ 验证版本
```

## 最小模板

```powershell
#Requires -Version 5.1

return @{
    ToolName       = 'mytool'
    DisplayName    = 'MyTool'
    ExeName        = 'mytool.exe'
    Source         = 'github-release'
    Repo           = 'owner/mytool'
    TagPrefix      = 'v'                    # 可选，默认 ''（无前缀）
    GetArchiveName = { param($v) "mytool-$v-x86_64-windows.zip" }
    ExtractType    = 'standalone'           # standalone | zip | tar | none | 7z-sfx
    GetSetupDir    = { param($r) "$r\.config\mytool" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = '(\d+\.\d+\.\d+)'
}
```

### 必填字段

| 字段 | 说明 |
|------|------|
| `ToolName` | 唯一标识符，与文件名一致 |
| `ExeName` | bin 目录中的可执行文件名 |
| `Source` | `'github-release'` 或 `'direct-download'` |
| `ExtractType` | `standalone`、`zip`、`tar`、`none`、`7z-sfx` |
| `GetSetupDir` | `param($r)` → 配置目录（`.config\<tool>`） |
| `GetBinDir` | `param($r)` → 二进制目录 |

### 可选字段

| 字段 | 说明 |
|------|------|
| `DisplayName` | 显示名称（默认取 `ToolName`） |
| `Repo` | GitHub `owner/repo`（`github-release` 时必填） |
| `TagPrefix` | 版本前缀，如 `'v'` |
| `GetArchiveName` | `param($v)` → 归档文件名。省略则使用 API 自动发现 |
| `AssetNamePattern` | API 资产发现的正则过滤 |
| `AssetPlatform` | 平台过滤（默认 `'windows'`） |
| `AssetArch` | 架构过滤（默认 `'x86_64'`） |
| `CacheCategory` | `'base'` 表示基础层工具，默认 `'tools'` |
| `GetInstallDir` | 完整安装目录（非 bin 类工具） |
| `VersionCommand` | 获取版本字符串的 CLI 参数 |
| `VersionPattern` | 从输出中提取版本的正则 |
| `PostInstall` | `{ param($ToolDef, $Version, $RootDir) }` |
| `PreUninstall` | `{ param($ToolDef, $RootDir) }` |
| `PreDownload` | `{ param($ToolDef, $Version) }` |
| `PostDownload` | `{ param($ToolDef, $Version, $FilePath) }` |
| `Assets` | `@(@{ Name = 'companion.exe'; Pattern = '.*companion.*' })` |

## API 资产发现（无 GetArchiveName）

省略 `GetArchiveName` 时，`core.ps1` 查询 GitHub API 并按平台/架构/扩展名过滤：

```powershell
return @{
    ToolName       = 'mytool'
    ExeName        = 'mytool.exe'
    Source         = 'github-release'
    Repo           = 'owner/mytool'
    ExtractType    = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\mytool" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    AssetPlatform  = 'windows'
    AssetArch      = 'x86_64'
    AssetExtPreference = @('.zip', '.tar.gz', '.exe')
    # AssetNamePattern = '.*x86_64.*'  # 可选正则过滤
    VersionCommand = '--version'
    VersionPattern = '(\d+\.\d+\.\d+)'
}
```

## 附属 Assets

工具随附多个二进制文件（如 mq-lsp.exe、mq-check.exe 伴随 mq.exe）：

```powershell
return @{
    # ... 标准字段 ...
    Assets = @(
        @{ Name = 'mq-lsp.exe'; Pattern = '.*mq-lsp.*' }
        @{ Name = 'mq-check.exe'; Pattern = '.*mq-check.*' }
    )
}
```

生命周期引擎处理流程：
1. 在主文件缓存检查**之前**下载附属 assets（同一 release）
2. SHA256 存入 `config.json` 的 `assets[]` 数组
3. 主文件解压后从缓存复制到 bin

## Lock 与配置

配置文件：`.config\<ToolName>\config.json`，由 `core.ps1` 自动管理。

```json
{
    "prefix": "D:\\ohmyclaude",
    "lock": "15.1.0",
    "sha256": "124510B94B6BAA3380D051FDF4650EAA80A302C876D611E9DBA0B2E18D87493A",
    "asset": "ripgrep-15.1.0-x86_64-pc-windows-msvc.zip",
    "assets": [
        { "name": "mq-lsp.exe", "sha256": "63167DF9..." },
        { "name": "mq-check.exe", "sha256": "8F36EC73..." }
    ]
}
```

Lock 由 `Invoke-ToolDownload` 和 `Invoke-ToolInstall` 写入。**不需要手动管理 lock。** 生命周期引擎自动处理：
- 下载时自动写入 lock（version、asset name、SHA256）
- 安装时自动写入 lock
- 跳过路径自动修复 lock（install 和 update 路径都检查 `-not $lockVer`）
- update 跳过路径自动填充缓存（如果归档缺失）

## 注意事项

### AssetNamePattern 不能跳过架构过滤

`Find-GitHubReleaseAsset` 设置 `NamePattern` 后尝试提前返回（`-Select-Object -First 1`），跳过了 platform/arch 过滤。GitHub API 返回的 assets 顺序不确定（如 aarch64 排在 x86_64 前面）。**不要用 `AssetNamePattern` 作为精确匹配的快捷方式** — 让所有 assets 先经过 platform + arch 过滤。

### Save-GitHubReleaseAsset 不能用于安装 gh 自身

`Save-GitHubReleaseAsset` 首行检查 `Test-GhAuthenticated`，gh 不存在时直接 throw。**`$BaseTools` 中 gh 依赖的工具**必须在 `Invoke-ToolDownload` 中实现回退下载路径。

### 缓存命中不能跳过附属 Assets

`Invoke-ToolDownload` 将 companion asset 下载移到主文件缓存检查**之前**。如果放在后面，主文件缓存命中时 companion assets 永远不会被下载。

### ExtractType Standalone 无匹配文件

`Expand-Archive` 解压后如果没有文件匹配 `ExeName`，`core.ps1` 会将归档中**所有**文件复制到 bin（输出 `[WARN] No matching files`）。应设置 `KeepFiles` 或确保归档结构匹配 `ExeName`。

### 7z-sfx 三级解压

依次尝试：7z CLI → `Start-Process`（无 admin）→ `Start-Process -Verb RunAs`（admin UAC）。

### install 路径：无 lock + 未安装 → 获取最新版

未指定版本、非 update 模式、工具未安装时：
1. 检查 lock → 使用锁定版本
2. 无 lock → 从 GitHub API 获取最新版
3. API 不可用 → 报错退出

### update 路径：已安装 + lock 匹配最新 → 填充缓存

即使已处于最新版，`Invoke-ToolInstall -Update` 也会检查缓存归档是否存在且有效。缺失时下载以填充缓存。这确保 `omc download <tool>` 在 update 后可用。
