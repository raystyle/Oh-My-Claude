#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

    $newTool = 'SetVerLock_new_' + (Get-Random)
    $testTool = 'SetVerLock_test_' + (Get-Random)
}

Describe 'Set-VersionLock' {
    Context 'Setting a new lock on fresh config' {
        It 'Creates config directory if missing' {
            Set-VersionLock -ToolName $newTool -Version '1.0.0'
            $cfgPath = Join-Path $script:OhmyRoot ".config\$newTool\config.json"
            Test-Path $cfgPath | Should -BeTrue
        }
        It 'Writes the lock field correctly' {
            Set-VersionLock -ToolName $newTool -Version '1.0.0'
            $cfg = Get-Content (Join-Path $script:OhmyRoot ".config\$newTool\config.json") -Raw | ConvertFrom-Json
            $cfg.lock | Should -Be '1.0.0'
        }
    }

    Context 'Updating an existing lock' {
        BeforeEach {
            New-TestConfig -ToolName $testTool
            Set-VersionLock -ToolName $testTool -Version '1.0.0'
        }
        It 'Overwrites the previous lock value' {
            Set-VersionLock -ToolName $testTool -Version '2.0.0'
            $cfg = Get-Content (Join-Path $script:OhmyRoot ".config\$testTool\config.json") -Raw | ConvertFrom-Json
            $cfg.lock | Should -Be '2.0.0'
        }
        It 'Preserves other config fields like prefix' {
            $cfgPath = Join-Path $script:OhmyRoot ".config\$testTool\config.json"
            @{ prefix = 'D:\ohmyclaude'; lock = '1.0.0' } | ConvertTo-Json -Depth 1 | Set-Content $cfgPath -Encoding UTF8
            Set-VersionLock -ToolName $testTool -Version '2.0.0'
            $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
            $cfg.prefix | Should -Be 'D:\ohmyclaude'
            $cfg.lock | Should -Be '2.0.0'
        }
    }

    Context 'Removing a lock' {
        BeforeEach {
            New-TestConfig -ToolName $testTool
            Set-VersionLock -ToolName $testTool -Version '1.0.0'
        }
        It 'Removes lock when empty string is passed' {
            Set-VersionLock -ToolName $testTool -Version ''
            $cfg = Get-Content (Join-Path $script:OhmyRoot ".config\$testTool\config.json") -Raw | ConvertFrom-Json
            $cfg.lock | Should -BeNullOrEmpty
        }
    }
}

AfterAll {
    Remove-TestConfig -ToolName $newTool
    Remove-TestConfig -ToolName $testTool
}
