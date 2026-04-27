#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

    Mock Get-ToolConfig { return @{} }
    Mock Set-ToolConfig {}
    Mock Get-FileHash { return @{ Hash = 'FAKEHASH1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890' } }
    Mock Test-GitHubAssetAttestation { return $false }
    Mock Save-GitHubReleaseAsset {}
    Mock Invoke-DownloadWithProgress {}
    Mock Show-LockWrite {}
    Mock New-Item {}
    Mock Remove-Item {}
}

Describe 'Invoke-ToolDownload' {
    Context 'Cache hit with matching hash' {
        It 'Returns cached file without re-downloading' {
            $toolDef = New-TestToolDefinition -Override @{
                GetArchiveName = { param($v) "tool-$v.zip" }
            }
            Mock Get-GitHubRelease {
                $asset = New-SyntheticAsset -Name 'tool-1.0.0.zip'
                New-SyntheticRelease -TagName 'v1.0.0' -Assets @($asset)
            }

            $cacheDir = Get-ToolCacheDir -ToolDef $toolDef -RootDir $global:Tool_RootDir
            $cacheFile = Join-Path $cacheDir 'tool-1.0.0.zip'
            if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
            Set-Content $cacheFile -Value 'cached content' -Encoding UTF8

            Mock Get-ToolConfig {
                return @{
                    asset  = 'tool-1.0.0.zip'
                    sha256 = 'FAKEHASH1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890'
                }
            }

            $result = Invoke-ToolDownload -ToolDef $toolDef -Version '1.0.0'
            $result | Should -Be $cacheFile
        }
    }

    Context 'Companion assets download' {
        It 'Downloads companion assets defined in tool definition' {
            $toolDef = New-TestToolDefinition -Override @{
                GetArchiveName = { param($v) "tool-$v.zip" }
                Assets = @(
                    @{ Name = 'companion.exe'; Pattern = 'companion-x86_64\.exe$' }
                )
            }

            $releaseAsset = New-SyntheticAsset -Name 'tool-1.0.0.zip'
            $companionAsset = New-SyntheticAsset -Name 'companion-x86_64.exe' `
                -BrowserDownloadUrl 'https://example.com/companion-x86_64.exe'
            Mock Get-GitHubRelease {
                New-SyntheticRelease -TagName 'v1.0.0' -Assets @($releaseAsset, $companionAsset)
            }

            Mock Get-ToolConfig { return @{} }

            { Invoke-ToolDownload -ToolDef $toolDef -Version '1.0.0' } | Should -Not -Throw
        }
    }
}
