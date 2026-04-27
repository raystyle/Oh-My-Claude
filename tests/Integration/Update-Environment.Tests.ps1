#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"
}

Describe 'Update-Environment' {
    BeforeAll {
        # Save current User PATH so we can restore it
        $script:savedUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    }
    AfterAll {
        # Restore original User PATH
        [Environment]::SetEnvironmentVariable("Path", $script:savedUserPath, "User")
    }

    It 'Merges Machine and User PATH into $env:Path' {
        # Set a known User PATH value
        $testUserPath = 'D:\test\omc\bin'
        [Environment]::SetEnvironmentVariable("Path", $testUserPath, "User")

        Update-Environment

        # Machine PATH entries should be present
        $env:Path | Should -Match 'System32'
        # Our test User PATH entry should be present
        $env:Path | Should -Match 'D:\\test\\omc\\bin'
    }

    It 'Deduplicates PATH entries' {
        $dupEntry = "D:\dup_$(Get-Random)"
        $testUserPath = "$dupEntry;$dupEntry"
        [Environment]::SetEnvironmentVariable("Path", $testUserPath, "User")

        Update-Environment

        $count = ($env:Path -split ';' | Where-Object { $_ -eq $dupEntry }).Count
        $count | Should -Be 1
    }
}
