<#
.SYNOPSIS
Fires the daily_claims_digest timer skill now through the admin endpoint, then tells you where to look.

.EXAMPLE
.\Invoke-TimerSkill.ps1
#>
[CmdletBinding()]
param([string]$Skill = 'daily_claims_digest')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')
$values = Get-AzdValues -RepoRoot (Get-RepoRoot)
$master = az functionapp keys list --resource-group $values['AZURE_RESOURCE_GROUP'] --name $values['AZURE_FUNCTION_NAME'] --query 'masterKey' --output tsv
Assert-LastExitCode 'az functionapp keys list'
$url = "$($values['AZURE_FUNCTION_URL'])/admin/functions/$Skill"
$response = Invoke-WebRequest -Uri $url -Method Post -Headers @{ 'x-functions-key' = $master; 'Content-Type' = 'application/json' } -Body '{"input":""}' -UseBasicParsing
Write-Host "HTTP $($response.StatusCode). The skill runs in the background; expect a digest blob in container '$($values['CLAIMS_DIGEST_CONTAINER'])' within a minute or two."
Write-Host "az storage blob list --account-name $($values['AZURE_STORAGE_ACCOUNT_NAME']) --container-name $($values['CLAIMS_DIGEST_CONTAINER']) --auth-mode login --output table"
