#Requires -Version 5.1

<#
.SYNOPSIS
    Add or remove a line in PowerShell profile (CurrentUserCurrentHost).
    Manages both PS5 and PS7 profiles with idempotent behavior.
.PARAMETER Action
    "add" or "remove"
.PARAMETER Line
    The line(s) to add/remove. Accepts one or more strings for multi-line blocks.
.PARAMETER Comment
    Comment placed above the line (used as marker for identification)
.PARAMETER BlockName
    When specified, wraps the line(s) in a marked block:
      # BEGIN ohmywinclaude: <BlockName>
      ...
      # END ohmywinclaude: <BlockName>
    Re-running "add" replaces the entire block. "remove" deletes it.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('add', 'remove')]
    [string]$Action,

    [string[]]$Line,

    [string]$Comment,

    [string]$BlockName
)

$myDocs = [Environment]::GetFolderPath('MyDocuments')

# CurrentUserCurrentHost profile for each PS version
$targets = @(
    @{
        Path  = "$myDocs\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
        Label = "PS5 CurrentHost"
    }
    @{
        Path  = "$myDocs\PowerShell\Microsoft.PowerShell_profile.ps1"
        Label = "PS7 CurrentHost"
    }
)

$commentLine = "# $Comment"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Block markers
$useBlock = $false
$beginMarker = ''
$endMarker   = ''
if ($BlockName) {
    $useBlock    = $true
    $beginMarker = "# BEGIN ohmywinclaude: $BlockName"
    $endMarker   = "# END ohmywinclaude: $BlockName"
}

if (-not $Line -and $Action -eq 'add') {
    throw '-Line is required when Action is "add"'
}
if (-not $Line -and -not $useBlock) {
    throw '-Line is required when BlockName is not specified'
}
if ($Action -eq 'add' -and -not $Comment) {
    throw '-Comment is required when Action is "add"'
}

function Remove-Block {
    <#
    .SYNOPSIS
        Remove a marked block (BEGIN/END markers) from an array of lines.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [string[]]$lines,

        [Parameter(Mandatory)]
        [string]$begin,

        [Parameter(Mandatory)]
        [string]$end
    )
    if (-not $lines) { return ,@() }
    $result = @()
    $inBlock = $false
    foreach ($l in $lines) {
        if (-not $inBlock -and $l.Trim() -eq $begin) {
            $inBlock = $true
            continue
        }
        if ($inBlock) {
            if ($l.Trim() -eq $end) {
                $inBlock = $false
            }
            continue
        }
        $result += $l
    }
    return ,@($result)
}

function Remove-TrailingBlanks {
    <#
    .SYNOPSIS
        Remove trailing blank lines from an array of lines.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [string[]]$lines
    )
    if (-not $lines) { return ,@() }
    $endIndex = $lines.Count - 1
    while ($endIndex -ge 0 -and $lines[$endIndex].Trim() -eq '') {
        $endIndex--
    }
    if ($endIndex -lt 0) { return ,@() }
    if ($endIndex -lt $lines.Count - 1) { return ,@($lines[0..$endIndex]) }
    return $lines
}

foreach ($t in $targets) {
    $profilePath = $t.Path
    $label = $t.Label

    # Ensure parent directory exists
    $parentDir = Split-Path $profilePath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # Read existing content (or empty array if file doesn't exist)
    if (Test-Path $profilePath) {
        $lines = @(Get-Content -Path $profilePath -Encoding UTF8)
    }
    else {
        $lines = @()
    }

    if ($useBlock) {
        # ---- Block mode ----
        if ($Action -eq 'add') {
            # Remove existing block, then append new
            $filtered = Remove-Block -lines $lines -begin $beginMarker -end $endMarker
            $newLines = @($filtered)
            if ($newLines.Count -gt 0 -and $newLines[-1].Trim() -ne '') {
                $newLines += ''
            }
            $newLines += $beginMarker
            $newLines += $commentLine
            foreach ($l in $Line) { $newLines += $l }
            $newLines += $endMarker

            [System.IO.File]::WriteAllLines($profilePath, $newLines, $utf8NoBom)
            Write-Host "[OK] $label : block [$BlockName] updated" -ForegroundColor Green
        }
        elseif ($Action -eq 'remove') {
            $filtered = Remove-Block -lines $lines -begin $beginMarker -end $endMarker
            $filtered = Remove-TrailingBlanks -lines $filtered

            if ($filtered.Count -ne $lines.Count) {
                [System.IO.File]::WriteAllLines($profilePath, [string[]]$filtered, $utf8NoBom)
                Write-Host "[OK] $label : block [$BlockName] removed" -ForegroundColor Green
            }
            else {
                Write-Host "[OK] $label : block [$BlockName] not found, nothing to remove" -ForegroundColor DarkGray
            }
        }
    }
    else {
        # ---- Legacy single-line mode ----
        if ($Action -eq 'add') {
            # Idempotent: skip if all lines already present
            $allFound = $true
            foreach ($targetLine in $Line) {
                $found = $false
                foreach ($l in $lines) {
                    if ($l.Trim() -eq $targetLine.Trim()) {
                        $found = $true
                        break
                    }
                }
                if (-not $found) { $allFound = $false; break }
            }
            if ($allFound) {
                Write-Host "[OK] Already present: $label" -ForegroundColor DarkGray
                continue
            }

            # Append comment + lines
            $newLines = @($lines)
            if ($newLines.Count -gt 0 -and $newLines[-1].Trim() -ne '') {
                $newLines += ''
            }
            $newLines += $commentLine
            foreach ($l in $Line) { $newLines += $l }

            [System.IO.File]::WriteAllLines($profilePath, $newLines, $utf8NoBom)
            Write-Host "[OK] $label : added" -ForegroundColor Green
        }
        elseif ($Action -eq 'remove') {
            if (-not (Test-Path $profilePath)) {
                Write-Host "[OK] $label : profile not found, nothing to remove" -ForegroundColor DarkGray
                continue
            }

            # Remove comment line and all target lines
            $filtered = @()
            $skipNext = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($skipNext) {
                    $skipNext = $false
                    continue
                }
                # Match comment line, then check if following lines match targets
                if ($lines[$i].Trim() -eq $commentLine.Trim()) {
                    $match = $true
                    for ($j = 0; $j -lt $Line.Count; $j++) {
                        if (($i + 1 + $j) -ge $lines.Count -or $lines[$i + 1 + $j].Trim() -ne $Line[$j].Trim()) {
                            $match = $false
                            break
                        }
                    }
                    if ($match) {
                        $skipCount = $Line.Count
                        for ($j = 0; $j -lt $skipCount; $j++) {
                            $i++
                        }
                        continue
                    }
                }
                # Also remove standalone target lines (without comment)
                $isTarget = $false
                foreach ($targetLine in $Line) {
                    if ($lines[$i].Trim() -eq $targetLine.Trim()) {
                        $isTarget = $true
                        break
                    }
                }
                if ($isTarget) { continue }
                $filtered += $lines[$i]
            }

            $filtered = Remove-TrailingBlanks $filtered

            if ($filtered.Count -ne $lines.Count) {
                [System.IO.File]::WriteAllLines($profilePath, [string[]]$filtered, $utf8NoBom)
                Write-Host "[OK] $label : removed" -ForegroundColor Green
            }
            else {
                Write-Host "[OK] $label : not found, nothing to remove" -ForegroundColor DarkGray
            }
        }
    }
}
