#Requires -Version 5.1
BeforeAll {
    . "$PSScriptRoot\..\Helpers\TestHelpers.ps1"

}

Describe 'Restore-ToolVersion' {
    It 'Throws when backup file does not exist' {
        { Restore-ToolVersion -ToolName 'fake' -BackupPath 'C:\nonexistent\backup.exe' -TargetPath 'C:\target\tool.exe' } |
            Should -Throw '*not found*'
    }
    It 'Restores from backup to target' {
        $backupPath = Join-Path $TestDrive 'backup\tool.exe'
        New-Item -ItemType Directory -Path (Split-Path $backupPath -Parent) -Force | Out-Null
        Set-Content $backupPath -Value 'restored content' -Encoding UTF8 -NoNewline
        $targetPath = Join-Path $TestDrive 'target\tool.exe'

        Restore-ToolVersion -ToolName 'testtool' -BackupPath $backupPath -TargetPath $targetPath
        Test-Path $targetPath | Should -BeTrue
        (Get-Content $targetPath -Raw).Trim() | Should -Be 'restored content'
    }
    It 'Creates target directory if missing' {
        $backupPath = Join-Path $TestDrive 'backup\tool.exe'
        New-Item -ItemType Directory -Path (Split-Path $backupPath -Parent) -Force | Out-Null
        Set-Content $backupPath -Value 'data' -Encoding UTF8
        $targetPath = Join-Path $TestDrive 'newdir\subdir\tool.exe'

        Restore-ToolVersion -ToolName 'testtool' -BackupPath $backupPath -TargetPath $targetPath
        Test-Path $targetPath | Should -BeTrue
    }
}
