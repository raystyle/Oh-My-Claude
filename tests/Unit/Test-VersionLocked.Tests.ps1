#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

    $testTool = 'VerLock_' + (Get-Random)
    $configDir = Join-Path $script:OhmyRoot ".config\$testTool"
    $configPath = Join-Path $configDir 'config.json'
}

Describe 'Test-VersionLocked' {
    Context 'Config file does not exist' {
        It 'Returns $null when config file is missing' {
            Test-VersionLocked -ToolName 'nonexistent' | Should -BeNullOrEmpty
        }
    }

    Context 'Config file exists without lock field' {
        BeforeEach {
            New-TestConfig -ToolName $testTool
            @{ prefix = 'D:\test' } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
        }
        It 'Returns $null when lock field is missing' {
            Test-VersionLocked -ToolName $testTool | Should -BeNullOrEmpty
        }
    }

    Context 'Config file exists with lock field' {
        BeforeEach {
            New-TestConfig -ToolName $testTool
            @{ prefix = 'D:\test'; lock = '1.2.3' } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
        }
        It 'Returns the locked version string' {
            Test-VersionLocked -ToolName $testTool | Should -Be '1.2.3'
        }
    }

    Context 'Config file has invalid JSON' {
        BeforeEach {
            New-TestConfig -ToolName $testTool
            Set-Content $configPath -Value 'not valid json' -Encoding UTF8
        }
        It 'Returns $null for invalid JSON' {
            Test-VersionLocked -ToolName $testTool | Should -BeNullOrEmpty
        }
    }

    Context 'Config file has lock field with empty string' {
        BeforeEach {
            New-TestConfig -ToolName $testTool
            @{ prefix = 'D:\test'; lock = '' } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
        }
        It 'Returns $null for empty lock string' {
            Test-VersionLocked -ToolName $testTool | Should -BeNullOrEmpty
        }
    }

    Context 'Config file has other fields but no lock' {
        BeforeEach {
            New-TestConfig -ToolName $testTool
            @{ prefix = 'D:\test'; sha256 = 'ABC123'; asset = 'tool.zip' } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
        }
        It 'Returns $null when lock is absent among other fields' {
            Test-VersionLocked -ToolName $testTool | Should -BeNullOrEmpty
        }
    }
}

AfterAll {
    Remove-TestConfig -ToolName $testTool
}
