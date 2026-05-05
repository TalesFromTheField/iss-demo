"""Container entry point for ISS Demo scheduler.

Runs timer-triggered functions using APScheduler instead of Azure Functions runtime.
Fetches ISS location and astronaut data and streams events directly to a
Microsoft Fabric KQL Database (Eventhouse) via the Kusto streaming ingestion API.
"""

import io
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone

from apscheduler.schedulers.background import BackgroundScheduler
from azure.identity import DefaultAzureCredential
from azure.kusto.data import KustoConnectionStringBuilder
from azure.kusto.ingest import KustoStreamingIngestClient, IngestionProperties
from azure.kusto.ingest.ingestion_properties import DataFormat
from function_app import (
    ISS_LOCATION_URL,
    ASTRONAUTS_URL,
    _fetch_with_retry,
)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)
logger = logging.getLogger(__name__)

# Fabric configuration — set via Container App environment variables.
# FabricIngestionUri: the Eventhouse Query URI from the Fabric portal
#   (e.g. https://trd-xxxxxxxxxxxx.z6.kusto.data.microsoft.com)
FABRIC_INGESTION_URI = os.environ.get("FabricIngestionUri")
FABRIC_DATABASE_NAME = os.environ.get("FabricDatabaseName", "iss-demo-kqldb")
FABRIC_ISS_TABLE = os.environ.get("FabricIssTable", "ISS_Loc")
FABRIC_ASTRONAUTS_TABLE = os.environ.get("FabricAstronautsTable", "Astronauts")


def _get_ingest_client() -> KustoStreamingIngestClient:
    """Return a Kusto streaming ingest client authenticated via managed identity."""
    if not FABRIC_INGESTION_URI:
        raise RuntimeError(
            "Missing Fabric configuration. Set the FabricIngestionUri environment variable "
            "to the Eventhouse Query URI from the Fabric portal."
        )
    kcsb = KustoConnectionStringBuilder.with_azure_token_credential(
        FABRIC_INGESTION_URI,
        DefaultAzureCredential(exclude_interactive_browser_credential=True),
    )
    return KustoStreamingIngestClient(kcsb)


def send_to_fabric(table: str, record: dict) -> None:
    """Send a single JSON record to a Fabric KQL Database table via streaming ingestion."""
    client = _get_ingest_client()
    properties = IngestionProperties(
        database=FABRIC_DATABASE_NAME,
        table=table,
        data_format=DataFormat.JSON,
    )
    stream = io.BytesIO(json.dumps(record).encode("utf-8"))
    client.ingest_from_stream(stream, ingestion_properties=properties)


def job_get_iss_location() -> None:
    """Scheduled job: fetch ISS location every 5 seconds and stream to Fabric."""
    try:
        response = _fetch_with_retry(ISS_LOCATION_URL, timeout=10, retries=1, backoff=2)
        iss_data = response.json()
        position = iss_data.get("iss_position", {})

        record = {
            "Timestamp": datetime.fromtimestamp(
                iss_data.get("timestamp", 0), tz=timezone.utc
            ).isoformat(),
            "CollectedAtUtc": datetime.now(timezone.utc).isoformat(),
            "Latitude": float(position.get("latitude", 0)),
            "Longitude": float(position.get("longitude", 0)),
        }

        send_to_fabric(FABRIC_ISS_TABLE, record)
        logger.info(
            "ISS location sent to Fabric: lat=%s, lon=%s",
            record["Latitude"],
            record["Longitude"],
        )
    except Exception as exc:
        logger.error("Error in job_get_iss_location: %s", exc, exc_info=True)


def job_get_astronauts() -> None:
    """Scheduled job: fetch astronauts in space every minute and stream to Fabric."""
    try:
        response = _fetch_with_retry(ASTRONAUTS_URL, timeout=10, retries=1, backoff=2)
        astro_data = response.json()

        record = {
            "CollectedAtUtc": datetime.now(timezone.utc).isoformat(),
            "Number": astro_data.get("number", 0),
            "People": astro_data.get("people", []),
        }

        send_to_fabric(FABRIC_ASTRONAUTS_TABLE, record)
        logger.info("Astronauts sent to Fabric: %d people in space", record["Number"])
    except Exception as exc:
        logger.error("Error in job_get_astronauts: %s", exc, exc_info=True)


def main() -> None:
    """Start the scheduler and run jobs indefinitely."""
    logger.info("Starting ISS Demo scheduler...")
    logger.info("Fabric ingestion URI: %s", FABRIC_INGESTION_URI or "(not set)")
    logger.info("Fabric database: %s", FABRIC_DATABASE_NAME)

    scheduler = BackgroundScheduler()
    scheduler.add_job(job_get_iss_location, "interval", seconds=5, id="iss-location")
    scheduler.add_job(job_get_astronauts, "interval", seconds=60, id="astronauts")

    scheduler.start()
    logger.info("Scheduler started. Jobs running...")

    def signal_handler(signum: int, frame) -> None:
        """Handle SIGTERM and SIGINT gracefully."""
        logger.info("Scheduler shutdown requested (signal %s).", signum)
        scheduler.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info("Scheduler shutdown requested (KeyboardInterrupt).")
        scheduler.shutdown()
        sys.exit(0)


if __name__ == "__main__":
    main()

