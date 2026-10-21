param accountName string
param projectName string
param location string = resourceGroup().location
param tags object = {}
param modelDeploymentName string = 'gpt-5.4'
param modelName string = 'gpt-5.4'
param modelVersion string = '2026-03-05'
param deploymentCapacity int = 50
param managedIdentityPrincipalId string
param deployerPrincipalId string = ''
@allowed(['User', 'ServicePrincipal'])
param deployerPrincipalType string = 'User'

var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'
var cognitiveServicesOpenAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' = {
  name: accountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' = {
  parent: foundryAccount
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: projectName
    description: 'hosted-skills-azure claims triage project'
  }
}

// The account rejects concurrent child operations (RequestConflict), so the model
// deployment waits for the project and the role assignments wait for the deployment.
resource foundryModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: foundryAccount
  name: modelDeploymentName
  dependsOn: [foundryProject]
  sku: {
    name: 'GlobalStandard'
    capacity: deploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

resource functionCognitiveServicesUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  dependsOn: [foundryModelDeployment]
  name: guid(foundryAccount.id, managedIdentityPrincipalId, cognitiveServicesUserRoleId)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource functionOpenAiUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  dependsOn: [foundryModelDeployment]
  name: guid(foundryAccount.id, managedIdentityPrincipalId, cognitiveServicesOpenAiUserRoleId)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAiUserRoleId)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Same two roles for whoever runs func start locally.
resource deployerCognitiveServicesUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  dependsOn: [foundryModelDeployment]
  name: guid(foundryAccount.id, deployerPrincipalId, cognitiveServicesUserRoleId)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
  }
}

resource deployerOpenAiUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  dependsOn: [foundryModelDeployment]
  name: guid(foundryAccount.id, deployerPrincipalId, cognitiveServicesOpenAiUserRoleId)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAiUserRoleId)
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
  }
}

output accountName string = foundryAccount.name
output projectName string = foundryProject.name
output projectEndpoint string = 'https://${foundryAccount.name}.services.ai.azure.com/api/projects/${foundryProject.name}'
output modelDeploymentName string = foundryModelDeployment.name
