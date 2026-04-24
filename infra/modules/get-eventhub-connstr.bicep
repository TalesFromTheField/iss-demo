// ---------------------------------------------------------------------------
// Helper Module: Retrieve Event Hubs Connection String
// Queries an existing Event Hubs namespace and outputs the connection string.
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Name of the Event Hubs namespace.')
param eventHubNamespaceName string

@description('Name of the resource group (for querying existing resource).')
param resourceGroupName string

// ── Resource Reference (Existing) ───────────────────────────────────────────

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' existing = {
  name: eventHubNamespaceName
}

// ── Retrieve Connection String ──────────────────────────────────────────────

resource rootManageRule 'Microsoft.EventHub/namespaces/authorizationRules@2024-01-01' existing = {
  name: 'RootManageSharedAccessKey'
  parent: eventHubNamespace
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('Primary connection string for the Event Hubs namespace.')
output connectionString string = rootManageRule.listKeys().primaryConnectionString
