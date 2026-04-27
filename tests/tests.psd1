@{
    Run = @{
        Path        = '.'
        ExcludePath = @('*.psd1', 'Helpers\*')
    }
    Output = @{
        Verbosity = 'Detailed'
    }
    TestDrive = @{
        Enabled = $true
    }
    CodeCoverage = @{
        Enabled      = $false
        OutputFormat = 'JaCoCo'
        OutputPath   = 'coverage.xml'
        Path         = @(
            '..\.scripts\helpers.ps1'
            '..\.scripts\core.ps1'
        )
    }
}
