# Project Memory

This file captures project learnings that persist across agent sessions.

## Project Overview

**ISS Demo** — A real-time tracking demo for the International Space Station, built on Microsoft Fabric with Azure services for data ingestion.

### What It Does
Polls the [Open Notify API](http://open-notify.org/Open-Notify-API/) for:
- **ISS position** (`iss-now.json`) — latitude/longitude/timestamp, every 5 seconds
- **Astronaut info** (`astros.json`) — people in space and their craft, every 1 minute

Data flows directly from the Container App via Kusto streaming ingestion into a KQL Database for ad-hoc analysis and a Power BI dashboard for real-time visualization. Azure Event Hubs was removed to eliminate the key-based authentication requirement.

### Architecture

```
Azure Container App (Python, APScheduler)
  ├─ job_get_iss_location  (every 5s)  ──┐
  └─ job_get_astronauts    (every 1m)  ──┤
                                         │ Kusto streaming ingestion
                                         ▼
                              KQL Database (tables: ISS_Loc, Astronauts)
                                         │
                                         ▼
                              Power BI Dashboard (auto-refresh every 5s)
```

### Tech Stack
- **Ingestion:** Azure Container App (Python, APScheduler), streaming directly to Fabric
- **Storage/Analytics:** Microsoft Fabric KQL Database + KQL Queryset (Eventhouse)
- **Visualization:** Power BI (`.pbix` report connected to KQL DB)
- **Infrastructure as Code:** Bicep (modular structure under `infra/`)
- **CI/CD:** GitHub Actions (OIDC auth, `dev` environment)
- **Testing:** pytest (unit + integration), Bicep lint/validation
- **Linting:** ruff (Python), az bicep lint
- **AI Framework:** Teamwork (agents, skills, instructions)

### Key Decisions
- **Azure Event Hubs removed** — original architecture used Event Hubs + Fabric EventStreams for ingestion. Removed because key-based authentication was unavailable and managed identity for Fabric EventStreams is not straightforward. Replaced with direct Kusto streaming ingestion from the Container App using `azure-kusto-ingest` + managed identity via `DefaultAzureCredential`.
- **Direct Fabric streaming ingestion** — the Container App uses `KustoStreamingIngestClient` from `azure-kusto-ingest` to write directly to KQL Database tables. Auth is via Container App system-assigned managed identity (`DefaultAzureCredential`). The Eventhouse Query URI (`queryServiceUri`) must be set as the `FabricIngestionUri` environment variable.
- **KQL table schema in `kql/schema.kql`** — tables (`ISS_Loc`, `Astronauts`) and streaming ingestion policy must be created manually via the Fabric portal KQL editor before the Container App can ingest. Run `kql/schema.kql` once after `deploy-fabric.ps1/sh`.
- **Azure Functions replaces Logic Apps** — Logic Apps were the original ingestion service. Functions are cheaper and code-first.
- **Container App replaced Azure Functions runtime** — `run.py` uses APScheduler so the same fetch logic runs in a Container App environment without the Functions host.
- **Deploy to Azure button for public users** — the primary deployment path for the public is the one-click Deploy to Azure portal button. It deploys `infra/main.bicep` and pulls the pre-built Container App image from GHCR.
- **GitHub Actions CD is for maintainers only** — OIDC-based CD workflow for the core team. NOT the intended path for public/demo users.
- **Local scripts for Fabric** — `scripts/deploy-fabric.ps1` (Windows) and `scripts/deploy-fabric.sh` (Mac/Linux) automate Fabric resource creation. They output the `FabricIngestionUri` to set on the Container App.
- **Fabric resources are NOT deployed by IaC** — KQL Database is a Fabric workspace item. Documented in `docs/fabric-setup.md`.

### Repository Structure
```
iss-demo/
├── .github/workflows/     # CI/CD pipelines
├── infra/                 # Bicep modules (Event Hubs, Function App, RBAC)
├── functions/             # Azure Functions Python project
├── kql/                   # KQL queries for ad-hoc analysis
├── PBI/                   # Power BI dashboard (.pbix)
├── docs/                  # Deployment guide, Fabric setup, ADRs
├── logicapps/             # Legacy Logic App definitions (reference only)
└── images/                # Architecture diagrams
```

## Conventions
- Conventional commits: `type(scope): description`
- Branch naming: `feature/`, `bugfix/`, `chore/`, etc.
- Python: ruff for linting, pytest for testing
- Bicep: modular under `infra/modules/`, parameters in `infra/parameters/`
- One PR per task, ~300 lines max
