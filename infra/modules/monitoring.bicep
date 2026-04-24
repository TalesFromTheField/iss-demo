// ---------------------------------------------------------------------------
// Module: monitoring.bicep
// Provisions Log Analytics Workspace, Application Insights, and metric alerts
// for the ISS Demo Function App.
// ---------------------------------------------------------------------------

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Environment name used for resource naming (e.g. dev, staging, prod).')
param environmentName string

@description('Azure region for all resources in this module.')
param location string

@description('Name of the Function App (informational; for backward compatibility).')
param functionAppName string = ''

@description('Resource ID of the Function App (for backward compatibility; used in alert display names).')
param functionAppResourceId string = ''

@description('Name of the Container App (informational; used in alert display names).')
param containerAppName string = ''

@description('Resource ID of the Container App to scope metric alerts against. When empty, alert rules are not deployed.')
param containerAppResourceId string = ''

// ── Variables ───────────────────────────────────────────────────────────────

var normalizedEnvironmentName = toLower(replace(replace(replace(environmentName, ' ', '-'), '_', '-'), '.', '-'))
var logAnalyticsName = 'law-iss-${normalizedEnvironmentName}'
var appInsightsName = 'appi-iss-${normalizedEnvironmentName}'

// Use Container App resource ID if provided, otherwise fall back to Function App
var effectiveAppResourceId = !empty(containerAppResourceId) ? containerAppResourceId : functionAppResourceId
var effectiveAppName = !empty(containerAppName) ? containerAppName : functionAppName

var alertsEnabled = !empty(effectiveAppResourceId)

// ── Log Analytics Workspace ─────────────────────────────────────────────────

@description('Log Analytics Workspace that backs Application Insights.')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ── Application Insights ────────────────────────────────────────────────────

@description('Application Insights instance connected to the Log Analytics Workspace.')
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    RetentionInDays: 30
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ── Metric Alert: Function Execution Failures ───────────────────────────────

@description('Fires when Function App execution failures exceed 5 within a 5-minute window.')
resource failureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (alertsEnabled && !empty(functionAppResourceId)) {
  name: 'alert-func-failures-${normalizedEnvironmentName}'
  location: 'global'
  properties: {
    description: 'Function execution failures exceeded threshold (>5 in 5 min) for ${effectiveAppName}.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      effectiveAppResourceId
    ]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FunctionExecutionFailures'
          metricName: 'FunctionExecutionCount'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          dimensions: [
            {
              name: 'FunctionExecutionStatus'
              operator: 'Include'
              values: [
                'Failed'
              ]
            }
          ]
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.Web/sites'
    targetResourceRegion: location
  }
}

// ── Metric Alert: Zero Successful Executions (Function Stopped) ─────────────

@description('Fires when there are zero successful Function executions over a 10-minute window, indicating the Function App may have stopped.')
resource stoppedAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (alertsEnabled && !empty(functionAppResourceId)) {
  name: 'alert-func-stopped-${normalizedEnvironmentName}'
  location: 'global'
  properties: {
    description: 'No successful function executions detected in the last 10 minutes for ${effectiveAppName}. The Function App may have stopped.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [
      effectiveAppResourceId
    ]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ZeroSuccessfulExecutions'
          metricName: 'FunctionExecutionCount'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'LessThanOrEqual'
          threshold: 0
          timeAggregation: 'Total'
          dimensions: [
            {
              name: 'FunctionExecutionStatus'
              operator: 'Include'
              values: [
                'Completed'
              ]
            }
          ]
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.Web/sites'
    targetResourceRegion: location
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('Application Insights connection string for the Function App configuration.')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Application Insights instrumentation key (legacy; prefer connection string).')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('Resource ID of the Log Analytics Workspace.')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
