#Requires -Version 5.1

# ripgrep tool definition
return @{
    ToolName       = 'ripgrep'
    DisplayName    = 'ripgrep'
    ExeName        = 'rg.exe'
    Source         = 'github-release'
    Repo           = 'BurntSushi/ripgrep'
    AssetNamePattern = 'msvc'
    ExtractType      = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\ripgrep" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = 'ripgrep\s+(\d+\.\d+\.\d+)'
}
