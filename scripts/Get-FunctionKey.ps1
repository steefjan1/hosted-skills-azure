<#
.SYNOPSIS
Prints the default function key (for the chat UI, chat API and HTTP skills) or the MCP system key.

.EXAMPLE
.\Get-FunctionKey.ps1
.\Get-FunctionKey.ps1 -Mcp
#>
[CmdletBinding()]
param([switch]$Mcp)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')
$values = Get-AzdValues -RepoRoot (Get-RepoRoot)
$query = 'functionKeys.default'
if ($Mcp) { $query = 'systemKeys.mcp_extension' }
$key = az functionapp keys list --resource-group $values['AZURE_RESOURCE_GROUP'] --name $values['AZURE_FUNCTION_NAME'] --query $query --output tsv
Assert-LastExitCode 'az functionapp keys list'
Write-Output $key
