#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Invoke-ToolLock' {
    Context 'Set lock with explicit version' {
        It 'Calls Set-VersionLock with specified version' {
            $toolDef = New-TestToolDefinition
            Mock Set-VersionLock {}

            Invoke-ToolLock -ToolDef $toolDef -Version '1.5.0'
            Should -Invoke Set-VersionLock -Times 1 -ParameterFilter { $Version -eq '1.5.0' }
        }
    }

    Context 'Remove lock' {
        It 'Calls Set-VersionLock with empty string' {
            $toolDef = New-TestToolDefinition
            Mock Set-VersionLock {}

            Invoke-ToolLock -ToolDef $toolDef -Remove
            Should -Invoke Set-VersionLock -Times 1 -ParameterFilter { $Version -eq '' }
        }
    }

    Context 'Auto-detect version' {
        It 'Uses installed version when no version specified' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolInstalledVersion { return '2.3.4' }
            Mock Set-VersionLock {}

            Invoke-ToolLock -ToolDef $toolDef
            Should -Invoke Set-VersionLock -Times 1 -ParameterFilter { $Version -eq '2.3.4' }
        }
        It 'Errors when tool not installed and no version specified' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolInstalledVersion { return $null }
            Mock Set-VersionLock {}

            { Invoke-ToolLock -ToolDef $toolDef } | Should -Throw '*not installed*'
        }
    }
}
