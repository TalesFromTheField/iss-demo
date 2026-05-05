// ---------------------------------------------------------------------------
// Module: Bootstrap — one-shot Fabric setup via Azure deploymentScript
//
// Runs automatically during deployment. Installs ms-fabric-cli, authenticates
// with the provided app registration, creates the Fabric workspace (the app
// registration automatically becomes Admin), creates all Fabric resources
// (Eventhouse, KQL Database, tables), optionally grants a user/group Admin
// access, optionally deploys the Power BI report, captures FabricIngestionUri,
// and updates the Container App so it can start streaming data to Fabric.
//
// Prerequisites (one-time, done before deployment):
//   1. Create an Azure App Registration (= service principal) in Entra ID
//   2. Enable "Service principals can use Fabric APIs" in the Fabric Admin portal
//   3. Pass client ID, secret, and tenant ID as deployment parameters
//   No pre-existing workspace is required — bootstrap creates it.
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Azure region for the deploymentScript and its managed identity.')
param location string

@description('Name of the Container App to update with FabricIngestionUri after setup.')
param containerAppName string

@description('Name of the Container App resource group.')
param resourceGroupName string = resourceGroup().name

@description('Display name for the Fabric workspace to create (e.g., "iss-demo").')
param fabricWorkspaceName string = 'iss-demo'

@description('Entra tenant ID for Fabric app registration authentication.')
param fabricTenantId string

@description('Application (client) ID of the app registration used for Fabric access.')
param fabricClientId string

@description('Client secret of the app registration. Store this value in a Key Vault in production.')
@secure()
param fabricClientSecret string

@description('Email address of the user or group to grant Admin access to the created Fabric workspace. Required so a human can access and manage the workspace after bootstrap.')
param adminEmail string

@description('Set to true to automatically deploy the Power BI report from PBI/ISS.pbix.')
param deployPbiReport bool = false

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

// ── Storage Account for deploymentScript ────────────────────────────────────
// deploymentScript requires a storage account for logs and outputs.
// We provision our own so we can explicitly allow key-based auth
// (the platform-created one would also need it, but some policies block it).

resource bootstrapStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'stbootstrap${uniqueString(resourceGroup().id)}'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
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
    storageAccountSettings: {
      storageAccountName: bootstrapStorage.name
      storageAccountKey: bootstrapStorage.listKeys().keys[0].value
    }
    environmentVariables: [
      { name: 'FABRIC_CLIENT_ID', value: fabricClientId }
      { name: 'FABRIC_CLIENT_SECRET', secureValue: fabricClientSecret }
      { name: 'FABRIC_TENANT_ID', value: fabricTenantId }
      { name: 'FABRIC_WORKSPACE_NAME', value: fabricWorkspaceName }
      { name: 'CONTAINER_APP_NAME', value: containerAppName }
      { name: 'AZURE_RESOURCE_GROUP', value: resourceGroupName }
      { name: 'ADMIN_EMAIL', value: adminEmail }
      { name: 'DEPLOY_PBI_REPORT', value: deployPbiReport ? 'true' : 'false' }
      { name: 'DEPLOY_FABRIC_SCRIPT', value: deployFabricScriptUrl }
    ]
    scriptContent: loadTextContent('../../scripts/bootstrap.sh')
  }
  dependsOn: [
    contributorRoleAssignment
    bootstrapStorage
  ]
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('Fabric Ingestion URI detected and applied to the Container App by the bootstrap script.')
output fabricIngestionUri string = bootstrapScript.properties.outputs.fabricIngestionUri ?? ''

@description('Fabric workspace GUID created (or reused) by the bootstrap script.')
output workspaceId string = bootstrapScript.properties.outputs.workspaceId ?? ''
