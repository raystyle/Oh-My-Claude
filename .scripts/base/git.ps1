return @{
    ToolName         = 'git'
    DisplayName      = 'Git for Windows'
    ExeName          = 'git.exe'
    Source           = 'github-release'
    Repo             = 'git-for-windows/git'
    TagPrefix        = 'v'
    ExtractType      = '7z-sfx'
    CacheCategory    = 'base'
    GetSetupDir      = { param($r) "$r\.config\git" }
    GetBinDir        = { param($r) "$r\.envs\base\git\cmd" }
    GetInstallDir    = { param($r) "$r\.envs\base\git" }
    VersionCommand   = '--version'
    VersionPattern   = 'git version\s+(.+)'
    AssetNamePattern = 'PortableGit.*64-bit.*\.7z\.exe$'
    PostInstall      = {
        param($ToolDef, $Version, $RootDir)
        $installDir = & $ToolDef.GetInstallDir $RootDir
        $binDir     = & $ToolDef.GetBinDir $RootDir
        # Registry
        $regKey = "HKCU:\Software\GitForWindows"
        if (-not (Test-Path (Split-Path $regKey -Parent))) {
            New-Item -Path (Split-Path $regKey -Parent) -Force | Out-Null
        }
        New-Item -Path $regKey -Force | Out-Null
        Set-ItemProperty -Path $regKey -Name "InstallPath" -Value $installDir -Type String -Force
        $baseVer = ($Version -split '\.')[0..2] -join '.'
        Set-ItemProperty -Path $regKey -Name "Version" -Value $baseVer -Type String -Force
        Write-Host "[OK] Registry: $regKey" -ForegroundColor Green
        # PATH
        Add-UserPath -Dir $binDir
        $env:PATH = "$binDir;$env:PATH"
        # .bashrc
        $bashrcPath = "$env:USERPROFILE\.bashrc"
        $bashrcLines = @(
            "# Chinese environment for Git Bash"
            "export PYTHONIOENCODING=utf-8"
            "export LANG=zh_CN.UTF-8"
            "export LC_ALL=zh_CN.UTF-8"
        )
        $existing = if (Test-Path $bashrcPath) { Get-Content $bashrcPath -Raw } else { "" }
        if ($existing -notmatch 'PYTHONIOENCODING=utf-8') {
            Add-Content -Path $bashrcPath -Value ("`n" + ($bashrcLines -join "`n")) -Encoding UTF8
            Write-Host "[OK] .bashrc configured (Chinese env)" -ForegroundColor Green
        }
    }
    PreUninstall    = {
        param($ToolDef, $RootDir)
        $installDir = & $ToolDef.GetInstallDir $RootDir
        $binDir     = & $ToolDef.GetBinDir $RootDir
        # Directory
        if (Test-Path $installDir) {
            $removed = $false
            for ($i = 1; $i -le 3; $i++) {
                try {
                    Remove-Item $installDir -Recurse -Force -ErrorAction Stop
                    $removed = $true; break
                } catch { if ($i -lt 3) { Start-Sleep -Seconds 1 } }
            }
            if ($removed) { Write-Host "[OK] Removed $installDir" -ForegroundColor Green }
            else { Write-Host "[WARN] Files locked, cannot remove $installDir" -ForegroundColor Yellow }
        }
        # Registry
        $regKey = "HKCU:\Software\GitForWindows"
        if (Test-Path $regKey) {
            Remove-Item -Path $regKey -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Registry key removed" -ForegroundColor Green
        }
        # PATH
        Remove-UserPath -Dir $binDir
    }
}
