# Teamwork CLI

## Overview

The Teamwork CLI (`teamwork`) provides human oversight and control over agent workflows. It is the primary interface for developers to initialize, monitor, approve, and manage the lifecycle of agent-driven tasks.

## Installation

### GitHub CLI Extension (Recommended)

The easiest way to get started is via the `gh` CLI extension:

```bash
gh extension install JoshLuedeman/gh-teamwork
gh teamwork init
```

See [gh-teamwork Extension](#gh-teamwork-extension) below for extension commands.

### Docker (Recommended)

```bash
# Build the image
make docker-build

# Run any command
docker run --rm -v "$(pwd):/project" teamwork status

# Or use the Makefile shortcut
make docker-run CMD="status"
```

Set up a shell alias for convenience:

```bash
alias teamwork='docker run --rm -u "$(id -u):$(id -g)" -v "$(pwd):/project" teamwork'
```

### From Source

Requires Go 1.22+.

```bash
make build-cli    # builds to bin/teamwork
make install-cli  # installs to GOPATH/bin

# Or directly
go install github.com/JoshLuedeman/teamwork/cmd/teamwork@latest
```

## Commands

### `teamwork init`

Initialize a complete Teamwork project: fetch framework files and create config.

```bash
teamwork init [flags]
```

Sets up a complete Teamwork project in two steps:

1. **Fetches framework files** (agents, skills, docs, instructions, templates) from the upstream Teamwork repository.
2. **Creates the `.teamwork/` directory** with config, memory seeds, and subdirectories.

If framework files are already installed, the fetch step is skipped and only the config is created. Use `--force` to re-fetch framework files.

**Flags:**
- `--source` — Source repository in `owner/repo` format (default: `joshluedeman/teamwork`)
- `--ref` — Git ref to install from (branch, tag, or SHA; default: `main`)
- `--force` — Re-fetch framework files even if already installed
- `--preset` — Use a preset config for a specific stack (e.g., `go-api`, `ts-react`)
- `--non-interactive` — Skip the interactive wizard

**Example:**
```bash
# Full setup from the official Teamwork template
teamwork init

# Use a custom fork as the source
teamwork init --source myorg/teamwork-template

# Install from a specific version
teamwork init --ref v1.2.0

# Re-fetch framework files (overwrite existing)
teamwork init --force

# Use a preset for a Go API project
teamwork init --preset go-api
```

### `teamwork install` *(deprecated)*

> **Deprecated:** Use `teamwork init` instead — it now fetches framework files and creates config in one step.

The `install` command still works but delegates to `init` internally.

### `teamwork update`

Update Teamwork framework files to the latest version.

```bash
teamwork update [flags]
```

Fetches the latest framework files from the upstream Teamwork repository and applies changes. Files that have been modified locally are skipped with a warning unless `--force` is set.

**Flags:**
- `--source` — Source repository in `owner/repo` format (default: `joshluedeman/teamwork`)
- `--ref` — Git ref to update to (branch, tag, or SHA; default: `main`)
- `--force` — Overwrite user-modified files without warning
- `--check` — Check for drift between local files and upstream without writing any changes (exits 1 if drift detected)
- `--create-issue` — Create a GitHub issue assigned to Copilot when placeholders are detected after update (default: `true`)

**Example:**
```bash
# Update to the latest version
teamwork update

# Update from a custom source
teamwork update --source myorg/teamwork-template

# Update to a specific version
teamwork update --ref v1.2.0

# Force update, overwriting local changes
teamwork update --force

# Check for drift without making changes (useful in CI)
teamwork update --check
```

### `teamwork validate`

Validate the `.teamwork/` directory structure and contents.

```bash
teamwork validate [flags]
```

Checks that configuration, state files, handoff documents, and memory files are well-formed and contain required fields.

**Flags:**
- `--json` — Output results as a JSON array
- `--quiet` — Suppress passing checks (only show failures)

**Exit codes:**
- `0` — All checks passed
- `1` — One or more checks failed
- `2` — Cannot run validation (e.g., `.teamwork/` directory not found)

**Example:**
```bash
# Human-readable output
teamwork validate

# JSON output for CI pipelines
teamwork validate --json

# Only show failures
teamwork validate --quiet
```

### `teamwork start <type> <goal>`

Start a new workflow.

```bash
teamwork start <type> <goal> [flags]
```

**Arguments:**
- `type` — Workflow type: `feature`, `bugfix`, `refactor`, `hotfix`, `security-response`, `dependency-update`, `documentation`, `spike`, `release`, or `rollback`
- `goal` — Description of what the workflow should accomplish

**Flags:**
- `--issue <number>` (or `-i`) — Link the workflow to a GitHub issue

**Example:**
```bash
teamwork start feature "Add user authentication" --issue 42
```

### `teamwork status`

Show the status of all active workflows.

```bash
teamwork status
```

Displays each active workflow with its current phase, pending actions, and overall progress.

### `teamwork next`

Show pending actions that need human attention.

```bash
teamwork next
```

Lists quality gates awaiting approval, blocked workflows, and other items requiring human input.

### `teamwork approve <id>`

Approve a quality gate to advance a workflow.

```bash
teamwork approve <id>
```

**Arguments:**
- `id` — The workflow identifier (e.g., `feature/42-add-user-authentication`)

### `teamwork block <id>`

Block a workflow with a reason.

```bash
teamwork block <id> --reason <text>
```

**Arguments:**
- `id` — The workflow identifier

**Flags:**
- `--reason <text>` — Explanation for why the workflow is blocked (required)

### `teamwork complete <id>`

Mark a workflow as complete.

```bash
teamwork complete <id>
```

**Arguments:**
- `id` — The workflow identifier

### `teamwork cancel <id>`

Cancel an active or blocked workflow.

```bash
teamwork cancel <id> [--reason <text>]
```

**Arguments:**
- `id` — The workflow identifier

**Flags:**
- `--reason <text>` (or `-r`) — Explanation for the cancellation (optional)

Cancellation sets the workflow to terminal `cancelled` status. It refuses to operate on already-terminal workflows (completed, cancelled, failed). State files are preserved for audit trail.

### `teamwork fail <id>`

Mark a workflow as failed.

```bash
teamwork fail <id> --reason <text>
```

**Arguments:**
- `id` — The workflow identifier

**Flags:**
- `--reason <text>` (or `-r`) — Explanation for the failure (required)

Failure sets the workflow to terminal `failed` status. It refuses to operate on already-terminal workflows. The reason is recorded in the state file and logged as a metrics event.

### `teamwork history <id>`

Show the full history of a workflow.

```bash
teamwork history <id>
```

**Arguments:**
- `id` — The workflow identifier

Displays all state transitions, approvals, blocks, and agent actions for the workflow.

### `teamwork dashboard`

Open the interactive TUI dashboard.

```bash
teamwork dashboard
```

Provides a terminal-based interface for monitoring and managing all workflows in real time.

### `teamwork doctor`

Check environment and project health.

```bash
teamwork doctor
```

Runs diagnostic checks on the development environment and project configuration, reporting issues with actionable fixes.

**Checks performed:**
- `.teamwork/` directory exists with expected subdirectories
- `config.yaml` is valid (reuses `teamwork validate` logic)
- Git is installed and configured (user.name, user.email)
- AI CLI tools available (Claude, GitHub Copilot CLI)
- GitHub CLI installed and authenticated
- `GH_TOKEN` environment variable set
- Go toolchain available

**Output format:**
```
[✓] .teamwork/ directory initialized
[✓] config.yaml valid
[✓] Git configured (user: Josh)
[✗] Claude CLI not found — install: npm install -g @anthropic-ai/claude-code
[✓] GitHub CLI authenticated
[!] GH_TOKEN not set — required for private repos
```

**Exit codes:**
- `0` — All checks passed (warnings are OK)
- `1` — One or more checks failed

### `teamwork scan`

Run a secrets scan on the project.

```bash
teamwork scan
```

Scans the project directory for secrets using `gitleaks`, `detect-secrets`, or `trufflehog` (whichever is available). Exits `0` if the project is clean; exits `1` if secrets are found.

### `teamwork timeline <id>`

Show a visual timeline of workflow steps.

```bash
teamwork timeline <workflow-id> [flags]
```

Displays an ASCII table of workflow steps with status, duration, and handoff information.

**Arguments:**
- `id` — The workflow identifier

**Flags:**
- `--mermaid` — Emit a Mermaid Gantt diagram instead of an ASCII table

**Example:**
```bash
teamwork timeline feature/42-auth
teamwork timeline feature/42-auth --mermaid
```

### `teamwork resume <id>`

Resume a workflow from a saved checkpoint.

```bash
teamwork resume <workflow-id> [flags]
```

Loads and displays a saved checkpoint for the given workflow, showing where work was interrupted so an agent can pick up without losing context.

**Arguments:**
- `id` — The workflow identifier

**Flags:**
- `--clear` — Delete the checkpoint without resuming

**Example:**
```bash
teamwork resume feature/42-auth
teamwork resume feature/42-auth --clear
```

### `teamwork report <id>`

Generate an exportable workflow report.

```bash
teamwork report <workflow-id> [flags]
```

Builds a consolidated report including steps, handoffs, gate results, and cost estimates.

**Arguments:**
- `id` — The workflow identifier

**Flags:**
- `--format` — Output format: `md` (default), `json`, or `html`

**Example:**
```bash
teamwork report feature/42-auth
teamwork report feature/42-auth --format json
teamwork report feature/42-auth --format html > report.html
```

### `teamwork search <query>`

Search memory, handoffs, ADRs, and state for matching content.

```bash
teamwork search <query> [flags]
```

Searches across all `.teamwork/` artifacts for the given query string. Multi-word queries can be written without quotes.

**Arguments:**
- `query` — Search query (multi-word queries without quotes are joined automatically)

**Flags:**
- `--domain` — Filter memory results by domain tag
- `--type` — Filter by artifact type: `memory`, `handoff`, `adr`, or `state`

**Example:**
```bash
teamwork search authentication
teamwork search "rate limiting" --type adr
teamwork search auth --domain security
```

### `teamwork context <id>`

Assemble distilled agent context for a workflow step.

```bash
teamwork context <workflow-id> [flags]
```

Gathers state, handoff, memory, and metrics data for the given workflow step and emits it as a compact context block suitable for pasting into an agent session.

**Arguments:**
- `id` — The workflow identifier

**Flags:**
- `--step` — Step number to assemble context for (default: current step)

**Example:**
```bash
teamwork context feature/42-auth
teamwork context feature/42-auth --step 3
```

### `teamwork memory`

Manage structured project memory.

```bash
teamwork memory <subcommand> [flags]
```

#### `teamwork memory add`

Add a new memory entry.

```bash
teamwork memory add --category <cat> --domain <domains> --content <text> [flags]
```

**Flags:**
- `--category` — Category: `patterns`, `antipatterns`, `decisions`, `feedback` (required)
- `--domain` — Comma-separated domain tags (required)
- `--content` — Memory content (required)
- `--source` — Where this was learned (e.g., `PR #42`)
- `--context` — Additional context

**Example:**
```bash
teamwork memory add \
  --category patterns \
  --domain auth,api \
  --content "Use middleware for auth checks" \
  --source "PR #42 review"
```

#### `teamwork memory search`

Search memory entries by domain.

```bash
teamwork memory search <domain>
```

**Example:**
```bash
teamwork memory search auth
```

#### `teamwork memory list`

List all memory entries, optionally filtered by category.

```bash
teamwork memory list [--category <cat>]
```

#### `teamwork memory sync`

Sync memory entries to a spoke repository by domain.

```bash
teamwork memory sync --repo <name> --domain <domains>
```

Copies entries matching the specified domains from the hub repo's memory to the target spoke repo. Requires repos to be configured in `.teamwork/config.yaml`.

**Example:**
```bash
teamwork memory sync --repo api --domain auth,api
```

### `teamwork metrics`

View workflow metrics and reports.

```bash
teamwork metrics <subcommand>
```

#### `teamwork metrics summary`

Show per-workflow metric summaries including steps, duration, failures, escalations, defects, and cost estimates.

```bash
teamwork metrics summary
```

#### `teamwork metrics roles`

Show per-role aggregate statistics across all workflows.

```bash
teamwork metrics roles
```

#### `teamwork metrics agents`

Show a per-agent performance scorecard including gate pass rate, escalation rate, and cost.

```bash
teamwork metrics agents [flags]
```

**Flags:**
- `--since` — Filter events after this duration ago (e.g. `24h`, `7d`)
- `--format` — Output format: `json`

### `teamwork handoff`

Manage handoff artifacts between workflow roles.

```bash
teamwork handoff <subcommand>
```

#### `teamwork handoff init <id>`

Generate a role-specific handoff template for the current step of a workflow.

```bash
teamwork handoff init <workflow-id>
```

Creates a template handoff document at `.teamwork/handoffs/<id>/step-N-<role>.md` pre-filled with the role's expected outputs and acceptance criteria.

**Arguments:**
- `id` — The workflow identifier

**Example:**
```bash
teamwork handoff init feature/42-auth
```

### `teamwork feedback`

Manage structured reviewer feedback entries.

```bash
teamwork feedback <subcommand>
```

#### `teamwork feedback list`

List feedback entries, optionally filtered by domain or status.

```bash
teamwork feedback list [flags]
```

**Flags:**
- `--domain` — Filter by domain tag
- `--status` — Filter by status: `open` or `resolved`

#### `teamwork feedback resolve <id>`

Mark a feedback entry as resolved.

```bash
teamwork feedback resolve <feedback-id>
```

### `teamwork analytics`

View aggregate workflow analytics.

```bash
teamwork analytics <subcommand>
```

#### `teamwork analytics summary`

Show aggregate workflow summary statistics across all workflows.

```bash
teamwork analytics summary [flags]
```

**Flags:**
- `--since` — Only include workflows created after this duration ago (e.g. `24h`, `7d`)
- `--type` — Filter by workflow type
- `--format` — Output format: `json`

**Example:**
```bash
teamwork analytics summary
teamwork analytics summary --since 7d --type feature
teamwork analytics summary --format json
```

### `teamwork repos`

List configured repositories and their status.

```bash
teamwork repos
```

Shows each configured spoke repository with its name, GitHub slug, local path, and status (clean, dirty, not found).

## gh-teamwork Extension

The `gh-teamwork` extension provides `gh` CLI aliases for common Teamwork commands. Install it with:

```bash
gh extension install JoshLuedeman/gh-teamwork
```

### Extension Commands

| Command | Equivalent | Description |
|---------|-----------|-------------|
| `gh teamwork init` | `teamwork init` | Initialize `.teamwork/` directory structure |
| `gh teamwork update` | `teamwork update` | Update Teamwork framework files to latest version |

All other Teamwork commands are available via the `teamwork` CLI directly (see [Installation](#installation) to install the binary).

## Examples

A typical workflow session:

```bash
# Initialize in a new project
teamwork init

# Start a feature workflow
teamwork start feature "Add user authentication" --issue 42

# Check what needs to happen next
teamwork next

# After an agent completes a step, check status
teamwork status

# Approve the work and advance
teamwork approve feature/42-add-user-authentication

# View the full history
teamwork history feature/42-add-user-authentication

# Open the interactive dashboard
teamwork dashboard
```

## Configuration

The CLI reads configuration from `.teamwork/config.yaml` in the project root. See [`docs/protocols.md`](protocols.md) for details on the protocol file format and coordination model.

## How It Works

The CLI reads and writes `.teamwork/` protocol files to manage workflow state. It does not invoke AI tools directly — that is the orchestrator agent's responsibility. The CLI provides human visibility and control over the workflow lifecycle, acting as the interface between developers and the agent coordination layer.
