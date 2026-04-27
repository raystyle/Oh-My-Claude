#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Import-ToolDefinition' {
    Context 'Valid tool definitions' {
        It 'Loads ripgrep definition with all required fields' {
            $def = Import-ToolDefinition -ToolName 'ripgrep'
            $def.ToolName | Should -Be 'ripgrep'
            $def.ExeName | Should -Be 'rg.exe'
            $def.Source | Should -Be 'github-release'
            $def.Repo | Should -Be 'BurntSushi/ripgrep'
            $def.ExtractType | Should -Be 'standalone'
        }
        It 'Loads mq definition with Assets array' {
            $def = Import-ToolDefinition -ToolName 'mq'
            $def.Assets.Count | Should -Be 2
            $def.Assets[0].Name | Should -Be 'mq-lsp.exe'
            $def.Assets[1].Name | Should -Be 'mq-check.exe'
        }
        It 'Fills in default DisplayName when matches ToolName' {
            $def = Import-ToolDefinition -ToolName 'just'
            $def.DisplayName | Should -Be 'just'
        }
        It 'Fills in default asset discovery fields' {
            $def = Import-ToolDefinition -ToolName 'just'
            $def.AssetPlatform | Should -Be 'windows'
            $def.AssetArch | Should -Be 'x86_64'
            $def.AssetExtPreference | Should -Contain '.zip'
        }
        It 'Loads 7z definition with CacheCategory base' {
            $def = Import-ToolDefinition -ToolName '7z'
            $def.CacheCategory | Should -Be 'base'
            $def.ExtractType | Should -Be '7z-sfx'
        }
        It 'Loads git definition with PostInstall and PreUninstall' {
            $def = Import-ToolDefinition -ToolName 'git'
            $def.PostInstall | Should -Not -BeNullOrEmpty
            $def.PreUninstall | Should -Not -BeNullOrEmpty
        }
        It 'Loads starship definition with PostUninstall' {
            $def = Import-ToolDefinition -ToolName 'starship'
            $def.PostInstall | Should -Not -BeNullOrEmpty
            $def.PostUninstall | Should -Not -BeNullOrEmpty
        }
        It 'Loads yq definition with AssetExtPreference' {
            $def = Import-ToolDefinition -ToolName 'yq'
            $def.AssetExtPreference | Should -Contain '.exe'
        }
    }

    Context 'Validation errors' {
        It 'Throws when tool definition file does not exist' {
            { Import-ToolDefinition -ToolName 'nonexistent_tool_xyz' } |
                Should -Throw '*Tool definition not found*'
        }
    }
}
