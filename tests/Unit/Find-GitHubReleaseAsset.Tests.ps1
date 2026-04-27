#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Find-GitHubReleaseAsset' {
    BeforeAll {
        $assets = @(
            New-SyntheticAsset -Name 'tool-v1.0.0-x86_64-pc-windows-msvc.zip'
            New-SyntheticAsset -Name 'tool-v1.0.0-aarch64-pc-windows-msvc.zip'
            New-SyntheticAsset -Name 'tool-v1.0.0-x86_64-linux-gnu.tar.gz'
            New-SyntheticAsset -Name 'tool-v1.0.0-x86_64-apple-darwin.tar.gz'
            New-SyntheticAsset -Name 'tool-v1.0.0-windows-x86_64.zip'
            New-SyntheticAsset -Name 'tool-v1.0.0-x86_64-pc-windows-msvc.exe'
        )
        $release = New-SyntheticRelease -Assets $assets
    }

    Context 'Platform filtering' {
        It 'Selects windows assets over linux and macos' {
            $result = Find-GitHubReleaseAsset -Release $release -Platform 'windows' -Arch 'x86_64'
            $result.name | Should -Match 'windows|msvc'
        }
        It 'Selects linux assets' {
            $result = Find-GitHubReleaseAsset -Release $release -Platform 'linux' -Arch 'x86_64'
            $result.name | Should -Match 'linux|gnu'
        }
        It 'Selects macos assets' {
            $result = Find-GitHubReleaseAsset -Release $release -Platform 'macos' -Arch 'x86_64'
            $result.name | Should -Match 'darwin|apple'
        }
    }

    Context 'Architecture filtering' {
        It 'Selects x86_64 over aarch64 on windows' {
            $result = Find-GitHubReleaseAsset -Release $release -Platform 'windows' -Arch 'x86_64'
            $result.name | Should -Not -Match 'aarch64'
        }
        It 'Selects aarch64 when requested' {
            $result = Find-GitHubReleaseAsset -Release $release -Platform 'windows' -Arch 'aarch64'
            $result.name | Should -Match 'aarch64'
        }
    }

    Context 'Extension preference' {
        It 'Prefers .zip over .tar.gz when both match' {
            $result = Find-GitHubReleaseAsset -Release $release -Platform 'windows' -Arch 'x86_64' `
                -ExtPreference @('.zip', '.tar.gz')
            $result.name | Should -Match '\.zip$'
        }
        It 'Prefers .exe when listed first' {
            $result = Find-GitHubReleaseAsset -Release $release -Platform 'windows' -Arch 'x86_64' `
                -ExtPreference @('.exe', '.zip')
            $result.name | Should -Match '\.exe$'
        }
    }

    Context 'NamePattern filtering' {
        It 'Applies NamePattern after platform/arch filtering' {
            $result = Find-GitHubReleaseAsset -Release $release -Platform 'windows' -Arch 'x86_64' `
                -NamePattern '^tool-v1\.0\.0-x86_64-pc-windows-msvc\.zip$'
            $result.name | Should -Be 'tool-v1.0.0-x86_64-pc-windows-msvc.zip'
        }
        It 'Filters to specific pattern among multiple windows assets' {
            $result = Find-GitHubReleaseAsset -Release $release -Platform 'windows' -Arch 'x86_64' `
                -NamePattern 'windows-x86_64\.zip$'
            $result.name | Should -Be 'tool-v1.0.0-windows-x86_64.zip'
        }
    }

    Context 'Error cases' {
        It 'Throws when release has no assets' {
            $emptyRelease = New-SyntheticRelease
            { Find-GitHubReleaseAsset -Release $emptyRelease } | Should -Throw '*no assets*'
        }
        It 'Throws when no asset matches platform/arch' {
            { Find-GitHubReleaseAsset -Release $release -Platform 'linux' -Arch 'aarch64' } |
                Should -Throw '*No asset matching*'
        }
        It 'Throws when no asset matches extension preference' {
            { Find-GitHubReleaseAsset -Release $release -Platform 'windows' -Arch 'x86_64' `
                -ExtPreference @('.deb', '.rpm') } | Should -Throw '*No asset matching*'
        }
    }
}
