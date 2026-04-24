"""Container entry point for ISS Demo scheduler.

Runs timer-triggered functions using APScheduler instead of Azure Functions runtime.
This enables the same function code to run in a Container App environment.
"""

import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone

from apscheduler.schedulers.background import BackgroundScheduler
from azure.eventhub import EventData, EventHubProducerClient
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

# Environment configuration
EVENT_HUB_CONNECTION_STRING = os.environ.get("EventHubConnection")
ISS_LOCATION_HUB_NAME = os.environ.get("IssLocationHubName", "iss-location")
ASTRONAUTS_HUB_NAME = os.environ.get("AstronautsHubName", "astronauts")

if not EVENT_HUB_CONNECTION_STRING:
    raise RuntimeError("EventHubConnection environment variable not set")


def send_to_event_hub(connection_string: str, hub_name: str, message: str) -> None:
    """Send a message to an Event Hub."""
    producer = EventHubProducerClient.from_connection_string(
        connection_string, eventhub_name=hub_name
    )
    with producer:
        batch = producer.create_batch()
        batch.add(EventData(message))
        producer.send_batch(batch)


def job_get_iss_location() -> None:
    """Scheduled job: Fetch ISS location every 5 seconds."""
    try:
        response = _fetch_with_retry(ISS_LOCATION_URL, timeout=10, retries=1, backoff=2)
        iss_data = response.json()

        event = {
            "schemaVersion": "1.0",
            "eventType": "iss-location",
            "collectedAtUtc": datetime.now(timezone.utc).isoformat(),
            "data": iss_data,
        }

        send_to_event_hub(
            EVENT_HUB_CONNECTION_STRING,
            ISS_LOCATION_HUB_NAME,
            json.dumps(event),
        )
        logger.info(
            "ISS location event sent: lat=%s, lon=%s",
            iss_data.get("iss_position", {}).get("latitude", "?"),
            iss_data.get("iss_position", {}).get("longitude", "?"),
        )
    except Exception as exc:
        logger.error("Error in job_get_iss_location: %s", exc, exc_info=True)


def job_get_astronauts() -> None:
    """Scheduled job: Fetch astronauts every minute."""
    try:
        response = _fetch_with_retry(ASTRONAUTS_URL, timeout=10, retries=1, backoff=2)
        astro_data = response.json()

        event = {
            "schemaVersion": "1.0",
            "eventType": "astronauts",
            "collectedAtUtc": datetime.now(timezone.utc).isoformat(),
            "data": astro_data,
        }

        send_to_event_hub(
            EVENT_HUB_CONNECTION_STRING,
            ASTRONAUTS_HUB_NAME,
            json.dumps(event),
        )
        logger.info("Astronauts event sent: %d people in space", astro_data.get("number", 0))
    except Exception as exc:
        logger.error("Error in job_get_astronauts: %s", exc, exc_info=True)


def main() -> None:
    """Start the scheduler and run jobs indefinitely."""
    logger.info("Starting ISS Demo scheduler...")

    scheduler = BackgroundScheduler()

    # Schedule jobs to match the original timer triggers
    # ISS location: every 5 seconds
    scheduler.add_job(job_get_iss_location, "interval", seconds=5, id="iss-location")

    # Astronauts: every 60 seconds
    scheduler.add_job(job_get_astronauts, "interval", seconds=60, id="astronauts")

    scheduler.start()
    logger.info("Scheduler started. Jobs running...")

    def signal_handler(signum: int, frame) -> None:
        """Handle SIGTERM and SIGINT gracefully."""
        logger.info("Scheduler shutdown requested (signal %s).", signum)
        scheduler.shutdown()
        sys.exit(0)

    # Register signal handlers for graceful shutdown in Container Apps
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    try:
        # Keep the main thread alive
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info("Scheduler shutdown requested (KeyboardInterrupt).")
        scheduler.shutdown()
        sys.exit(0)


if __name__ == "__main__":
    main()
