#Requires -Version 5.1

<#
.SYNOPSIS
    Manage PowerShell module installations via local PSRepository.
.PARAMETER Command
    Action: check, install, update, uninstall, download, register, unregister.
.PARAMETER Module
    Module name (default: PSScriptAnalyzer).
.PARAMETER Version
    Specific version to install (default: latest).
.PARAMETER Force
    Skip upgrade confirmation.
#>

[CmdletBinding()]
param(
    [ValidateSet('check', 'install', 'update', 'uninstall', 'download', 'register', 'unregister')]
    [string]$Command = 'check',

    [string]$Module = 'PSScriptAnalyzer',

    [AllowEmptyString()]
    [string]$Version = '',

    [switch]$Force
)

. "$PSScriptRoot\..\helpers.ps1"
. "$PSScriptRoot\psmodule.ps1"

# Module definitions
$ModuleDefs = @{
    PSScriptAnalyzer = @{
        DisplayName = 'PSScriptAnalyzer'
    }
    Pester = @{
        DisplayName = 'Pester'
    }
    PSFzf = @{
        DisplayName = 'PSFzf'
        ProfileBlock = @{
            BlockName = 'PSFzf'
            Comment = 'replace ''Ctrl+t'' and ''Ctrl+r'' with your preferred bindings:'
            Lines = @(
                'Import-Module PSFzf'
                'Set-PsFzfOption -PSReadlineChordProvider ''Ctrl+t'' -PSReadlineChordReverseHistory ''Ctrl+r'''
            )
        }
    }
}

$def = $ModuleDefs[$Module]
if (-not $def) { throw "Unknown module: $Module" }

switch ($Command) {
    'check'      { Invoke-PSModuleCheck -ModuleDef $def -ModuleName $Module }
    'download'   { Invoke-PSModuleDownload -ModuleDef $def -ModuleName $Module -Version $Version }
    'install'    { Invoke-PSModuleInstall -ModuleDef $def -ModuleName $Module -Version $Version -Command install -Force:$Force }
    'update'     { Invoke-PSModuleInstall -ModuleDef $def -ModuleName $Module -Version $Version -Command update -Force }
    'uninstall'  { Invoke-PSModuleUninstall -ModuleDef $def -ModuleName $Module }
    'register'   { Register-OhMyClaudeLocalRepo }
    'unregister' { Unregister-OhMyClaudeLocalRepo -RemoveFiles }
}
