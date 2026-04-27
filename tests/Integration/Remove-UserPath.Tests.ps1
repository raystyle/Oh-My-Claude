#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"
}

Describe 'Remove-UserPath' {
    BeforeAll {
        $script:savedUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    }
    AfterAll {
        [Environment]::SetEnvironmentVariable("Path", $script:savedUserPath, "User")
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ';' +
                    [Environment]::GetEnvironmentVariable("Path", "User")
    }

    It 'Removes directory from User PATH' {
        $keepDir  = "D:\omc_keep_$(Get-Random)"
        $removeDir = "D:\omc_remove_$(Get-Random)"
        [Environment]::SetEnvironmentVariable("Path", "$keepDir;$removeDir", "User")

        Remove-UserPath -Dir $removeDir

        $result = [Environment]::GetEnvironmentVariable("Path", "User")
        $result | Should -Match ([regex]::Escape($keepDir))
        $result | Should -Not -Match ([regex]::Escape($removeDir))
    }

    It 'Does nothing when directory not in PATH' {
        $originalPath = "D:\omc_stay_$(Get-Random)"
        [Environment]::SetEnvironmentVariable("Path", $originalPath, "User")

        Remove-UserPath -Dir 'D:\omc_notpresent'

        $result = [Environment]::GetEnvironmentVariable("Path", "User")
        $result | Should -Be $originalPath
    }

    It 'Does nothing when PATH is empty' {
        [Environment]::SetEnvironmentVariable("Path", '', "User")

        { Remove-UserPath -Dir 'D:\omc_anything' } | Should -Not -Throw

        $result = [Environment]::GetEnvironmentVariable("Path", "User")
        $result | Should -BeNullOrEmpty
    }

    It 'Normalizes trailing backslashes' {
        $keepDir   = "D:\omc_k2_$(Get-Random)"
        $removeDir = "D:\omc_r2_$(Get-Random)"
        [Environment]::SetEnvironmentVariable("Path", "$keepDir;$removeDir", "User")

        Remove-UserPath -Dir "$removeDir\"

        $result = [Environment]::GetEnvironmentVariable("Path", "User")
        $result | Should -Match ([regex]::Escape($keepDir))
        $result | Should -Not -Match ([regex]::Escape($removeDir))
    }
}
