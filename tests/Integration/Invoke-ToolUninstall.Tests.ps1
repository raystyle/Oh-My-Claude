#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"
}

Describe 'Invoke-ToolUninstall' {
    Context 'Tool not installed' {
        It 'Returns early with info message' {
            $toolDef = New-TestToolDefinition
            Mock Get-ToolExePath { return 'C:\nonexistent\tool.exe' }
            Mock Test-Path { return $false }

            { Invoke-ToolUninstall -ToolDef $toolDef } | Should -Not -Throw
        }
    }

    Context 'Tool installed in shared bin' {
        It 'Removes only the executable' {
            $toolDef = New-TestToolDefinition
            $exePath = Join-Path $global:Tool_RootDir '.envs\tools\bin\testtool.exe'
            $binDir = Join-Path $global:Tool_RootDir '.envs\tools\bin'
            if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
            Set-Content $exePath -Value 'fake exe' -Encoding UTF8

            Mock Get-ToolExePath { return $exePath }
            Mock Get-ToolInstalledVersion { return '1.0.0' }

            Invoke-ToolUninstall -ToolDef $toolDef

            Test-Path $exePath | Should -BeFalse
        }
    }

    Context 'Tool with companion assets' {
        It 'Removes companion assets from bin and cache' {
            $toolDef = New-TestToolDefinition -Override @{
                Assets = @(
                    @{ Name = 'companion.exe'; Pattern = 'companion\.exe$' }
                )
            }
            $exePath = Join-Path $global:Tool_RootDir '.envs\tools\bin\testtool.exe'
            $companionPath = Join-Path $global:Tool_RootDir '.envs\tools\bin\companion.exe'
            $cacheDir = Join-Path $global:Tool_RootDir '.cache\tools\testtool'
            $cacheCompanion = Join-Path $cacheDir 'companion.exe'
            $binDir = Join-Path $global:Tool_RootDir '.envs\tools\bin'
            if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
            if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
            Set-Content $exePath -Value 'fake' -Encoding UTF8
            Set-Content $companionPath -Value 'fake companion' -Encoding UTF8
            Set-Content $cacheCompanion -Value 'cached companion' -Encoding UTF8

            Mock Get-ToolExePath { return $exePath }
            Mock Get-ToolInstalledVersion { return '1.0.0' }

            Invoke-ToolUninstall -ToolDef $toolDef

            Test-Path $exePath | Should -BeFalse
            Test-Path $companionPath | Should -BeFalse
            Test-Path $cacheCompanion | Should -BeFalse
        }
    }
}
