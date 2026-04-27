#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"
}

Describe 'Convert-PSGalleryEntry' {
    Context 'Standard string properties' {
        It 'Converts all fields correctly' {
            $hashBytes = [byte[]]@(0xAB, 0xCD, 0xEF, 0x01, 0x23)
            $base64Hash = [Convert]::ToBase64String($hashBytes)
            $props = [PSCustomObject]@{
                NormalizedVersion    = '1.20.0'
                IsPrerelease         = 'false'
                PackageHash          = $base64Hash
                PackageHashAlgorithm = 'SHA512'
            }
            $result = Convert-PSGalleryEntry -Properties $props
            $result.Version | Should -Be '1.20.0'
            $result.IsPrerelease | Should -BeFalse
            $result.HashAlgorithm | Should -Be 'SHA512'
            $result.PackageHashHex | Should -Be 'ABCDEF0123'
        }
    }

    Context 'XmlElement properties (PS 5.1 behavior)' {
        It 'Handles XmlElement IsPrerelease' {
            $xml = [xml]'<p><IsPrerelease>true</IsPrerelease></p>'
            $result = Convert-PSGalleryEntry -Properties $xml.p
            $result.IsPrerelease | Should -BeTrue
        }
        It 'Handles XmlElement PackageHash' {
            $hashBytes = [byte[]]@(0xFF, 0x00)
            $base64Hash = [Convert]::ToBase64String($hashBytes)
            $xml = [xml]"<p><PackageHash>$base64Hash</PackageHash><PackageHashAlgorithm>SHA256</PackageHashAlgorithm></p>"
            $result = Convert-PSGalleryEntry -Properties $xml.p
            $result.PackageHashHex | Should -Be 'FF00'
            $result.HashAlgorithm | Should -Be 'SHA256'
        }
    }

    Context 'Defaults and edge cases' {
        It 'Defaults HashAlgorithm to SHA512 when empty' {
            $props = [PSCustomObject]@{
                NormalizedVersion    = '1.0.0'
                IsPrerelease         = 'false'
                PackageHash          = ''
                PackageHashAlgorithm = ''
            }
            $result = Convert-PSGalleryEntry -Properties $props
            $result.HashAlgorithm | Should -Be 'SHA512'
        }
        It 'Returns empty PackageHashHex when PackageHash is empty' {
            $props = [PSCustomObject]@{
                NormalizedVersion = '1.0.0'
                IsPrerelease      = 'false'
                PackageHash       = ''
            }
            $result = Convert-PSGalleryEntry -Properties $props
            $result.PackageHashHex | Should -Be ''
        }
        It 'Handles IsPrerelease true as string' {
            $props = [PSCustomObject]@{
                NormalizedVersion = '2.0.0-rc1'
                IsPrerelease      = 'true'
            }
            $result = Convert-PSGalleryEntry -Properties $props
            $result.IsPrerelease | Should -BeTrue
        }
    }
}
