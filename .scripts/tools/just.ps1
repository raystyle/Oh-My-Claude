#Requires -Version 5.1

# just tool definition - dot-sourced by core.ps1 via Import-ToolDefinition
return @{
    ToolName       = 'just'
    DisplayName    = 'just'
    ExeName        = 'just.exe'
    Source         = 'github-release'
    Repo           = 'casey/just'
    ExtractType = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\just" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = '(\d+\.\d+\.\d+)'
}
