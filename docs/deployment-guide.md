# 🚀 Deployment Guide

> From zero to live ISS tracking — here's the happy path!

This guide walks you through deploying the full ISS Demo stack: Azure infrastructure via Bicep, Microsoft Fabric real-time analytics, and a Power BI dashboard that tracks the International Space Station across the globe. Buckle up! 🛰️

## 📋 Prerequisites

Before you begin, make sure you have:

- **Azure subscription** with permissions to create resources
- **Microsoft Fabric workspace** with capacity assigned
- **GitHub repository** forked/cloned
- **Azure CLI** installed (`az --version`)
- **GitHub CLI** (optional, for creating secrets)

### OIDC Setup (One-Time)

GitHub Actions authenticates to Azure using OpenID Connect — no stored secrets needed! 🔐

1. **Create an Entra App Registration**
   - Navigate to Azure Portal → Entra ID → App registrations → New registration
   - Name it something memorable (e.g., `iss-demo-github-actions`)

2. **Add federated credentials for GitHub Actions**
   - In the App Registration → Certificates & secrets → Federated credentials → Add credential
   - Issuer: `https://token.actions.githubusercontent.com`
   - **Primary (required for CD):** Subject identifier: `repo:talesfromthefield/iss-demo:environment:dev` — Name: `github-actions-dev-env`
   - **Optional (for CI on main):** Subject identifier: `repo:talesfromthefield/iss-demo:ref:refs/heads/main` — Name: `github-actions-main`

   > ⚠️ **Important:** The CD workflow uses `environment: dev`, so the `environment:dev` credential is **required**. The `ref:refs/heads/main` credential only matches jobs without an environment.

3. **Note the following values** (you'll need them for GitHub secrets):
   - `CLIENT_ID` — from the App Registration overview
   - `TENANT_ID` — from the App Registration overview
   - `SUBSCRIPTION_ID` — from your Azure subscription

4. **Create a resource group:**
   ```bash
   az group create -n rg-iss-demo-dev -l eastus2
   ```

5. **Grant the app registration Owner role on the resource group:**
   ```bash
   az role assignment create \
     --assignee <CLIENT_ID> \
     --role Owner \
     --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-iss-demo-dev
   ```

   > ⚠️ **Why Owner?** The Bicep deployment creates RBAC role assignments (Function App MI → Event Hubs Data Sender). The `Contributor` role cannot create role assignments — you need `Owner` or `Contributor` + `User Access Administrator`.

### GitHub Secrets

Add these secrets to the repository (Settings → Secrets and variables → Actions → New repository secret):

| Secret Name              | Value                          |
|--------------------------|--------------------------------|
| `AZURE_CLIENT_ID`       | App Registration Client ID     |
| `AZURE_TENANT_ID`       | Entra Tenant ID                |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID          |

> 🛡️ **Security note:** These are non-sensitive identifiers — the actual auth happens via OIDC federation. No passwords or client secrets needed!

## Step 1: Deploy Azure Resources ☁️ (~5 min)

Push to `main` or manually trigger the CD workflow. This deploys:

- **Event Hubs namespace** (Standard tier) with 2 hubs (`iss-location` + `astronauts`)
- **Function App** (Python 3.11, Consumption plan)
- **Application Insights** + **Log Analytics** workspace
- **RBAC role assignments** (Function App Managed Identity → Event Hubs Data Sender)

```bash
# Push to main to trigger the CD workflow
git push origin main

# Or trigger manually via GitHub CLI
gh workflow run cd.yml
```

The Bicep templates in `infra/` handle all the resource provisioning — no portal clicking required! 🎉

✅ **Checkpoint:** CD workflow succeeds in GitHub Actions
```bash
# Verify the workflow completed
gh run list --workflow=cd.yml --limit 1
```

## Step 2: Configure Fabric 🌐 (~10 min)

Follow the [Fabric Setup Guide](./fabric-setup.md) to:

1. **Create Eventhouse + KQL Database** (or run `scripts/deploy-fabric.sh` for automated setup)
2. **Create 2 EventStreams** and wire them:
   - `iss-location` Event Hub → `ISS_Loc` KQL table
   - `astronauts` Event Hub → `Astronauts` KQL table
3. **Verify data** is flowing into the KQL Database

> 🌊 **What's happening:** Timer-triggered Azure Functions poll the ISS APIs, push events to Event Hubs, and Fabric EventStreams ingest them into KQL tables in real time.

✅ **Checkpoint:** `ISS_Loc | count` returns increasing numbers
```kql
ISS_Loc
| count

Astronauts
| count
```

## Step 3: Import Power BI Dashboard 📊 (~5 min)

1. Open `PBI/ISS.pbix` in **Power BI Desktop**
2. Update parameters (Transform data → Edit parameters):
   - `kusto_db_url` → Your KQL Database URI (found in KQL DB settings)
   - `kusto_db_name` → `iss-demo-kqldb`
3. Click **Refresh** to pull live data
4. Configure auto-refresh:
   - Page settings → Page refresh → **Every 5 seconds**
   - *(Requires DirectQuery mode or a Fabric capacity that supports auto page refresh at this interval)*
5. **Publish** to your Fabric workspace

✅ **Checkpoint:** Live ISS position updating on the map! 🗺️

## Step 4: Validate 🎉

Run through the smoke test checklist to confirm everything is humming:

- [ ] **Function App is running**
  ```bash
  az functionapp show -n func-iss-dev -g rg-iss-demo-dev --query "state" -o tsv
  # Expected: Running
  ```
- [ ] **Both timer functions registered**
  ```bash
  az functionapp function list -n func-iss-dev -g rg-iss-demo-dev --query "[].name" -o tsv
  # Expected: get_iss_location, get_astronauts
  ```
- [ ] **Events flowing through Event Hubs** — check incoming messages in the Azure Portal
- [ ] **KQL Database has data** in both `ISS_Loc` and `Astronauts` tables
- [ ] **Power BI dashboard auto-refreshes** — watch the ISS dot move! 🛰️

> 🎊 **Congratulations!** You've got a live ISS tracking dashboard powered by Azure Functions, Event Hubs, Microsoft Fabric, and Power BI. That's a lot of cloud goodness!

## 🔧 Troubleshooting

Hit a snag? Here are the most common issues and their fixes:

| Problem | Likely Cause | Solution |
|---------|-------------|----------|
| CD workflow fails at login | OIDC not configured | Check federated credential matches repo/branch/environment |
| Function App not running | Deployment failed | Check CD workflow logs, verify resource group exists |
| No events in Event Hub | Function App can't reach API | Check Function App logs in Application Insights |
| Fabric EventStream no data | Consumer group mismatch | Ensure using `fabric-eventstream` consumer group |
| Power BI shows stale data | Auto-refresh not configured | Set DirectQuery refresh interval to 5s |
| RBAC errors in Function App | Managed Identity not assigned | Verify Bicep deployed the Event Hubs Data Sender role assignment |
| KQL query returns 0 rows | EventStream not wired correctly | Re-check source/destination mappings in the Fabric portal |

> 🆘 **Still stuck?** Open an issue on the repo with the `bug` label and include the relevant logs. We're happy to help!

## 📐 Architecture Reference

Here's how all the pieces fit together:

```
GitHub Actions (CI/CD)
  │
  ├── Deploy: Bicep → Azure Resource Group
  │     ├── Event Hubs Namespace (Standard)
  │     │     ├── iss-location hub
  │     │     └── astronauts hub
  │     ├── Function App (Python 3.11, Consumption)
  │     ├── Application Insights + Log Analytics
  │     └── RBAC: Function App MI → Event Hubs Data Sender
  │
  └── Deploy: Function App code
        ├── get_iss_location (every 5s)
        └── get_astronauts (every 1m)

Fabric (Manual / CLI setup)
  ├── EventStreams (2x) ← Event Hubs
  ├── KQL Database ← EventStreams
  └── Power BI Dashboard ← KQL Database
```

For deeper architectural context, see the [Architecture Decision Records](./architecture.md) and the [Code Walkthrough](./code-walkthrough.md).

---

*Happy tracking! If you can see the ISS moving across your dashboard, you've nailed it.* 🚀✨
