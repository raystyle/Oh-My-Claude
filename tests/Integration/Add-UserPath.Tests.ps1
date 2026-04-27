#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"
}

Describe 'Add-UserPath' {
    BeforeAll {
        $script:savedUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    }
    AfterAll {
        [Environment]::SetEnvironmentVariable("Path", $script:savedUserPath, "User")
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ';' +
                    [Environment]::GetEnvironmentVariable("Path", "User")
    }

    It 'Adds directory to User PATH when not present' {
        $testDir = "D:\omc_test_add_$(Get-Random)"
        # Start with a known PATH (no test dir)
        [Environment]::SetEnvironmentVariable("Path", 'C:\Existing;D:\Another', "User")

        Add-UserPath -Dir $testDir

        $result = [Environment]::GetEnvironmentVariable("Path", "User")
        $result | Should -Match ([regex]::Escape($testDir))
    }

    It 'Does not add duplicate entries' {
        $testDir = "D:\omc_test_dup_$(Get-Random)"
        [Environment]::SetEnvironmentVariable("Path", $testDir, "User")

        Add-UserPath -Dir $testDir

        $result = [Environment]::GetEnvironmentVariable("Path", "User")
        # Should appear only once
        ($result -split ';' | Where-Object { $_ -eq $testDir }).Count | Should -Be 1
    }

    It 'Normalizes trailing backslashes for dedup' {
        $testDir = "D:\omc_test_norm_$(Get-Random)"
        [Environment]::SetEnvironmentVariable("Path", $testDir, "User")

        Add-UserPath -Dir "$testDir\"

        $result = [Environment]::GetEnvironmentVariable("Path", "User")
        ($result -split ';' | Where-Object { $_ -eq $testDir }).Count | Should -Be 1
    }
}
