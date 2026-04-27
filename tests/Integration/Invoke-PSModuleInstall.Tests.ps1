#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Invoke-PSModuleInstall' {
    It 'Skips when already installed in both PS versions' {
        $moduleDef = @{ DisplayName = 'TestModule' }
        Mock Get-PSModuleVersionInstalled { return '1.0.0' }
        Mock Get-PSModuleLock { return $null }
        Mock Set-PSModuleLock {}

        Invoke-PSModuleInstall -ModuleDef $moduleDef -ModuleName 'TestModule' -Command 'install'
        Should -Invoke Set-PSModuleLock -Times 1
    }

    It 'Installs module when not present' {
        $moduleDef = @{ DisplayName = 'TestModule' }
        Mock Get-PSModuleVersionInstalled { return $null }
        Mock Get-PSModuleLock { return $null }
        Mock Get-PSGalleryModuleInfo {
            [PSCustomObject]@{ Version = '1.20.0' }
        }
        Mock Register-OhMyClaudeLocalRepo { return 'OhMyClaude' }
        Mock Get-LocalRepoPath { return (Join-Path $TestDrive 'LocalRepo') }
        Mock Save-ModuleNupkg {}
        Mock Install-Module {}
        Mock Set-PSModuleLock {}
        Mock Show-LockWrite {}
        Mock Show-Installing {}
        Mock Show-InstallComplete {}
        Mock Test-PSModuleValid { return $false }
        Mock New-Item {}
        Mock Copy-Item {}

        Invoke-PSModuleInstall -ModuleDef $moduleDef -ModuleName 'TestModule' -Command 'install'
        Should -Invoke Install-Module -Times 1
    }
}
