"""Unit tests for the GetAstronauts function."""

import json
from unittest.mock import MagicMock, patch

import requests as req

from function_app import get_astronauts


SAMPLE_ASTRO_RESPONSE = {
    "number": 7,
    "people": [
        {"name": "Oleg Kononenko", "craft": "ISS"},
        {"name": "Nikolai Chub", "craft": "ISS"},
        {"name": "Tracy Dyson", "craft": "ISS"},
        {"name": "Matthew Dominick", "craft": "ISS"},
        {"name": "Michael Barratt", "craft": "ISS"},
        {"name": "Jeanette Epps", "craft": "ISS"},
        {"name": "Alexander Grebenkin", "craft": "ISS"},
    ],
    "message": "success",
}


class TestGetAstronauts:
    """Tests for the get_astronauts Azure Function."""

    def _make_mocks(self):
        timer = MagicMock()
        output = MagicMock()
        return timer, output

    @patch("function_app._fetch_with_retry")
    def test_successful_poll_sends_event(self, mock_fetch):
        mock_resp = MagicMock()
        mock_resp.json.return_value = SAMPLE_ASTRO_RESPONSE
        mock_fetch.return_value = mock_resp
        timer, output = self._make_mocks()

        get_astronauts(timer, output)

        output.set.assert_called_once()
        event = json.loads(output.set.call_args[0][0])
        assert event["schemaVersion"] == "1.0"
        assert event["eventType"] == "astronauts"
        assert "collectedAtUtc" in event
        assert event["data"] == SAMPLE_ASTRO_RESPONSE

    @patch("function_app._fetch_with_retry")
    def test_correct_url_called(self, mock_fetch):
        mock_resp = MagicMock()
        mock_resp.json.return_value = SAMPLE_ASTRO_RESPONSE
        mock_fetch.return_value = mock_resp
        timer, output = self._make_mocks()

        get_astronauts(timer, output)

        mock_fetch.assert_called_once_with(
            "https://api.open-notify.org/astros.json",
            timeout=10, retries=1, backoff=2,
        )

    @patch("function_app._fetch_with_retry")
    def test_http_failure_skips_cycle(self, mock_fetch):
        mock_fetch.side_effect = req.RequestException("Connection refused")
        timer, output = self._make_mocks()

        get_astronauts(timer, output)

        output.set.assert_not_called()

    @patch("function_app._fetch_with_retry")
    def test_invalid_json_skips_cycle(self, mock_fetch):
        mock_resp = MagicMock()
        mock_resp.json.side_effect = ValueError("Invalid JSON")
        mock_fetch.return_value = mock_resp
        timer, output = self._make_mocks()

        get_astronauts(timer, output)

        output.set.assert_not_called()

    @patch("function_app._fetch_with_retry")
    def test_timeout_skips_cycle(self, mock_fetch):
        mock_fetch.side_effect = req.Timeout("Timed out")
        timer, output = self._make_mocks()

        get_astronauts(timer, output)

        output.set.assert_not_called()

    @patch("function_app._fetch_with_retry")
    def test_connection_error_skips_cycle(self, mock_fetch):
        mock_fetch.side_effect = req.ConnectionError("DNS failure")
        timer, output = self._make_mocks()

        get_astronauts(timer, output)

        output.set.assert_not_called()
