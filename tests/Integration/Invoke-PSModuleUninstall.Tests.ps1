#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Invoke-PSModuleUninstall' {
    It 'Calls Uninstall-Module for current PS version' {
        $moduleDef = @{ DisplayName = 'TestModule' }
        Mock Get-Module { return $null }
        Mock Uninstall-Module {}
        Mock Set-PSModuleLock {}

        Invoke-PSModuleUninstall -ModuleDef $moduleDef -ModuleName 'TestModule'
        Should -Invoke Uninstall-Module -Times 1
    }

    It 'Handles NoModuleFound error gracefully' {
        $moduleDef = @{ DisplayName = 'TestModule' }
        Mock Get-Module { return $null }
        Mock Uninstall-Module { throw (New-Object System.Management.Automation.ErrorRecord(
            'NoModuleFound', 'NoModuleFoundForGivenCriteria', 'ObjectNotFound', $null)) }
        Mock Set-PSModuleLock {}

        { Invoke-PSModuleUninstall -ModuleDef $moduleDef -ModuleName 'TestModule' } | Should -Not -Throw
    }

    It 'Removes lock file after uninstall' {
        $configDir = Join-Path $script:OhmyRoot '.config\TestModule'
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        Set-Content (Join-Path $configDir 'config.json') -Value '{"lock":"1.0.0"}' -Encoding UTF8

        $moduleDef = @{ DisplayName = 'TestModule' }
        Mock Get-Module { return $null }
        Mock Uninstall-Module {}
        Mock Remove-Item {}

        Invoke-PSModuleUninstall -ModuleDef $moduleDef -ModuleName 'TestModule'
        Should -Invoke Remove-Item -Times 1 -ParameterFilter {
            $Path -like '*config.json'
        }
    }
}
