// ---------------------------------------------------------------------------
// Module: RBAC role assignments for ISS Demo
// Grants the Container App managed identity roles for:
//   - Azure Event Hubs Data Sender (Event Hubs namespace)
//   - AcrPull (Container Registry)
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('The principal ID of the Container App system-assigned Managed Identity.')
param principalId string

@description('Full resource ID of the Event Hubs namespace (used for scoping, kept for backward compatibility).')
#disable-next-line no-unused-params
param eventHubNamespaceResourceId string

@description('Name of the existing Event Hubs namespace.')
param eventHubNamespaceName string

@description('Full resource ID of the Azure Container Registry (optional).')
param acrResourceId string = ''

// ── Variables ───────────────────────────────────────────────────────────────

@description('Built-in role definition ID for Azure Event Hubs Data Sender.')
var eventHubsDataSenderRoleId = '2b629674-e913-4c01-ae53-ef4638d8f975'

@description('Built-in role definition ID for AcrPull.')
var acrPullRoleId = '7f951dda-4ed3-468d-8ac7-5cbf6c5e8b58'

// ── Existing Resource Reference ─────────────────────────────────────────────

@description('Reference to the existing Event Hubs namespace for scoping the role assignment.')
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' existing = {
  name: eventHubNamespaceName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (!empty(acrResourceId)) {
  name: last(split(acrResourceId, '/'))
}

// ── Role Assignments ────────────────────────────────────────────────────────

@description('Assigns the Azure Event Hubs Data Sender role to the Container App managed identity, scoped to the Event Hubs namespace.')
resource ehRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHubNamespace.id, principalId, eventHubsDataSenderRoleId)
  scope: eventHubNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventHubsDataSenderRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Assigns the AcrPull role to the Container App managed identity, scoped to the Container Registry.')
resource acrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(acrResourceId)) {
  name: guid(acrResourceId, principalId, acrPullRoleId)
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('The resource ID of the Event Hubs role assignment.')
output ehRoleAssignmentId string = ehRoleAssignment.id

@description('The resource ID of the ACR pull role assignment (if ACR provided).')
output acrRoleAssignmentId string = !empty(acrResourceId) ? acrRoleAssignment.id : ''
