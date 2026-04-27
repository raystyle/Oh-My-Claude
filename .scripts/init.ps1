#Requires -Version 5.1

<#
.SYNOPSIS
    First-run bootstrap for ohmyclaude.
.DESCRIPTION
    Unlocks PS execution policy, unblocks downloaded files, invokes omc init,
    and reloads the user PATH into the current shell session.
#>

$Root = Split-Path $PSScriptRoot -Parent

try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop } catch { }
Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue | Unblock-File

& "$Root\omc.exe" init

# Reload user PATH into current shell
$baseBin  = Join-Path $Root '.envs\base\bin'
$base7z   = Join-Path $Root '.envs\base\7z'
$toolsBin = Join-Path $Root '.envs\tools\bin'
$devBin   = Join-Path $Root '.envs\dev\bin'
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
foreach ($dir in @($Root, $baseBin, $base7z, $toolsBin, $devBin)) {
    if ($userPath -notlike "*$dir*") {
        $env:Path = "$dir;$env:Path"
    }
}
