return @{
    ToolName       = '7z'
    DisplayName    = '7-Zip'
    ExeName        = '7z.exe'
    Source         = 'github-release'
    Repo           = 'ip7z/7zip'
    ExtractType    = '7z-sfx'
    CacheCategory  = 'base'
    GetSetupDir    = { param($r) "$r\.config\7z" }
    GetBinDir      = { param($r) "$r\.envs\base\7z" }
    VersionCommand = '--help'
    VersionPattern = '7-Zip\s+(\d+\.\d+)'
    GetArchiveName = { param($v) "7z$($v -replace '\.')-x64.exe" }
}
