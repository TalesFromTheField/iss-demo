[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias('workspace-id')]
    [string]$WorkspaceId,

    [Alias('eventhouse')]
    [string]$EventhouseName = 'iss-demo-eventhouse',

    [Alias('kqldb')]
    [string]$KqlDbName = 'iss-demo-kqldb',

    [Alias('FabVerbose')]
    [switch]$CliVerbose
)

$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO]  $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK]    $Message" -ForegroundColor Green
}

function Write-WarnMsg {
    param([string]$Message)
    Write-Host "[WARN]  $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Invoke-Fab {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = & fab @Arguments 2>&1 | Out-String
    if (-not $AllowFailure -and $LASTEXITCODE -ne 0) {
        throw ($output.Trim())
    }

    return $output.Trim()
}

function Invoke-FabApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Payload
    )

    $arguments = @('api', '-X', 'post', $Path, '-i', $Payload)
    if ($CliVerbose) {
        $arguments += '--verbose'
    }

    return Invoke-Fab -Arguments $arguments
}

# Runs a single KQL management command against a Fabric KQL database.
# Uses the Kusto REST management endpoint with a bearer token from az CLI.
# Returns $true on success, $false on failure (non-throwing).
function Invoke-KustoMgmt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$QueryUri,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $body = (@{ csl = $Command; db = $Database } | ConvertTo-Json -Compress)
    $headers = @{
        Authorization  = "Bearer $Token"
        'Content-Type' = 'application/json'
    }
    try {
        $null = Invoke-RestMethod -Uri "$QueryUri/v1/rest/mgmt" -Method Post -Headers $headers -Body $body -ErrorAction Stop
        return $true
    } catch {
        Write-WarnMsg "  Command failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-FabResourceId {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    # `fab api` wraps responses as { status_code, text: { ... } }.
    # Older versions / direct REST responses return the resource directly.
    if ($Response.PSObject.Properties.Name -contains 'text' -and $Response.text) {
        if ($Response.text.PSObject.Properties.Name -contains 'id') {
            return [string]$Response.text.id
        }
    }
    if ($Response.PSObject.Properties.Name -contains 'id') {
        return [string]$Response.id
    }
    return $null
}

# Returns $true if the parsed response object represents a 409 conflict.
function Test-IsConflict {
    param($Response)
    $code = $null
    if ($Response.PSObject.Properties.Name -contains 'status_code') { $code = [int]$Response.status_code }
    return $code -eq 409
}

# Returns $true if the parsed response object represents a 202 Accepted (async operation).
function Test-IsAccepted {
    param($Response)
    $code = $null
    if ($Response.PSObject.Properties.Name -contains 'status_code') { $code = [int]$Response.status_code }
    return $code -eq 202
}

# Lists items at $ListPath and returns the ID of the one matching $DisplayName.
function Get-ExistingFabId {
    param(
        [string]$ListPath,
        [string]$DisplayName
    )

    $listArgs = @('api', '-X', 'get', $ListPath)
    if ($CliVerbose) { $listArgs += '--verbose' }
    $listRaw = Invoke-Fab -Arguments $listArgs -AllowFailure
    $list = $listRaw | ConvertFrom-Json

    # Items may be at top-level .value or inside .text.value
    $items = $null
    if ($list.PSObject.Properties.Name -contains 'text' -and $list.text.PSObject.Properties.Name -contains 'value') {
        $items = $list.text.value
    } elseif ($list.PSObject.Properties.Name -contains 'value') {
        $items = $list.value
    }

    if (-not $items) { return $null }
    $match = $items | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    if ($match) { return [string]$match.id }
    return $null
}

# Waits for an async-created Fabric resource to appear in the list.
# Polls $ListPath every $IntervalSeconds until displayName match is found or $MaxWaitSeconds elapses.
function Wait-FabResourceId {
    param(
        [string]$ListPath,
        [string]$DisplayName,
        [int]$MaxWaitSeconds = 120,
        [int]$IntervalSeconds = 5
    )

    $elapsed = 0
    while ($elapsed -lt $MaxWaitSeconds) {
        $id = Get-ExistingFabId -ListPath $ListPath -DisplayName $DisplayName
        if ($id) { return $id }
        Write-Info "  Waiting for '$DisplayName' to be ready... ($elapsed/$MaxWaitSeconds s)"
        Start-Sleep -Seconds $IntervalSeconds
        $elapsed += $IntervalSeconds
    }
    return $null
}

Write-Info "Checking prerequisites..."

if (-not (Get-Command fab -ErrorAction SilentlyContinue)) {
    Write-Err "Fabric CLI ('fab') not found."
    Write-Err "Install Microsoft Fabric CLI with: pip install ms-fabric-cli"
    Write-Err "If you installed 'fabric-cli', uninstall it and install 'ms-fabric-cli'."
    Write-Err "Then authenticate: fab auth login"
    exit 1
}

$fabVersion = Invoke-Fab -Arguments @('--version') -AllowFailure
Write-Ok "Fabric CLI found: $fabVersion"

$fabHelp = Invoke-Fab -Arguments @('--help') -AllowFailure
if ($fabHelp -notmatch '\bauth\b' -or $fabHelp -notmatch '\bapi\b') {
    Write-Err "Detected a 'fab' executable that does not expose required 'auth'/'api' commands."
    Write-Err "Install the Microsoft Fabric CLI package: pip install ms-fabric-cli"
    Write-Err "Use manual setup in docs/fabric-setup.md if this environment cannot run fab."
    exit 1
}

$authArgs = @('auth', 'status')
if ($CliVerbose) {
    $authArgs += '--verbose'
}

$authStatus = Invoke-Fab -Arguments $authArgs -AllowFailure
if ($LASTEXITCODE -ne 0) {
    Write-Err "Not authenticated with Fabric CLI."
    Write-Err "Run: fab auth login"
    exit 1
}

Write-Ok "Fabric CLI authenticated"
Write-Info "Workspace ID: $WorkspaceId"
Write-Host ""

Write-Info "Creating Eventhouse '$EventhouseName'..."
$eventhousePayload = (@{
        displayName = $EventhouseName
        description = 'Eventhouse for ISS Demo - hosts the KQL database for real-time ISS tracking.'
    } | ConvertTo-Json -Compress)

try {
    $eventhouseResponse = Invoke-FabApi -Path "workspaces/$WorkspaceId/eventhouses" -Payload $eventhousePayload
}
catch {
    Write-Err 'Failed to create Eventhouse.'
    Write-Err $_.Exception.Message
    exit 1
}

$eventhouse = $eventhouseResponse | ConvertFrom-Json
$eventhouseId = Get-FabResourceId -Response $eventhouse

if (-not $eventhouseId) {
    if (Test-IsConflict -Response $eventhouse) {
        Write-WarnMsg "Eventhouse '$EventhouseName' already exists — looking up existing ID..."
        $eventhouseId = Get-ExistingFabId -ListPath "workspaces/$WorkspaceId/eventhouses" -DisplayName $EventhouseName
        if (-not $eventhouseId) {
            Write-Err "Could not find existing Eventhouse '$EventhouseName' in workspace."
            exit 1
        }
        Write-Ok "Using existing Eventhouse: $eventhouseId"
    } elseif (Test-IsAccepted -Response $eventhouse) {
        Write-Info "Eventhouse creation accepted (async) — polling until ready..."
        $eventhouseId = Wait-FabResourceId -ListPath "workspaces/$WorkspaceId/eventhouses" -DisplayName $EventhouseName
        if (-not $eventhouseId) {
            Write-Err "Timed out waiting for Eventhouse '$EventhouseName' to be provisioned."
            exit 1
        }
        Write-Ok "Eventhouse ready: $eventhouseId"
    } else {
        Write-Err 'Could not extract Eventhouse ID from response:'
        Write-Err $eventhouseResponse
        exit 1
    }
} else {
    Write-Ok "Eventhouse created: $eventhouseId"
}

Write-Info "Creating KQL Database '$KqlDbName'..."
$kqlDbPayload = (@{
        displayName     = $KqlDbName
        description     = 'KQL Database for ISS Demo - stores ISS_Loc and Astronauts tables for real-time ISS tracking.'
        creationPayload = @{
            databaseType           = 'ReadWrite'
            parentEventhouseItemId = $eventhouseId
        }
    } | ConvertTo-Json -Compress -Depth 5)

try {
    $kqlDbResponse = Invoke-FabApi -Path "workspaces/$WorkspaceId/kqlDatabases" -Payload $kqlDbPayload
}
catch {
    Write-Err 'Failed to create KQL Database.'
    Write-Err $_.Exception.Message
    exit 1
}

$kqlDb = $kqlDbResponse | ConvertFrom-Json
$kqlDbId = Get-FabResourceId -Response $kqlDb

if (-not $kqlDbId) {
    if (Test-IsConflict -Response $kqlDb) {
        Write-WarnMsg "KQL Database '$KqlDbName' already exists — looking up existing ID..."
        $kqlDbId = Get-ExistingFabId -ListPath "workspaces/$WorkspaceId/kqlDatabases" -DisplayName $KqlDbName
        if (-not $kqlDbId) {
            Write-Err "Could not find existing KQL Database '$KqlDbName' in workspace."
            exit 1
        }
        Write-Ok "Using existing KQL Database: $kqlDbId"
    } elseif (Test-IsAccepted -Response $kqlDb) {
        Write-Info "KQL Database creation accepted (async) — polling until ready..."
        $kqlDbId = Wait-FabResourceId -ListPath "workspaces/$WorkspaceId/kqlDatabases" -DisplayName $KqlDbName
        if (-not $kqlDbId) {
            Write-Err "Timed out waiting for KQL Database '$KqlDbName' to be provisioned."
            exit 1
        }
        Write-Ok "KQL Database ready: $kqlDbId"
    } else {
        Write-Err 'Could not extract KQL Database ID from response:'
        Write-Err $kqlDbResponse
        exit 1
    }
} else {
    Write-Ok "KQL Database created: $kqlDbId"
}

# -- Fetch KQL Database Query URI -------------------------------------------

Write-Info "Fetching KQL Database properties to get Fabric Ingestion URI..."
$kqlDbArgs = @('api', '-X', 'get', "workspaces/$WorkspaceId/kqlDatabases/$kqlDbId")
if ($CliVerbose) { $kqlDbArgs += '--verbose' }
$kqlDbPropsRaw = Invoke-Fab -Arguments $kqlDbArgs -AllowFailure
$kqlDbProps = $kqlDbPropsRaw | ConvertFrom-Json

$fabricQueryUri = $null
if ($kqlDbProps.PSObject.Properties.Name -contains 'text' -and $kqlDbProps.text) {
    $fabricQueryUri = $kqlDbProps.text.properties.queryServiceUri
}
if (-not $fabricQueryUri -and $kqlDbProps.PSObject.Properties.Name -contains 'properties') {
    $fabricQueryUri = $kqlDbProps.properties.queryServiceUri
}

if (-not $fabricQueryUri) {
    Write-WarnMsg "Could not auto-detect Fabric Ingestion URI from API response."
    Write-WarnMsg "Open the KQL Database in the Fabric portal and copy the Query URI."
} else {
    Write-Ok "Fabric Ingestion URI detected: $fabricQueryUri"
}

# -- Apply KQL Schema -------------------------------------------------------

if (-not $fabricQueryUri) {
    Write-WarnMsg "Skipping automated schema setup — Query URI not available."
    Write-WarnMsg "Run kql/schema.kql manually in the Fabric KQL Database editor."
} elseif (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-WarnMsg "Azure CLI ('az') not found — skipping automated schema setup."
    Write-WarnMsg "Run kql/schema.kql manually in the Fabric KQL Database editor."
} else {
    Write-Info "Applying KQL schema (tables, mappings, streaming ingestion policy)..."

    $kustoToken = $null
    try {
        $kustoToken = (az account get-access-token --resource https://kusto.windows.net --query accessToken -o tsv 2>&1).Trim()
        if ($LASTEXITCODE -ne 0) { $kustoToken = $null }
    } catch {
        $kustoToken = $null
    }

    if (-not $kustoToken) {
        Write-WarnMsg "Could not get Kusto access token — are you logged in with 'az login'?"
        Write-WarnMsg "Run kql/schema.kql manually in the Fabric KQL Database editor."
    } else {
        # JSON mapping arrays (single-quoted PS literals so double-quotes are preserved as-is)
        $issMapping = '[{"column":"Timestamp","path":"$.Timestamp","datatype":"datetime"},{"column":"CollectedAtUtc","path":"$.CollectedAtUtc","datatype":"datetime"},{"column":"Latitude","path":"$.Latitude","datatype":"real"},{"column":"Longitude","path":"$.Longitude","datatype":"real"}]'
        $astroMapping = '[{"column":"CollectedAtUtc","path":"$.CollectedAtUtc","datatype":"datetime"},{"column":"Number","path":"$.Number","datatype":"int"},{"column":"People","path":"$.People","datatype":"dynamic"}]'

        $schemaCommands = @(
            ".alter database ['$KqlDbName'] policy streamingingestion enable",
            ".create-merge table ISS_Loc (Timestamp: datetime, CollectedAtUtc: datetime, Latitude: real, Longitude: real)",
            ".create-or-alter table ISS_Loc ingestion json mapping 'ISS_Loc_JSON_Mapping' '$issMapping'",
            ".create-merge table Astronauts (CollectedAtUtc: datetime, Number: int, People: dynamic)",
            ".create-or-alter table Astronauts ingestion json mapping 'Astronauts_JSON_Mapping' '$astroMapping'"
        )

        # Brief pause to ensure the KQL database management endpoint is fully ready
        Start-Sleep -Seconds 5

        $schemaOk = $true
        foreach ($cmd in $schemaCommands) {
            $label = if ($cmd.Length -gt 70) { $cmd.Substring(0, 70) + '…' } else { $cmd }
            Write-Info "  $label"
            $ok = Invoke-KustoMgmt -QueryUri $fabricQueryUri -Database $KqlDbName -Token $kustoToken -Command $cmd
            if ($ok) {
                Write-Ok "  Done"
            } else {
                $schemaOk = $false
            }
        }

        if ($schemaOk) {
            Write-Ok "KQL schema applied: ISS_Loc, Astronauts tables + streaming ingestion policy"
        } else {
            Write-WarnMsg "Some schema commands failed — see warnings above."
            Write-WarnMsg "Re-run this script or apply kql/schema.kql manually to finish setup."
        }
    }
}

Write-Host ''
Write-Host '======================================================================'
Write-Host '  ISS DEMO - FABRIC RESOURCE DEPLOYMENT SUMMARY'
Write-Host '======================================================================'
Write-Host ''
Write-Host "  Workspace ID   : $WorkspaceId"
Write-Host "  Eventhouse     : $eventhouseId  ($EventhouseName)"
Write-Host "  KQL Database   : $kqlDbId  ($KqlDbName)"
Write-Host ''

if ($fabricQueryUri) {
    Write-Host '  *** IMPORTANT — set this environment variable on your Container App: ***'
    Write-Host ''
    Write-Host "  FabricIngestionUri = $fabricQueryUri"
    Write-Host ''
    Write-Host '  Azure CLI (update existing Container App):'
    Write-Host "    az containerapp update --name <app-name> --resource-group <rg> \"
    Write-Host "      --set-env-vars FabricIngestionUri=$fabricQueryUri"
} else {
    Write-Host '  *** IMPORTANT — get the Fabric Ingestion URI manually: ***'
    Write-Host ''
    Write-Host '  1. Open the Fabric portal: https://app.fabric.microsoft.com'
    Write-Host "  2. Navigate to your KQL Database: $KqlDbName"
    Write-Host '  3. Copy the "Query URI" (looks like https://trd-xxx.region.kusto.data.microsoft.com)'
    Write-Host '  4. Set it as the FabricIngestionUri env var on your Container App'
}

Write-Host ''
Write-Host '  NEXT STEPS:'
Write-Host '  ------------------------------------------------------'
Write-Host '  1. Set FabricIngestionUri on your Container App (see above)'
Write-Host ''
Write-Host '  2. Verify data is flowing (run in Fabric KQL Database editor):'
Write-Host '       ISS_Loc | count'
Write-Host '       Astronauts | count'
Write-Host ''
Write-Host '  Note: If schema setup was skipped, run kql/schema.kql manually first.'
Write-Host '  For detailed instructions, see: docs/fabric-setup.md'
Write-Host '======================================================================'
Write-Host ''

Write-Info 'Deployment complete. See next steps above.'