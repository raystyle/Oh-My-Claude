#Requires -Version 5.1

# jq tool definition
return @{
    ToolName       = 'jq'
    DisplayName    = 'jq'
    ExeName        = 'jq.exe'
    Source         = 'github-release'
    Repo           = 'jqlang/jq'
    TagPrefix      = 'jq-'
    ExtractType    = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\jq" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = 'jq-(\d+\.\d+\.\d+)'
}
