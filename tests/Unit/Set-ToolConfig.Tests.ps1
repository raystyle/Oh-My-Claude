#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

    $toolName = 'SetCfg_' + (Get-Random)
    $toolDef = New-TestToolDefinition -ToolName $toolName
}

Describe 'Set-ToolConfig' {
    Context 'Basic field operations' {
        It 'Creates config directory and file when none exists' {
            Set-ToolConfig -ToolDef $toolDef -Prefix 'D:\test'
            $setupDir = & $toolDef.GetSetupDir $global:Tool_RootDir
            Test-Path (Join-Path $setupDir 'config.json') | Should -BeTrue
        }
        It 'Sets prefix field' {
            Set-ToolConfig -ToolDef $toolDef -Prefix 'D:\myprefix'
            $cfg = Get-ToolConfig -ToolDef $toolDef
            $cfg.prefix | Should -Be 'D:\myprefix'
        }
        It 'Sets lock field' {
            Set-ToolConfig -ToolDef $toolDef -Lock '1.0.0'
            (Get-ToolConfig -ToolDef $toolDef).lock | Should -Be '1.0.0'
        }
        It 'Removes lock when empty string' {
            Set-ToolConfig -ToolDef $toolDef -Lock '1.0.0'
            Set-ToolConfig -ToolDef $toolDef -Lock ''
            $cfg = Get-ToolConfig -ToolDef $toolDef
            $cfg.lock | Should -BeNullOrEmpty
        }
        It 'Sets asset field and removes legacy cacheName' {
            $setupDir = & $toolDef.GetSetupDir $global:Tool_RootDir
            $configPath = Join-Path $setupDir 'config.json'
            @{ cacheName = 'old.zip' } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8

            Set-ToolConfig -ToolDef $toolDef -Asset 'tool.zip'
            $cfg = Get-ToolConfig -ToolDef $toolDef
            $cfg.asset | Should -Be 'tool.zip'
            $cfg.cacheName | Should -BeNullOrEmpty
        }
        It 'Sets sha256 field' {
            Set-ToolConfig -ToolDef $toolDef -Sha256 'AABB'
            (Get-ToolConfig -ToolDef $toolDef).sha256 | Should -Be 'AABB'
        }
    }

    Context 'Companion assets' {
        BeforeEach {
            # Clear config before each companion asset test
            $setupDir = & $toolDef.GetSetupDir $global:Tool_RootDir
            $configPath = Join-Path $setupDir 'config.json'
            if (Test-Path $configPath) { Remove-Item $configPath -Force }
        }
        It 'Adds a companion asset to the assets array' {
            Set-ToolConfig -ToolDef $toolDef -AssetName 'mq-lsp.exe' -AssetSha256 '1122'
            $cfg = Get-ToolConfig -ToolDef $toolDef
            $cfg.assets.Count | Should -Be 1
            $cfg.assets[0].name | Should -Be 'mq-lsp.exe'
            $cfg.assets[0].sha256 | Should -Be '1122'
        }
        It 'Updates existing companion asset hash' {
            Set-ToolConfig -ToolDef $toolDef -AssetName 'mq-lsp.exe' -AssetSha256 '1122'
            Set-ToolConfig -ToolDef $toolDef -AssetName 'mq-lsp.exe' -AssetSha256 '3344'
            $cfg = Get-ToolConfig -ToolDef $toolDef
            $cfg.assets.Count | Should -Be 1
            $cfg.assets[0].sha256 | Should -Be '3344'
        }
        It 'Adds multiple companion assets' {
            Set-ToolConfig -ToolDef $toolDef -AssetName 'a.exe' -AssetSha256 '11'
            Set-ToolConfig -ToolDef $toolDef -AssetName 'b.exe' -AssetSha256 '22'
            $cfg = Get-ToolConfig -ToolDef $toolDef
            $cfg.assets.Count | Should -Be 2
        }
        It 'Uses empty sha256 when AssetSha256 not provided' {
            Set-ToolConfig -ToolDef $toolDef -AssetName 'new.exe'
            $cfg = Get-ToolConfig -ToolDef $toolDef
            $found = $cfg.assets | Where-Object { $_.name -eq 'new.exe' }
            $found.sha256 | Should -Be ''
        }
    }

    Context 'Multiple fields in sequence' {
        It 'Preserves all fields across multiple Set calls' {
            Set-ToolConfig -ToolDef $toolDef -Prefix 'D:\test' -Lock '1.0.0' -Asset 'tool.zip' -Sha256 'HASH123'
            Set-ToolConfig -ToolDef $toolDef -Lock '2.0.0'
            $cfg = Get-ToolConfig -ToolDef $toolDef
            $cfg.prefix | Should -Be 'D:\test'
            $cfg.lock | Should -Be '2.0.0'
            $cfg.asset | Should -Be 'tool.zip'
            $cfg.sha256 | Should -Be 'HASH123'
        }
    }
}

AfterAll {
    Remove-TestConfig -ToolName $toolName
}
