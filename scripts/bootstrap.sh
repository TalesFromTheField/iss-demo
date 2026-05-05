#!/bin/bash
# =============================================================================
# ISS Demo — Fabric Bootstrap Script
#
# Runs inside an Azure deploymentScript (managed ACI) as part of 'azd up' or
# the Deploy to Azure flow. Performs all Fabric setup automatically:
#
#   1. Installs ms-fabric-cli
#   2. Authenticates with Fabric using a service principal
#   3. Creates Eventhouse, KQL Database, and tables (idempotent)
#   4. Captures the FabricIngestionUri from the deployment output
#   5. Updates the Container App with FabricIngestionUri so it can start
#      streaming data to Fabric immediately
#
# Environment variables (injected by Bicep deploymentScript):
#   FABRIC_CLIENT_ID       — Service principal application (client) ID
#   FABRIC_CLIENT_SECRET   — Service principal client secret (secure)
#   FABRIC_TENANT_ID       — Azure / Entra tenant ID
#   FABRIC_WORKSPACE_ID    — Fabric workspace GUID
#   CONTAINER_APP_NAME     — Name of the Azure Container App to update
#   AZURE_RESOURCE_GROUP   — Resource group containing the Container App
#   DEPLOY_FABRIC_SCRIPT   — URL of deploy-fabric.sh to download (optional override)
#
# Output (written to $AZ_SCRIPTS_OUTPUT_PATH):
#   { "fabricIngestionUri": "https://trd-xxx.region.kusto.data.microsoft.com" }
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -- Validate required env vars -----------------------------------------------

for var in FABRIC_CLIENT_ID FABRIC_CLIENT_SECRET FABRIC_TENANT_ID FABRIC_WORKSPACE_ID \
           CONTAINER_APP_NAME AZURE_RESOURCE_GROUP; do
    if [[ -z "${!var:-}" ]]; then
        err "Missing required environment variable: $var"
        exit 1
    fi
done

# -- Install ms-fabric-cli ----------------------------------------------------

info "Installing ms-fabric-cli..."
pip install -q --disable-pip-version-check ms-fabric-cli
ok "ms-fabric-cli installed: $(fab --version 2>/dev/null || echo 'unknown')"

# -- Authenticate with Fabric -------------------------------------------------

info "Authenticating with Fabric (service principal)..."
fab auth login \
    -u "$FABRIC_CLIENT_ID" \
    -p "$FABRIC_CLIENT_SECRET" \
    --tenant "$FABRIC_TENANT_ID"
ok "Fabric authenticated"

# -- Download and run deploy-fabric.sh ----------------------------------------

SCRIPT_URL="${DEPLOY_FABRIC_SCRIPT:-https://raw.githubusercontent.com/TalesFromTheField/iss-demo/main/scripts/deploy-fabric.sh}"
info "Downloading deploy-fabric.sh from: $SCRIPT_URL"
curl -fsSL "$SCRIPT_URL" -o /tmp/deploy-fabric.sh
chmod +x /tmp/deploy-fabric.sh
ok "Script downloaded"

info "Running Fabric deployment for workspace: $FABRIC_WORKSPACE_ID"
DEPLOY_OUTPUT=$(/tmp/deploy-fabric.sh --workspace-id "$FABRIC_WORKSPACE_ID" 2>&1) || {
    err "deploy-fabric.sh failed. Output:"
    echo "$DEPLOY_OUTPUT"
    exit 1
}

echo "$DEPLOY_OUTPUT"

# -- Extract FabricIngestionUri -----------------------------------------------

FABRIC_URI=$(echo "$DEPLOY_OUTPUT" | grep "FabricIngestionUri = " | awk '{print $NF}' | tail -1)

if [[ -z "$FABRIC_URI" ]]; then
    warn "Could not extract FabricIngestionUri from deployment output."
    warn "You can set it manually:"
    warn "  az containerapp update --name $CONTAINER_APP_NAME --resource-group $AZURE_RESOURCE_GROUP --set-env-vars FabricIngestionUri=<uri>"
    # Write empty output so deploymentScript does not fail
    echo '{"fabricIngestionUri":""}' > "${AZ_SCRIPTS_OUTPUT_PATH:-/dev/null}"
    exit 0
fi

ok "FabricIngestionUri: $FABRIC_URI"

# -- Update Container App env var ---------------------------------------------

info "Updating Container App '$CONTAINER_APP_NAME' with FabricIngestionUri..."
az containerapp update \
    --name "$CONTAINER_APP_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --set-env-vars "FabricIngestionUri=$FABRIC_URI" \
    --output none
ok "Container App updated — ISS Demo is now streaming to Fabric"

# -- Write outputs ------------------------------------------------------------

echo "{\"fabricIngestionUri\": \"$FABRIC_URI\"}" > "${AZ_SCRIPTS_OUTPUT_PATH:-/dev/null}"
info "Bootstrap complete."
