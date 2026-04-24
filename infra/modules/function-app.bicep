// ---------------------------------------------------------------------------
// Module: Function App infrastructure for ISS Demo
// Provisions a Storage Account, Consumption App Service Plan, and Linux
// Python 3.11 Function App with system-assigned Managed Identity.
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Environment name used for resource naming (e.g., dev, prod).')
param environmentName string

@description('Azure region for all resources.')
param location string

@description('Fully qualified domain name of the Event Hubs namespace (e.g., evhns-iss-dev.servicebus.windows.net).')
param eventHubNamespaceFqdn string

@description('Application Insights connection string for telemetry.')
param appInsightsConnectionString string

@description('Name of the ISS location Event Hub.')
param issLocationHubName string = 'iss-location'

@description('Name of the astronauts Event Hub.')
param astronautsHubName string = 'astronauts'

// ── Variables ───────────────────────────────────────────────────────────────

// Storage account names must be 3-24 characters, lowercase alphanumeric only.
var normalizedEnvironmentName = toLower(replace(replace(replace(environmentName, ' ', '-'), '_', '-'), '.', '-'))
var envToken = replace(normalizedEnvironmentName, '-', '')
var storageSuffix = take(uniqueString(subscription().id, resourceGroup().id, environmentName), 6)
var storageAccountName = take('stissf${envToken}${storageSuffix}', 24)
var appServicePlanName = 'asp-iss-${normalizedEnvironmentName}'
var functionAppName    = 'func-iss-${normalizedEnvironmentName}'

// ── Storage Account (Functions runtime) ─────────────────────────────────────

@description('Storage account used by the Functions runtime for triggers, logging, and state.')
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// ── App Service Plan (Consumption Y1, Linux) ────────────────────────────────

@description('Consumption (Y1) App Service Plan for the Function App.')
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// ── Function App (Python 3.11, Linux) ───────────────────────────────────────

@description('Linux Python 3.11 Function App with system-assigned Managed Identity.')
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
      appSettings: [
        {
          name: 'EventHubConnection__fullyQualifiedNamespace'
          value: eventHubNamespaceFqdn
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
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
      ]
    }
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('The name of the Function App resource.')
output functionAppName string = functionApp.name

@description('The principal ID of the Function App system-assigned Managed Identity (for RBAC assignments).')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('The resource ID of the Function App.')
output functionAppResourceId string = functionApp.id
