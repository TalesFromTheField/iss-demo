// ---------------------------------------------------------------------------
// Module: Azure Container Registry for ISS Demo
// Provisions a container registry for storing the ISS Demo container image.
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Environment name used for resource naming (e.g., dev, prod).')
param environmentName string

@description('Azure region for the container registry.')
param location string

// ── Variables ───────────────────────────────────────────────────────────────

// ACR names must be 5-50 characters, lowercase alphanumeric only (no hyphens).
var acrName = 'acriss${environmentName}'

// ── Container Registry ──────────────────────────────────────────────────────

@description('Azure Container Registry for ISS Demo container images.')
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('The name of the container registry.')
output registryName string = containerRegistry.name

@description('The login server URL of the container registry.')
output loginServer string = containerRegistry.properties.loginServer

@description('The resource ID of the container registry.')
output registryResourceId string = containerRegistry.id
