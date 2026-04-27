#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

    $testTool = 'UpgReq_' + (Get-Random)
}

Describe 'Test-UpgradeRequired' {
    Context 'Version lock present' {
        BeforeAll {
            New-TestConfig -ToolName $testTool
            Set-VersionLock -ToolName $testTool -Version '1.0.0'
        }
        AfterAll {
            Set-VersionLock -ToolName $testTool -Version ''
            Remove-TestConfig -ToolName $testTool
        }
        It 'Returns Required=false when tool is locked' {
            $result = Test-UpgradeRequired -Current '0.5.0' -Target '2.0.0' -ToolName $testTool
            $result.Required | Should -BeFalse
            $result.Reason | Should -Match 'locked'
        }
        It 'Returns Required=false even when target is lower' {
            $result = Test-UpgradeRequired -Current '2.0.0' -Target '0.5.0' -ToolName $testTool
            $result.Required | Should -BeFalse
            $result.Reason | Should -Match 'locked'
        }
    }

    Context 'Force mode' {
        BeforeAll {
            New-TestConfig -ToolName $testTool
            Set-VersionLock -ToolName $testTool -Version '1.0.0'
        }
        AfterAll {
            Set-VersionLock -ToolName $testTool -Version ''
            Remove-TestConfig -ToolName $testTool
        }
        It 'Returns Required=true even when locked, if Force is set' {
            $result = Test-UpgradeRequired -Current '1.0.0' -Target '2.0.0' -ToolName $testTool -Force
            $result.Required | Should -BeTrue
            $result.Reason | Should -Match 'Force'
        }
        It 'Returns Required=true with Force and no lock' {
            $result = Test-UpgradeRequired -Current '1.0.0' -Target '1.0.0' -Force
            $result.Required | Should -BeTrue
        }
    }

    Context 'No lock, semantic comparison' {
        It 'Returns Required=true when Current < Target' {
            $result = Test-UpgradeRequired -Current '1.0.0' -Target '2.0.0'
            $result.Required | Should -BeTrue
            $result.Reason | Should -Match 'Upgrade available'
        }
        It 'Returns Required=false when Current > Target' {
            $result = Test-UpgradeRequired -Current '2.0.0' -Target '1.0.0'
            $result.Required | Should -BeFalse
            $result.Reason | Should -Match 'newer'
        }
        It 'Returns Required=false when versions are equal' {
            $result = Test-UpgradeRequired -Current '1.0.0' -Target '1.0.0'
            $result.Required | Should -BeFalse
            $result.Reason | Should -Match 'up to date'
        }
    }

    Context 'Return value format validation' {
        It 'Always returns a hashtable with Required and Reason keys' {
            $result = Test-UpgradeRequired -Current '1.0.0' -Target '1.0.0'
            $result | Should -BeOfType [hashtable]
            $result.ContainsKey('Required') | Should -BeTrue
            $result.ContainsKey('Reason') | Should -BeTrue
        }
        It 'Required is always a boolean' {
            $result = Test-UpgradeRequired -Current '1.0.0' -Target '2.0.0'
            $result.Required | Should -BeOfType [bool]
        }
        It 'Reason is always a non-empty string' {
            $result = Test-UpgradeRequired -Current '1.0.0' -Target '1.0.0'
            $result.Reason | Should -Not -BeNullOrEmpty
            $result.Reason | Should -BeOfType [string]
        }
    }

    Context 'Without ToolName' {
        It 'Skips lock check and does semantic comparison' {
            $result = Test-UpgradeRequired -Current '1.0.0' -Target '2.0.0'
            $result.Required | Should -BeTrue
        }
    }
}
