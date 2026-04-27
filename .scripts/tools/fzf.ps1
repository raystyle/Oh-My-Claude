#Requires -Version 5.1

# fzf tool definition
return @{
    ToolName       = 'fzf'
    DisplayName    = 'fzf'
    ExeName        = 'fzf.exe'
    Source         = 'github-release'
    Repo           = 'junegunn/fzf'
    TagPrefix   = 'v'
    ExtractType = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\fzf" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = '(\d+\.\d+\.\d+)'
}
