// ---------------------------------------------------------------------------
// Module: Bootstrap — one-shot Fabric setup via Azure Container Instance
//
// Runs automatically during deployment. The bootstrap container authenticates
// with the provided app registration, creates the Fabric workspace (the app
// registration automatically becomes Admin), creates all Fabric resources
// (Eventhouse, KQL Database, tables), grants a user/group Admin access,
// optionally deploys the Power BI report, and updates the Container App
// with FabricIngestionUri so it can start streaming data to Fabric.
//
// Uses a plain ACI container group (not deploymentScript) to avoid the
// key-based storage auth requirement imposed by deploymentScript.
//
// Prerequisites (one-time, done before deployment):
//   1. Create an Azure App Registration (= service principal) in Entra ID
//   2. Enable "Service principals can use Fabric APIs" in the Fabric Admin portal
//   3. Pass client ID, secret, and tenant ID as deployment parameters
//   No pre-existing workspace is required — bootstrap creates it.
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Azure region for the bootstrap container instance and its managed identity.')
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

@description('Optional URL override for deploy-fabric.sh. Leave blank to use the script from the main branch of the TalesFromTheField/iss-demo repository.')
param deployFabricScriptUrl string = ''

@description('Bootstrap container image URI. Defaults to the latest image from GHCR.')
param bootstrapImageUri string = 'ghcr.io/talesfromthefield/iss-demo-bootstrap:latest'

@description('Azure subscription ID — passed to the container so az account set works correctly.')
param subscriptionId string = subscription().subscriptionId

// ── User-assigned Managed Identity ─────────────────────────────────────────
// The ACI uses this identity to call 'az login --identity' and then
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
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
    )
    principalId: bootstrapIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Bootstrap Container Instance ───────────────────────────────────────────
// Runs bootstrap.sh once (restartPolicy: Never). No storage account needed —
// the script updates the Container App directly via az CLI + managed identity.

resource bootstrapContainer 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: 'aci-bootstrap-iss'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${bootstrapIdentity.id}': {}
    }
  }
  properties: {
    restartPolicy: 'Never'
    osType: 'Linux'
    containers: [
      {
        name: 'bootstrap'
        properties: {
          image: bootstrapImageUri
          environmentVariables: [
            { name: 'FABRIC_CLIENT_ID',       value: fabricClientId }
            { name: 'FABRIC_CLIENT_SECRET',   secureValue: fabricClientSecret }
            { name: 'FABRIC_TENANT_ID',       value: fabricTenantId }
            { name: 'FABRIC_WORKSPACE_NAME',  value: fabricWorkspaceName }
            { name: 'CONTAINER_APP_NAME',     value: containerAppName }
            { name: 'AZURE_RESOURCE_GROUP',   value: resourceGroupName }
            { name: 'AZURE_SUBSCRIPTION_ID',  value: subscriptionId }
            { name: 'UAMI_CLIENT_ID',         value: bootstrapIdentity.properties.clientId }
            { name: 'ADMIN_EMAIL',            value: adminEmail }
            { name: 'DEPLOY_PBI_REPORT',      value: deployPbiReport ? 'true' : 'false' }
            { name: 'DEPLOY_FABRIC_SCRIPT',   value: deployFabricScriptUrl }
          ]
          resources: {
            requests: {
              cpu: 1
              memoryInGB: json('1.5')
            }
          }
        }
      }
    ]
  }
  dependsOn: [
    contributorRoleAssignment
  ]
}

// ── Outputs ─────────────────────────────────────────────────────────────────
// The ACI updates the Container App env var directly — no ARM outputs needed.
// main.bicep should not depend on fabricIngestionUri from this module.
