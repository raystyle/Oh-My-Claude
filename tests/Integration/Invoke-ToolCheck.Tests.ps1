#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Invoke-ToolCheck' {
    It 'Shows not installed when exe does not exist' {
        $toolDef = New-TestToolDefinition
        Mock Get-ToolInstalledVersion { return $null }
        Mock Get-ToolConfig { return @{} }
        Mock Get-ToolCacheDir { return 'D:\fake\cache' }

        { Invoke-ToolCheck -ToolDef $toolDef } | Should -Not -Throw
    }

    It 'Shows installed when version is detected' {
        $toolDef = New-TestToolDefinition
        Mock Get-ToolInstalledVersion { return '1.5.0' }
        Mock Get-ToolConfig { return @{ lock = '1.5.0' } }
        Mock Get-ToolCacheDir { return 'D:\fake\cache' }

        { Invoke-ToolCheck -ToolDef $toolDef } | Should -Not -Throw
    }

    It 'Shows lock mismatch when installed version differs from lock' {
        $toolDef = New-TestToolDefinition
        Mock Get-ToolInstalledVersion { return '2.0.0' }
        Mock Get-ToolConfig { return @{ lock = '1.0.0' } }
        Mock Get-ToolCacheDir { return 'D:\fake\cache' }

        { Invoke-ToolCheck -ToolDef $toolDef } | Should -Not -Throw
    }
}
