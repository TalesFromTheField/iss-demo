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

// Normalize user-provided environment names for resource naming safety.
var normalizedEnvironmentName = toLower(replace(replace(replace(environmentName, ' ', '-'), '_', '-'), '.', '-'))

// ── Module: Event Hubs ──────────────────────────────────────────────────────

module eventHubs 'modules/event-hubs.bicep' = {
  name: 'event-hubs'
  params: {
    environmentName: normalizedEnvironmentName
    location: location
  }
}

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

// Determine effective image URI (use provided image or default to published GHCR image)
var effectiveImageUri = !empty(containerImageUri) 
  ? containerImageUri 
  : 'ghcr.io/talesfromthefield/iss-demo:latest'

// Event Hubs namespace name is deterministic from environmentName in event-hubs module.
var eventHubNamespaceName = eventHubs.outputs.namespaceName

module containerApp 'modules/container-app.bicep' = {
  name: 'container-app'
  params: {
    environmentName: normalizedEnvironmentName
    location: location
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    issLocationHubName: eventHubs.outputs.issLocationHubName
    astronautsHubName: eventHubs.outputs.astronautsHubName
    eventHubNamespaceName: eventHubNamespaceName
    containerImageUri: effectiveImageUri
  }
}

// ── Module: Role Assignments ────────────────────────────────────────────────

module roleAssignments 'modules/role-assignments.bicep' = {
  name: 'role-assignments'
  params: {
    principalId: containerApp.outputs.containerAppPrincipalId
    eventHubNamespaceResourceId: resourceId('Microsoft.EventHub/namespaces', eventHubNamespaceName)
    eventHubNamespaceName: eventHubNamespaceName
    acrResourceId: containerRegistry.outputs.registryResourceId
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('Fully qualified domain name of the Event Hubs namespace.')
output eventHubNamespaceFqdn string = eventHubs.outputs.namespaceFqdn

@description('Name of the deployed Container App.')
output containerAppName string = containerApp.outputs.containerAppName

@description('Container image URI deployed.')
output containerImageUri string = effectiveImageUri

@description('Container Registry login server.')
output acrLoginServer string = containerRegistry.outputs.loginServer

// App Insights connection string intentionally omitted from outputs
// to avoid exposing sensitive values in ARM deployment history.
