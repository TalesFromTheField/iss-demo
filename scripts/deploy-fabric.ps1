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
        description     = 'KQL Database for ISS Demo - stores ISS_Loc and Astronauts tables ingested via EventStreams.'
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
    } else {
        Write-Err 'Could not extract KQL Database ID from response:'
        Write-Err $kqlDbResponse
        exit 1
    }
} else {
    Write-Ok "KQL Database created: $kqlDbId"
}

$eventStreamIds = [ordered]@{}
foreach ($eventStreamName in @('iss-location-eventstream', 'astronauts-eventstream')) {
    Write-Info "Creating EventStream '$eventStreamName'..."
    $eventStreamPayload = (@{
            displayName = $eventStreamName
            description = "EventStream for ISS Demo - $eventStreamName."
        } | ConvertTo-Json -Compress)

    try {
        $eventStreamResponse = Invoke-FabApi -Path "workspaces/$WorkspaceId/eventstreams" -Payload $eventStreamPayload
    }
    catch {
        Write-Err "Failed to create EventStream '$eventStreamName'."
        Write-Err $_.Exception.Message
        exit 1
    }

    $eventStream = $eventStreamResponse | ConvertFrom-Json
    $eventStreamId = Get-FabResourceId -Response $eventStream

    if (-not $eventStreamId) {
        if (Test-IsConflict -Response $eventStream) {
            Write-WarnMsg "EventStream '$eventStreamName' already exists — looking up existing ID..."
            $eventStreamId = Get-ExistingFabId -ListPath "workspaces/$WorkspaceId/eventstreams" -DisplayName $eventStreamName
            if (-not $eventStreamId) {
                Write-Err "Could not find existing EventStream '$eventStreamName' in workspace."
                exit 1
            }
            Write-Ok "Using existing EventStream: $eventStreamId ($eventStreamName)"
        } else {
            Write-Err 'Could not extract EventStream ID from response:'
            Write-Err $eventStreamResponse
            exit 1
        }
    } else {
        Write-Ok "EventStream created: $eventStreamId ($eventStreamName)"
    }

    $eventStreamIds[$eventStreamName] = $eventStreamId
}

Write-Host ''
Write-Host '======================================================================'
Write-Host '  ISS DEMO - FABRIC RESOURCE DEPLOYMENT SUMMARY'
Write-Host '======================================================================'
Write-Host ''
Write-Host "  Workspace ID:  $WorkspaceId"
Write-Host ''
Write-Host '  Created resources:'
Write-Host "     Eventhouse      : $eventhouseId  ($EventhouseName)"
Write-Host "     KQL Database    : $kqlDbId  ($KqlDbName)"
foreach ($entry in $eventStreamIds.GetEnumerator()) {
    Write-Host "     EventStream     : $($entry.Value)  ($($entry.Key))"
}
Write-Host ''
Write-Host '  MANUAL STEPS REQUIRED:'
Write-Host '  ------------------------------------------------------'
Write-Host '  The EventStream-to-KQL DB data connection cannot be'
Write-Host '  fully automated via API. Complete these steps in the'
Write-Host '  Fabric portal (https://app.fabric.microsoft.com):'
Write-Host ''
Write-Host "  1. Open 'iss-location-eventstream'"
Write-Host '     a. Add source -> Azure Event Hub -> iss-location hub'
Write-Host "     b. Add destination -> KQL Database -> $KqlDbName"
Write-Host '     c. Map to table: ISS_Loc'
Write-Host ''
Write-Host "  2. Open 'astronauts-eventstream'"
Write-Host '     a. Add source -> Azure Event Hub -> astronauts hub'
Write-Host "     b. Add destination -> KQL Database -> $KqlDbName"
Write-Host '     c. Map to table: Astronauts'
Write-Host ''
Write-Host '  3. Verify data is flowing:'
Write-Host '     Open the KQL Database and run:'
Write-Host '       ISS_Loc | count'
Write-Host '       Astronauts | count'
Write-Host ''
Write-Host '  For detailed instructions, see: docs/fabric-setup.md'
Write-Host '======================================================================'
Write-Host ''

Write-Info 'Deployment complete. See manual steps above.'