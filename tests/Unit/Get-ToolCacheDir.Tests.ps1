#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"
}

Describe 'Get-ToolCacheDir' {
    It 'Returns .cache/tools/<ToolName> for standard tools' {
        $toolDef = New-TestToolDefinition
        $result = Get-ToolCacheDir -ToolDef $toolDef -RootDir 'D:\test'
        $result | Should -Be 'D:\test\.cache\tools\testtool'
    }
    It 'Returns .cache/base/<ToolName> for CacheCategory=base tools' {
        $toolDef = New-TestToolDefinition -Override @{ CacheCategory = 'base' }
        $result = Get-ToolCacheDir -ToolDef $toolDef -RootDir 'D:\test'
        $result | Should -Be 'D:\test\.cache\base\testtool'
    }
    It 'Uses ToolName from definition' {
        $toolDef = New-TestToolDefinition -ToolName 'mycustomtool'
        $result = Get-ToolCacheDir -ToolDef $toolDef -RootDir 'D:\test'
        $result | Should -Be 'D:\test\.cache\tools\mycustomtool'
    }
}
