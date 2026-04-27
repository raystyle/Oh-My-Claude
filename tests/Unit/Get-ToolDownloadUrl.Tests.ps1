#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Get-ToolDownloadUrl' {
    Context 'github-release source' {
        It 'Constructs URL from GetArchiveName with TagPrefix' {
            $toolDef = New-TestToolDefinition -Override @{
                GetArchiveName = { param($v) "tool-$v-windows-x64.zip" }
            }
            $url = Get-ToolDownloadUrl -ToolDef $toolDef -Version '1.0.0'
            $url | Should -Be 'https://github.com/testowner/testrepo/releases/download/v1.0.0/tool-1.0.0-windows-x64.zip'
        }
        It 'Uses explicit Tag over TagPrefix' {
            $toolDef = New-TestToolDefinition -Override @{
                GetArchiveName = { param($v) "tool-$v.zip" }
            }
            $url = Get-ToolDownloadUrl -ToolDef $toolDef -Version '1.0.0' -Tag 'custom-tag'
            $url | Should -BeLike '*custom-tag*'
            $url | Should -BeLike '*tool-1.0.0.zip'
        }
        It 'Uses TagPrefix when no explicit Tag' {
            $toolDef = New-TestToolDefinition -Override @{
                TagPrefix = 'release-'
                GetArchiveName = { param($v) "tool-$v.zip" }
            }
            $url = Get-ToolDownloadUrl -ToolDef $toolDef -Version '1.0.0'
            $url | Should -BeLike '*release-1.0.0*'
        }
        It 'Uses Version directly when no TagPrefix' {
            $toolDef = New-TestToolDefinition -Override @{
                TagPrefix = $null
                GetArchiveName = { param($v) "tool-$v.zip" }
            }
            $url = Get-ToolDownloadUrl -ToolDef $toolDef -Version '1.0.0'
            $url | Should -Be 'https://github.com/testowner/testrepo/releases/download/1.0.0/tool-1.0.0.zip'
        }
    }
    Context 'direct-download source' {
        It 'Throws when DownloadUrlTemplate is missing' {
            $toolDef = New-TestToolDefinition -Override @{
                Source = 'direct-download'
                GetArchiveName = { param($v) 'tool.zip' }
            }
            { Get-ToolDownloadUrl -ToolDef $toolDef -Version '1.0.0' } |
                Should -Throw '*DownloadUrlTemplate*'
        }
        It 'Constructs URL from DownloadUrlTemplate' {
            $toolDef = New-TestToolDefinition -Override @{
                Source = 'direct-download'
                GetArchiveName = { param($v) "tool-$v.zip" }
                DownloadUrlTemplate = 'https://example.com/downloads/{0}/{1}'
            }
            $url = Get-ToolDownloadUrl -ToolDef $toolDef -Version '1.0.0'
            $url | Should -Be 'https://example.com/downloads/1.0.0/tool-1.0.0.zip'
        }
    }
    Context 'Unknown source' {
        It 'Throws for unknown source type' {
            $toolDef = New-TestToolDefinition -Override @{
                Source = 'unknown'
                GetArchiveName = { param($v) 'tool.zip' }
            }
            { Get-ToolDownloadUrl -ToolDef $toolDef -Version '1.0.0' } |
                Should -Throw '*Unknown source*'
        }
    }
}
