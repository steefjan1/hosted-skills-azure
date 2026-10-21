<#
.SYNOPSIS
Puts one sample claim on the tool-loop queue, the workflow queue, or both.

.EXAMPLE
.\Send-Claim.ps1 -ClaimId CLM-2026-0502 -Mode both
.\Send-Claim.ps1 -ClaimId CLM-2026-0501 -Mode tool_loop -Local
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClaimId,
    [ValidateSet('tool_loop', 'workflow', 'both')][string]$Mode = 'both',
    [switch]$Local
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')
$root = Get-RepoRoot
$claimPath = Join-Path $root "samples\claims\$ClaimId.json"
if (-not (Test-Path $claimPath)) { throw "No sample claim at $claimPath" }
$content = (Get-Content $claimPath -Raw) -replace '\s+', ' '
# The Functions queue trigger expects base64 (host.json messageEncoding default). az storage message put
# sends the text as-is, so an unencoded JSON body fails decoding five times and lands in the poison queue.
# Base64 also sidesteps Windows PowerShell 5.1's lack of quote escaping for native commands.
$contentArg = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))

$queues = @()
if ($Mode -eq 'tool_loop' -or $Mode -eq 'both') { $queues += 'claims-in' }
if ($Mode -eq 'workflow' -or $Mode -eq 'both') { $queues += 'claims-in-workflow' }

$sentLog = Join-Path $root 'measurements\sent.csv'
if (-not (Test-Path (Split-Path $sentLog))) { New-Item -ItemType Directory -Path (Split-Path $sentLog) | Out-Null }
if (-not (Test-Path $sentLog)) { 'claim_id,queue,mode,sent_utc' | Set-Content $sentLog }

foreach ($queue in $queues) {
    $modeName = 'tool_loop'
    if ($queue -eq 'claims-in-workflow') { $modeName = 'workflow' }
    $sentUtc = (Get-Date).ToUniversalTime().ToString('o')
    if ($Local) {
        # Azurite. The Bicep creates the queues in Azure; locally nothing does, and message put does not create them.
        az storage queue create --name $queue --connection-string 'UseDevelopmentStorage=true' --output none
        Assert-LastExitCode "az storage queue create ($queue, local)"
        az storage message put --queue-name $queue --connection-string 'UseDevelopmentStorage=true' --content $contentArg --output none
        Assert-LastExitCode "az storage message put ($queue, local)"
    }
    else {
        $values = Get-AzdValues -RepoRoot $root
        az storage message put --account-name $values['AZURE_STORAGE_ACCOUNT_NAME'] --queue-name $queue --auth-mode login --content $contentArg --output none
        Assert-LastExitCode "az storage message put ($queue)"
    }
    "$ClaimId,$queue,$modeName,$sentUtc" | Add-Content $sentLog
    Write-Host "Sent $ClaimId to $queue at $sentUtc"
}
