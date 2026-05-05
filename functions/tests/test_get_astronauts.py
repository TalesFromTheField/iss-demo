"""Unit tests for job_get_astronauts in run.py."""

from unittest.mock import MagicMock, patch

import requests as req

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import run


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


class TestJobGetAstronauts:
    """Tests for the job_get_astronauts scheduler job."""

    @patch("run.send_to_fabric")
    @patch("run._fetch_with_retry")
    def test_successful_poll_sends_record(self, mock_fetch, mock_send):
        mock_resp = MagicMock()
        mock_resp.json.return_value = SAMPLE_ASTRO_RESPONSE
        mock_fetch.return_value = mock_resp

        run.job_get_astronauts()

        mock_send.assert_called_once()
        table, record = mock_send.call_args[0]
        assert table == run.FABRIC_ASTRONAUTS_TABLE
        assert record["Number"] == 7
        assert record["People"] == SAMPLE_ASTRO_RESPONSE["people"]
        assert "CollectedAtUtc" in record

    @patch("run.send_to_fabric")
    @patch("run._fetch_with_retry")
    def test_correct_url_called(self, mock_fetch, mock_send):
        mock_resp = MagicMock()
        mock_resp.json.return_value = SAMPLE_ASTRO_RESPONSE
        mock_fetch.return_value = mock_resp

        run.job_get_astronauts()

        mock_fetch.assert_called_once_with(
            "https://api.open-notify.org/astros.json",
            timeout=10, retries=1, backoff=2,
        )

    @patch("run.send_to_fabric")
    @patch("run._fetch_with_retry")
    def test_http_failure_does_not_raise(self, mock_fetch, mock_send):
        mock_fetch.side_effect = req.RequestException("Connection refused")

        run.job_get_astronauts()

        mock_send.assert_not_called()

    @patch("run.send_to_fabric")
    @patch("run._fetch_with_retry")
    def test_timeout_does_not_raise(self, mock_fetch, mock_send):
        mock_fetch.side_effect = req.Timeout("Timed out")

        run.job_get_astronauts()

        mock_send.assert_not_called()

