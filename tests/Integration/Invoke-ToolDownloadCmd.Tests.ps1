#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Invoke-ToolDownloadCmd' {
    It 'Uses cached version when lock matches latest' {
        $toolDef = New-TestToolDefinition
        Mock Get-ToolConfig { return @{ lock = '1.0.0' } }
        Mock Get-LatestGitHubVersion {
            [PSCustomObject]@{ Tag = 'v1.0.0'; Version = '1.0.0' }
        }
        Mock Get-ToolCacheDir { return (Join-Path $TestDrive 'cache') }
        Mock Get-FileHash { return @{ Hash = 'FAKEHASH' } }
        Mock Show-ToolAssets {}
        Mock Invoke-ToolDownload {}

        $cacheDir = Get-ToolCacheDir -ToolDef $toolDef -RootDir $global:Tool_RootDir
        $cacheFile = Join-Path $cacheDir 'tool-1.0.0.zip'
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        Set-Content $cacheFile -Value 'cached' -Encoding UTF8

        Mock Get-ToolConfig {
            return @{
                lock   = '1.0.0'
                asset  = 'tool-1.0.0.zip'
                sha256 = 'FAKEHASH'
            }
        }

        Invoke-ToolDownloadCmd -ToolDef $toolDef
        Should -Invoke Invoke-ToolDownload -Times 0
    }

    It 'Downloads when no cache available' {
        $toolDef = New-TestToolDefinition
        Mock Get-ToolConfig { return @{ lock = '1.0.0' } }
        Mock Get-LatestGitHubVersion {
            [PSCustomObject]@{ Tag = 'v2.0.0'; Version = '2.0.0' }
        }
        Mock Invoke-ToolDownload {}
        Mock Show-ToolAssets {}

        Invoke-ToolDownloadCmd -ToolDef $toolDef
        Should -Invoke Invoke-ToolDownload -Times 1
    }
}
