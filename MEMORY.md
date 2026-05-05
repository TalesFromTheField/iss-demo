# Project Memory

This file captures project learnings that persist across agent sessions.

## Project Overview

**ISS Demo** — A real-time tracking demo for the International Space Station, built on Microsoft Fabric with Azure services for data ingestion.

### What It Does
Polls the [Open Notify API](http://open-notify.org/Open-Notify-API/) for:
- **ISS position** (`iss-now.json`) — latitude/longitude/timestamp, every 5 seconds
- **Astronaut info** (`astros.json`) — people in space and their craft, every 1 minute

Data flows through Azure Event Hubs into Microsoft Fabric EventStreams, landing in a KQL Database for ad-hoc analysis and a Power BI dashboard for real-time visualization.

### Architecture

```
Azure Functions (Python, Timer triggers)
  ├─ GetIssLocation  (every 5s) → Event Hub: iss-location
  └─ GetAstronauts   (every 1m) → Event Hub: astronauts
        │
        ▼
Fabric EventStreams (2x, one per hub)
        │
        ▼
KQL Database (tables: ISS_Loc, Astronauts)
        │
        ▼
Power BI Dashboard (auto-refresh every 5s)
```

### Tech Stack
- **Ingestion:** Azure Functions (Python v2 programming model, timer triggers)
- **Messaging:** Azure Event Hubs (2 hubs in one namespace)
- **Streaming:** Microsoft Fabric EventStreams
- **Storage/Analytics:** Microsoft Fabric KQL Database + KQL Queryset
- **Visualization:** Power BI (`.pbix` report connected to KQL DB)
- **Infrastructure as Code:** Bicep (modular structure under `infra/`)
- **CI/CD:** GitHub Actions (OIDC auth, `dev` environment)
- **Testing:** pytest (unit + integration), Bicep lint/validation
- **Linting:** ruff (Python), az bicep lint
- **AI Framework:** Teamwork (agents, skills, instructions)

### Key Decisions
- **Azure Functions replaces Logic Apps** — Logic Apps were the original ingestion service (scheduled HTTP polling + Event Hub forwarding). Functions are cheaper, code-first, and easier to version-control/test.
- **Python v2 model** — decorator-based, single `function_app.py` file, readable for the data analytics audience.
- **Bicep over Terraform** — Azure-native, simpler for a single-cloud solution.
- **Deploy to Azure button for public users** — the primary deployment path for the public (Tales From the Field viewers) is the one-click Deploy to Azure portal button. It deploys `infra/main.bicep` and pulls the pre-built Container App image from GHCR. No local tooling or GitHub fork required.
- **GitHub Actions CD is for maintainers only** — OIDC-based CD workflow exists for the core team to push infrastructure updates. It is NOT the intended path for public/demo users.
- **Local scripts for Fabric** — `scripts/deploy-fabric.ps1` (Windows) and `scripts/deploy-fabric.sh` (Mac/Linux) automate Fabric resource creation for users who prefer CLI over portal.
- **Fabric resources are NOT deployed by IaC** — EventStreams, KQL Database, and Power BI are workspace items that require Fabric REST APIs or portal setup. Documented in `docs/fabric-setup.md`.

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
