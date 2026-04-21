"""ISS Demo — Azure Functions for real-time ISS tracking."""

import json
import logging
import time
from datetime import datetime, timezone

import azure.functions as func
import requests

app = func.FunctionApp()

logger = logging.getLogger(__name__)

ISS_LOCATION_URL = "https://api.open-notify.org/iss-now.json"


def _fetch_with_retry(url: str, timeout: int = 10, retries: int = 1, backoff: int = 2) -> requests.Response:
    """HTTP GET with simple retry logic.

    Attempts the request once, then retries up to *retries* additional times
    with exponential back-off on failure.  Both functions in this module share
    this helper so retry behaviour is consistent.

    Args:
        url: The URL to fetch.
        timeout: Timeout in seconds for each request attempt.
        retries: Number of retry attempts after the initial request.
        backoff: Base delay in seconds between retries (doubles each retry).

    Returns:
        A :class:`requests.Response` on success.

    Raises:
        requests.RequestException: If all attempts fail.
    """
    last_exception: requests.RequestException | None = None
    for attempt in range(1 + retries):
        try:
            response = requests.get(url, timeout=timeout)
            response.raise_for_status()
            return response
        except requests.RequestException as exc:
            last_exception = exc
            if attempt < retries:
                delay = backoff * (2 ** attempt)
                logger.warning(
                    "Attempt %d for %s failed (%s). Retrying in %ds…",
                    attempt + 1,
                    url,
                    exc,
                    delay,
                )
                time.sleep(delay)
    # All attempts exhausted — re-raise the last exception
    if last_exception is not None:
        raise last_exception
    raise requests.RequestException("All retry attempts failed with no exception captured")


# ---------------------------------------------------------------------------
# GetIssLocation — fires every 5 seconds
# ---------------------------------------------------------------------------

@app.timer_trigger(schedule="*/5 * * * * *", arg_name="timer", run_after_startup=False)
@app.event_hub_output(arg_name="outputEvent", connection="EventHubConnection", event_hub_name="%IssLocationHubName%")
def get_iss_location(timer: func.TimerRequest, outputEvent: func.Out[str]) -> None:
    """Fetch the current ISS position and send a normalised event to Event Hubs."""

    # 1. Fetch data from the ISS API
    try:
        response = _fetch_with_retry(ISS_LOCATION_URL, timeout=10, retries=1, backoff=2)
    except requests.RequestException as exc:
        logger.warning("ISS location API unavailable, skipping cycle: %s", exc)
        return

    # 2. Parse JSON
    try:
        iss_data = response.json()
    except (json.JSONDecodeError, ValueError) as exc:
        logger.error("Invalid JSON from ISS API: %s", exc)
        return

    # 3. Build normalised event envelope
    event = {
        "schemaVersion": "1.0",
        "eventType": "iss-location",
        "collectedAtUtc": datetime.now(timezone.utc).isoformat(),
        "data": iss_data,
    }

    # 4. Send to Event Hub
    outputEvent.set(json.dumps(event))
    logger.info("ISS location event sent: lat=%s, lon=%s",
                iss_data.get("iss_position", {}).get("latitude", "?"),
                iss_data.get("iss_position", {}).get("longitude", "?"))


# ---------------------------------------------------------------------------
# GetAstronauts — fires every minute
# ---------------------------------------------------------------------------

ASTRONAUTS_URL = "https://api.open-notify.org/astros.json"


@app.timer_trigger(schedule="0 * * * * *", arg_name="timer", run_after_startup=False)
@app.event_hub_output(arg_name="outputEvent", connection="EventHubConnection", event_hub_name="%AstronautsHubName%")
def get_astronauts(timer: func.TimerRequest, outputEvent: func.Out[str]) -> None:
    """Fetch the current astronauts in space and send a normalised event to Event Hubs."""

    # 1. Fetch data from the astronauts API
    try:
        response = _fetch_with_retry(ASTRONAUTS_URL, timeout=10, retries=1, backoff=2)
    except requests.RequestException as exc:
        logger.warning("Astronauts API unavailable, skipping cycle: %s", exc)
        return

    # 2. Parse JSON
    try:
        astro_data = response.json()
    except (json.JSONDecodeError, ValueError) as exc:
        logger.error("Invalid JSON from Astronauts API: %s", exc)
        return

    # 3. Build normalised event envelope
    event = {
        "schemaVersion": "1.0",
        "eventType": "astronauts",
        "collectedAtUtc": datetime.now(timezone.utc).isoformat(),
        "data": astro_data,
    }

    # 4. Send to Event Hub
    outputEvent.set(json.dumps(event))
    logger.info("Astronauts event sent: %d people in space",
                astro_data.get("number", 0))
