// ---------------------------------------------------------------------------
// Module: RBAC role assignments for ISS Demo
// Grants the Container App managed identity the AcrPull role on the
// Container Registry so it can pull images without stored credentials.
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('The principal ID of the Container App system-assigned Managed Identity.')
param principalId string

@description('Full resource ID of the Azure Container Registry (optional).')
param acrResourceId string = ''

// ── Variables ───────────────────────────────────────────────────────────────

@description('Built-in role definition ID for AcrPull.')
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// ── Existing Resource Reference ─────────────────────────────────────────────

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (!empty(acrResourceId)) {
  name: last(split(acrResourceId, '/'))
}

// ── Role Assignments ────────────────────────────────────────────────────────

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

@description('The resource ID of the ACR pull role assignment (if ACR provided).')
output acrRoleAssignmentId string = !empty(acrResourceId) ? acrRoleAssignment.id : ''

