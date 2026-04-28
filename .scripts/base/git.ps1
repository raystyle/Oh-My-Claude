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
    GetArchiveName  = { param($v) $base = ($v -split '\.')[0..2] -join '.'; "PortableGit-$base-64-bit.7z.exe" }
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
        # .bashrc — idempotent with BEGIN/END markers
        $bashrcPath = "$env:USERPROFILE\.bashrc"
        $baseBin   = "$RootDir\.envs\base\bin"
        $toolsBin  = "$RootDir\.envs\tools\bin"
        $pathLine  = 'export PATH="' + $baseBin + ':' + $toolsBin + '":$PATH'
        $beginMarker = '# BEGIN ohmywinclaude: git'
        $endMarker   = '# END ohmywinclaude: git'
        $newBlock = @(
            $beginMarker
            $pathLine
            '# Chinese environment for Git Bash'
            'export PYTHONIOENCODING=utf-8'
            'export LANG=zh_CN.UTF-8'
            'export LC_ALL=zh_CN.UTF-8'
            $endMarker
        )
        $noBom = New-Object System.Text.UTF8Encoding $false
        if (Test-Path $bashrcPath) {
            $raw = [System.IO.File]::ReadAllText($bashrcPath, $noBom)
        } else {
            $raw = ''
        }
        # Remove old block (if any) and legacy Chinese env block
        $lines = $raw -split "`n"
        $cleaned = @()
        $inBlock = $false
        $skipLegacy = $false
        foreach ($line in $lines) {
            if (-not $inBlock -and $line.Trim() -eq $beginMarker) {
                $inBlock = $true; continue
            }
            if ($inBlock) {
                if ($line.Trim() -eq $endMarker) { $inBlock = $false }
                continue
            }
            if ($line.Trim() -eq '# Chinese environment for Git Bash') {
                $skipLegacy = $true; continue
            }
            if ($skipLegacy -and $line.Trim() -match '^export (PYTHONIOENCODING|LANG|LC_ALL)=') {
                continue
            }
            if ($line.Trim() -eq '# omc binary paths') {
                $skipLegacy = $true; continue
            }
            if ($skipLegacy -and $line.Trim() -match '^export PATH=') {
                continue
            }
            $skipLegacy = $false
            $cleaned += $line
        }
        # Append new block
        if ($cleaned.Count -gt 0 -and $cleaned[-1].Trim() -ne '') {
            $cleaned += ''
        }
        $cleaned += $newBlock
        [System.IO.File]::WriteAllLines($bashrcPath, [string[]]$cleaned, $noBom)
        Write-Host "[OK] .bashrc configured (PATH + Chinese env)" -ForegroundColor Green
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
        # .bashrc — remove omc block
        $bashrcPath = "$env:USERPROFILE\.bashrc"
        if (-not (Test-Path $bashrcPath)) { return }
        $noBom = New-Object System.Text.UTF8Encoding $false
        $raw = [System.IO.File]::ReadAllText($bashrcPath, $noBom)
        $beginMarker = '# BEGIN ohmywinclaude: git'
        $endMarker   = '# END ohmywinclaude: git'
        $lines = $raw -split "`n"
        $cleaned = @()
        $inBlock = $false
        foreach ($line in $lines) {
            if (-not $inBlock -and $line.Trim() -eq $beginMarker) {
                $inBlock = $true; continue
            }
            if ($inBlock) {
                if ($line.Trim() -eq $endMarker) { $inBlock = $false }
                continue
            }
            $cleaned += $line
        }
        # Remove trailing blank lines
        while ($cleaned.Count -gt 0 -and $cleaned[-1].Trim() -eq '') {
            $cleaned = $cleaned[0..($cleaned.Count - 2)]
        }
        [System.IO.File]::WriteAllLines($bashrcPath, [string[]]$cleaned, $noBom)
        Write-Host "[OK] .bashrc block removed" -ForegroundColor Green
    }
}
