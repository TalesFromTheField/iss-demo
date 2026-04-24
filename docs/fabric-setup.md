# 🌐 Fabric Setup Guide

> This guide covers the manual Fabric resource setup. If you haven't deployed the Azure infrastructure yet, start with the [Deployment Guide](./deployment-guide.md) first!

## 📋 Prerequisites

- Microsoft Fabric workspace with capacity assigned
- Azure Event Hubs deployed (via Bicep — see deployment guide)
- Event Hub namespace FQDN (e.g., `evhns-iss-dev.servicebus.windows.net`)
- Fabric CLI installed (optional — for automated resource creation)

### Windows requirement for Fabric CLI

If you install `fabric-cli` on Windows, install **Build Tools for Visual Studio 2022**
with the following components before running `pip install ms-fabric-cli`:

- MSVC v143 - VS 2022 C++ x64/x86 build tools (Latest)
- Windows 10 SDK (10.0.19041+) or Windows 11 SDK
- C++ CMake tools for Windows

After installing these components, open **x64 Native Tools Command Prompt for VS 2022**
and run `pip install ms-fabric-cli` from that prompt.

## 🚀 Option A: Automated Setup (Fabric CLI)

The fastest way! Run one of the deployment scripts:

```bash
# Install Fabric CLI if you haven't
pip install ms-fabric-cli

# Authenticate (the CLI must provide auth/api commands)
fab auth login

# Deploy Fabric resources from Bash
./scripts/deploy-fabric.sh --workspace-id <YOUR_WORKSPACE_ID>
```

```powershell
# Install Fabric CLI if you haven't
pip install ms-fabric-cli

# Authenticate
fab auth login

# Deploy Fabric resources from PowerShell
.\scripts\deploy-fabric.ps1 -WorkspaceId <YOUR_WORKSPACE_ID>
```

This creates the Eventhouse, KQL Database, and EventStreams automatically. You'll still need to complete the manual wiring steps in Section 3 below.

If your install gives you `fabric-cli` instead of `fab`, you likely installed the wrong
package (`fabric-cli` from PyPI, which is unrelated). Install `ms-fabric-cli` instead.
If `fab --help` does not show `auth` and `api` commands, the script path will not work.
Use Option B (manual portal setup) in that case.

## 🖱️ Option B: Manual Setup (Fabric Portal)

### Step 1: Create an Eventhouse 🏠

1. Open your Fabric workspace
2. Click **+ New** → **Eventhouse**
3. Name it: `iss-demo-eventhouse`
4. Click **Create**

✅ **Checkpoint:** You should see the Eventhouse in your workspace items.

### Step 2: Create a KQL Database 🗄️

1. Open the Eventhouse you just created
2. Click **+ New database**
3. Name it: `iss-demo-kqldb`
4. Select **ReadWrite** type
5. Click **Create**

✅ **Checkpoint:** The KQL Database appears under the Eventhouse.

### Step 3: Create EventStreams 🌊

Create **two** EventStreams — one for each data feed:

#### 3a. ISS Location EventStream

1. In your workspace, click **+ New** → **EventStream**
2. Name it: `iss-location-eventstream`
3. **Add Source:**
   - Select **Azure Event Hub**
   - Connection: your Event Hub namespace (e.g., `evhns-iss-dev`)
   - Event Hub: `iss-location`
   - Consumer group: `fabric-eventstream`
   - Authentication: Shared Access Key or Managed Identity
4. **Add Destination:**
   - Select **KQL Database**
   - Select: `iss-demo-kqldb`
   - Table name: `ISS_Loc`
   - Input data format: JSON
5. Click **Publish**

✅ **Checkpoint:** Events should start flowing within seconds. Check the EventStream preview.

#### 3b. Astronauts EventStream

1. Create another EventStream: `astronauts-eventstream`
2. **Add Source:** Azure Event Hub → `astronauts` hub, `fabric-eventstream` consumer group
3. **Add Destination:** KQL Database → `iss-demo-kqldb` → table: `Astronauts`
4. Click **Publish**

✅ **Checkpoint:** Both EventStreams show data flowing.

### Step 4: Verify Data in KQL Database 🔍

Open the KQL Database and run these queries:

```kql
// Check ISS location data
ISS_Loc
| count

// Check astronaut data
Astronauts
| count

// See latest ISS position
ISS_Loc
| top 5 by Timestamp
| project Longitude, Latitude, Timestamp
```

✅ **Checkpoint:** Both tables have records and counts are increasing.

### Step 5: Set Up Power BI Dashboard 📊

1. Open the Power BI file: `PBI/ISS.pbix`
2. Update parameters:
   - `kusto_db_url`: Your KQL Database URI (found in the KQL DB settings)
   - `kusto_db_name`: `iss-demo-kqldb`
3. Refresh the data
4. Configure auto-refresh every 5 seconds for live tracking

✅ **Checkpoint:** The dashboard shows the ISS position on a map and updates in real time!

## 🔧 Expected KQL Table Schemas

### ISS_Loc Table

| Column    | Type     | Description                       |
|-----------|----------|-----------------------------------|
| Timestamp | datetime | When the position was recorded    |
| Latitude  | real     | ISS latitude (-90 to 90)         |
| Longitude | real     | ISS longitude (-180 to 180)      |

### Astronauts Table

| Column | Type    | Description                        |
|--------|---------|------------------------------------|
| number | int     | Total people in space              |
| people | dynamic | Array of {name, craft} objects     |

## ❓ Troubleshooting

| Problem                      | Solution                                                                                              |
|------------------------------|-------------------------------------------------------------------------------------------------------|
| EventStream shows no data    | Verify the Container App is running and check its logs (`az containerapp logs show -n ca-iss-dev -g rg-iss-demo-dev --follow`) |
| KQL table not created        | Ensure EventStream destination mapping is complete — table is auto-created on first event             |
| Power BI won't connect       | Double-check `kusto_db_url` parameter — it should be the full URI from KQL DB settings               |
| Consumer group error         | Ensure `fabric-eventstream` consumer group exists on the Event Hub (created by Bicep)                |

## 🎉 Done!

Your Fabric pipeline is now live! The ISS position updates every 5 seconds and astronaut data refreshes every minute. Head back to the [README](../README.md) to see what else you can do.
