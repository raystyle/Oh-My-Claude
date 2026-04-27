#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Get-PSModuleVersionInstalled' {
    It 'Returns $null when module directory does not exist' {
        Get-PSModuleVersionInstalled -ModDir (Join-Path $TestDrive 'NonExistent') -Name 'Fake' | Should -BeNullOrEmpty
    }
    It 'Returns version string for a valid module' {
        $modDir = Join-Path $TestDrive 'TestMod'
        $verDir = Join-Path $modDir '1.5.0'
        New-Item -ItemType Directory -Path $verDir -Force | Out-Null
        @"
@{
    RootModule = 'TestMod.psm1'
    ModuleVersion = '1.5.0'
    GUID = '00000000-0000-0000-0000-000000000000'
}
"@ | Set-Content (Join-Path $verDir 'TestMod.psd1') -Encoding UTF8
        New-Item -ItemType File -Path (Join-Path $verDir 'TestMod.psm1') -Force | Out-Null
        Get-PSModuleVersionInstalled -ModDir $modDir -Name 'TestMod' | Should -Be '1.5.0'
    }
    It 'Returns latest version when multiple versions exist' {
        $modDir = Join-Path $TestDrive 'MultiMod'
        foreach ($ver in @('1.0.0', '2.0.0', '1.5.0')) {
            $verDir = Join-Path $modDir $ver
            New-Item -ItemType Directory -Path $verDir -Force | Out-Null
            @"
@{
    RootModule = 'MultiMod.psm1'
    ModuleVersion = '$ver'
    GUID = '00000000-0000-0000-0000-000000000000'
}
"@ | Set-Content (Join-Path $verDir 'MultiMod.psd1') -Encoding UTF8
            New-Item -ItemType File -Path (Join-Path $verDir 'MultiMod.psm1') -Force | Out-Null
        }
        Get-PSModuleVersionInstalled -ModDir $modDir -Name 'MultiMod' | Should -Be '2.0.0'
    }
    It 'Skips directories without valid module manifests' {
        $modDir = Join-Path $TestDrive 'SkipInvalid'
        $verDir = Join-Path $modDir '1.0.0'
        New-Item -ItemType Directory -Path $verDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $modDir 'junk') -Force | Out-Null
        Get-PSModuleVersionInstalled -ModDir $modDir -Name 'SkipInvalid' | Should -BeNullOrEmpty
    }
}
