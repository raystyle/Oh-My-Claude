#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Backup-ToolVersion' {
    It 'Throws when executable does not exist' {
        { Backup-ToolVersion -ToolName 'fake' -ExePath 'C:\nonexistent\fake.exe' } |
            Should -Throw '*not found*'
    }
    It 'Creates backup with timestamp in directory name' {
        $exePath = Join-Path $TestDrive 'tool.exe'
        Set-Content $exePath -Value 'fake exe content' -Encoding UTF8
        $backupPath = Backup-ToolVersion -ToolName 'testtool' -ExePath $exePath
        $backupPath | Should -Not -BeNullOrEmpty
        Test-Path $backupPath | Should -BeTrue
        $backupPath | Should -Match 'testtool-backup-\d{8}-\d{6}'
    }
    It 'Backup file has same content as original' {
        $exePath = Join-Path $TestDrive 'original.exe'
        Set-Content $exePath -Value 'original content here' -Encoding UTF8 -NoNewline
        $backupPath = Backup-ToolVersion -ToolName 'testtool' -ExePath $exePath
        $backupContent = Get-Content $backupPath -Raw
        $backupContent.Trim() | Should -Be 'original content here'
    }
}
