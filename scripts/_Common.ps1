# Shared helpers for the scripts. Windows PowerShell 5.1 compatible: no ??, no ternary, no &&.

function Get-AzdValues {
    param([string]$RepoRoot)
    Push-Location $RepoRoot
    try {
        $lines = azd env get-values 2>$null
        if ($LASTEXITCODE -ne 0) { throw "azd env get-values failed. Run 'azd up' first (or pass -Local)." }
    }
    finally { Pop-Location }
    $values = @{}
    foreach ($line in $lines) {
        if ($line -match '^([^=]+)=(.*)$') {
            $values[$Matches[1]] = $Matches[2].Trim('"')
        }
    }
    return $values
}

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Assert-LastExitCode {
    param([string]$What)
    if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE" }
}
