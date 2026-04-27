#Requires -Version 5.1

# markdown-oxide tool definition
return @{
    ToolName       = 'markdown-oxide'
    DisplayName    = 'markdown-oxide'
    ExeName        = 'markdown-oxide.exe'
    Source         = 'github-release'
    Repo           = 'Feel-ix-343/markdown-oxide'
    TagPrefix   = 'v'
    ExtractType = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\markdown-oxide" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = '(\d+\.\d+\.\d+)'
}
