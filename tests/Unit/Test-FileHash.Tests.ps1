#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"


    $testFile = Join-Path $TestDrive 'testfile.zip'
    'test content for hash verification' | Set-Content $testFile -Encoding UTF8 -NoNewline
    $actualHash = (Get-FileHash -Path $testFile -Algorithm SHA256).Hash
}

Describe 'Test-FileHash' {
    Context 'Method 1: GitHub API digest field' {
        It 'Returns $true when digest matches' {
            $asset = New-SyntheticAsset -Name 'testfile.zip' -Digest "sha256:$actualHash"
            $release = New-SyntheticRelease -Assets @($asset)
            Test-FileHash -FilePath $testFile -Release $release -AssetName 'testfile.zip' |
                Should -BeTrue
        }
        It 'Throws when digest does not match' {
            $wrongHash = '0000000000000000000000000000000000000000000000000000000000000000'
            $asset = New-SyntheticAsset -Name 'testfile.zip' -Digest "sha256:$wrongHash"
            $release = New-SyntheticRelease -Assets @($asset)
            { Test-FileHash -FilePath $testFile -Release $release -AssetName 'testfile.zip' } |
                Should -Throw '*Integrity check failed*'
        }
    }

    Context 'Method 2: checksums.txt from release assets' {
        It 'Verifies via checksums.txt download' {
            Mock Invoke-RestMethod { return "$actualHash  testfile.zip" }

            $csAsset = New-SyntheticAsset -Name 'checksums.txt' `
                -BrowserDownloadUrl 'https://example.com/checksums.txt'
            $mainAsset = New-SyntheticAsset -Name 'testfile.zip'
            $release = New-SyntheticRelease -Assets @($mainAsset, $csAsset)

            Test-FileHash -FilePath $testFile -Release $release -AssetName 'testfile.zip' `
                -Repo 'owner/repo' -Tag 'v1.0.0' | Should -BeTrue
        }
        It 'Throws when checksums.txt hash does not match' {
            $wrongHash = '0000000000000000000000000000000000000000000000000000000000000000'
            Mock Invoke-RestMethod { return "${wrongHash}  testfile.zip" }

            $csAsset = New-SyntheticAsset -Name 'checksums.txt' `
                -BrowserDownloadUrl 'https://example.com/checksums.txt'
            $mainAsset = New-SyntheticAsset -Name 'testfile.zip'
            $release = New-SyntheticRelease -Assets @($mainAsset, $csAsset)

            { Test-FileHash -FilePath $testFile -Release $release -AssetName 'testfile.zip' `
                -Repo 'owner/repo' -Tag 'v1.0.0' } | Should -Throw '*Integrity check failed*'
        }
    }

    Context 'Fallback: no verification source' {
        It 'Returns $true when no digest available' {
            $asset = New-SyntheticAsset -Name 'testfile.zip'
            $release = New-SyntheticRelease -Assets @($asset)
            Test-FileHash -FilePath $testFile -Release $release -AssetName 'testfile.zip' |
                Should -BeTrue
        }
        It 'Returns $true when Release is $null' {
            Test-FileHash -FilePath $testFile -Release $null -AssetName 'testfile.zip' |
                Should -BeTrue
        }
    }
}
