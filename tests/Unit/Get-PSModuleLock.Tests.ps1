#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

    $testModule = 'TestLockMod_' + (Get-Random)
}

Describe 'Get-PSModuleLock' {
    It 'Returns $null when config does not exist' {
        Get-PSModuleLock -ModuleName 'FakeModule' | Should -BeNullOrEmpty
    }
    It 'Returns locked version when config exists' {
        New-TestConfig -ToolName $testModule
        $dir = Join-Path $script:OhmyRoot ".config\$testModule"
        @{ lock = '1.21.0' } | ConvertTo-Json | Set-Content (Join-Path $dir 'config.json') -Encoding UTF8
        Get-PSModuleLock -ModuleName $testModule | Should -Be '1.21.0'
    }
    It 'Returns $null when lock field is missing' {
        $noLockModule = 'NoLockMod_' + (Get-Random)
        New-TestConfig -ToolName $noLockModule
        $dir = Join-Path $script:OhmyRoot ".config\$noLockModule"
        @{ prefix = 'test' } | ConvertTo-Json | Set-Content (Join-Path $dir 'config.json') -Encoding UTF8
        Get-PSModuleLock -ModuleName $noLockModule | Should -BeNullOrEmpty
        Remove-TestConfig -ToolName $noLockModule
    }
}

AfterAll {
    Remove-TestConfig -ToolName $testModule
}
