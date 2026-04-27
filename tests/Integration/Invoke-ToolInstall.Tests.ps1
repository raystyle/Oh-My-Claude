#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

    Mock Get-ToolConfig { return @{} }
    Mock Set-ToolConfig {}
    Mock Add-UserPath {}
    Mock Update-Environment {}
    Mock Get-FileHash { return @{ Hash = 'FAKEHASH1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890' } }
    Mock Test-GitHubAssetAttestation { return $false }
    Mock Save-GitHubReleaseAsset {}
    Mock Invoke-DownloadWithProgress {}
    Mock Show-InstallComplete {}
    Mock Show-AlreadyInstalled {}
    Mock Show-LockWrite {}
    Mock Show-ToolAssets {}
    Mock Get-ToolCacheDir { return (Join-Path $TestDrive 'cache') }
    Mock New-Item {}
    Mock Remove-Item {}
    Mock Expand-Archive {}
    Mock Copy-Item {}
    Mock Test-Path { return $true }
}

Describe 'Invoke-ToolInstall' {
    Context 'Fresh install with explicit version' {
        It 'Downloads and extracts the tool' {
            $toolDef = New-TestToolDefinition -Override @{
                GetArchiveName = { param($v) "tool-$v.zip" }
            }
            Mock Get-ToolInstalledVersion { return $null }
            Mock Get-GitHubRelease {
                $asset = New-SyntheticAsset -Name 'tool-1.0.0.zip'
                New-SyntheticRelease -TagName 'v1.0.0' -Assets @($asset)
            }
            Mock Invoke-ToolDownload { return (Join-Path $TestDrive 'tool-1.0.0.zip') }

            Invoke-ToolInstall -ToolDef $toolDef -Version '1.0.0'
            Should -Invoke Invoke-ToolDownload -Times 1
        }
    }

    Context 'Already installed, same version' {
        It 'Skips installation and shows already installed' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolInstalledVersion { return '1.0.0' }

            Invoke-ToolInstall -ToolDef $toolDef -Version '1.0.0'
            Should -Invoke Show-AlreadyInstalled -Times 1
        }
    }

    Context 'Update mode' {
        It 'Prompts user when newer version available and user declines' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolInstalledVersion { return '1.0.0' }
            Mock Get-LatestGitHubVersion {
                [PSCustomObject]@{ Tag = 'v2.0.0'; Version = '2.0.0' }
            }
            Mock Compare-SemanticVersion { return -1 }
            Mock Read-Host { return 'n' }

            Invoke-ToolInstall -ToolDef $toolDef -Update
            Should -Invoke Read-Host -Times 1
        }
        It 'Skips when already at latest version' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolInstalledVersion { return '2.0.0' }
            Mock Get-LatestGitHubVersion {
                [PSCustomObject]@{ Tag = 'v2.0.0'; Version = '2.0.0' }
            }
            Mock Compare-SemanticVersion { return 0 }

            Invoke-ToolInstall -ToolDef $toolDef -Update
            Should -Invoke Show-AlreadyInstalled -Times 1
        }
    }
}
