# Demo Acceptance Criteria

This document defines when the ISS demo is considered complete and working.

## Definition of Done

The demo is complete when a new user can:

1. Clone the repository.
2. Use the Deploy to Azure button to provision the Azure resources.
3. Complete Fabric setup.
4. Open Power BI and see live ISS updates.

Target time: less than 30 minutes from start to live dashboard.

## End-to-End Acceptance Test

### Prerequisites Verified

- [ ] Azure subscription with Contributor access
- [ ] Fabric workspace with capacity
- [ ] Azure resources can be created in the selected subscription

### Azure Deployment

- [ ] Deploy to Azure button deployment completes without errors
- [ ] Azure Container Registry is created
- [ ] Container App is created
- [ ] Container App is deployed with the published GHCR image

### Container App

- [ ] Container App provisioning state is `Succeeded`
- [ ] Container App logs show the scheduler starting
- [ ] ISS location events are emitted every ~5 seconds
- [ ] Astronaut events are emitted every ~1 minute

### Event Hubs

- [ ] `iss-location` hub receives messages
- [ ] `astronauts` hub receives messages
- [ ] `fabric-eventstream` consumer groups exist on both hubs

### Fabric Resources

- [ ] Eventhouse exists
- [ ] KQL Database exists and is attached to the Eventhouse
- [ ] ISS Location EventStream connects Event Hub to KQL Database
- [ ] Astronauts EventStream connects Event Hub to KQL Database

### KQL Database

- [ ] `ISS_Loc` table exists and contains records
- [ ] `Astronauts` table exists and contains records
- [ ] Record counts increase over time
- [ ] Queries from `kql/ISS.kql` return valid results

### Power BI Dashboard

- [ ] Dashboard connects to the KQL Database
- [ ] ISS position renders on the map
- [ ] Orbital trajectory visualization works
- [ ] Astronaut list displays the current crew
- [ ] Auto-refresh updates the dashboard every 5 seconds

## Quick Smoke Test Commands

```bash
az containerapp show \
  --name ca-iss-dev \
  --resource-group rg-iss-demo-dev \
  --query "properties.provisioningState" -o tsv

az containerapp show \
  --name ca-iss-dev \
  --resource-group rg-iss-demo-dev \
  --query "properties.template.containers[0].image" -o tsv

az containerapp logs show \
  --name ca-iss-dev \
  --resource-group rg-iss-demo-dev \
  --follow

az monitor metrics list \
  --resource "/subscriptions/<SUB_ID>/resourceGroups/rg-iss-demo-dev/providers/Microsoft.EventHub/namespaces/evhns-iss-dev/eventhubs/iss-location" \
  --metric "IncomingMessages" \
  --interval PT5M \
  --query "value[0].timeseries[0].data[-1].total" -o tsv
```

## Failure Modes and Recovery

| Failure | Detection | Recovery |
| --- | --- | --- |
| Container App crash loop | Logs show restart or startup failures | Check Container App logs, fix image or settings, redeploy image if needed |
| Open Notify API down | Warning logs and no new events | Automatic recovery when the upstream API returns |
| Event Hub quota exceeded | Throttling errors in logs | Upgrade tier or reduce polling frequency |
| Fabric EventStream disconnected | KQL tables stop growing | Reconnect the EventStream and verify Event Hub connectivity |
| Power BI refresh failure | Stale dashboard | Verify KQL parameters and refresh settings |

## Success Metrics

When everything is working, you should see:

- About 12 ISS location events per minute
- About 1 astronaut event per minute
- Less than 10 seconds from poll to Power BI refresh
- No persistent failures in the Container App logs
