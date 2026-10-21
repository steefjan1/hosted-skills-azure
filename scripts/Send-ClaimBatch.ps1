<#
.SYNOPSIS
Sends every sample claim to both queues, N times each, for the tool-loop vs workflow measurement.

.EXAMPLE
.\Send-ClaimBatch.ps1 -Rounds 3 -Reset
.\Send-ClaimBatch.ps1 -Rounds 1 -Mode workflow -DelaySeconds 0
#>
[CmdletBinding()]
param(
    [int]$Rounds = 1,
    [ValidateSet('tool_loop', 'workflow', 'both')][string]$Mode = 'both',
    [int]$DelaySeconds = 20,
    [switch]$Reset,
    [switch]$Local
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')
$root = Get-RepoRoot
$sentLog = Join-Path $root 'measurements\sent.csv'
if ($Reset -and (Test-Path $sentLog)) {
    Remove-Item $sentLog
    Write-Host "Cleared $sentLog"
}
$claims = Get-ChildItem (Join-Path $root 'samples\claims') -Filter '*.json' | Sort-Object Name
for ($round = 1; $round -le $Rounds; $round++) {
    foreach ($claim in $claims) {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($claim.Name)
        if ($Local) { & (Join-Path $PSScriptRoot 'Send-Claim.ps1') -ClaimId $id -Mode $Mode -Local }
        else { & (Join-Path $PSScriptRoot 'Send-Claim.ps1') -ClaimId $id -Mode $Mode }
        # Pace the sends so the measurement reflects the runtime, not the model deployment's quota.
        if ($DelaySeconds -gt 0) { Start-Sleep -Seconds $DelaySeconds }
    }
    Write-Host "Round $round of $Rounds sent."
}
Write-Host "Wait a few minutes, then run .\Get-RunMetrics.ps1"
