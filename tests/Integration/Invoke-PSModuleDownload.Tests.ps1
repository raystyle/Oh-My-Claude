#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Invoke-PSModuleDownload' {
    It 'Skips when no version lock and no version specified' {
        $moduleDef = @{ DisplayName = 'TestModule' }
        Mock Get-PSModuleLock { return $null }

        Invoke-PSModuleDownload -ModuleDef $moduleDef -ModuleName 'TestModule'
    }

    It 'Uses locked version when available' {
        $moduleDef = @{ DisplayName = 'TestModule' }
        Mock Get-PSModuleLock { return '1.20.0' }
        Mock Get-LocalRepoPath { return (Join-Path $TestDrive 'LocalRepo') }
        Mock Save-ModuleNupkg {}

        Invoke-PSModuleDownload -ModuleDef $moduleDef -ModuleName 'TestModule'
        Should -Invoke Save-ModuleNupkg -Times 1
    }

    It 'Skips download when nupkg already cached' {
        $moduleDef = @{ DisplayName = 'TestModule' }
        Mock Get-PSModuleLock { return '1.20.0' }
        $localRepo = Join-Path $TestDrive 'LocalRepo'
        New-Item -ItemType Directory -Path $localRepo -Force | Out-Null
        Set-Content (Join-Path $localRepo 'TestModule.1.20.0.nupkg') -Value 'fake' -Encoding UTF8

        Mock Get-LocalRepoPath { return $localRepo }
        Mock Save-ModuleNupkg {}

        Invoke-PSModuleDownload -ModuleDef $moduleDef -ModuleName 'TestModule'
        Should -Invoke Save-ModuleNupkg -Times 0
    }
}
