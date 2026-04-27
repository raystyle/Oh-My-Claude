#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

    $newMod = 'SetLockNew_' + (Get-Random)
    $overMod = 'SetLockOver_' + (Get-Random)
    $encMod = 'SetLockEnc_' + (Get-Random)
}

Describe 'Set-PSModuleLock' {
    It 'Creates config directory and writes lock' {
        Set-PSModuleLock -ModuleName $newMod -Version '1.0.0'
        $cfgPath = Join-Path $script:OhmyRoot ".config\$newMod\config.json"
        Test-Path $cfgPath | Should -BeTrue
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        $cfg.lock | Should -Be '1.0.0'
    }
    It 'Overwrites existing lock' {
        Set-PSModuleLock -ModuleName $overMod -Version '1.0.0'
        Set-PSModuleLock -ModuleName $overMod -Version '2.0.0'
        $cfgPath = Join-Path $script:OhmyRoot ".config\$overMod\config.json"
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        $cfg.lock | Should -Be '2.0.0'
    }
    It 'Writes UTF8 without BOM' {
        Set-PSModuleLock -ModuleName $encMod -Version '1.0.0'
        $cfgPath = Join-Path $script:OhmyRoot ".config\$encMod\config.json"
        $bytes = [System.IO.File]::ReadAllBytes($cfgPath)
        $bytes[0] | Should -Not -Be 0xEF
    }
}

AfterAll {
    Remove-TestConfig -ToolName $newMod
    Remove-TestConfig -ToolName $overMod
    Remove-TestConfig -ToolName $encMod
}
