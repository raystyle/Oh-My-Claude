#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Get-PSModulePaths' {
    It 'Returns PS5 and PS7 paths' {
        $result = Get-PSModulePaths -ModuleName 'TestMod'
        $result.Count | Should -Be 2
        $result[0].Label | Should -Be 'PS5'
        $result[1].Label | Should -Be 'PS7'
    }
    It 'PS5 path contains WindowsPowerShell\Modules' {
        $result = Get-PSModulePaths -ModuleName 'TestMod'
        $result[0].Path | Should -Match 'WindowsPowerShell\\Modules\\TestMod$'
    }
    It 'PS7 path contains PowerShell\Modules' {
        $result = Get-PSModulePaths -ModuleName 'TestMod'
        $result[1].Path | Should -Match 'PowerShell\\Modules\\TestMod$'
    }
    It 'Returns hashtables with Path and Label keys' {
        $result = Get-PSModulePaths -ModuleName 'TestMod'
        foreach ($entry in $result) {
            $entry.Path | Should -Not -BeNullOrEmpty
            $entry.Label | Should -Not -BeNullOrEmpty
        }
    }
}
