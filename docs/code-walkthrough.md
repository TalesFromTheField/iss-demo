# 🛰️ ISS Tracker — Code Walkthrough

> **Tales From the Field** — Helping you solve real-world problems with insights from the field 🚀
>
> Grab a coffee ☕, buckle up, and let's take a guided tour through every layer of
> the ISS Tracker demo — from the Python functions that talk to the ISS, all the
> way down to the KQL queries that light up your Power BI dashboard.

---

## Table of Contents

1. [🌍 The Big Picture](#-the-big-picture)
2. [⚡ Azure Functions (`functions/function_app.py`)](#-azure-functions-functionsfunction_apppy)
3. [🏗️ Infrastructure as Code (`infra/`)](#️-infrastructure-as-code-infra)
4. [🔍 KQL Queries (`kql/ISS.kql`)](#-kql-queries-kqlisskql)
5. [📊 Power BI Dashboard](#-power-bi-dashboard)
6. [🔌 Fabric CLI Script (`scripts/deploy-fabric.sh`)](#-fabric-cli-script-scriptsdeploy-fabricsh)
7. [🧪 Testing](#-testing)
8. [🚀 CI/CD Pipelines](#-cicd-pipelines)

---

## 🌍 The Big Picture

Here's the 30,000-foot view (well, more like 254-mile view — that's how high the ISS orbits! 😄):

```
  ┌─────────────────┐         ┌────────────────────┐
  │   Open Notify    │  HTTP   │   Azure Functions   │
  │   ISS API 🛰️     │◄───────│   (Python 3.11)     │
  │                  │  GET    │   ⏱️ every 5s / 1m   │
  └─────────────────┘         └─────────┬──────────┘
                                        │
                                        │ Event Hub Output Binding
                                        │ (Managed Identity 🔐)
                                        ▼
                              ┌────────────────────┐
                              │   Azure Event Hubs  │
                              │   ┌──────────────┐  │
                              │   │ iss-location  │  │
                              │   └──────────────┘  │
                              │   ┌──────────────┐  │
                              │   │ astronauts    │  │
                              │   └──────────────┘  │
                              └─────────┬──────────┘
                                        │
                                        │ Consumer Group: fabric-eventstream
                                        ▼
                              ┌────────────────────┐
                              │ Fabric EventStreams │
                              │   ┌──────────────┐  │
                              │   │ iss-location  │  │
                              │   │ -eventstream  │  │
                              │   └──────────────┘  │
                              │   ┌──────────────┐  │
                              │   │ astronauts    │  │
                              │   │ -eventstream  │  │
                              │   └──────────────┘  │
                              └─────────┬──────────┘
                                        │
                                        │ Real-time ingestion
                                        ▼
                              ┌────────────────────┐
                              │ KQL Database 📊     │
                              │   (Eventhouse)      │
                              │   ┌──────────────┐  │
                              │   │ ISS_Loc       │  │
                              │   └──────────────┘  │
                              │   ┌──────────────┐  │
                              │   │ Astronauts    │  │
                              │   └──────────────┘  │
                              └─────────┬──────────┘
                                        │
                                        │ DirectQuery
                                        ▼
                              ┌────────────────────┐
                              │  Power BI Dashboard │
                              │  🗺️ Live ISS Map    │
                              │  👩‍🚀 Crew Roster     │
                              └────────────────────┘
```

**The short version:** We poll a free NASA-backed API, wrap each response in a
normalized event envelope, fire it into Event Hubs, let Fabric stream it into a
KQL database, and visualize it all in Power BI — in near real-time. ✨

### Data Flow Summary

| Step | Component | What Happens |
|------|-----------|-------------|
| 1 | **Open Notify API** | Returns the ISS's current lat/lon (updates every ~1s) and the list of astronauts in space |
| 2 | **Azure Functions** | Timer-triggered Python functions poll the API every 5s (location) and 1m (astronauts) |
| 3 | **Event Hubs** | Two hubs (`iss-location` and `astronauts`) buffer the streaming events |
| 4 | **Fabric EventStreams** | Picks up events from the `fabric-eventstream` consumer groups |
| 5 | **KQL Database** | Ingests into `ISS_Loc` and `Astronauts` tables for querying |
| 6 | **Power BI** | DirectQuery renders a live map, orbital trajectory, and crew roster |

---

## ⚡ Azure Functions (`functions/function_app.py`)

> 📁 [`functions/function_app.py`](../functions/function_app.py)

This is where the magic starts! Our Python Azure Functions are the "eyes" of the
system — they look up at the ISS, grab the data, and relay it downstream. Let's
walk through the code piece by piece. 🧩

### The Python v2 Programming Model

We use the **Python v2 programming model** for Azure Functions, which replaces
the old `function.json` files with clean Python **decorators**. Everything lives
in one file — no separate config needed!

```python
import azure.functions as func

app = func.FunctionApp()
```

That `app` object is the heart of it all. We hang our functions off it with
decorators like `@app.timer_trigger()` and `@app.event_hub_output()`. The
runtime reads these decorators at startup and wires everything automatically.
No `function.json` required! 🎉

### `_fetch_with_retry()` — The Resilient Helper

The ISS API is free and community-maintained, so it can hiccup. Rather than
crash on the first timeout, we built a shared retry helper:

```python
def _fetch_with_retry(url: str, timeout: int = 10, retries: int = 1, backoff: int = 2) -> requests.Response:
    """HTTP GET with simple retry logic."""
    last_exception: requests.RequestException | None = None
    for attempt in range(1 + retries):
        try:
            response = requests.get(url, timeout=timeout)
            response.raise_for_status()
            return response
        except requests.RequestException as exc:
            last_exception = exc
            if attempt < retries:
                delay = backoff * (2 ** attempt)
                logger.warning(
                    "Attempt %d for %s failed (%s). Retrying in %ds…",
                    attempt + 1, url, exc, delay,
                )
                time.sleep(delay)
    raise last_exception  # type: ignore[misc]
```

**Why does this matter?** 🤔

- **Transient failures happen.** Network blips, DNS hiccups, API rate limits —
  the internet is messy. A single retry with exponential backoff handles most
  transient issues.
- **Exponential backoff** (`2s → 4s → 8s…`) is kind to the upstream API. We
  don't slam a struggling server with rapid-fire retries.
- **Both functions share it** — DRY principle in action! One behavior, one
  place to fix it.
- If all retries fail, the exception bubbles up and the calling function
  gracefully skips that polling cycle (no crash, no partial data).

### `get_iss_location()` — Where Is the ISS Right Now? 🌍

```python
@app.timer_trigger(schedule="*/5 * * * * *", arg_name="timer", run_after_startup=False)
@app.event_hub_output(arg_name="outputEvent", connection="EventHubConnection",
                      event_hub_name="%IssLocationHubName%")
def get_iss_location(timer: func.TimerRequest, outputEvent: func.Out[str]) -> None:
```

Let's break down those decorators:

| Decorator | What It Does |
|-----------|-------------|
| `@app.timer_trigger(schedule="*/5 * * * * *")` | Fires every **5 seconds** (NCRONTAB — 6 fields including seconds!) |
| `@app.event_hub_output(...)` | Binds the `outputEvent` parameter to an Event Hub for zero-code publishing |
| `connection="EventHubConnection"` | Uses `EventHubConnection__fullyQualifiedNamespace` app setting → Managed Identity auth 🔐 |
| `event_hub_name="%IssLocationHubName%"` | The `%...%` syntax resolves the hub name from app settings at runtime |

**What the ISS API returns:**

```json
{
  "iss_position": { "latitude": "41.7370", "longitude": "-49.4507" },
  "timestamp": 1234567890,
  "message": "success"
}
```

**How we normalize it into our event envelope:**

```python
event = {
    "schemaVersion": "1.0",
    "eventType": "iss-location",
    "collectedAtUtc": datetime.now(timezone.utc).isoformat(),
    "data": iss_data,
}
outputEvent.set(json.dumps(event))
```

Then we just `outputEvent.set(...)` — the Azure Functions runtime handles
serialization and delivery to Event Hubs. Done! 🏁

**Error handling philosophy:** If the API is down or returns garbage JSON, we
log a warning and **skip the cycle**. No crash, no partial event. The next
timer tick (5 seconds later) will try again.

### `get_astronauts()` — Who's Up There? 👩‍🚀

```python
@app.timer_trigger(schedule="0 * * * * *", arg_name="timer", run_after_startup=False)
@app.event_hub_output(arg_name="outputEvent", connection="EventHubConnection",
                      event_hub_name="%AstronautsHubName%")
def get_astronauts(timer: func.TimerRequest, outputEvent: func.Out[str]) -> None:
```

Same pattern, different schedule: fires **every minute** (`0 * * * * *` = at the
0th second of every minute). The crew roster doesn't change every 5 seconds, so
once a minute is plenty! 😄

**What the Astronauts API returns:**

```json
{
  "number": 7,
  "people": [
    { "name": "Oleg Kononenko", "craft": "ISS" },
    { "name": "Tracy Dyson", "craft": "ISS" },
    ...
  ],
  "message": "success"
}
```

The function wraps this in the same normalized envelope (`schemaVersion`,
`eventType: "astronauts"`, `collectedAtUtc`, `data`) and ships it to the
`astronauts` Event Hub.

### The Normalized Event Schema 📐

Both functions wrap their API responses in the same envelope:

```json
{
  "schemaVersion": "1.0",
  "eventType": "iss-location | astronauts",
  "collectedAtUtc": "2024-01-15T12:34:56.789Z",
  "data": { /* raw API response */ }
}
```

**Why a standard envelope?**

- **Downstream consumers** (EventStreams, KQL) can route/filter on `eventType`
  without parsing the `data` payload.
- **`schemaVersion`** lets us evolve the schema without breaking consumers —
  v2.0 events can be handled differently.
- **`collectedAtUtc`** is *our* timestamp (when we fetched), not the API's.
  This matters for latency analysis.
- **Consistency** — every event through the system looks the same at the
  envelope level. Predictability is a feature! ✅

---

## 🏗️ Infrastructure as Code (`infra/`)

> 📁 [`infra/`](../infra/)

Everything in Azure is defined in **Bicep** — Microsoft's declarative IaC
language. No portal clicking here! Let's tour each module. 🏛️

### Module Dependency Chain

```
                    ┌───────────────┐
                    │  main.bicep   │  ← Orchestrator
                    │  (entrypoint) │
                    └───────┬───────┘
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             │
     ┌────────────┐  ┌────────────┐      │
     │ event-hubs │  │ monitoring │      │
     │   .bicep   │  │   .bicep   │      │
     └──────┬─────┘  └──────┬─────┘      │
            │               │             │
            │    ┌──────────┘             │
            ▼    ▼                        │
     ┌─────────────────┐                 │
     │  function-app   │                 │
     │    .bicep        │                 │
     └────────┬────────┘                 │
              │                          │
              ├──────────────────────────┘
              ▼                    ▼
     ┌────────────────┐   ┌─────────────────┐
     │ role-           │   │ monitoring      │
     │ assignments     │   │ (alerts pass)   │
     │ .bicep          │   │ .bicep          │
     └────────────────┘   └─────────────────┘
```

**Deploy order:** Event Hubs + Monitoring (base) → Function App → Role Assignments + Monitoring (alerts)

### `event-hubs.bicep` — The Message Highway 🛣️

> 📁 [`infra/modules/event-hubs.bicep`](../infra/modules/event-hubs.bicep)

```bicep
resource namespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: 'evhns-iss-${environmentName}'
  sku: {
    name: 'Standard'   // Required for Fabric EventStream compatibility!
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    isAutoInflateEnabled: false
    minimumTlsVersion: '1.2'
  }
}
```

**Key decisions:**

| Setting | Value | Why |
|---------|-------|-----|
| **SKU** | Standard | Fabric EventStreams require Standard tier (Basic won't work!) |
| **Hubs** | `iss-location` + `astronauts` | One hub per data stream — clean separation |
| **Partitions** | 1 per hub | Our throughput is tiny; one partition keeps it simple |
| **Retention** | 1 day | We're streaming, not archiving. 24h is plenty for replay |
| **Consumer Groups** | `fabric-eventstream` | Each consumer needs its own group. Fabric gets a dedicated one |
| **TLS** | 1.2 minimum | Security best practice — no legacy TLS |

Each hub also gets a `fabric-eventstream` consumer group:

```bicep
resource issLocationFabricCg 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  name: 'fabric-eventstream'
  parent: issLocationHub
}
```

### `function-app.bicep` — The Compute Engine 🖥️

> 📁 [`infra/modules/function-app.bicep`](../infra/modules/function-app.bicep)

This module provisions three resources:

1. **Storage Account** — The Functions runtime needs blob storage for trigger
   management, logging, and internal state.

   ```bicep
   resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
     name: 'stissf${environmentName}'
     sku: { name: 'Standard_LRS' }
     kind: 'StorageV2'
     properties: {
       supportsHttpsTrafficOnly: true
       minimumTlsVersion: 'TLS1_2'
       allowBlobPublicAccess: false   // 🔒 No public access!
     }
   }
   ```

2. **Consumption App Service Plan** (Y1) — Pay only for what you use.
   Perfect for a demo!

   ```bicep
   resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
     name: 'asp-iss-${environmentName}'
     sku: { name: 'Y1', tier: 'Dynamic' }
     kind: 'linux'
     properties: { reserved: true }  // 'reserved: true' = Linux
   }
   ```

3. **Function App** — Linux, Python 3.11, with **system-assigned Managed Identity**:

   ```bicep
   resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
     name: 'func-iss-${environmentName}'
     kind: 'functionapp,linux'
     identity: { type: 'SystemAssigned' }  // 🔐 No connection strings for Event Hubs!
     properties: {
       serverFarmId: appServicePlan.id
       httpsOnly: true
       siteConfig: {
         linuxFxVersion: 'Python|3.11'
         appSettings: [
           { name: 'EventHubConnection__fullyQualifiedNamespace', value: eventHubNamespaceFqdn }
           { name: 'IssLocationHubName', value: issLocationHubName }
           { name: 'AstronautsHubName',  value: astronautsHubName }
           { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
           { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
           // ... storage connection string
         ]
       }
     }
   }
   ```

**🔐 The Managed Identity trick:** Notice there's no Event Hub connection
string! The app setting `EventHubConnection__fullyQualifiedNamespace` tells the
Azure Functions runtime to use **Managed Identity** (via `DefaultAzureCredential`)
to authenticate with Event Hubs. No secrets to rotate! The `__fullyQualifiedNamespace`
suffix is the magic naming convention that triggers identity-based auth.

### `monitoring.bicep` — Eyes on the System 👀

> 📁 [`infra/modules/monitoring.bicep`](../infra/modules/monitoring.bicep)

This module is called **twice** by `main.bicep` — a clever pattern!

**First call (base):** Creates Log Analytics Workspace + Application Insights
(no alerts yet, because we don't have the Function App resource ID).

**Second call (alerts):** Re-deploys with `functionAppResourceId` provided,
which enables the conditional alert rules.

```bicep
var alertsEnabled = !empty(functionAppResourceId)
```

**Alert rules (deployed only when `alertsEnabled` is true):**

| Alert | Severity | Condition | Window |
|-------|----------|-----------|--------|
| **Execution Failures** | Sev 2 (Warning) | > 5 failed executions | 5 minutes |
| **Function Stopped** | Sev 1 (Error) | 0 successful executions | 10 minutes |

Both alerts have `autoMitigate: true` — they auto-resolve when the condition
clears. No alert fatigue! 🔕

**Log Analytics:** 30-day retention, PerGB2018 pricing tier. The workspace
backs Application Insights and can be queried directly with KQL.

### `role-assignments.bicep` — Least Privilege 🔐

> 📁 [`infra/modules/role-assignments.bicep`](../infra/modules/role-assignments.bicep)

```bicep
var eventHubsDataSenderRoleId = '2b629674-e913-4c01-ae53-ef4638d8f975'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHubNamespace.id, principalId, eventHubsDataSenderRoleId)
  scope: eventHubNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions', eventHubsDataSenderRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
```

This grants exactly **one role** to exactly **one principal**:

- **Who:** The Function App's system-assigned Managed Identity
- **What:** `Azure Event Hubs Data Sender` — can *send* events, cannot *read* or
  *manage* hubs
- **Where:** Scoped to the Event Hubs *namespace* (not subscription-wide!)

**Why this matters:** The Function App only needs to *send* events. It doesn't
need to create hubs, manage consumer groups, or read messages. Least privilege
means a compromised Function App can't exfiltrate data from Event Hubs. 🛡️

### `main.bicep` — The Orchestrator 🎼

> 📁 [`infra/main.bicep`](../infra/main.bicep)

This is the conductor that wires all the modules together:

```bicep
module eventHubs 'modules/event-hubs.bicep' = { ... }
module monitoring 'modules/monitoring.bicep' = { ... }

module functionApp 'modules/function-app.bicep' = {
  params: {
    eventHubNamespaceFqdn: eventHubs.outputs.namespaceFqdn       // ← wired!
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString  // ← wired!
    issLocationHubName: eventHubs.outputs.issLocationHubName     // ← wired!
    astronautsHubName: eventHubs.outputs.astronautsHubName       // ← wired!
  }
}

module roleAssignments 'modules/role-assignments.bicep' = {
  params: {
    principalId: functionApp.outputs.functionAppPrincipalId       // ← wired!
    eventHubNamespaceName: eventHubs.outputs.namespaceName        // ← wired!
  }
}
```

Notice how **outputs flow between modules** — Event Hubs outputs its FQDN,
which becomes the Function App's input. The Function App outputs its Managed
Identity principal ID, which becomes the role assignment's input. Bicep
figures out the deployment order automatically from these dependencies. Smart! 🧠

---

## 🔍 KQL Queries (`kql/ISS.kql`)

> 📁 [`kql/ISS.kql`](../kql/ISS.kql)

Once data lands in the KQL Database, we can query it with **Kusto Query
Language** — the same query language used by Azure Data Explorer and
Microsoft Fabric. Here's every query in the file, explained:

### 1. Timestamp Range Check ⏰

```kql
ISS_Loc
| summarize max(Timestamp), min(Timestamp)
```

**What it does:** Shows the earliest and latest data points in the `ISS_Loc`
table. Use this to sanity-check that data is flowing and how far back it goes.
Think of it as your "is the pipeline alive?" check. 💓

### 2. Record Count 📊

```kql
ISS_Loc
| count
```

**What it does:** Total number of ISS location records. At 1 event every 5
seconds, you'd expect ~720 records/hour, ~17,280/day. If this number isn't
growing, something upstream is broken!

### 3. Latest Trajectory (Scatter Map) 🗺️

```kql
ISS_Loc
| top 20 by Timestamp
| project Longitude, Latitude, Timestamp
| render scatterchart with ( kind=map )
```

**What it does:** Grabs the **20 most recent** position points and renders
them on a map. This gives you a quick "where has the ISS been in the last
~100 seconds?" view. The `render scatterchart with (kind=map)` is KQL magic
that turns lat/lon data into an interactive map visualization. 🪄

### 4. Complete Orbit (90-Minute Window) 🌐

```kql
ISS_Loc
| where Timestamp > ago(90m)
| project Longitude, Latitude, Timestamp
| render scatterchart with ( kind=map )
```

**What it does:** The ISS completes a full orbit every **~90 minutes**, so
this query pulls a full orbit's worth of data. You'll see a complete path
around the Earth! The ISS orbits at an inclination of ~51.6°, so the path
looks like a sine wave wrapped around the globe. 🌊

### 5. Current Astronauts in Space 👩‍🚀

```kql
Astronauts
| top 1 by ['x-opt-enqueued-time']
| mv-expand people
| project Name = people.name, Craft = people.craft
```

**What it does:** Takes the **most recent** astronaut event (using the Event
Hub enqueue timestamp), then uses `mv-expand` to "unpack" the `people` array
into individual rows. Each row shows an astronaut's name and which spacecraft
they're on.

**Fun fact:** `mv-expand` is KQL's equivalent of SQL's `UNNEST` or `LATERAL
JOIN`. It takes an array and turns each element into its own row. Super handy
for JSON data! 🧑‍🚀

---

## 📊 Power BI Dashboard

> 📁 [`PBI/ISS.pbix`](../PBI/ISS.pbix)

The Power BI report is the grand finale — where all that streaming data becomes
a beautiful, live dashboard! 🎨

### What the Dashboard Shows

| Visual | Description |
|--------|-------------|
| **🗺️ Live ISS Map** | A map visual showing the ISS's current position as a moving dot |
| **🌐 Orbital Trajectory** | The path the ISS has traced over the last 90 minutes — a complete orbit! |
| **👩‍🚀 Crew Roster** | A table listing every astronaut currently in space and their spacecraft |

### How Auto-Refresh Works 🔄

Power BI uses **DirectQuery** mode against the KQL Database, meaning:

- **No data import/cache** — every visual refresh queries the KQL DB live
- **Auto-refresh interval** — the report page refreshes on a configurable
  timer (typically every 10–30 seconds)
- **Always fresh** — you see the ISS position as it was seconds ago, not hours

### Connecting to the KQL Database

The `.pbix` file contains **parameters** that point it to your Fabric workspace:

1. **Cluster URI** — The Eventhouse KQL endpoint (e.g.,
   `https://iss-demo-eventhouse.z6.kusto.fabric.microsoft.com`)
2. **Database Name** — `iss-demo-kqldb`

When you open the file, Power BI Desktop prompts for these values. Update them
to match your Fabric deployment and you're off to the races! 🏎️

---

## 🔌 Fabric CLI Script (`scripts/deploy-fabric.sh`)

> 📁 [`scripts/deploy-fabric.sh`](../scripts/deploy-fabric.sh)

This Bash script automates the creation of Fabric resources using the
**Fabric CLI** (`fab`). It's your one-command setup for the Fabric side of
things! 🪄

### Usage

```bash
./scripts/deploy-fabric.sh --workspace-id <YOUR_WORKSPACE_GUID>
```

### What It Automates ✅

The script creates these resources in your Fabric workspace:

| Resource | Name | Purpose |
|----------|------|---------|
| **Eventhouse** | `iss-demo-eventhouse` | Hosts the KQL database |
| **KQL Database** | `iss-demo-kqldb` | Stores `ISS_Loc` and `Astronauts` tables |
| **EventStream** | `iss-location-eventstream` | Streams ISS location events from Event Hubs |
| **EventStream** | `astronauts-eventstream` | Streams astronaut events from Event Hubs |

Under the hood, it calls the Fabric REST API via `fab api -X POST` for each
resource, chaining them together (the KQL DB references the Eventhouse's ID).

### What Still Needs Manual Wiring 🔧

The **EventStream → KQL DB data connection** (the "last mile") must be
completed in the Fabric portal. Here's why:

1. **API limitations** — The Fabric EventStream API doesn't yet support
   programmatically adding sources and destinations to a stream
2. **Mapping complexity** — You need to map stream columns to KQL table
   columns, which involves a visual schema mapping experience

**Manual steps after running the script:**

1. Open each EventStream in the Fabric portal
2. Add **source** → Azure Event Hub (point to the `iss-location` / `astronauts` hub)
3. Add **destination** → KQL Database → `iss-demo-kqldb`
4. Map `iss-location-eventstream` → `ISS_Loc` table
5. Map `astronauts-eventstream` → `Astronauts` table

> 📖 For detailed instructions with screenshots, see
> [`docs/fabric-setup.md`](fabric-setup.md)

---

## 🧪 Testing

> 📁 [`functions/tests/`](../functions/tests/)

We take testing seriously — even for a demo! 🧪 Our test suite has two layers:

### Unit Tests — Fast, Isolated, Reliable 🏎️

> 📁 [`functions/tests/test_get_iss_location.py`](../functions/tests/test_get_iss_location.py)
> 📁 [`functions/tests/test_get_astronauts.py`](../functions/tests/test_get_astronauts.py)

Unit tests mock `_fetch_with_retry` (and by extension `requests.get`) so they
**never hit the network**. They run in milliseconds and test our logic, not
the internet.

**What they verify:**

| Test Case | What It Checks |
|-----------|---------------|
| `test_successful_poll_sends_event` | Happy path — correct schema, all envelope fields present |
| `test_correct_url_called` | The right API URL is called with the right timeout/retry params |
| `test_http_failure_skips_cycle` | `RequestException` → no event sent, no crash |
| `test_invalid_json_skips_cycle` | Garbage JSON → no event sent, no crash |
| `test_timeout_skips_cycle` | `Timeout` → graceful skip |
| `test_connection_error_skips_cycle` | `ConnectionError` → graceful skip |

**Example — testing the happy path:**

```python
@patch("function_app._fetch_with_retry")
def test_successful_poll_sends_event(self, mock_fetch):
    mock_resp = MagicMock()
    mock_resp.json.return_value = SAMPLE_ISS_RESPONSE
    mock_fetch.return_value = mock_resp
    timer, output = self._make_mocks()

    get_iss_location(timer, output)

    output.set.assert_called_once()
    event = json.loads(output.set.call_args[0][0])
    assert event["schemaVersion"] == "1.0"
    assert event["eventType"] == "iss-location"
    assert "collectedAtUtc" in event
    assert event["data"] == SAMPLE_ISS_RESPONSE
```

**Run unit tests:**

```bash
cd functions
python -m pytest tests/ -m "not integration" -v
```

### Integration Tests — Real APIs, Real Validation 🌐

> 📁 [`functions/tests/test_api_integration.py`](../functions/tests/test_api_integration.py)

Integration tests call the **real Open Notify APIs** and validate the response
schemas match what our functions expect. These catch upstream API changes before
they break production!

**What they verify:**

| Test Case | What It Checks |
|-----------|---------------|
| `test_returns_200` | API is up and returns 200 OK |
| `test_response_has_iss_position` | Response contains `latitude` and `longitude` |
| `test_response_has_timestamp` | Timestamp field exists and is an integer |
| `test_coordinates_are_valid_strings` | Lat is -90..90, Lon is -180..180 |
| `test_response_has_people_list` | People array length matches `number` field |
| `test_each_person_has_name_and_craft` | Every astronaut has both fields populated |

Integration tests are marked with `@pytest.mark.integration` and run
separately (they're slower and depend on external services):

```bash
cd functions
python -m pytest tests/ -m integration -v
```

> ⚠️ **Note:** Integration tests use `continue-on-error: true` in CI because
> the Open Notify API occasionally goes down. A failing integration test
> means "the API changed or is down", not "our code is broken".

### Test Configuration

> 📁 [`functions/tests/conftest.py`](../functions/tests/conftest.py)

```python
def pytest_configure(config):
    config.addinivalue_line(
        "markers",
        "integration: marks tests that call external APIs "
        "(deselect with '-m \"not integration\"')"
    )
```

This registers the custom `integration` marker so pytest doesn't warn about
unknown markers. Clean and simple! ✨

---

## 🚀 CI/CD Pipelines

> 📁 [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)

Our CI pipeline runs on **every push** and **every PR to `main`**. It's the
safety net that catches issues before they hit production.

### Pipeline Architecture

```
  ┌──────────┐     ┌─────────────┐
  │   Lint    │     │  Validate   │
  │  (ruff +  │     │  Infra      │
  │  bicep)   │     │  (bicep     │
  └─────┬─────┘     │   build)    │
        │           └─────────────┘
        │
  ┌─────┴─────┐     ┌─────────────┐
  │   Unit    │     │ Integration │
  │  Tests    │     │   Tests     │
  └─────┬─────┘     │ (continue   │
        │           │  on error)  │
        │           └─────────────┘
  ┌─────┴─────┐
  │   Build   │
  │ (package  │
  │  zip)     │
  └───────────┘
```

### CI Jobs Explained

| Job | Runs After | What It Does |
|-----|-----------|-------------|
| **Lint** | — (parallel start) | `ruff check functions/` for Python style + `az bicep build` to validate Bicep syntax |
| **Unit Tests** | — (parallel start) | `pytest tests/ -m "not integration"` — fast, mocked tests |
| **Integration Tests** | — (parallel start) | `pytest tests/ -m integration` — hits real APIs; `continue-on-error: true` |
| **Validate Infra** | — (parallel start) | `az bicep build --file infra/main.bicep` — compiles Bicep to ARM to catch errors |
| **Build** | Lint ✅ + Unit Tests ✅ | Packages the function app into a zip artifact (excludes tests and local settings) |

### CD Pipeline (Planned) 🔮

The CD pipeline is designed to deploy in three stages:

```
  Deploy Infra          Deploy Functions        Smoke Test
  (Bicep)        →      (func azure             →   (curl health
                          publish)                    endpoint)
```

| Stage | What It Does |
|-------|-------------|
| **Deploy Infra** | `az deployment group create` with `infra/main.bicep` — creates/updates all Azure resources |
| **Deploy Functions** | `func azure functionapp publish` — pushes the zipped function code to the Function App |
| **Smoke Test** | Verifies the Function App is running and events are flowing into Event Hubs |

---

## 🎓 Wrapping Up

You've now toured the entire ISS Tracker codebase — from the Python functions
that ping the ISS, through the Bicep infrastructure that hosts them, to the KQL
queries and Power BI dashboards that make the data shine. 🌟

**Key takeaways:**

- 🐍 **Python v2 model** makes Azure Functions feel natural and decorator-driven
- 🔐 **Managed Identity** eliminates secrets for Event Hub connectivity
- 📐 **Normalized event envelopes** keep downstream processing simple
- 🏗️ **Bicep modules** keep infrastructure DRY and dependency-ordered
- 🧪 **Two-layer testing** (unit + integration) catches bugs and API changes
- 🚀 **CI/CD** ensures quality on every commit

Happy tracking! 🛰️✨

---

*Built with ❤️ by the Tales From the Field crew*
