#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Initialize-ToolPrefix' {
    BeforeAll {
        Mock Add-UserPath {}
    }

    Context 'No stored config' {
        It 'Saves prefix to config and returns it' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolConfig { return @{} }
            Mock Set-ToolConfig {}
            Mock Test-Path { return $true }

            $result = Initialize-ToolPrefix -ToolDef $toolDef -DefaultPrefix 'D:\ohmyclaude'
            $result | Should -Be 'D:\ohmyclaude'
            Should -Invoke Set-ToolConfig -Times 1
        }
        It 'Falls back to C: when D: not available' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolConfig { return @{} }
            Mock Set-ToolConfig {}
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq 'D:\' }

            $result = Initialize-ToolPrefix -ToolDef $toolDef -DefaultPrefix 'D:\ohmyclaude'
            $result | Should -Be 'C:\ohmyclaude'
        }
    }

    Context 'Stored config exists' {
        It 'Uses stored prefix when it matches' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolConfig { return @{ prefix = 'D:\ohmyclaude' } }
            Mock Set-ToolConfig {}

            $result = Initialize-ToolPrefix -ToolDef $toolDef -DefaultPrefix 'D:\ohmyclaude'
            $result | Should -Be 'D:\ohmyclaude'
            Should -Invoke Set-ToolConfig -Times 0
        }
        It 'Prompts when stored prefix differs and user declines' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolConfig { return @{ prefix = 'E:\old' } }
            Mock Set-ToolConfig {}
            Mock Test-Path { return $true }
            Mock Read-Host { return 'n' }

            $result = Initialize-ToolPrefix -ToolDef $toolDef -SpecifiedPrefix 'D:\new'
            $result | Should -Be 'E:\old'
        }
        It 'Updates prefix when user confirms' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolConfig { return @{ prefix = 'E:\old' } }
            Mock Set-ToolConfig {}
            Mock Test-Path { return $true }
            Mock Read-Host { return 'y' }

            $result = Initialize-ToolPrefix -ToolDef $toolDef -SpecifiedPrefix 'D:\new'
            $result | Should -Be 'D:\new'
            Should -Invoke Set-ToolConfig -Times 1
        }
    }

    Context 'Specified prefix overrides default' {
        It 'Uses SpecifiedPrefix over DefaultPrefix' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolConfig { return @{} }
            Mock Set-ToolConfig {}
            Mock Test-Path { return $true }

            $result = Initialize-ToolPrefix -ToolDef $toolDef -DefaultPrefix 'D:\default' -SpecifiedPrefix 'E:\custom'
            $result | Should -Be 'E:\custom'
        }
    }
}
