// ---------------------------------------------------------------------------
// Main orchestrator for ISS Demo infrastructure
// Deploys all modules in dependency order, wiring outputs between them.
// ---------------------------------------------------------------------------

targetScope = 'resourceGroup'

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Environment name (e.g., dev, staging, prod).')
param environmentName string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Optional container image URI override. Leave blank to deploy ghcr.io/talesfromthefield/iss-demo:latest.')
param containerImageUri string = ''

@description('Eventhouse Query URI from the Fabric portal (e.g. https://trd-xxxx.z6.kusto.data.microsoft.com). Obtained after running scripts/deploy-fabric.ps1.')
param fabricIngestionUri string = ''

@description('Fabric KQL Database name to ingest data into.')
param fabricDatabaseName string = 'iss-demo-kqldb'

// ── Fabric Bootstrap parameters (optional — skip to configure Fabric manually) ──

@description('''
  Entra tenant ID for Fabric app registration authentication.
  When provided together with fabricClientId and fabricClientSecret, the
  deployment automatically provisions all Fabric resources and configures the
  Container App — no manual steps required.
  Leave blank to configure Fabric manually after deployment.
''')
param fabricTenantId string = ''

@description('Application (client) ID of the app registration used for Fabric access.')
param fabricClientId string = ''

@description('Client secret of the app registration. This value is never logged or stored in plain text.')
@secure()
param fabricClientSecret string = ''

@description('Display name for the Fabric workspace to create (e.g., "iss-demo"). The bootstrap will create it.')
param fabricWorkspaceName string = 'iss-demo'

@description('Optional email of a user or group to grant Admin access to the Fabric workspace.')
param adminEmail string = ''

@description('Set to true to automatically deploy the Power BI report from PBI/ISS.pbix during bootstrap.')
param deployPbiReport bool = false

// Normalize user-provided environment names for resource naming safety.
var normalizedEnvironmentName = toLower(replace(replace(replace(environmentName, ' ', '-'), '_', '-'), '.', '-'))

// Bootstrap is enabled when the three Fabric SP credentials are provided.
// The workspace is created automatically — no workspace ID needed.
var bootstrapEnabled = !empty(fabricTenantId) && !empty(fabricClientId) && !empty(fabricClientSecret)

// ── Module: Monitoring (base — Log Analytics + App Insights) ────────────────

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    environmentName: normalizedEnvironmentName
    location: location
  }
}

// ── Module: Container Registry ──────────────────────────────────────────────

module containerRegistry 'modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    environmentName: normalizedEnvironmentName
    location: location
  }
}

// ── Module: Container App ──────────────────────────────────────────────────

var effectiveImageUri = !empty(containerImageUri)
  ? containerImageUri
  : 'ghcr.io/talesfromthefield/iss-demo:latest'

module containerApp 'modules/container-app.bicep' = {
  name: 'container-app'
  params: {
    environmentName: normalizedEnvironmentName
    location: location
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    fabricIngestionUri: fabricIngestionUri
    fabricDatabaseName: fabricDatabaseName
    containerImageUri: effectiveImageUri
  }
}

// ── Module: Role Assignments ────────────────────────────────────────────────

module roleAssignments 'modules/role-assignments.bicep' = {
  name: 'role-assignments'
  params: {
    principalId: containerApp.outputs.containerAppPrincipalId
    acrResourceId: containerRegistry.outputs.registryResourceId
  }
}

// ── Module: Bootstrap (Fabric setup — runs when SP credentials are provided) ─

module bootstrap 'modules/bootstrap.bicep' = if (bootstrapEnabled) {
  name: 'bootstrap'
  params: {
    location: location
    containerAppName: containerApp.outputs.containerAppName
    fabricWorkspaceName: fabricWorkspaceName
    fabricTenantId: fabricTenantId
    fabricClientId: fabricClientId
    fabricClientSecret: fabricClientSecret
    adminEmail: adminEmail
    deployPbiReport: deployPbiReport
  }
  dependsOn: [
    roleAssignments
  ]
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('Name of the deployed Container App.')
output containerAppName string = containerApp.outputs.containerAppName

@description('Container image URI deployed.')
output containerImageUri string = effectiveImageUri

@description('Container Registry login server.')
output acrLoginServer string = containerRegistry.outputs.loginServer

@description('Fabric Ingestion URI applied to the Container App (only set when bootstrap ran).')
output fabricIngestionUri string = bootstrapEnabled ? bootstrap!.outputs.fabricIngestionUri : fabricIngestionUri

@description('Fabric workspace GUID created by the bootstrap (only set when bootstrap ran).')
output fabricWorkspaceId string = bootstrapEnabled ? bootstrap!.outputs.workspaceId : ''

