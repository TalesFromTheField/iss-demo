// ---------------------------------------------------------------------------
// Module: RBAC role assignments for ISS Demo
// Grants the Function App's managed identity the Azure Event Hubs Data Sender
// role scoped to the Event Hubs namespace (least-privilege).
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('The principal ID of the Function App system-assigned Managed Identity.')
param principalId string

@description('Full resource ID of the Event Hubs namespace (used for scoping).')
#disable-next-line no-unused-params
param eventHubNamespaceResourceId string

@description('Name of the existing Event Hubs namespace.')
param eventHubNamespaceName string

// ── Variables ───────────────────────────────────────────────────────────────

@description('Built-in role definition ID for Azure Event Hubs Data Sender.')
var eventHubsDataSenderRoleId = '2b629674-e913-4c01-ae53-ef4638d8f975'

// ── Existing Resource Reference ─────────────────────────────────────────────

@description('Reference to the existing Event Hubs namespace for scoping the role assignment.')
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' existing = {
  name: eventHubNamespaceName
}

// ── Role Assignment ─────────────────────────────────────────────────────────

@description('Assigns the Azure Event Hubs Data Sender role to the Function App managed identity, scoped to the Event Hubs namespace.')
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHubNamespace.id, principalId, eventHubsDataSenderRoleId)
  scope: eventHubNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventHubsDataSenderRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('The resource ID of the role assignment.')
output roleAssignmentId string = roleAssignment.id
