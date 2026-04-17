# ✅ Demo Acceptance Criteria

> How do you know the ISS Demo is working? This document defines "done" and provides a smoke test checklist.

## 🎯 Definition of Done

The demo is **complete and working** when a new user can:

1. Fork/clone the repository
2. Configure OIDC credentials and GitHub secrets
3. Push to `main` to trigger automated deployment
4. Complete Fabric setup (manual, ~15 min)
5. See live ISS coordinates updating on a Power BI dashboard

**Target time: < 30 minutes from start to live dashboard.**

## 🔍 End-to-End Acceptance Test

### Prerequisites Verified

- [ ] Azure subscription with Contributor access
- [ ] Fabric workspace with capacity
- [ ] GitHub secrets configured (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID)
- [ ] Resource group created

### Azure Deployment (Automated)

- [ ] CI pipeline passes: lint ✅, unit tests ✅, Bicep validation ✅
- [ ] CD pipeline deploys infrastructure without errors
- [ ] CD pipeline deploys Function App without errors
- [ ] Post-deploy smoke test passes

### Function App

- [ ] Function App state is `Running`
- [ ] `get_iss_location` function is registered and executing every ~5 seconds
- [ ] `get_astronauts` function is registered and executing every ~1 minute
- [ ] Application Insights shows successful executions (no persistent failures)

### Event Hubs

- [ ] `iss-location` hub receiving messages (IncomingMessages > 0)
- [ ] `astronauts` hub receiving messages (IncomingMessages > 0)
- [ ] `fabric-eventstream` consumer groups exist on both hubs

### Fabric Resources

- [ ] Eventhouse created
- [ ] KQL Database created and attached to Eventhouse
- [ ] ISS Location EventStream: source → Event Hub, destination → KQL DB
- [ ] Astronauts EventStream: source → Event Hub, destination → KQL DB

### KQL Database

- [ ] `ISS_Loc` table exists and has records
- [ ] `Astronauts` table exists and has records
- [ ] Record counts are increasing over time
- [ ] KQL queries from `kql/ISS.kql` return valid results

### Power BI Dashboard

- [ ] Dashboard connects to KQL Database
- [ ] ISS position shows on map
- [ ] Orbital trajectory visualization works
- [ ] Astronaut list displays current crew
- [ ] Auto-refresh updates the dashboard every 5 seconds

## 🧪 Quick Smoke Test Commands

```bash
# Check Function App status
az functionapp show --name func-iss-dev --resource-group rg-iss-demo-dev --query "state" -o tsv

# List registered functions
az functionapp function list --name func-iss-dev --resource-group rg-iss-demo-dev --query "[].name" -o tsv

# Check Event Hub metrics (last 5 minutes)
az monitor metrics list \
  --resource "/subscriptions/<SUB_ID>/resourceGroups/rg-iss-demo-dev/providers/Microsoft.EventHub/namespaces/evhns-iss-dev/eventhubs/iss-location" \
  --metric "IncomingMessages" \
  --interval PT5M \
  --query "value[0].timeseries[0].data[-1].total" -o tsv

# Check Application Insights for recent executions
az monitor app-insights query \
  --app appi-iss-dev \
  --analytics-query "requests | where timestamp > ago(5m) | summarize count() by name"
```

## 🚨 Failure Modes & Recovery

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Function App crash loop | App Insights alerts, zero executions | Check logs, redeploy via CD |
| Open Notify API down | Warning logs, no new events | Automatic recovery when API returns (retry logic handles transient failures) |
| Event Hub quota exceeded | Throttling errors in logs | Upgrade to higher tier or reduce polling frequency |
| Fabric EventStream disconnected | KQL tables stop growing | Reconnect in Fabric portal, check Event Hub connection |
| Power BI refresh failure | Stale dashboard | Verify KQL DB URI parameter, re-authenticate |

## 📊 Success Metrics

When everything is working, you should see:

- **~12 ISS location events/minute** (every 5 seconds)
- **~1 astronaut event/minute** (every minute)
- **< 10 second latency** from API poll to Power BI refresh
- **Zero persistent failures** in Application Insights (transient retries are OK)
