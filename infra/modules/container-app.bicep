// ---------------------------------------------------------------------------
// Module: Container App infrastructure for ISS Demo
// Provisions a Container App Environment and Container App resource
// running the ISS Demo scheduler, which streams directly to Fabric.
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Environment name used for resource naming (e.g., dev, prod).')
param environmentName string

@description('Azure region for all resources.')
param location string

@description('Application Insights connection string for telemetry.')
param appInsightsConnectionString string

@description('Eventhouse Query URI from the Fabric portal. Set after running deploy-fabric scripts.')
param fabricIngestionUri string = ''

@description('Fabric KQL Database name to ingest data into.')
param fabricDatabaseName string = 'iss-demo-kqldb'

@description('KQL table name for ISS location records.')
param fabricIssTable string = 'ISS_Loc'

@description('KQL table name for astronaut records.')
param fabricAstronautsTable string = 'Astronauts'

@description('Container image URI (e.g., ghcr.io/talesfromthefield/iss-demo:latest).')
param containerImageUri string

// ── Variables ───────────────────────────────────────────────────────────────

var normalizedEnvironmentName = toLower(replace(replace(replace(environmentName, ' ', '-'), '_', '-'), '.', '-'))
var containerAppEnvName = 'cae-iss-${normalizedEnvironmentName}'
var containerAppName = 'ca-iss-${normalizedEnvironmentName}'
var logAnalyticsWorkspaceName = 'law-iss-${normalizedEnvironmentName}'

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
              name: 'FabricIngestionUri'
              value: fabricIngestionUri
            }
            {
              name: 'FabricDatabaseName'
              value: fabricDatabaseName
            }
            {
              name: 'FabricIssTable'
              value: fabricIssTable
            }
            {
              name: 'FabricAstronautsTable'
              value: fabricAstronautsTable
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
