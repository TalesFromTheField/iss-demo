"""Tests for the _fetch_with_retry helper function."""

from unittest.mock import MagicMock, patch

import requests

from function_app import _fetch_with_retry


class TestFetchWithRetrySuccess:
    """Happy-path tests for _fetch_with_retry."""

    @patch("function_app.time.sleep")
    @patch("function_app.requests.get")
    def test_returns_response_on_first_attempt(self, mock_get, mock_sleep):
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_get.return_value = mock_response

        result = _fetch_with_retry("https://example.com", retries=1, backoff=2)

        assert result is mock_response
        mock_get.assert_called_once_with("https://example.com", timeout=10)
        mock_sleep.assert_not_called()

    @patch("function_app.time.sleep")
    @patch("function_app.requests.get")
    def test_succeeds_on_retry_after_failure(self, mock_get, mock_sleep):
        failure = requests.ConnectionError("connection refused")
        success = MagicMock()
        success.raise_for_status = MagicMock()
        mock_get.side_effect = [failure, success]

        result = _fetch_with_retry("https://example.com", retries=1, backoff=2)

        assert result is success
        assert mock_get.call_count == 2
        mock_sleep.assert_called_once_with(2)  # backoff * (2 ** 0) = 2


class TestFetchWithRetryFailure:
    """Tests for exhausted retries and error propagation."""

    @patch("function_app.time.sleep")
    @patch("function_app.requests.get")
    def test_raises_after_all_retries_exhausted(self, mock_get, mock_sleep):
        error = requests.ConnectionError("timeout")
        mock_get.side_effect = error

        try:
            _fetch_with_retry("https://example.com", retries=1, backoff=2)
            assert False, "Expected RequestException"
        except requests.RequestException as exc:
            assert exc is error

        assert mock_get.call_count == 2
        mock_sleep.assert_called_once_with(2)

    @patch("function_app.time.sleep")
    @patch("function_app.requests.get")
    def test_raises_on_http_500(self, mock_get, mock_sleep):
        mock_response = MagicMock()
        mock_response.raise_for_status.side_effect = requests.HTTPError("500 Server Error")
        mock_get.return_value = mock_response

        try:
            _fetch_with_retry("https://example.com", retries=0, backoff=2)
            assert False, "Expected HTTPError"
        except requests.HTTPError:
            pass

        mock_get.assert_called_once()
        mock_sleep.assert_not_called()

    @patch("function_app.time.sleep")
    @patch("function_app.requests.get")
    def test_zero_retries_makes_single_attempt(self, mock_get, mock_sleep):
        mock_get.side_effect = requests.Timeout("timed out")

        try:
            _fetch_with_retry("https://example.com", retries=0, backoff=2)
            assert False, "Expected Timeout"
        except requests.Timeout:
            pass

        mock_get.assert_called_once()
        mock_sleep.assert_not_called()


class TestFetchWithRetryBackoff:
    """Tests for backoff timing calculations."""

    @patch("function_app.time.sleep")
    @patch("function_app.requests.get")
    def test_backoff_doubles_each_retry(self, mock_get, mock_sleep):
        mock_get.side_effect = requests.ConnectionError("fail")

        try:
            _fetch_with_retry("https://example.com", retries=2, backoff=2)
        except requests.RequestException:
            pass

        assert mock_get.call_count == 3  # 1 initial + 2 retries
        assert mock_sleep.call_count == 2
        mock_sleep.assert_any_call(2)   # backoff * (2 ** 0) = 2
        mock_sleep.assert_any_call(4)   # backoff * (2 ** 1) = 4
