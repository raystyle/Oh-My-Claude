#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

    $toolName = 'GetCfg_' + (Get-Random)
    $toolDef = New-TestToolDefinition -ToolName $toolName
    New-TestConfig -ToolName $toolName
}

Describe 'Get-ToolConfig' {
    It 'Returns empty hashtable when config file does not exist' {
        $result = Get-ToolConfig -ToolDef $toolDef
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }

    It 'Reads existing config.json correctly' {
        $setupDir = & $toolDef.GetSetupDir $global:Tool_RootDir
        $configPath = Join-Path $setupDir 'config.json'
        @{ prefix = 'D:\test'; lock = '1.5.0'; sha256 = 'ABCD1234'; asset = 'tool.zip' } |
            ConvertTo-Json -Depth 3 | Set-Content $configPath -Encoding UTF8

        $result = Get-ToolConfig -ToolDef $toolDef
        $result.prefix | Should -Be 'D:\test'
        $result.lock | Should -Be '1.5.0'
        $result.sha256 | Should -Be 'ABCD1234'
        $result.asset | Should -Be 'tool.zip'
    }

    It 'Migrates legacy cacheName field to asset' {
        $setupDir = & $toolDef.GetSetupDir $global:Tool_RootDir
        $configPath = Join-Path $setupDir 'config.json'
        @{ cacheName = 'old-tool.zip' } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8

        $result = Get-ToolConfig -ToolDef $toolDef
        $result.asset | Should -Be 'old-tool.zip'
    }

    It 'Prefers asset over cacheName when both exist' {
        $setupDir = & $toolDef.GetSetupDir $global:Tool_RootDir
        $configPath = Join-Path $setupDir 'config.json'
        @{ cacheName = 'old.zip'; asset = 'new.zip' } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8

        $result = Get-ToolConfig -ToolDef $toolDef
        $result.asset | Should -Be 'new.zip'
    }

    It 'Returns empty hashtable for invalid JSON' {
        $setupDir = & $toolDef.GetSetupDir $global:Tool_RootDir
        $configPath = Join-Path $setupDir 'config.json'
        Set-Content $configPath -Value 'INVALID' -Encoding UTF8

        $result = Get-ToolConfig -ToolDef $toolDef
        $result.Count | Should -Be 0
    }
}

AfterAll {
    Remove-TestConfig -ToolName $toolName
}
