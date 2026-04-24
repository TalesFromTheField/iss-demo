// ---------------------------------------------------------------------------
// Module: Event Hubs infrastructure for ISS Demo
// ---------------------------------------------------------------------------

@description('Environment name used for resource naming (e.g., dev, prod).')
param environmentName string

@description('Azure region for all resources.')
param location string

// ---------------------------------------------------------------------------
// Event Hubs Namespace (Standard tier — required for Fabric EventStream)
// ---------------------------------------------------------------------------

var envToken = toLower(replace(replace(replace(environmentName, '-', ''), '_', ''), '.', ''))
var namespaceName = take('evhnsiss${envToken}', 50)

resource namespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    isAutoInflateEnabled: false
    minimumTlsVersion: '1.2'
  }
}

// ---------------------------------------------------------------------------
// Event Hub: iss-location
// ---------------------------------------------------------------------------

resource issLocationHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  name: 'iss-location'
  parent: namespace
  properties: {
    partitionCount: 1
    messageRetentionInDays: 1
  }
}

resource issLocationFabricCg 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  name: 'fabric-eventstream'
  parent: issLocationHub
  properties: {}
}

// ---------------------------------------------------------------------------
// Event Hub: astronauts
// ---------------------------------------------------------------------------

resource astronautsHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  name: 'astronauts'
  parent: namespace
  properties: {
    partitionCount: 1
    messageRetentionInDays: 1
  }
}

resource astronautsFabricCg 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  name: 'fabric-eventstream'
  parent: astronautsHub
  properties: {}
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('The name of the Event Hubs namespace.')
output namespaceName string = namespace.name

@description('The fully qualified domain name of the Event Hubs namespace.')
output namespaceFqdn string = '${namespace.name}.servicebus.windows.net'

@description('The name of the ISS location Event Hub.')
output issLocationHubName string = issLocationHub.name

@description('The name of the astronauts Event Hub.')
output astronautsHubName string = astronautsHub.name
