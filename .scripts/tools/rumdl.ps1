#Requires -Version 5.1

# rumdl - Markdown linter and formatter (rvben/rumdl)
return @{
    ToolName       = 'rumdl'
    DisplayName    = 'rumdl'
    ExeName        = 'rumdl.exe'
    Source         = 'github-release'
    Repo           = 'rvben/rumdl'
    TagPrefix      = 'v'
    GetArchiveName = { param($v) "rumdl-v${v}-x86_64-pc-windows-msvc.zip" }
    ExtractType    = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\rumdl" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = 'version'
    VersionPattern = '(\d+\.\d+\.\d+)'
}
