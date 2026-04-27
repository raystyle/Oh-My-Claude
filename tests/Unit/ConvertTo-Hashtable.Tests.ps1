#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"
}

Describe 'ConvertTo-Hashtable' {
    It 'Converts PSCustomObject to hashtable' {
        $obj = [PSCustomObject]@{ Name = 'test'; Value = 42 }
        $result = $obj | ConvertTo-Hashtable
        $result | Should -BeOfType [hashtable]
        $result.Name | Should -Be 'test'
        $result.Value | Should -Be 42
    }
    It 'Handles pipeline input with multiple objects' {
        $results = @([PSCustomObject]@{ A = 1 }, [PSCustomObject]@{ B = 2 }) | ConvertTo-Hashtable
        $results.Count | Should -Be 2
        $results[0].A | Should -Be 1
        $results[1].B | Should -Be 2
    }
    It 'Handles empty PSCustomObject' {
        $obj = [PSCustomObject]@{}
        $result = $obj | ConvertTo-Hashtable
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }
}
