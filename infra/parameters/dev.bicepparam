using '../main.bicep'

param environmentName = 'dev'
param location = 'eastus2'

// Fabric bootstrap — values injected from GitHub Actions secrets at deploy time.
// The CD pipeline sets these as environment variables; bicepparam reads them via readEnvironmentVariable().
param fabricTenantId  = readEnvironmentVariable('AZURE_TENANT_ID', '')
param fabricClientId  = readEnvironmentVariable('AZURE_CLIENT_ID', '')
param fabricClientSecret = readEnvironmentVariable('AZURE_CLIENT_SECRET', '')
param fabricWorkspaceName = 'iss-demo'
param adminEmail = readEnvironmentVariable('AZURE_ADMIN_EMAIL', '')
param deployPbiReport = false
