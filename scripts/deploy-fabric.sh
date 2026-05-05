#!/usr/bin/env bash
# ===========================================================================
# Deploy Fabric resources for ISS Demo using the Microsoft Fabric CLI (fab).
#
# Automates creation of Eventhouse, KQL Database, and EventStreams.
# The EventStream-to-KQL DB data connection (last-mile wiring) must be
# completed manually in the Fabric portal.
#
# Usage:
#     ./scripts/deploy-fabric.sh --workspace-id <WORKSPACE_ID>
#
# Prerequisites:
#     - Fabric CLI installed: pip install ms-fabric-cli
#     - Authenticated: fab auth login
#     - Fabric workspace with capacity assigned
#
# Resources created:
#     - Eventhouse: iss-demo-eventhouse
#     - KQL Database: iss-demo-kqldb
#     - EventStream: iss-location-eventstream
#     - EventStream: astronauts-eventstream
#
# Manual steps after running:
#     1. Open each EventStream in the Fabric portal
#     2. Add Azure Event Hub source (iss-location / astronauts hub)
#     3. Add KQL Database destination pointing to iss-demo-kqldb
#     4. Map iss-location stream -> ISS_Loc table
#     5. Map astronauts stream -> Astronauts table
# ===========================================================================

set -euo pipefail

# -- Defaults ---------------------------------------------------------------

EVENTHOUSE_NAME="iss-demo-eventhouse"
KQLDB_NAME="iss-demo-kqldb"
WORKSPACE_ID=""
VERBOSE=""

# -- Colors -----------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# -- Helpers ----------------------------------------------------------------

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") --workspace-id <WORKSPACE_ID> [OPTIONS]

Options:
  --workspace-id   ID   Fabric workspace GUID (required)
  --eventhouse     NAME Eventhouse display name (default: $EVENTHOUSE_NAME)
  --kqldb          NAME KQL Database display name (default: $KQLDB_NAME)
  --verbose              Enable verbose output
  -h, --help             Show this help

Example:
  $(basename "$0") --workspace-id 00000000-0000-0000-0000-000000000000
EOF
    exit 0
}

# Extract JSON field value (uses Python when available, grep fallback otherwise).
# Handles fab CLI's wrapped { status_code, text: { ... } } envelope by checking
# the 'text' key first, then falling back to top-level.
json_field() {
    local json="$1" field="$2"
    if command -v python3 >/dev/null 2>&1; then
        echo "$json" | python3 -c "import sys,json
data=json.load(sys.stdin)
if isinstance(data.get('text'), dict) and '$field' in data['text']:
    print(data['text']['$field'])
else:
    print(data.get('$field',''))"
    elif command -v python >/dev/null 2>&1; then
        echo "$json" | python -c "import sys,json
data=json.load(sys.stdin)
if isinstance(data.get('text'), dict) and '$field' in data['text']:
    print(data['text']['$field'])
else:
    print(data.get('$field',''))"
    else
        echo "$json" | grep -oP "\"$field\"\s*:\s*\"?\K[^\",}]+" | head -n 1
    fi
}

# Returns true (exit 0) if the response JSON has status_code 409.
is_conflict() {
    local json="$1"
    local code
    code=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status_code',''))" 2>/dev/null \
        || echo "$json" | python -c "import sys,json; print(json.load(sys.stdin).get('status_code',''))" 2>/dev/null \
        || echo "0")
    [[ "$code" == "409" ]]
}

# Lists items at $1 and returns the ID of the item whose displayName equals $2.
get_existing_id() {
    local list_path="$1" display_name="$2"
    local list_raw
    list_raw=$(fab api -X get "$list_path" $VERBOSE 2>&1) || return 1
    if command -v python3 >/dev/null 2>&1; then
        echo "$list_raw" | python3 -c "
import sys,json
data=json.load(sys.stdin)
items=data.get('text',data).get('value',[])
match=[i for i in items if i.get('displayName')=='$display_name']
print(match[0]['id'] if match else '')"
    elif command -v python >/dev/null 2>&1; then
        echo "$list_raw" | python -c "
import sys,json
data=json.load(sys.stdin)
items=data.get('text',data).get('value',[])
match=[i for i in items if i.get('displayName')=='$display_name']
print(match[0]['id'] if match else '')"
    fi
}

# -- Parse arguments --------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace-id)   WORKSPACE_ID="$2";      shift 2 ;;
        --eventhouse)     EVENTHOUSE_NAME="$2";    shift 2 ;;
        --kqldb)          KQLDB_NAME="$2";         shift 2 ;;
        --verbose)        VERBOSE="--verbose";     shift ;;
        -h|--help)        usage ;;
        *)                err "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "$WORKSPACE_ID" ]]; then
    err "Missing required argument: --workspace-id"
    echo ""
    usage
fi

# -- Preflight checks -------------------------------------------------------

info "Checking prerequisites..."

if ! command -v fab >/dev/null 2>&1; then
    err "Fabric CLI ('fab') not found."
    err "Install Microsoft Fabric CLI with: pip install ms-fabric-cli"
    err "If you installed 'fabric-cli', uninstall it and install 'ms-fabric-cli'."
    err "Then authenticate: fab auth login"
    exit 1
fi

ok "Fabric CLI found: $(fab --version 2>/dev/null || echo 'unknown version')"

if ! fab --help 2>&1 | grep -q "auth" || ! fab --help 2>&1 | grep -q "api"; then
    err "Detected a 'fab' executable that does not expose required 'auth'/'api' commands."
    err "Install the Microsoft Fabric CLI package: pip install ms-fabric-cli"
    err "Use manual setup in docs/fabric-setup.md if this environment cannot run fab."
    exit 1
fi

if ! fab auth status $VERBOSE >/dev/null 2>&1; then
    err "Not authenticated with Fabric CLI."
    err "Run: fab auth login"
    exit 1
fi

ok "Fabric CLI authenticated"
info "Workspace ID: $WORKSPACE_ID"
echo ""

# -- Create Eventhouse ------------------------------------------------------

info "Creating Eventhouse '$EVENTHOUSE_NAME'..."

EVENTHOUSE_RESPONSE=$(fab api -X post \
    "workspaces/$WORKSPACE_ID/eventhouses" \
    -i "{\"displayName\": \"$EVENTHOUSE_NAME\", \"description\": \"Eventhouse for ISS Demo - hosts the KQL database for real-time ISS tracking.\"}" \
    $VERBOSE 2>&1) || {
    err "Failed to create Eventhouse."
    err "$EVENTHOUSE_RESPONSE"
    exit 1
}

EVENTHOUSE_ID=$(json_field "$EVENTHOUSE_RESPONSE" "id")

if [[ -z "$EVENTHOUSE_ID" ]]; then
    if is_conflict "$EVENTHOUSE_RESPONSE"; then
        warn "Eventhouse '$EVENTHOUSE_NAME' already exists — looking up existing ID..."
        EVENTHOUSE_ID=$(get_existing_id "workspaces/$WORKSPACE_ID/eventhouses" "$EVENTHOUSE_NAME")
        if [[ -z "$EVENTHOUSE_ID" ]]; then
            err "Could not find existing Eventhouse '$EVENTHOUSE_NAME' in workspace."
            exit 1
        fi
        ok "Using existing Eventhouse: $EVENTHOUSE_ID"
    else
        err "Could not extract Eventhouse ID from response:"
        err "$EVENTHOUSE_RESPONSE"
        exit 1
    fi
else
    ok "Eventhouse created: $EVENTHOUSE_ID"
fi

# -- Create KQL Database ----------------------------------------------------

info "Creating KQL Database '$KQLDB_NAME'..."

KQLDB_PAYLOAD=$(cat <<JSON
{
    "displayName": "$KQLDB_NAME",
    "description": "KQL Database for ISS Demo - stores ISS_Loc and Astronauts tables ingested via EventStreams.",
    "creationPayload": {
        "databaseType": "ReadWrite",
        "parentEventhouseItemId": "$EVENTHOUSE_ID"
    }
}
JSON
)

KQLDB_RESPONSE=$(fab api -X post \
    "workspaces/$WORKSPACE_ID/kqlDatabases" \
    -i "$KQLDB_PAYLOAD" \
    $VERBOSE 2>&1) || {
    err "Failed to create KQL Database."
    err "$KQLDB_RESPONSE"
    exit 1
}

KQLDB_ID=$(json_field "$KQLDB_RESPONSE" "id")

if [[ -z "$KQLDB_ID" ]]; then
    if is_conflict "$KQLDB_RESPONSE"; then
        warn "KQL Database '$KQLDB_NAME' already exists — looking up existing ID..."
        KQLDB_ID=$(get_existing_id "workspaces/$WORKSPACE_ID/kqlDatabases" "$KQLDB_NAME")
        if [[ -z "$KQLDB_ID" ]]; then
            err "Could not find existing KQL Database '$KQLDB_NAME' in workspace."
            exit 1
        fi
        ok "Using existing KQL Database: $KQLDB_ID"
    else
        err "Could not extract KQL Database ID from response:"
        err "$KQLDB_RESPONSE"
        exit 1
    fi
else
    ok "KQL Database created: $KQLDB_ID"
fi

# -- Create EventStreams ----------------------------------------------------

declare -A EVENTSTREAM_IDS

for ES_NAME in "iss-location-eventstream" "astronauts-eventstream"; do
    info "Creating EventStream '$ES_NAME'..."

    ES_RESPONSE=$(fab api -X post \
        "workspaces/$WORKSPACE_ID/eventstreams" \
        -i "{\"displayName\": \"$ES_NAME\", \"description\": \"EventStream for ISS Demo - $ES_NAME.\"}" \
        $VERBOSE 2>&1) || {
        err "Failed to create EventStream '$ES_NAME'."
        err "$ES_RESPONSE"
        exit 1
    }

    ES_ID=$(json_field "$ES_RESPONSE" "id")

    if [[ -z "$ES_ID" ]]; then
        if is_conflict "$ES_RESPONSE"; then
            warn "EventStream '$ES_NAME' already exists — looking up existing ID..."
            ES_ID=$(get_existing_id "workspaces/$WORKSPACE_ID/eventstreams" "$ES_NAME")
            if [[ -z "$ES_ID" ]]; then
                err "Could not find existing EventStream '$ES_NAME' in workspace."
                exit 1
            fi
            ok "Using existing EventStream: $ES_ID ($ES_NAME)"
        else
            err "Could not extract EventStream ID from response:"
            err "$ES_RESPONSE"
            exit 1
        fi
    else
        ok "EventStream created: $ES_ID ($ES_NAME)"
    fi

    EVENTSTREAM_IDS[$ES_NAME]="$ES_ID"
done

# -- Summary ----------------------------------------------------------------

echo ""
echo "======================================================================"
echo "  ISS DEMO - FABRIC RESOURCE DEPLOYMENT SUMMARY"
echo "======================================================================"
echo ""
echo "  Workspace ID:  $WORKSPACE_ID"
echo ""
echo "  Created resources:"
echo "     Eventhouse      : $EVENTHOUSE_ID  ($EVENTHOUSE_NAME)"
echo "     KQL Database    : $KQLDB_ID  ($KQLDB_NAME)"
for ES_NAME in "${!EVENTSTREAM_IDS[@]}"; do
    echo "     EventStream     : ${EVENTSTREAM_IDS[$ES_NAME]}  ($ES_NAME)"
done
echo ""
echo "  MANUAL STEPS REQUIRED:"
echo "  ------------------------------------------------------"
echo "  The EventStream-to-KQL DB data connection cannot be"
echo "  fully automated via API. Complete these steps in the"
echo "  Fabric portal (https://app.fabric.microsoft.com):"
echo ""
echo "  1. Open 'iss-location-eventstream'"
echo "     a. Add source -> Azure Event Hub -> iss-location hub"
echo "     b. Add destination -> KQL Database -> $KQLDB_NAME"
echo "     c. Map to table: ISS_Loc"
echo ""
echo "  2. Open 'astronauts-eventstream'"
echo "     a. Add source -> Azure Event Hub -> astronauts hub"
echo "     b. Add destination -> KQL Database -> $KQLDB_NAME"
echo "     c. Map to table: Astronauts"
echo ""
echo "  3. Verify data is flowing:"
echo "     Open the KQL Database and run:"
echo "       ISS_Loc | count"
echo "       Astronauts | count"
echo ""
echo "  For detailed instructions, see: docs/fabric-setup.md"
echo "======================================================================"
echo ""

info "Deployment complete. See manual steps above."
