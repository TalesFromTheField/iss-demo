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

@description('Container image URI (e.g., acrissdev.azurecr.io/iss-demo:latest or docker.io/org/iss-demo:latest).')
param containerImageUri string = ''

@description('Azure Container Registry login server (only required if using private ACR).')
param acrLoginServer string = ''

@description('Azure Container Registry admin username (only required if using private ACR).')
param acrAdminUsername string = ''

@description('Azure Container Registry admin password (only required if using private ACR).')
@secure()
param acrAdminPassword string = ''

@description('Event Hubs connection string (for container app environment).')
@secure()
param eventHubConnectionString string = ''

// ── Module: Event Hubs ──────────────────────────────────────────────────────

module eventHubs 'modules/event-hubs.bicep' = {
  name: 'event-hubs'
  params: {
    environmentName: environmentName
    location: location
  }
}

// ── Module: Monitoring (base — Log Analytics + App Insights) ────────────────

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    environmentName: environmentName
    location: location
  }
}

// ── Module: Container Registry ──────────────────────────────────────────────

module containerRegistry 'modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    environmentName: environmentName
    location: location
  }
}

// ── Module: Container App ──────────────────────────────────────────────────

// Determine effective image URI (use provided image or construct from ACR)
var effectiveImageUri = !empty(containerImageUri) 
  ? containerImageUri 
  : '${containerRegistry.outputs.loginServer}/iss-demo:latest'

var effectiveAcrLoginServer = !empty(acrLoginServer) ? acrLoginServer : containerRegistry.outputs.loginServer
var effectiveAcrAdminUsername = !empty(acrAdminUsername) ? acrAdminUsername : 'admin'
var effectiveAcrAdminPassword = !empty(acrAdminPassword) ? acrAdminPassword : ''

// For Event Hub connection string, retrieve it from the Event Hubs namespace if not provided
module eventHubsConnStr 'modules/get-eventhub-connstr.bicep' = if (empty(eventHubConnectionString)) {
  name: 'get-eventhub-connstr'
  params: {
    eventHubNamespaceName: eventHubs.outputs.namespaceName
    resourceGroupName: resourceGroup().name
  }
}

var effectiveEventHubConnectionString = !empty(eventHubConnectionString)
  ? eventHubConnectionString
  : eventHubsConnStr.outputs.connectionString

module containerApp 'modules/container-app.bicep' = {
  name: 'container-app'
  params: {
    environmentName: environmentName
    location: location
    eventHubNamespaceFqdn: eventHubs.outputs.namespaceFqdn
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    issLocationHubName: eventHubs.outputs.issLocationHubName
    astronautsHubName: eventHubs.outputs.astronautsHubName
    containerImageUri: effectiveImageUri
    acrLoginServer: effectiveAcrLoginServer
    acrAdminUsername: effectiveAcrAdminUsername
    acrAdminPassword: effectiveAcrAdminPassword
    eventHubConnectionString: effectiveEventHubConnectionString
  }
}

// ── Module: Monitoring Alerts (re-deploy with Container App info) ──────────

module monitoringAlerts 'modules/monitoring.bicep' = {
  name: 'monitoring-alerts'
  params: {
    environmentName: environmentName
    location: location
    containerAppName: containerApp.outputs.containerAppName
    containerAppResourceId: containerApp.outputs.containerAppResourceId
  }
}

// ── Module: Role Assignments ────────────────────────────────────────────────

module roleAssignments 'modules/role-assignments.bicep' = {
  name: 'role-assignments'
  params: {
    principalId: containerApp.outputs.containerAppPrincipalId
    eventHubNamespaceResourceId: resourceId('Microsoft.EventHub/namespaces', eventHubs.outputs.namespaceName)
    eventHubNamespaceName: eventHubs.outputs.namespaceName
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
