#Requires -Version 5.1

# conclaude tool definition
return @{
    ToolName       = 'conclaude'
    DisplayName    = 'conclaude'
    ExeName        = 'conclaude.exe'
    Source         = 'github-release'
    Repo           = 'connerohnesorge/conclaude'
    TagPrefix      = 'v'
    ExtractType    = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\conclaude" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = '(\d+\.\d+\.\d+)'
}
