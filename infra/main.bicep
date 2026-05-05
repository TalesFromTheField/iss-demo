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

// Normalize user-provided environment names for resource naming safety.
var normalizedEnvironmentName = toLower(replace(replace(replace(environmentName, ' ', '-'), '_', '-'), '.', '-'))

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

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('Name of the deployed Container App.')
output containerAppName string = containerApp.outputs.containerAppName

@description('Container image URI deployed.')
output containerImageUri string = effectiveImageUri

@description('Container Registry login server.')
output acrLoginServer string = containerRegistry.outputs.loginServer

