#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Get-LatestGitHubVersion' {
    It 'Strips v prefix from tag' {
        Mock Get-GitHubRelease {
            [PSCustomObject]@{ tag_name = 'v2.5.0' }
        }
        $result = Get-LatestGitHubVersion -Repo 'owner/repo' -PrefixPattern '^v'
        $result.Tag | Should -Be 'v2.5.0'
        $result.Version | Should -Be '2.5.0'
    }
    It 'Strips custom prefix like jq-' {
        Mock Get-GitHubRelease {
            [PSCustomObject]@{ tag_name = 'jq-1.7.1' }
        }
        $result = Get-LatestGitHubVersion -Repo 'jqlang/jq' -PrefixPattern '^jq-'
        $result.Tag | Should -Be 'jq-1.7.1'
        $result.Version | Should -Be '1.7.1'
    }
    It 'Returns full tag when no prefix matches' {
        Mock Get-GitHubRelease {
            [PSCustomObject]@{ tag_name = '2024.01.01' }
        }
        $result = Get-LatestGitHubVersion -Repo 'owner/repo' -PrefixPattern '^v'
        $result.Tag | Should -Be '2024.01.01'
        $result.Version | Should -Be '2024.01.01'
    }
    It 'Returns PSCustomObject with Tag and Version properties' {
        Mock Get-GitHubRelease {
            [PSCustomObject]@{ tag_name = 'v1.0.0' }
        }
        $result = Get-LatestGitHubVersion -Repo 'owner/repo'
        $result.Tag | Should -Not -BeNullOrEmpty
        $result.Version | Should -Not -BeNullOrEmpty
    }
}
