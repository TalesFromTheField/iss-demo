"""Unit tests for job_get_iss_location in run.py."""

from datetime import timezone
from unittest.mock import MagicMock, call, patch

import requests as req

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import run


SAMPLE_ISS_RESPONSE = {
    "iss_position": {"latitude": "41.7370", "longitude": "-49.4507"},
    "timestamp": 1234567890,
    "message": "success",
}


class TestJobGetIssLocation:
    """Tests for the job_get_iss_location scheduler job."""

    @patch("run.send_to_fabric")
    @patch("run._fetch_with_retry")
    def test_successful_poll_sends_record(self, mock_fetch, mock_send):
        mock_resp = MagicMock()
        mock_resp.json.return_value = SAMPLE_ISS_RESPONSE
        mock_fetch.return_value = mock_resp

        run.job_get_iss_location()

        mock_send.assert_called_once()
        table, record = mock_send.call_args[0]
        assert table == run.FABRIC_ISS_TABLE
        assert record["Latitude"] == 41.737
        assert record["Longitude"] == -49.4507
        assert "Timestamp" in record
        assert "CollectedAtUtc" in record

    @patch("run.send_to_fabric")
    @patch("run._fetch_with_retry")
    def test_correct_url_called(self, mock_fetch, mock_send):
        mock_resp = MagicMock()
        mock_resp.json.return_value = SAMPLE_ISS_RESPONSE
        mock_fetch.return_value = mock_resp

        run.job_get_iss_location()

        mock_fetch.assert_called_once_with(
            "https://api.open-notify.org/iss-now.json",
            timeout=10, retries=1, backoff=2,
        )

    @patch("run.send_to_fabric")
    @patch("run._fetch_with_retry")
    def test_http_failure_does_not_raise(self, mock_fetch, mock_send):
        mock_fetch.side_effect = req.RequestException("Connection refused")

        # Should not raise — errors are caught and logged
        run.job_get_iss_location()

        mock_send.assert_not_called()

    @patch("run.send_to_fabric")
    @patch("run._fetch_with_retry")
    def test_timeout_does_not_raise(self, mock_fetch, mock_send):
        mock_fetch.side_effect = req.Timeout("Timed out")

        run.job_get_iss_location()

        mock_send.assert_not_called()

