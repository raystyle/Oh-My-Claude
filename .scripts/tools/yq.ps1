#Requires -Version 5.1

# yq tool definition - dot-sourced by core.ps1 via Import-ToolDefinition
return @{
    ToolName           = 'yq'
    DisplayName        = 'yq'
    ExeName            = 'yq.exe'
    Source             = 'github-release'
    Repo               = 'mikefarah/yq'
    TagPrefix          = 'v'
    ExtractType        = 'standalone'
    GetSetupDir        = { param($r) "$r\.config\yq" }
    GetBinDir          = { param($r) "$r\.envs\tools\bin" }
    VersionCommand     = '--version'
    VersionPattern     = '(\d+\.\d+\.\d+)'
    AssetExtPreference = @('.exe', '.zip', '.tar.gz')
}
