# Secrets Policy

How agents and humans handle secrets, credentials, and sensitive data in this project.

## Rules

1. **Never commit secrets.** Agents and humans must never commit API keys, tokens,
   passwords, private keys, or any credentials to the repository. No exceptions.

2. **Use environment variables.** Secrets should be provided via environment variables
   or `.env` files. All `.env` files must be listed in `.gitignore` (they already are).

3. **Agent authentication.** Each tool manages its own authentication separately:
   - Claude CLI uses its own auth mechanism (`claude` login)
   - GitHub CLI uses `gh auth`
   - Other tools use their respective credential stores
   - Agents do not share credentials with each other or store them in the repo.

4. **Escalate when blocked.** If an agent needs a secret to complete its work (e.g., an
   API key for a third-party service), it must stop and escalate to the Human. Agents
   must not attempt to find, guess, or extract secrets from other sources.

5. **Security Auditor checks.** The Security Auditor role is responsible for verifying
   that no secrets appear in PRs or committed code. This includes checking for:
   - Hardcoded credentials or API keys
   - Private keys or certificates
   - Connection strings with embedded passwords
   - Tokens or session identifiers

## Pre-Commit Protection

This project uses a pre-commit hook that detects private keys before they can be
committed. See `.pre-commit-config.yaml` for the configuration. This is a safety net,
not a substitute for careful handling — agents should never reach the point where the
hook needs to catch something.

## If a Secret Is Accidentally Committed

1. Rotate the exposed credential immediately.
2. Remove it from Git history (not just the working tree).
3. File an incident report documenting what was exposed and for how long.
4. The Security Auditor should review the incident and recommend preventive measures.

## Automated Scanning

Teamwork can enforce automated secrets scanning as a quality gate during workflow
handoff advancement. When enabled, no workflow step can advance until the
repository is confirmed free of secrets.

### Configuration

Set `quality_gates.secrets_scan: true` in `.teamwork/config.yaml` to enforce
scanning on every handoff. The default is `false` (opt-in).

```yaml
quality_gates:
  secrets_scan: false   # set to true to enforce on every handoff
```

### Supported Scanners

Teamwork tries each of the following tools in order, using the first one found
in `PATH`:

| Tool | Installation | Command Run |
|------|-------------|-------------|
| [gitleaks](https://github.com/gitleaks/gitleaks) | `brew install gitleaks` or download from GitHub releases | `gitleaks detect --source . --no-git` |
| [detect-secrets](https://github.com/Yelp/detect-secrets) | `pip install detect-secrets` | `detect-secrets scan` |
| [trufflehog](https://github.com/trufflesecurity/trufflehog) | `brew install trufflehog` or download from GitHub releases | `trufflehog filesystem .` |

If none of these tools are installed, the gate logs a warning and **does not
block** the workflow. Install at least one scanner to get enforcement.

A non-zero exit code from any scanner is interpreted as "secrets found" and
the gate fails, blocking handoff advancement.

### Running Scans On Demand

Use `teamwork scan [--dir <path>]` to run a secrets scan outside of a workflow:

```bash
teamwork scan
# Running secrets scan...
# ✅ No secrets found.

teamwork scan --dir /path/to/project
```

Exit codes:
- `0` — no secrets detected
- `1` — secrets found (output includes scanner details)

### False Positives

If the scanner flags a legitimate fixture or test value, configure the scanner's
allowlist (e.g., `.gitleaksignore` for gitleaks) before disabling the gate
project-wide.
