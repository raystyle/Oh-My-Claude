#Requires -Version 5.1

# mq tool definition - three binaries from one repo
return @{
    ToolName        = 'mq'
    DisplayName     = 'mq'
    ExeName         = 'mq.exe'
    Source          = 'github-release'
    Repo            = 'harehare/mq'
    TagPrefix       = 'v'
    ExtractType     = 'standalone'
    GetSetupDir     = { param($r) "$r\.config\mq" }
    GetBinDir       = { param($r) "$r\.envs\tools\bin" }
    VersionCommand  = '--version'
    VersionPattern  = '(\d+\.\d+\.\d+)'
    AssetNamePattern = '^mq-x86_64-pc-windows-msvc\.exe$'
    Assets          = @(
        @{ Name = 'mq-lsp.exe';   Pattern = 'mq-lsp-x86_64-pc-windows-msvc\.exe$' }
        @{ Name = 'mq-check.exe'; Pattern = 'mq-check-x86_64-pc-windows-msvc\.exe$' }
    )
}
