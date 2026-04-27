#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

    $profileScript = Join-Path $_testProjectRoot '.scripts\dev\profile-line.ps1'

    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    $ps5Profile = Join-Path $myDocs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    $ps7Profile = Join-Path $myDocs 'PowerShell\Microsoft.PowerShell_profile.ps1'

    # Back up existing profiles
    $ps5Backup = $null
    $ps7Backup = $null
    if (Test-Path $ps5Profile) {
        $ps5Backup = Get-Content $ps5Profile -Raw -Encoding UTF8
    }
    if (Test-Path $ps7Profile) {
        $ps7Backup = Get-Content $ps7Profile -Raw -Encoding UTF8
    }
}

Describe 'Profile-Line Script' {
    Context 'Block mode - add' {
        It 'Creates profile with marked block when file does not exist' {
            & $profileScript -Action add `
                -Line 'Import-Module PSFzf' -Comment 'PSFzf bindings' -BlockName 'TestBlock1'

            $content = Get-Content $ps5Profile -Raw
            $content | Should -Match '# BEGIN ohmywinclaude: TestBlock1'
            $content | Should -Match 'Import-Module PSFzf'
            $content | Should -Match '# END ohmywinclaude: TestBlock1'
        }
        It 'Replaces existing block on second add' {
            & $profileScript -Action add `
                -Line 'Old line' -Comment 'test' -BlockName 'ReplaceTest'
            & $profileScript -Action add `
                -Line 'New line' -Comment 'test' -BlockName 'ReplaceTest'

            $content = Get-Content $ps5Profile -Raw
            $content | Should -Not -Match 'Old line'
            $content | Should -Match 'New line'
            ([regex]::Matches($content, '# BEGIN ohmywinclaude: ReplaceTest')).Count | Should -Be 1
        }
        It 'Creates block in both PS5 and PS7 profiles' {
            & $profileScript -Action add `
                -Line 'Shared line' -Comment 'shared' -BlockName 'BothProfiles'

            Get-Content $ps5Profile -Raw | Should -Match 'Shared line'
            Get-Content $ps7Profile -Raw | Should -Match 'Shared line'
        }
    }

    Context 'Block mode - remove' {
        It 'Removes existing block' {
            & $profileScript -Action add `
                -Line 'Some line' -Comment 'test' -BlockName 'RemoveTest'
            & $profileScript -Action remove -BlockName 'RemoveTest'

            $content = Get-Content $ps5Profile -Raw
            $content | Should -Not -Match 'Some line'
            $content | Should -Not -Match 'BEGIN ohmywinclaude: RemoveTest'
        }
        It 'Does not error when block not found' {
            { & $profileScript -Action remove -BlockName 'NonExistentBlock' } | Should -Not -Throw
        }
    }

    Context 'Legacy single-line mode - add' {
        It 'Adds line with comment' {
            & $profileScript -Action add `
                -Line 'Set-PSReadLineOption -EditMode Emacs' -Comment 'PSReadLine config'

            $content = Get-Content $ps5Profile -Raw
            $content | Should -Match 'Set-PSReadLineOption -EditMode Emacs'
            $content | Should -Match '# PSReadLine config'
        }
    }

    Context 'Legacy single-line mode - remove' {
        It 'Removes line and comment' {
            & $profileScript -Action add `
                -Line 'RemoveMe' -Comment 'to remove'
            & $profileScript -Action remove `
                -Line 'RemoveMe' -Comment 'to remove'

            $content = Get-Content $ps5Profile -Raw
            $content | Should -Not -Match 'RemoveMe'
        }
    }
}

AfterAll {
    # Restore original profiles
    foreach ($f in @($ps5Profile, $ps7Profile)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    $ps5Dir = Split-Path $ps5Profile -Parent
    $ps7Dir = Split-Path $ps7Profile -Parent
    if ((Test-Path $ps5Dir) -and (-not (Get-ChildItem $ps5Dir -Recurse -Force -ErrorAction SilentlyContinue))) {
        Remove-Item $ps5Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ((Test-Path $ps7Dir) -and (-not (Get-ChildItem $ps7Dir -Recurse -Force -ErrorAction SilentlyContinue))) {
        Remove-Item $ps7Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($ps5Backup) {
        $ps5Dir | ForEach-Object { New-Item -ItemType Directory -Path (Split-Path $ps5Profile -Parent) -Force | Out-Null }
        Set-Content $ps5Profile -Value $ps5Backup -Encoding UTF8 -NoNewline
    }
    if ($ps7Backup) {
        $ps7Dir | ForEach-Object { New-Item -ItemType Directory -Path (Split-Path $ps7Profile -Parent) -Force | Out-Null }
        Set-Content $ps7Profile -Value $ps7Backup -Encoding UTF8 -NoNewline
    }
}
