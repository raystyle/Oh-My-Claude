#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Test-PSModuleValid' {
    It 'Returns $false when .psd1 does not exist' {
        Test-PSModuleValid -ModDir $TestDrive -Name 'NonExistent' | Should -BeFalse
    }
    It 'Returns $true when .psd1 exists with valid RootModule' {
        $modDir = Join-Path $TestDrive 'ValidModule'
        New-Item -ItemType Directory -Path $modDir -Force | Out-Null
        @"
@{
    RootModule = 'ValidModule.psm1'
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000000'
}
"@ | Set-Content (Join-Path $modDir 'ValidModule.psd1') -Encoding UTF8
        New-Item -ItemType File -Path (Join-Path $modDir 'ValidModule.psm1') -Force | Out-Null
        Test-PSModuleValid -ModDir $modDir -Name 'ValidModule' | Should -BeTrue
    }
    It 'Returns $false when RootModule file is missing' {
        $modDir = Join-Path $TestDrive 'BrokenModule'
        New-Item -ItemType Directory -Path $modDir -Force | Out-Null
        @"
@{
    RootModule = 'MissingFile.psm1'
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000000'
}
"@ | Set-Content (Join-Path $modDir 'BrokenModule.psd1') -Encoding UTF8
        Test-PSModuleValid -ModDir $modDir -Name 'BrokenModule' | Should -BeFalse
    }
    It 'Handles ModuleToProcess as fallback for RootModule' {
        $modDir = Join-Path $TestDrive 'LegacyModule'
        New-Item -ItemType Directory -Path $modDir -Force | Out-Null
        @"
@{
    ModuleToProcess = 'LegacyModule.psm1'
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000000'
}
"@ | Set-Content (Join-Path $modDir 'LegacyModule.psd1') -Encoding UTF8
        New-Item -ItemType File -Path (Join-Path $modDir 'LegacyModule.psm1') -Force | Out-Null
        Test-PSModuleValid -ModDir $modDir -Name 'LegacyModule' | Should -BeTrue
    }
    It 'Returns $false when .psd1 has no RootModule or ModuleToProcess' {
        $modDir = Join-Path $TestDrive 'NoRootModule'
        New-Item -ItemType Directory -Path $modDir -Force | Out-Null
        @"
@{
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000000'
}
"@ | Set-Content (Join-Path $modDir 'NoRootModule.psd1') -Encoding UTF8
        Test-PSModuleValid -ModDir $modDir -Name 'NoRootModule' | Should -BeTrue
    }
}
