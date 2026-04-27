#Requires -Version 5.1

# gh (GitHub CLI) tool definition — managed by core.ps1 lifecycle
return @{
    ToolName       = 'gh'
    ExeName        = 'gh.exe'
    DisplayName    = 'gh'
    Source         = 'github-release'
    Repo           = 'cli/cli'
    TagPrefix   = 'v'
    ExtractType = 'standalone'
    CacheCategory  = 'base'
    GetSetupDir    = { param($r) "$r\.config\gh" }
    GetBinDir      = { param($r) "$r\.envs\base\bin" }
    VersionCommand = '--version'
    VersionPattern = 'gh version (\d+\.\d+\.\d+)'
    PostInstall    = {
        param($ToolDef, $RootDir)
        $binDir = & $ToolDef.GetBinDir $RootDir
        $ghExe  = Join-Path $binDir 'gh.exe'

        & $ghExe auth status 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host '[OK] gh auth configured' -ForegroundColor Green
        } else {
            Write-Host '[INFO] gh not authenticated -- run: gh auth login' -ForegroundColor DarkGray
        }

        if ($env:GH_TOKEN) {
            Write-Host '[OK] GH_TOKEN is set' -ForegroundColor Green
        } else {
            Write-Host '[INFO] GH_TOKEN is not set' -ForegroundColor DarkGray
            $setToken = Read-Host '  Set GH_TOKEN now? (y/N)'
            if ($setToken -eq 'y' -or $setToken -eq 'Y') {
                $token = Read-Host '  Enter GitHub token'
                if ($token) {
                    [Environment]::SetEnvironmentVariable('GH_TOKEN', $token, 'User')
                    $env:GH_TOKEN = $token
                    Write-Host '[OK] GH_TOKEN saved to user environment' -ForegroundColor Green
                }
            }
        }
    }
}
