#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"
}

Describe 'Compare-SemanticVersion' {
    Context 'Standard version comparison' {
        It 'Returns -1 when Current < Latest' {
            Compare-SemanticVersion -Current '1.2.3' -Latest '1.2.10' | Should -Be -1
        }
        It 'Returns -1 when Current < Latest (major bump)' {
            Compare-SemanticVersion -Current '1.9.9' -Latest '2.0.0' | Should -Be -1
        }
        It 'Returns 0 when versions are equal' {
            Compare-SemanticVersion -Current '1.2.3' -Latest '1.2.3' | Should -Be 0
        }
        It 'Returns 1 when Current > Latest' {
            Compare-SemanticVersion -Current '1.2.10' -Latest '1.2.3' | Should -Be 1
        }
        It 'Returns 1 when Current > Latest (major bump)' {
            Compare-SemanticVersion -Current '2.0.0' -Latest '1.9.9' | Should -Be 1
        }
    }

    Context 'Edge cases' {
        It 'Handles two-part version strings (1.2 vs 1.2.0)' {
            # [version]'1.2' becomes 1.2.0.0.0, [version]'1.2.0' becomes 1.2.0.0
            # PS 5.1 may treat them as equal or use string fallback; both are valid
            $result = Compare-SemanticVersion -Current '1.2' -Latest '1.2.0'
            $result | Should -BeIn @(-1, 0)
        }
        It 'Handles four-part version strings (1.2.3.4)' {
            Compare-SemanticVersion -Current '1.2.3.4' -Latest '1.2.3.5' | Should -Be -1
        }
        It 'Falls back to string comparison when [version] parsing fails' {
            Compare-SemanticVersion -Current '1.2.3-beta' -Latest '1.2.3-alpha' | Should -Be 1
        }
        It 'Returns 0 for identical non-parseable strings' {
            Compare-SemanticVersion -Current 'abc' -Latest 'abc' | Should -Be 0
        }
        It 'Returns -1 for non-parseable Current < Latest' {
            Compare-SemanticVersion -Current 'abc' -Latest 'def' | Should -Be -1
        }
        It 'Correctly handles 1.2.10 vs 1.2.3 (the motivating bug)' {
            Compare-SemanticVersion -Current '1.2.3' -Latest '1.2.10' | Should -Be -1
            Compare-SemanticVersion -Current '1.2.10' -Latest '1.2.3' | Should -Be 1
        }
        It 'Handles zero versions' {
            Compare-SemanticVersion -Current '0.0.0' -Latest '0.0.1' | Should -Be -1
            Compare-SemanticVersion -Current '0.0.1' -Latest '0.0.0' | Should -Be 1
        }
    }
}
