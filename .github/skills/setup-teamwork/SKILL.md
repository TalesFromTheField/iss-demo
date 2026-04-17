---
name: setup-teamwork
description: "Fill in all CUSTOMIZE placeholders across Teamwork agent files by analyzing the repository's tech stack, languages, and tooling. Use after installing Teamwork into a new repository."
---

# Setup Teamwork

## Overview

This skill scans the repository to detect the tech stack, languages, build tools, and test frameworks, then fills in all `<!-- CUSTOMIZE -->` placeholders in the agent files under `.github/agents/`.

## Steps

### Step 0: Detect Project Type

Before analyzing the tech stack, determine what kind of project this is. Look for the following indicators:

**Software project indicators** (any of these present → likely a software project):
- `package.json`, `go.mod`, `Cargo.toml`, `requirements.txt`, `pyproject.toml`, `setup.py`, `Gemfile`, `pom.xml`, `build.gradle`, `*.csproj`

**Non-software indicators** (check these when no software indicators are found):

| Indicator | Likely Project Type |
|-----------|-------------------|
| `*.sql` files or `migrations/` directory | Database / data engineering |
| `*.tf`, `*.bicep`, `*.bicepparam`, or `*.yaml` files under `infra/`, `terraform/`, `iac/`, or `deploy/` | Infrastructure (IaC) |
| Only `*.md` files with no code | Documentation only |

**Present the detected project type to the user for confirmation:**

```
Detected project type: [software | database | infrastructure | documentation | unknown]

Detected indicators:
- [list the files or directories that led to this conclusion]

Is this correct? (y/n, or describe your project type)
```

**If the user confirms or corrects the type, apply the corresponding agent preset:**

| Project Type | Recommended Agent Set | Skip or Deprioritize |
|---|---|---|
| **Software** (default) | All 8 core agents | None |
| **Database** | planner, coder (SQL/migrations), reviewer, security-auditor, documenter, orchestrator | api-agent, tester (unless integration tests exist), architect (unless schema design is complex) |
| **Infrastructure** | planner, architect, coder (IaC), reviewer, security-auditor, documenter, orchestrator | api-agent, tester (unless policy tests exist) |
| **Documentation** | planner, documenter, reviewer, orchestrator | coder, tester, security-auditor, architect |

After confirming the type, proceed to Step 1 to analyze the tech stack.

**If the project type cannot be determined**, ask the user directly:

```
I couldn't detect your project type from the repository contents.
What best describes this project?
  1. Software application (web app, API, CLI, library, etc.)
  2. Database / data engineering (schemas, migrations, pipelines)
  3. Infrastructure as code (Terraform, Bicep, Ansible, Kubernetes, etc.)
  4. Documentation only
  5. Something else — describe it
```

### Step 1: Analyze the Repository

Detect the project's technology stack by examining these files (check each if it exists):

| File | What to Extract |
|------|----------------|
| `package.json` | Languages (TypeScript/JavaScript), package manager (npm/yarn/pnpm), test framework (Jest/Vitest/Mocha), build/lint/test scripts |
| `go.mod` | Go version, module name |
| `pyproject.toml` / `requirements.txt` / `setup.py` | Python version, dependencies, test framework (pytest/unittest) |
| `Cargo.toml` | Rust version, dependencies |
| `Makefile` | Build, test, lint commands |
| `Dockerfile` | Base image, build steps |
| `.github/workflows/` | CI commands, test/lint/build steps |
| `tsconfig.json` | TypeScript configuration |
| `.eslintrc*` / `biome.json` / `.prettierrc` | Lint/format tools |
| `docker-compose.yml` | Database engine, services |
| `prisma/schema.prisma` / `migrations/` | ORM, database engine |

**If the repository is empty or has no detectable config files**, skip auto-detection and go directly to Step 2 to ask the user for their project details.

### Step 2: Build a Summary

**If config files were found:** compile the detected information into a summary and present it to the user for confirmation or corrections.

**If the repository is empty or new:** ask the user directly for their project details:

- What languages and frameworks will you use?
- What package manager? (npm, pnpm, yarn, go mod, pip, cargo, etc.)
- What test framework? (Jest, pytest, go test, etc.)
- What are your build, test, and lint commands?
- Will the project have an API? If so, what framework? (Express, FastAPI, Gin, etc.)
- Will the project use a database? If so, which engine and ORM?

Present the gathered information as a summary:

```
Tech Stack: [detected or user-provided]
Languages: [detected or user-provided]
Package Manager: [detected or user-provided]
Test Framework: [detected or user-provided]
Build Command: [detected or user-provided]
Test Command: [detected or user-provided]
Lint Command: [detected or user-provided]
API Framework: [if applicable]
Database Engine: [if applicable]
ORM/Migration Tool: [if applicable]
```

### Step 3: Confirm with User

Before making changes, show the full summary and ask the user to confirm or correct any values.

**If the user doesn't know their tech stack yet or can't provide details**, stop here. Do not fill in any placeholders with guessed or assumed values. Inform the user they can run `/setup-teamwork` again later when their tech stack is decided.

### Step 4: Fill In Placeholders

For each `.agent.md` file in `.github/agents/`:

1. Read the file
2. Find lines containing `<!-- CUSTOMIZE -->` and bracketed placeholder values like `[e.g., ...]`
3. Replace the bracketed placeholder text with the actual detected values
4. Remove the `<!-- CUSTOMIZE -->` comment (it's no longer needed once filled in)
5. Write the updated file

Only fill in values that were detected or confirmed by the user. Leave unknown values as placeholders.

### Step 5: Verify

List all remaining unfilled placeholders (if any) and inform the user which agent files still need manual input.

## What Not to Do

- 🚫 Never guess values — only use what's detected or confirmed by the user.
- 🚫 Never modify agent instructions, boundaries, or responsibilities — only fill in Project Knowledge placeholders.
- 🚫 Never remove agent files that aren't relevant (e.g., `dba-agent` when there's no database). The user decides which agents to keep.
- 🚫 Never skip Step 0 — project type detection affects which placeholders are relevant and which agents the user actually needs.
