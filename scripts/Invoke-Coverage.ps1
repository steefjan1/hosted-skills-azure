<#
.SYNOPSIS
Calls the HTTP-triggered coverage_question hosted skill and prints the validated JSON verdict.

.EXAMPLE
.\Invoke-Coverage.ps1 -PolicyNumber POL-1003 -Question "Is a crown covered and up to what amount?"
.\Invoke-Coverage.ps1 -PolicyNumber POL-1002 -Question "Is a cracked windscreen covered?" -Local
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PolicyNumber,
    [Parameter(Mandatory = $true)][string]$Question,
    [switch]$Local
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')
$body = @{ policy_number = $PolicyNumber; question = $Question } | ConvertTo-Json -Compress
if ($Local) {
    $url = 'http://localhost:7071/coverage'
    $headers = @{ 'Content-Type' = 'application/json' }
}
else {
    $values = Get-AzdValues -RepoRoot (Get-RepoRoot)
    $key = & (Join-Path $PSScriptRoot 'Get-FunctionKey.ps1')
    $url = "$($values['AZURE_FUNCTION_URL'])/coverage"
    $headers = @{ 'Content-Type' = 'application/json'; 'x-functions-key' = $key }
}
$response = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -UseBasicParsing
Write-Host "HTTP $($response.StatusCode), session $($response.Headers['x-ms-session-id'])"
$response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 5
