// ---------------------------------------------------------------------------
// Module: Bootstrap — one-shot Fabric setup via Azure deploymentScript
//
// Runs automatically during deployment. Installs ms-fabric-cli, authenticates
// with the provided service principal, creates all Fabric resources (Eventhouse,
// KQL Database, tables), captures FabricIngestionUri, and updates the Container
// App so it can start streaming data to Fabric immediately.
//
// Prerequisites (one-time, done before deployment):
//   1. Create an Azure App Registration (service principal)
//   2. Grant it "Member" or higher on the target Fabric workspace
//   3. Pass client ID, secret, and tenant ID as deployment parameters
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Azure region for the deploymentScript and its managed identity.')
param location string

@description('Name of the Container App to update with FabricIngestionUri after setup.')
param containerAppName string

@description('Name of the Container App resource group.')
param resourceGroupName string = resourceGroup().name

@description('Fabric workspace GUID (from the Fabric portal URL).')
param fabricWorkspaceId string

@description('Entra tenant ID for Fabric service principal authentication.')
param fabricTenantId string

@description('Application (client) ID of the service principal granted access to the Fabric workspace.')
param fabricClientId string

@description('Client secret of the service principal. Store this value in a Key Vault in production.')
@secure()
param fabricClientSecret string

@description('''
  Optional URL override for deploy-fabric.sh. Leave blank to use the script
  from the main branch of the TalesFromTheField/iss-demo repository.
''')
param deployFabricScriptUrl string = ''

// ── User-assigned Managed Identity ─────────────────────────────────────────
// The deploymentScript needs a managed identity so it can call
// 'az containerapp update' to write FabricIngestionUri back to the Container App.

resource bootstrapIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uami-bootstrap-iss'
  location: location
}

// Grant the bootstrap identity Contributor on this resource group so it can
// update the Container App environment variables.
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, bootstrapIdentity.id, 'contributor-bootstrap')
  scope: resourceGroup()
  properties: {
    // Contributor
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c'
    )
    principalId: bootstrapIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Deployment Script ───────────────────────────────────────────────────────

resource bootstrapScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'bootstrap-fabric'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${bootstrapIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.59.0'
    timeout: 'PT30M'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      { name: 'FABRIC_CLIENT_ID', value: fabricClientId }
      { name: 'FABRIC_CLIENT_SECRET', secureValue: fabricClientSecret }
      { name: 'FABRIC_TENANT_ID', value: fabricTenantId }
      { name: 'FABRIC_WORKSPACE_ID', value: fabricWorkspaceId }
      { name: 'CONTAINER_APP_NAME', value: containerAppName }
      { name: 'AZURE_RESOURCE_GROUP', value: resourceGroupName }
      { name: 'DEPLOY_FABRIC_SCRIPT', value: deployFabricScriptUrl }
    ]
    scriptContent: loadTextContent('../../scripts/bootstrap.sh')
  }
  dependsOn: [
    contributorRoleAssignment
  ]
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('Fabric Ingestion URI detected and applied to the Container App by the bootstrap script.')
output fabricIngestionUri string = bootstrapScript.properties.outputs.fabricIngestionUri ?? ''
