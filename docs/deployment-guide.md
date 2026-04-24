# Deployment Guide

This guide covers the supported deployment path for the ISS demo.

The intended customer flow is:

1. Click the Deploy to Azure button.
2. Let Azure provision the infrastructure.
3. Let the deployed Container App run from the public image published from repository releases.
4. Complete the Fabric and Power BI setup.

No local Docker build is required for customers using the Deploy to Azure button.

## One-Click Azure Deployment

Use the repository's Deploy to Azure button for portal-based provisioning:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FTalesFromTheField%2Fiss-demo%2Fmain%2Finfra%2Fazuredeploy.json)

The deployment provisions:

- Event Hubs namespace with `iss-location` and `astronauts`
- Azure Container Registry
- Container Apps environment and Container App
- Application Insights and Log Analytics
- RBAC for the Container App managed identity

By default, the Container App uses the public image `ghcr.io/talesfromthefield/iss-demo:latest`, which is published by the repository's release workflow.

## Step 1: Deploy Azure Resources

1. Click the Deploy to Azure button.
2. Choose the Azure subscription and resource group.
3. Set `environmentName` and `location`.
4. Review the template parameters.
5. Start the deployment.

Optional:

- You can override `containerImageUri` if you want to deploy a different published image.
- Most customers should keep the default image value.

Checkpoint:

```bash
az containerapp show \
  --name ca-iss-dev \
  --resource-group rg-iss-demo-dev \
  --query "properties.provisioningState" -o tsv

az containerapp show \
  --name ca-iss-dev \
  --resource-group rg-iss-demo-dev \
  --query "properties.template.containers[0].image" -o tsv
```

Expected results:

- Provisioning state is `Succeeded`
- Image is `ghcr.io/talesfromthefield/iss-demo:latest` or your override

## Step 2: Configure Fabric

Follow the [Fabric Setup Guide](./fabric-setup.md) to:

1. Create an Eventhouse and KQL Database, or run `scripts/deploy-fabric.sh` / `scripts/deploy-fabric.ps1`
2. Create two EventStreams:
   - `iss-location` Event Hub to `ISS_Loc`
   - `astronauts` Event Hub to `Astronauts`
3. Verify data is flowing into the KQL Database

The Container App starts the APScheduler worker automatically. It polls the ISS APIs, sends events to Event Hubs, and Fabric ingests them into KQL.

Checkpoint:

```kql
ISS_Loc
| count

Astronauts
| count
```

Both counts should increase over time.

## Step 3: Import the Power BI Dashboard

1. Open `PBI/ISS.pbix` in Power BI Desktop.
2. Update the parameters:
   - `kusto_db_url`: your KQL Database URI
   - `kusto_db_name`: `iss-demo-kqldb`
3. Refresh the report.
4. Configure page refresh for every 5 seconds.
5. Publish the report to your Fabric workspace.

## Step 4: Validate

Use this smoke test checklist:

- [ ] Container App is provisioned

  ```bash
  az containerapp show \
    --name ca-iss-dev \
    --resource-group rg-iss-demo-dev \
    --query "properties.provisioningState" -o tsv
  ```

- [ ] Container App is using the expected image

  ```bash
  az containerapp show \
    --name ca-iss-dev \
    --resource-group rg-iss-demo-dev \
    --query "properties.template.containers[0].image" -o tsv
  ```

- [ ] Scheduler startup appears in logs

  ```bash
  az containerapp logs show \
    --name ca-iss-dev \
    --resource-group rg-iss-demo-dev \
    --follow
  ```

- [ ] Event Hubs are receiving messages
- [ ] Fabric KQL tables contain data
- [ ] Power BI refreshes with current ISS position

## Maintainer Override: Custom Image Build

Customers using the deploy button do not need this section.

Maintainers can still build a custom image and deploy it by overriding `containerImageUri` in the template or updating the Container App after deployment.

```bash
docker build -t iss-demo:custom .
```

## Troubleshooting

| Problem | Likely Cause | Solution |
| --- | --- | --- |
| Container App is provisioned but not starting | The published image is unavailable or the revision failed | Check `az containerapp logs show -n ca-iss-dev -g rg-iss-demo-dev --follow` |
| Container App is using the wrong image | Template override or stale revision | Check `containerImageUri` in the deployment and verify the deployed revision |
| No events in Event Hubs | Scheduler failed at runtime | Review Container App logs and Application Insights |
| Fabric EventStream shows no data | EventStream source or consumer group is wrong | Verify `fabric-eventstream` is selected for both Event Hubs |
| Power BI shows stale data | Auto-refresh or connection is misconfigured | Recheck the KQL connection parameters and refresh settings |

## Architecture Reference

```text
Deploy to Azure button
  │
  └── ARM template wrapper → Bicep deployment
        ├── Event Hubs namespace
        ├── Azure Container Registry
        ├── Container Apps environment
        ├── Container App
        ├── Application Insights
        └── RBAC assignments

Public release image
  └── GHCR package → Container App image pull

Fabric setup
  ├── EventStreams ← Event Hubs
  ├── KQL Database ← EventStreams
  └── Power BI ← KQL Database
```

For broader context, see [docs/architecture.md](./architecture.md) and [docs/code-walkthrough.md](./code-walkthrough.md).
