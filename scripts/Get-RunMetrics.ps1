<#
.SYNOPSIS
Compares the tool-loop and workflow triage skills: model calls and tokens per run from
Application Insights, and end-to-end latency from enqueue time to the recorded decision.

.DESCRIPTION
Needs the Azure CLI application-insights extension (az extension add --name application-insights).
Token attributes come from the Microsoft Agent Framework gen_ai spans that the runtime's
[monitor] extra exports. Allow 2-5 minutes after sending for ingestion.

.EXAMPLE
.\Get-RunMetrics.ps1 -Hours 2
#>
[CmdletBinding()]
param(
    [int]$Hours = 6,
    [string]$OutFile = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')
$root = Get-RepoRoot
$values = Get-AzdValues -RepoRoot $root
$rg = $values['AZURE_RESOURCE_GROUP']
$appi = $values['APPLICATIONINSIGHTS_NAME']
$storage = $values['AZURE_STORAGE_ACCOUNT_NAME']
$table = $values['CLAIMS_TABLE_NAME']

# 1. Tokens and model round trips per run, per agent, from App Insights.
# KQL with single-quoted strings only: Windows PowerShell 5.1 mangles embedded double quotes
# when it hands arguments to native commands. Collapsed to one line for the same reason.
$kqlLines = @(
    "let runs = dependencies",
    "| where timestamp > ago(${Hours}h)",
    "| where name startswith 'agent.run '",
    "| extend agent = tostring(customDimensions['af.agent.name']), outcome = tostring(customDimensions['af.agent.outcome']), toolCalls = toint(customDimensions['af.agent.tool_call_count'])",
    "| where agent in ('claim_triage', 'claim_triage_workflow')",
    "| project operation_Id, agent, outcome, toolCalls, agentRunMs = duration;",
    "dependencies",
    "| where timestamp > ago(${Hours}h)",
    "| where name startswith 'chat '",
    "| extend inTok = toint(customDimensions['gen_ai.usage.input_tokens']), outTok = toint(customDimensions['gen_ai.usage.output_tokens'])",
    "| summarize modelCalls = count(), inputTokens = sum(inTok), outputTokens = sum(outTok) by operation_Id",
    "| join kind=inner runs on operation_Id",
    "| summarize runs = count(), avgModelCalls = round(avg(modelCalls), 1), avgToolCalls = round(avg(toolCalls), 1), avgInputTokens = round(avg(inputTokens), 0), avgOutputTokens = round(avg(outputTokens), 0), avgAgentRunSec = round(avg(agentRunMs) / 1000, 1), errors = countif(outcome != 'success') by agent",
    "| order by agent asc"
)
$kql = $kqlLines -join ' '
Write-Host "Querying Application Insights ($appi) for the last $Hours hour(s)..."
$json = az monitor app-insights query --app $appi --resource-group $rg --analytics-query $kql --output json
Assert-LastExitCode 'az monitor app-insights query'
$result = $json | ConvertFrom-Json
$columns = $result.tables[0].columns | ForEach-Object { $_.name }
$tokenRows = @()
foreach ($row in $result.tables[0].rows) {
    $obj = [ordered]@{}
    for ($i = 0; $i -lt $columns.Count; $i++) { $obj[$columns[$i]] = $row[$i] }
    $tokenRows += [pscustomobject]$obj
}
Write-Host ''
Write-Host 'Model calls and tokens per run (agent.run span + gen_ai chat spans):'
$tokenRows | Format-Table -AutoSize

# 2. End-to-end latency: enqueue time (measurements\sent.csv) to RecordedAt in the decisions table.
$sentLog = Join-Path $root 'measurements\sent.csv'
if (-not (Test-Path $sentLog)) { Write-Warning "No $sentLog, skipping latency."; return }
$sent = Import-Csv $sentLog
$since = (Get-Date).ToUniversalTime().AddHours(-$Hours)
$sent = $sent | Where-Object { [datetime]::Parse($_.sent_utc).ToUniversalTime() -ge $since }

$entitiesJson = az storage entity query --account-name $storage --table-name $table --auth-mode login --num-results 1000 --output json
Assert-LastExitCode 'az storage entity query'
$entities = ($entitiesJson | ConvertFrom-Json).items

$latency = @()
$sentSorted = $sent | Sort-Object { [datetime]::Parse($_.sent_utc) }
foreach ($s in $sentSorted) {
    $sentTime = [datetime]::Parse($s.sent_utc).ToUniversalTime()
    # The window for this send closes when the same claim is sent to the same queue again.
    $nextSend = $sentSorted | Where-Object { $_.claim_id -eq $s.claim_id -and $_.mode -eq $s.mode -and [datetime]::Parse($_.sent_utc).ToUniversalTime() -gt $sentTime } |
        Sort-Object { [datetime]::Parse($_.sent_utc) } | Select-Object -First 1
    $windowEnd = [datetime]::MaxValue
    if ($null -ne $nextSend) { $windowEnd = [datetime]::Parse($nextSend.sent_utc).ToUniversalTime() }
    $match = $entities | Where-Object { $_.ClaimId -eq $s.claim_id -and $_.Mode -eq $s.mode } |
        Where-Object { $t = [datetime]::Parse($_.RecordedAt).ToUniversalTime(); $t -ge $sentTime -and $t -lt $windowEnd } |
        Sort-Object { [datetime]::Parse($_.RecordedAt) } | Select-Object -First 1
    if ($null -ne $match) {
        $recorded = [datetime]::Parse($match.RecordedAt).ToUniversalTime()
        $latency += [pscustomobject]@{
            claim_id = $s.claim_id
            mode     = $s.mode
            route    = $match.Route
            severity = $match.Severity
            seconds  = [math]::Round(($recorded - $sentTime).TotalSeconds, 1)
        }
    }
    else {
        $latency += [pscustomobject]@{ claim_id = $s.claim_id; mode = $s.mode; route = '(not recorded)'; severity = ''; seconds = $null }
    }
}
Write-Host 'End-to-end latency per claim (enqueue to recorded decision):'
$latency | Sort-Object claim_id, mode | Format-Table -AutoSize
Write-Host 'Average seconds per mode:'
$latency | Where-Object { $null -ne $_.seconds } | Group-Object mode | ForEach-Object {
    [pscustomobject]@{ mode = $_.Name; runs = $_.Count; avgSeconds = [math]::Round(($_.Group | Measure-Object seconds -Average).Average, 1) }
} | Format-Table -AutoSize

# Did both modes reach the same decision?
Write-Host 'Decision agreement between modes (same claim, same route):'
$byClaim = $latency | Where-Object { $_.route -notlike '(*' } | Group-Object claim_id
foreach ($g in $byClaim) {
    $routes = $g.Group | Select-Object -ExpandProperty route -Unique
    $verdict = 'agree'
    if ($routes.Count -gt 1) { $verdict = 'DIFFER: ' + (($g.Group | ForEach-Object { $_.mode + '=' + $_.route }) -join ', ') }
    Write-Host ("  {0}: {1}" -f $g.Name, $verdict)
}

if ($OutFile -ne '') {
    $latency | Export-Csv -NoTypeInformation -Path $OutFile
    Write-Host "Latency rows written to $OutFile"
}
