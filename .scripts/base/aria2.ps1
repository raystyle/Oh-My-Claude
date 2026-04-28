#Requires -Version 5.1

# aria2 tool definition — managed by core.ps1 lifecycle
return @{
    ToolName       = 'aria2'
    ExeName        = 'aria2c.exe'
    DisplayName    = 'aria2'
    Source         = 'github-release'
    Repo           = 'aria2/aria2'
    TagPrefix      = 'release-'
    ExtractType    = 'standalone'
    CacheCategory  = 'base'
    GetSetupDir    = { param($r) "$r\.config\aria2" }
    GetBinDir      = { param($r) "$r\.envs\base\bin" }
    VersionCommand = '--version'
    VersionPattern = 'aria2 version (\d+\.\d+\.\d+)'
    GetArchiveName = { param($v) "aria2-$v-win-64bit-build1.zip" }
}
