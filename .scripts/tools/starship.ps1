#Requires -Version 5.1

# Starship cross-shell prompt tool definition
return @{
    ToolName       = 'starship'
    DisplayName    = 'starship'
    ExeName        = 'starship.exe'
    Source         = 'github-release'
    Repo           = 'starship/starship'
    TagPrefix   = 'v'
    ExtractType = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\starship" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = '(\d+\.\d+\.\d+)'
    PostInstall    = {
        param($RootDir)
        $profileScript = Join-Path $RootDir '.scripts\dev\profile-line.ps1'
        & $profileScript -Action add -Line 'Invoke-Expression (&starship init powershell)' `
            -Comment 'starship prompt' -BlockName 'Starship'

        $srcConfig = Join-Path $RootDir '.config\starship\starship.toml'
        $dstConfig = "$env:USERPROFILE\.config\starship.toml"
        if (Test-Path $srcConfig) {
            $dstDir = Split-Path $dstConfig -Parent
            if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item -Path $srcConfig -Destination $dstConfig -Force
            Write-Host "[OK] starship.toml copied to ~/.config/" -ForegroundColor Green
        }
    }
    PostUninstall  = {
        param($RootDir)
        $profileScript = Join-Path $RootDir '.scripts\dev\profile-line.ps1'
        & $profileScript -Action remove -BlockName 'Starship'
    }
}
