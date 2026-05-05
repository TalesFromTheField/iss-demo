"""ISS Demo — shared fetch logic for real-time ISS tracking.

This module provides shared constants and utilities imported by run.py
(the Container App scheduler entry point).
"""

import logging
import time

import requests

logger = logging.getLogger(__name__)

ISS_LOCATION_URL = "https://api.open-notify.org/iss-now.json"
ASTRONAUTS_URL = "https://api.open-notify.org/astros.json"


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
    if last_exception is not None:
        raise last_exception
    raise requests.RequestException("All retry attempts failed with no exception captured")

