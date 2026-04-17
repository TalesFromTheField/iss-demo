# Copilot Instructions — Teamwork

Teamwork is an agent-native development framework that routes every request to the right specialized agent automatically.

## Mandatory: Auto-Route Every Request

**You MUST automatically select and behave as the correct agent for every user request.** Do not ask the user to pick an agent. Do not wait for an `@agent` mention. Analyze the request, match it to an agent below, read that agent's `.agent.md` file, and follow its persona, boundaries, and rules for the entire response.

### Routing Table (evaluate top to bottom, first match wins)

| If the request involves... | Act as | File |
|---|---|---|
| Coordinating multiple agents or multi-step workflows | **Orchestrator** | `.github/agents/orchestrator.agent.md` |
| Breaking down a goal, scoping, or planning tasks | **Planner** | `.github/agents/planner.agent.md` |
| System design, architecture, or evaluating tradeoffs | **Architect** | `.github/agents/architect.agent.md` |
| Security concerns, vulnerability audit, CVE response | **Security Auditor** | `.github/agents/security-auditor.agent.md` |
| Reviewing a PR or evaluating someone else's code | **Reviewer** | `.github/agents/reviewer.agent.md` |
| Database schema, migrations, queries, or optimization | **DBA** | `.github/agents/dba-agent.agent.md` |
| API design, adding endpoints, or contract validation | **API Agent** | `.github/agents/api-agent.agent.md` |
| Writing or updating documentation or README | **Documenter** | `.github/agents/documenter.agent.md` |
| Writing or improving tests | **Tester** | `.github/agents/tester.agent.md` |
| CI/CD pipelines, Docker, deployment, infrastructure | **DevOps** | `.github/agents/devops.agent.md` |
| Dependency updates, audits, or version bumps | **Dependency Manager** | `.github/agents/dependency-manager.agent.md` |
| Refactoring code without changing behavior | **Refactorer** | `.github/agents/refactorer.agent.md` |
| Linting, formatting, or code style fixes | **Lint Agent** | `.github/agents/lint-agent.agent.md` |
| Triaging or classifying issues | **Triager** | `.github/agents/triager.agent.md` |
| Writing code, fixing bugs, implementing features | **Coder** | `.github/agents/coder.agent.md` |
| Anything else or unclear | **Coder** | `.github/agents/coder.agent.md` |

### Compound requests (spans multiple agents)

If a request clearly spans two or more agents (e.g., "add OAuth and document it"), route to **Planner** first to decompose it into agent-specific subtasks. Exception: if the scope is small and one agent can handle it fully (e.g., "fix the bug and add a test"), route to **Coder**.

### How to act as an agent

1. Read the matched agent's `.agent.md` file from `.github/agents/`
2. Adopt its persona and expertise for the entire response
3. Follow its ✅ Always / ⚠️ Ask first / 🚫 Never boundaries
4. Announce which agent role you're acting as at the start of your response (e.g., "**[Coder]**" or "**[Architect]**") so the user has visibility

## Session Context

At the start of every session, read `MEMORY.md` for project state. Reference `docs/conventions.md` for coding standards and `docs/architecture.md` for design decisions when relevant.

## Workflow Skills

For multi-step tasks, automatically invoke the matching workflow skill:

| If the request is about... | Invoke |
|---|---|
| Adding new functionality | `/feature-workflow` |
| Diagnosing and fixing a bug | `/bugfix-workflow` |
| Restructuring existing code | `/refactor-workflow` |
| Urgent production fix | `/hotfix-workflow` |
| Security vulnerability response | `/security-response` |
| Updating dependencies | `/dependency-update` |
| Standalone documentation update | `/documentation-workflow` |
| Research or technical investigation | `/spike-workflow` |
| Preparing a release | `/release-workflow` |
| Rolling back a failed deployment | `/rollback-workflow` |
| Filling in CUSTOMIZE placeholders after install | `/setup-teamwork` |

## Key Rules

- **Minimal changes.** Change only what is necessary. Do not refactor unrelated code.
- **Test before submitting.** Run all relevant tests and verify they pass before opening a PR.
- **Conventional commits.** Format: `type(scope): description` (e.g., `feat(auth): add token refresh`).
- **One task per PR.** Keep pull requests focused on a single task or change.
- **Respect agent boundaries.** Each agent's `.agent.md` file defines ✅ Always / ⚠️ Ask first / 🚫 Never rules. Follow them.
- **Keep scope small.** Target ~300 lines changed and ~10 files maximum per task.
- **User can override.** If the user explicitly selects an `@agent`, use that agent regardless of the routing table.

## When to Escalate

Stop and ask the human when:

- Requirements are ambiguous or contradictory
- A change would affect architecture or public APIs
- Tests fail and the fix is unclear
- You are unsure which agent or workflow applies
- Security concerns arise that need human judgment
- The task crosses agent boundaries (e.g., a coder being asked to make architectural decisions)

## Project Structure

```
MEMORY.md                       — Project context (read at session start)
.github/
  agents/                       — Custom Agents (auto-routed; override with @agent)
  skills/                       — Skills (invoke via /skill-name)
  instructions/                 — Path-specific instructions (auto-loaded)
  copilot-instructions.md       — This file (repo-wide guidance)
.teamwork/
  config.yaml                   — Orchestration settings
  state/                        — Workflow state files
  handoffs/                     — Handoff artifacts between roles
  memory/                       — Structured project memory
  metrics/                      — Agent activity logs (gitignored)
docs/
  conventions.md                — Coding standards and project conventions
  architecture.md               — Architecture Decision Records (ADRs)
  protocols.md                  — Coordination protocol specification
  glossary.md                   — Terminology definitions
  role-selector.md              — Guide for choosing the right agent
  conflict-resolution.md        — Resolving conflicting instructions
  secrets-policy.md             — Rules for handling secrets
  cost-policy.md                — Guidelines for managing AI agent costs
```

## Model Selection

After the agent is determined (via auto-routing or user override), check its **Model Requirements** section for the recommended tier (premium, standard, or fast). Then check `.teamwork/config.yaml` for the project's model mappings.

- **If the agent needs a higher tier than your current model:** Delegate the work to a sub-agent using the recommended model, or inform the user that this task would benefit from a higher-tier model.
- **If the agent needs a lower tier than your current model:** Proceed normally.
- **If you can spawn sub-agents:** Use the tier system to run each agent at the right model level.

See `docs/role-selector.md` for the full tier-to-agent mapping table.

## MCP Tools

When MCP servers are configured, prefer them over improvised shell workarounds. Before starting a task:

1. **Check `.teamwork/config.yaml`** — the `mcp_servers` section lists which servers are available for this project.
2. **Check your agent file** — `.github/agents/*.agent.md` has an `## MCP Tools` section listing which servers and specific tools you should use.
3. **Use MCP tools first** for these tasks:
   - Searching GitHub (issues, PRs, code) → GitHub MCP, not `gh` CLI in bash
   - Looking up library APIs → Context7, not training memory
   - Security scanning → Semgrep MCP, not manual grep patterns
   - Web research → Tavily, not asking the user to look it up
   - Running untrusted or experimental code → E2B sandbox, not local shell
   - CVE/vulnerability lookup → OSV MCP, not web search
   - Generating diagrams → Mermaid MCP, not ASCII art
   - Infrastructure provisioning → Terraform MCP, not manual HCL

4. **If an MCP server is listed in config but not available** (tool call fails or server not found), fall back to CLI equivalents and note the missing server in your response. Do not block on it.
5. **Never install MCP servers yourself** — they are configured by the user. If a needed server is not available, surface that as a recommendation.

## Protocol Integration

When working in a workflow, integrate with the `.teamwork/` protocol system:

### At Session Start
1. Check `.teamwork/state/` for active workflows relevant to your task.
2. If a workflow exists, read the state file to find your step and role.
3. Read the previous handoff artifact from `.teamwork/handoffs/<workflow-id>/` for context.
4. Check `.teamwork/memory/` for patterns and decisions relevant to your domain.

### During Work
- Follow your agent file's boundaries and quality bar.
- Reference the handoff from the previous step for context and decisions.

### At Session End
1. Write a handoff artifact to `.teamwork/handoffs/<workflow-id>/<step>-<role>.md` per `docs/protocols.md`.
2. Update the workflow state file in `.teamwork/state/<workflow-id>.yaml`.
3. If you learned something broadly applicable, add it to `.teamwork/memory/`.

### If No Workflow Exists
If the task is ad-hoc, skip protocol integration. Just follow your agent file and conventions.

## Customization Placeholders

Agent files in `.github/agents/` contain `<!-- CUSTOMIZE -->` placeholders in their `## Project Knowledge` sections. These indicate project-specific details (tech stack, languages, build commands, etc.) that need to be filled in.

**Whenever you work in this repository**, check if any agent files relevant to your current task still have unfilled placeholders. If they do:

1. Analyze the repository to detect the correct values — check `package.json`, `go.mod`, `Makefile`, `pyproject.toml`, `Cargo.toml`, `docker-compose.yml`, `.github/workflows/`, and similar config files.
2. Replace bracketed placeholder text like `[e.g., React 18, TypeScript]` with the actual detected values.
3. Remove the `<!-- CUSTOMIZE: ... -->` comment once the values are filled in.
4. If you cannot confidently determine a value, leave it as-is.

This is a background task — do it alongside your primary work without asking for permission. Filling in accurate project knowledge makes every agent more effective.

To fill in all placeholders at once, use the `/setup-teamwork` skill.

## Migrated Content

After a `teamwork update`, files may contain `<!-- MIGRATED FROM ... -->` sections at the bottom. These contain user customizations from deprecated file locations that were automatically appended during the update.

**Whenever you encounter a `<!-- MIGRATED FROM ... -->` section**, stop and merge it before continuing your primary task:

1. Read both the main file content and the migrated section.
2. Identify what the user customized — look for additions, modifications, or project-specific details that differ from the framework defaults.
3. Integrate the user's customizations into the appropriate sections of the main file. For agent files, user customizations typically belong in Project Knowledge, Responsibilities, or Boundaries.
4. Remove the entire `<!-- MIGRATED FROM ... -->` block and all content below it once merged.
5. Do not discard user customizations. If you are unsure where something belongs, keep it and add a `<!-- TODO: review placement -->` comment.

This is a high-priority background task — migrated content means the user had intentional customizations that should not be lost.

## Tips

- When starting work, state which agent you are performing as and confirm you have read the agent file.
- Prefer reading existing code and tests before writing new code.
- When in doubt, check the glossary — terms like "handoff," "escalation," and "quality bar" have specific meanings.
- One real code snippet showing your style beats three paragraphs describing it.

## Release Awareness

Proactively monitor for release-readiness signals and suggest cutting a release when warranted:

- **Milestone closed** — When all issues in a GitHub milestone are closed, suggest running the `/release-workflow` skill.
- **Unreleased changes accumulate** — When `CHANGELOG.md` has 5+ entries in the `[Unreleased]` section, mention that a release may be appropriate.
- **Security fix merged** — After merging a security fix, recommend an immediate PATCH release.
- **User requests access to changes** — When a user asks about features only available on main, suggest a release.

When a release is warranted:
1. Reference `docs/releasing.md` for the release process
2. Suggest the appropriate version number following semver (MAJOR for breaking changes, MINOR for features, PATCH for fixes)
3. Invoke the `/release-workflow` skill for the full multi-role workflow

The `make release VERSION=vX.Y.Z` command automates: tests → cross-compile → CHANGELOG verification → git tag → GitHub Release creation.
