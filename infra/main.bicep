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

// ── Module: Function App ────────────────────────────────────────────────────

module functionApp 'modules/function-app.bicep' = {
  name: 'function-app'
  params: {
    environmentName: environmentName
    location: location
    eventHubNamespaceFqdn: eventHubs.outputs.namespaceFqdn
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    issLocationHubName: eventHubs.outputs.issLocationHubName
    astronautsHubName: eventHubs.outputs.astronautsHubName
  }
}

// ── Module: Monitoring Alerts (re-deploy with Function App info) ────────────

module monitoringAlerts 'modules/monitoring.bicep' = {
  name: 'monitoring-alerts'
  params: {
    environmentName: environmentName
    location: location
    functionAppName: functionApp.outputs.functionAppName
    functionAppResourceId: functionApp.outputs.functionAppResourceId
  }
}

// ── Module: Role Assignments ────────────────────────────────────────────────

module roleAssignments 'modules/role-assignments.bicep' = {
  name: 'role-assignments'
  params: {
    principalId: functionApp.outputs.functionAppPrincipalId
    eventHubNamespaceResourceId: resourceId('Microsoft.EventHub/namespaces', eventHubs.outputs.namespaceName)
    eventHubNamespaceName: eventHubs.outputs.namespaceName
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('Fully qualified domain name of the Event Hubs namespace.')
output eventHubNamespaceFqdn string = eventHubs.outputs.namespaceFqdn

@description('Name of the deployed Function App.')
output functionAppName string = functionApp.outputs.functionAppName

// App Insights connection string intentionally omitted from outputs
// to avoid exposing sensitive values in ARM deployment history.
