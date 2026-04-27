#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"
}

Describe 'Get-ToolExePath' {
    It 'Joins BinDir and ExeName correctly' {
        $toolDef = New-TestToolDefinition
        $result = Get-ToolExePath -ToolDef $toolDef -RootDir 'D:\test'
        $result | Should -Be 'D:\test\.envs\tools\bin\testtool.exe'
    }
    It 'Works with custom GetBinDir scriptblock' {
        $toolDef = New-TestToolDefinition -Override @{
            GetBinDir = { param($r) "$r\.envs\base\bin" }
            ExeName   = '7z.exe'
        }
        $result = Get-ToolExePath -ToolDef $toolDef -RootDir 'D:\test'
        $result | Should -Be 'D:\test\.envs\base\bin\7z.exe'
    }
    It 'Works with duckdb-style GetBinDir' {
        $toolDef = New-TestToolDefinition -Override @{
            GetBinDir = { param($r) "$r\.envs\tools\duckdb" }
            ExeName   = 'duckdb.exe'
        }
        $result = Get-ToolExePath -ToolDef $toolDef -RootDir 'D:\test'
        $result | Should -Be 'D:\test\.envs\tools\duckdb\duckdb.exe'
    }
}
