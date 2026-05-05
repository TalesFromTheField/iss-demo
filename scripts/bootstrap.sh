#!/bin/bash
# =============================================================================
# ISS Demo — Fabric Bootstrap Script
#
# Runs inside an Azure deploymentScript (managed ACI) as part of 'azd up' or
# the Deploy to Azure flow. Performs all Fabric setup automatically:
#
#   1. Installs ms-fabric-cli
#   2. Authenticates with Fabric using an app registration (service principal)
#   3. Creates the Fabric workspace (app registration auto-becomes Admin)
#   4. Optionally grants Admin access to ADMIN_EMAIL
#   5. Creates Eventhouse, KQL Database, and tables (idempotent)
#   6. Optionally deploys Power BI report from PBI/ISS.pbix
#   7. Captures the FabricIngestionUri from the deployment output
#   8. Updates the Container App with FabricIngestionUri so it can start
#      streaming data to Fabric immediately
#
# Environment variables (injected by Bicep deploymentScript):
#   FABRIC_CLIENT_ID        — App Registration (client) ID
#   FABRIC_CLIENT_SECRET    — App Registration client secret (secure)
#   FABRIC_TENANT_ID        — Azure / Entra tenant ID
#   CONTAINER_APP_NAME      — Name of the Azure Container App to update
#   AZURE_RESOURCE_GROUP    — Resource group containing the Container App
#   FABRIC_WORKSPACE_NAME   — Display name for the workspace to create (default: iss-demo)
#   ADMIN_EMAIL             — Optional: user or group email to grant Admin on the workspace
#   DEPLOY_PBI_REPORT       — Optional: set to "true" to deploy PBI/ISS.pbix automatically
#   DEPLOY_FABRIC_SCRIPT    — Optional: URL override for deploy-fabric.sh
#
# Output (written to $AZ_SCRIPTS_OUTPUT_PATH):
#   { "fabricIngestionUri": "https://trd-xxx.region.kusto.data.microsoft.com",
#     "workspaceId": "<guid>" }
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -- Defaults -----------------------------------------------------------------

FABRIC_WORKSPACE_NAME="${FABRIC_WORKSPACE_NAME:-iss-demo}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
DEPLOY_PBI_REPORT="${DEPLOY_PBI_REPORT:-false}"

# -- Validate required env vars -----------------------------------------------

for var in FABRIC_CLIENT_ID FABRIC_CLIENT_SECRET FABRIC_TENANT_ID \
           CONTAINER_APP_NAME AZURE_RESOURCE_GROUP; do
    if [[ -z "${!var:-}" ]]; then
        err "Missing required environment variable: $var"
        exit 1
    fi
done

# -- JSON helper (written to a temp file to avoid inline quoting issues) ------

cat > /tmp/json_helper.py << 'PYEOF'
#!/usr/bin/env python3
"""Parse fields from fab API JSON responses. Handles the { status_code, text: {...} } envelope."""
import sys, json

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ''
    data = json.load(sys.stdin)

    if action == 'status':
        print(data.get('status_code', ''))

    elif action == 'field':
        field = sys.argv[2]
        inner = data.get('text', data)
        if isinstance(inner, dict) and field in inner:
            print(inner[field])
        elif field in data:
            print(data[field])
        else:
            print('')

    elif action == 'find_by_name':
        name = sys.argv[2]
        inner = data.get('text', data)
        items = inner.get('value', []) if isinstance(inner, dict) else []
        match = [w for w in items if w.get('displayName') == name]
        print(match[0]['id'] if match else '')

if __name__ == '__main__':
    main()
PYEOF

# Helpers that use json_helper.py to parse fab API JSON envelopes.
json_status()    { echo "$1" | python3 /tmp/json_helper.py status; }
json_field()     { echo "$1" | python3 /tmp/json_helper.py field "$2"; }
find_by_name()   { echo "$1" | python3 /tmp/json_helper.py find_by_name "$2"; }

# URL-encode a value (keeps client secret off the process argument list).
url_encode() { printf '%s' "$1" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read()))"; }

# -- Install ms-fabric-cli ----------------------------------------------------

info "Installing ms-fabric-cli..."
pip install -q --disable-pip-version-check ms-fabric-cli
ok "ms-fabric-cli installed: $(fab --version 2>/dev/null || echo 'unknown')"

# -- Authenticate with Fabric -------------------------------------------------

info "Authenticating with Fabric (app registration: $FABRIC_CLIENT_ID)..."
fab auth login \
    -u "$FABRIC_CLIENT_ID" \
    -p "$FABRIC_CLIENT_SECRET" \
    --tenant "$FABRIC_TENANT_ID"
ok "Fabric authenticated"

# -- Create or reuse Fabric workspace -----------------------------------------

info "Creating Fabric workspace '$FABRIC_WORKSPACE_NAME'..."

WORKSPACE_RESPONSE=$(fab api -X post workspaces \
    -i "{\"displayName\": \"$FABRIC_WORKSPACE_NAME\"}" 2>&1) || true

STATUS=$(json_status "$WORKSPACE_RESPONSE")
WORKSPACE_ID=""

if [[ "$STATUS" == "201" ]]; then
    WORKSPACE_ID=$(json_field "$WORKSPACE_RESPONSE" "id")
    ok "Workspace created: $WORKSPACE_ID (app registration is auto-Admin)"
elif [[ "$STATUS" == "409" ]]; then
    warn "Workspace '$FABRIC_WORKSPACE_NAME' already exists — finding existing workspace ID..."
    WORKSPACE_LIST=$(fab api -X get workspaces 2>&1) || true
    WORKSPACE_ID=$(find_by_name "$WORKSPACE_LIST" "$FABRIC_WORKSPACE_NAME")
    if [[ -z "$WORKSPACE_ID" ]]; then
        err "Workspace '$FABRIC_WORKSPACE_NAME' exists but the app registration cannot access it."
        err "Grant the app registration (client ID: $FABRIC_CLIENT_ID) Admin or Member access"
        err "in the Fabric portal, then re-run the bootstrap."
        exit 1
    fi
    ok "Using existing workspace: $WORKSPACE_ID"
else
    err "Failed to create workspace '$FABRIC_WORKSPACE_NAME' (status: $STATUS):"
    err "$WORKSPACE_RESPONSE"
    exit 1
fi

# -- Grant Admin access to ADMIN_EMAIL (optional) -----------------------------

if [[ -n "$ADMIN_EMAIL" ]]; then
    info "Granting Admin access to '$ADMIN_EMAIL'..."
    ADMIN_OBJECT_ID=""

    # Try az CLI user lookup (UAMI has Directory.Read if granted via Bicep)
    ADMIN_OBJECT_ID=$(az ad user show --id "$ADMIN_EMAIL" --query id -o tsv 2>/dev/null || echo "")

    # Try az CLI group lookup (handles group emails / display names)
    if [[ -z "$ADMIN_OBJECT_ID" ]]; then
        ADMIN_OBJECT_ID=$(az ad group show --group "$ADMIN_EMAIL" --query id -o tsv 2>/dev/null || echo "")
    fi

    # Fallback: Microsoft Graph API with SP credentials (needs User.Read.All or Directory.Read.All)
    if [[ -z "$ADMIN_OBJECT_ID" ]]; then
        info "  az lookup failed — trying Microsoft Graph API with SP credentials..."
        ENCODED_SECRET=$(url_encode "$FABRIC_CLIENT_SECRET")
        GRAPH_TOKEN=$(curl -s -X POST \
            "https://login.microsoftonline.com/$FABRIC_TENANT_ID/oauth2/v2.0/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=client_credentials&client_id=$FABRIC_CLIENT_ID&client_secret=${ENCODED_SECRET}&scope=https://graph.microsoft.com/.default" \
            | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

        if [[ -n "$GRAPH_TOKEN" ]]; then
            ADMIN_OBJECT_ID=$(curl -s \
                "https://graph.microsoft.com/v1.0/users/$ADMIN_EMAIL" \
                -H "Authorization: Bearer $GRAPH_TOKEN" \
                | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
        fi
    fi

    if [[ -n "$ADMIN_OBJECT_ID" ]]; then
        if fab acl set "${FABRIC_WORKSPACE_NAME}.Workspace" -I "$ADMIN_OBJECT_ID" -R Admin --force 2>&1; then
            ok "Admin access granted to $ADMIN_EMAIL (object ID: $ADMIN_OBJECT_ID)"
        else
            warn "fab acl set failed — add '$ADMIN_EMAIL' as Admin manually in the Fabric portal."
        fi
    else
        warn "Could not resolve Entra object ID for '$ADMIN_EMAIL'."
        warn "Add Admin access manually in the Fabric portal: https://app.fabric.microsoft.com"
        warn "  Workspace: $FABRIC_WORKSPACE_NAME"
    fi
fi

# -- Download and run deploy-fabric.sh ----------------------------------------

SCRIPT_URL="${DEPLOY_FABRIC_SCRIPT:-https://raw.githubusercontent.com/TalesFromTheField/iss-demo/main/scripts/deploy-fabric.sh}"
info "Downloading deploy-fabric.sh from: $SCRIPT_URL"
curl -fsSL "$SCRIPT_URL" -o /tmp/deploy-fabric.sh
chmod +x /tmp/deploy-fabric.sh
ok "Script downloaded"

info "Running Fabric deployment for workspace: $WORKSPACE_ID"
DEPLOY_OUTPUT=$(/tmp/deploy-fabric.sh --workspace-id "$WORKSPACE_ID" 2>&1) || {
    err "deploy-fabric.sh failed. Output:"
    echo "$DEPLOY_OUTPUT"
    exit 1
}

echo "$DEPLOY_OUTPUT"

# -- Extract FabricIngestionUri -----------------------------------------------

FABRIC_URI=$(echo "$DEPLOY_OUTPUT" | grep "FabricIngestionUri = " | awk '{print $NF}' | tail -1)

if [[ -z "$FABRIC_URI" ]]; then
    warn "Could not extract FabricIngestionUri from deployment output."
    warn "Set it manually after deployment:"
    warn "  az containerapp update --name $CONTAINER_APP_NAME --resource-group $AZURE_RESOURCE_GROUP \\"
    warn "    --set-env-vars FabricIngestionUri=<uri>"
    echo "{\"fabricIngestionUri\":\"\",\"workspaceId\":\"$WORKSPACE_ID\"}" > "${AZ_SCRIPTS_OUTPUT_PATH:-/dev/null}"
    exit 0
fi

ok "FabricIngestionUri: $FABRIC_URI"

# -- Deploy Power BI report (optional) ----------------------------------------

if [[ "${DEPLOY_PBI_REPORT}" == "true" ]]; then
    info "Deploying Power BI report (PBI/ISS.pbix) via Power BI REST API..."

    PBIX_URL="https://github.com/TalesFromTheField/iss-demo/raw/main/PBI/ISS.pbix"
    if curl -fL "$PBIX_URL" -o /tmp/ISS.pbix 2>/dev/null; then
        # Get Power BI API bearer token using SP client credentials flow
        ENCODED_SECRET=$(url_encode "$FABRIC_CLIENT_SECRET")
        PBI_TOKEN=$(curl -s -X POST \
            "https://login.microsoftonline.com/$FABRIC_TENANT_ID/oauth2/v2.0/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=client_credentials&client_id=$FABRIC_CLIENT_ID&client_secret=${ENCODED_SECRET}&scope=https://analysis.windows.net/powerbi/api/.default" \
            | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

        if [[ -n "$PBI_TOKEN" ]]; then
            HTTP_CODE=$(curl -s -o /tmp/pbi-import.json -w "%{http_code}" \
                -X POST \
                "https://api.powerbi.com/v1.0/myorg/groups/$WORKSPACE_ID/imports?datasetDisplayName=ISS&nameConflict=CreateOrOverwrite" \
                -H "Authorization: Bearer $PBI_TOKEN" \
                -F "file=@/tmp/ISS.pbix") || true

            if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "202" ]]; then
                ok "Power BI report imported successfully (HTTP $HTTP_CODE)"
            else
                warn "Power BI import returned HTTP $HTTP_CODE. Check /tmp/pbi-import.json for details."
                warn "Import manually: open the Fabric workspace and upload PBI/ISS.pbix"
            fi
        else
            warn "Could not obtain Power BI API token — skipping report import."
            warn "Import manually: open the Fabric workspace and upload PBI/ISS.pbix"
        fi
    else
        warn "Could not download ISS.pbix from GitHub — skipping report import."
    fi
fi

# -- Update Container App env var ---------------------------------------------

info "Updating Container App '$CONTAINER_APP_NAME' with FabricIngestionUri..."
az containerapp update \
    --name "$CONTAINER_APP_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --set-env-vars "FabricIngestionUri=$FABRIC_URI" \
    --output none
ok "Container App updated — ISS Demo is now streaming to Fabric"

# -- Write outputs ------------------------------------------------------------

echo "{\"fabricIngestionUri\": \"$FABRIC_URI\", \"workspaceId\": \"$WORKSPACE_ID\"}" > "${AZ_SCRIPTS_OUTPUT_PATH:-/dev/null}"
info "Bootstrap complete."
