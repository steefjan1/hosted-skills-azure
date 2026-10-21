targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the azd environment. Used to generate a short unique hash for all resource names.')
param environmentName string

@minLength(1)
@description('Primary location for all resources. Needs Azure Functions Flex Consumption and the chosen Foundry model on GlobalStandard. swedencentral has both.')
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

@description('Foundry model deployment name (what FOUNDRY_MODEL points at).')
param foundryModel string = 'gpt-5.4'

@description('Foundry model name.')
param foundryModelName string = 'gpt-5.4'

@description('Foundry model version.')
param foundryModelVersion string = '2026-03-05'

@description('Foundry deployment capacity in thousands of tokens per minute.')
param foundryDeploymentCapacity int = 50

@description('Reasoning effort for reasoning-capable models. Leave empty for models that do not support it (for example gpt-4.1).')
param reasoningEffort string = 'medium'

@description('Reasoning summary setting for reasoning-capable models.')
param reasoningSummary string = 'concise'

@description('Object id of the person or principal running azd. Gets data-plane roles so func start works locally against the same storage and Foundry.')
param deployerPrincipalId string = deployer().objectId

@description('Principal type of deployerPrincipalId: User for a person, ServicePrincipal for CI.')
@allowed(['User', 'ServicePrincipal'])
param deployerPrincipalType string = 'User'

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = '${abbrs.webSitesFunctions}claims-${resourceToken}'
var foundryAccountName = 'cog-${resourceToken}'
var foundryProjectName = '${foundryAccountName}-proj'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'

// Names the hosted skills and the tools depend on. Keep in sync with the agent files.
var toolLoopQueueName = 'claims-in'
var workflowQueueName = 'claims-in-workflow'
var decisionsTableName = 'claimdecisions'
var digestContainerName = 'claim-digests'
var taskHubName = 'claims${take(resourceToken, 8)}'

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module apiUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'apiUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    name: '${abbrs.managedIdentityUserAssignedIdentities}claims-${resourceToken}'
  }
}

module foundry './app/foundry.bicep' = {
  name: 'foundry'
  scope: rg
  params: {
    accountName: foundryAccountName
    projectName: foundryProjectName
    location: location
    tags: tags
    modelDeploymentName: foundryModel
    modelName: foundryModelName
    modelVersion: foundryModelVersion
    deploymentCapacity: foundryDeploymentCapacity
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    deployerPrincipalId: deployerPrincipalId
    deployerPrincipalType: deployerPrincipalType
  }
}

module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: '${abbrs.webServerFarms}${resourceToken}'
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
    reserved: true
    location: location
    tags: tags
  }
}

module api './app/api.bicep' = {
  name: 'api'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.name
    appServicePlanId: appServicePlan.outputs.resourceId
    runtimeName: 'python'
    runtimeVersion: '3.13'
    storageAccountName: storage.outputs.name
    deploymentStorageContainerName: deploymentStorageContainerName
    identityId: apiUserAssignedIdentity.outputs.resourceId
    identityClientId: apiUserAssignedIdentity.outputs.clientId
    appSettings: {
      AZURE_FUNCTIONS_AGENTS_PROVIDER: 'foundry'
      FOUNDRY_PROJECT_ENDPOINT: foundry.outputs.projectEndpoint
      FOUNDRY_MODEL: foundry.outputs.modelDeploymentName
      AZURE_FUNCTIONS_AGENTS_REASONING_EFFORT: reasoningEffort
      AZURE_FUNCTIONS_AGENTS_REASONING_SUMMARY: reasoningSummary
      AZURE_CLIENT_ID: apiUserAssignedIdentity.outputs.clientId
      TASKHUB_NAME: taskHubName
      CLAIMS_TABLE_NAME: decisionsTableName
      CLAIMS_DIGEST_CONTAINER: digestContainerName
      ENABLE_MULTIPLATFORM_BUILD: 'true'
      PYTHON_ENABLE_INIT_INDEXING: '1'
    }
  }
}

module storage 'br/public:avm/res/storage/storage-account:0.8.3' = {
  name: 'storage'
  scope: rg
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    dnsEndpointType: 'Standard'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    blobServices: {
      containers: [
        { name: deploymentStorageContainerName }
        { name: digestContainerName }
      ]
    }
    queueServices: {
      queues: [
        { name: toolLoopQueueName }
        { name: workflowQueueName }
      ]
    }
    tableServices: {
      tables: [
        { name: decisionsTableName }
      ]
    }
    minimumTlsVersion: 'TLS1_2'
    location: location
    tags: tags
  }
}

module rbac './app/rbac.bicep' = {
  name: 'rbacAssignments'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    appInsightsName: monitoring.outputs.name
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    deployerPrincipalId: deployerPrincipalId
    deployerPrincipalType: deployerPrincipalType
  }
}

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.7.0' = {
  name: '${uniqueString(deployment().name, location)}-loganalytics'
  scope: rg
  params: {
    name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
    dataRetention: 30
  }
}

module monitoring 'br/public:avm/res/insights/component:0.4.1' = {
  name: '${uniqueString(deployment().name, location)}-appinsights'
  scope: rg
  params: {
    name: '${abbrs.insightsComponents}${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
    disableLocalAuth: true
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_FUNCTION_NAME string = api.outputs.SERVICE_API_NAME
output AZURE_FUNCTION_URL string = 'https://${api.outputs.SERVICE_API_NAME}.azurewebsites.net'
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.name
output CLAIMS_TOOL_LOOP_QUEUE string = toolLoopQueueName
output CLAIMS_WORKFLOW_QUEUE string = workflowQueueName
output CLAIMS_TABLE_NAME string = decisionsTableName
output CLAIMS_DIGEST_CONTAINER string = digestContainerName
output TASKHUB_NAME string = taskHubName
output FOUNDRY_PROJECT_ENDPOINT string = foundry.outputs.projectEndpoint
output FOUNDRY_MODEL string = foundry.outputs.modelDeploymentName
output APPLICATIONINSIGHTS_NAME string = monitoring.outputs.name
