// ---------------------------------------------------------------------------
// Module: Container App infrastructure for ISS Demo
// Provisions a Container App Environment and Container App resource
// running the ISS Demo scheduler.
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Environment name used for resource naming (e.g., dev, prod).')
param environmentName string

@description('Azure region for all resources.')
param location string

@description('Application Insights connection string for telemetry.')
param appInsightsConnectionString string

@description('Name of the ISS location Event Hub.')
param issLocationHubName string = 'iss-location'

@description('Name of the astronauts Event Hub.')
param astronautsHubName string = 'astronauts'

@description('Name of the Event Hubs namespace used for fallback connection-string lookup.')
param eventHubNamespaceName string

@description('Container image URI (e.g., acrissdev.azurecr.io/iss-demo:latest).')
param containerImageUri string

@description('Event Hubs namespace connection string (for event publishing).')
@secure()
param eventHubConnectionString string = ''

// ── Variables ───────────────────────────────────────────────────────────────

var normalizedEnvironmentName = toLower(replace(replace(replace(environmentName, ' ', '-'), '_', '-'), '.', '-'))
var containerAppEnvName = 'cae-iss-${normalizedEnvironmentName}'
var containerAppName = 'ca-iss-${normalizedEnvironmentName}'
var logAnalyticsWorkspaceName = 'law-iss-${normalizedEnvironmentName}'
var effectiveEventHubConnectionString = !empty(eventHubConnectionString)
  ? eventHubConnectionString
  : listKeys(resourceId('Microsoft.EventHub/namespaces/authorizationRules', eventHubNamespaceName, 'RootManageSharedAccessKey'), '2024-01-01').primaryConnectionString

// ── Outputs (for querying Log Analytics) ────────────────────────────────────

// Note: In a full implementation, we would query the existing Log Analytics workspace
// and pass its resource ID. For now, we'll rely on the monitoring module to provide it.

// ── Container App Environment ───────────────────────────────────────────────

@description('Container App Environment for ISS Demo.')
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

// Query the Log Analytics workspace created by the monitoring module
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

// ── Container App ──────────────────────────────────────────────────────────

@description('Container App running the ISS Demo scheduler.')
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppEnvironment.id
    configuration: {
      // No explicit registry credentials needed — container app uses managed identity for ACR pulls
      // (requires AcrPull role assignment via RBAC in role-assignments module)
    }
    template: {
      containers: [
        {
          image: containerImageUri
          name: 'iss-demo-scheduler'
          env: [
            {
              name: 'EventHubConnection'
              value: effectiveEventHubConnectionString
            }
            {
              name: 'IssLocationHubName'
              value: issLocationHubName
            }
            {
              name: 'AstronautsHubName'
              value: astronautsHubName
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsightsConnectionString
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('The name of the Container App.')
output containerAppName string = containerApp.name

@description('The principal ID of the Container App system-assigned Managed Identity.')
output containerAppPrincipalId string = containerApp.identity.principalId

@description('The resource ID of the Container App.')
output containerAppResourceId string = containerApp.id

@description('The FQDN of the Container App (if ingress is external).')
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
