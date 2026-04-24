"""Integration tests for Open Notify API endpoints.

These tests call the real API and validate response schemas.
They are marked with @pytest.mark.integration and can be run with:
    pytest functions/tests/ -m integration
"""

import pytest
import requests

ISS_LOCATION_URL = "https://api.open-notify.org/iss-now.json"
ASTRONAUTS_URL = "https://api.open-notify.org/astros.json"
REQUEST_TIMEOUT = 15


def _get(url: str) -> requests.Response:
    """Make a GET request, skipping the test if the API is unreachable."""
    try:
        return requests.get(url, timeout=REQUEST_TIMEOUT)
    except requests.exceptions.RequestException as exc:
        pytest.skip(f"External API unreachable: {exc}")


@pytest.mark.integration
class TestIssLocationApi:
    """Tests for the ISS location API endpoint."""

    def test_returns_200(self):
        resp = _get(ISS_LOCATION_URL)
        assert resp.status_code == 200

    def test_response_has_iss_position(self):
        resp = _get(ISS_LOCATION_URL)
        data = resp.json()
        assert "iss_position" in data
        assert "latitude" in data["iss_position"]
        assert "longitude" in data["iss_position"]

    def test_response_has_timestamp(self):
        resp = _get(ISS_LOCATION_URL)
        data = resp.json()
        assert "timestamp" in data
        assert isinstance(data["timestamp"], int)

    def test_response_message_is_success(self):
        resp = _get(ISS_LOCATION_URL)
        data = resp.json()
        assert data.get("message") == "success"

    def test_coordinates_are_valid_strings(self):
        resp = _get(ISS_LOCATION_URL)
        pos = resp.json()["iss_position"]
        # Coordinates come as strings; verify they're parseable floats
        lat = float(pos["latitude"])
        lon = float(pos["longitude"])
        assert -90 <= lat <= 90
        assert -180 <= lon <= 180


@pytest.mark.integration
class TestAstronautsApi:
    """Tests for the astronauts API endpoint."""

    def test_returns_200(self):
        resp = _get(ASTRONAUTS_URL)
        assert resp.status_code == 200

    def test_response_has_number(self):
        resp = _get(ASTRONAUTS_URL)
        data = resp.json()
        assert "number" in data
        assert isinstance(data["number"], int)
        assert data["number"] > 0

    def test_response_has_people_list(self):
        resp = _get(ASTRONAUTS_URL)
        data = resp.json()
        assert "people" in data
        assert isinstance(data["people"], list)
        assert len(data["people"]) == data["number"]

    def test_each_person_has_name_and_craft(self):
        resp = _get(ASTRONAUTS_URL)
        data = resp.json()
        for person in data["people"]:
            assert "name" in person and person["name"]
            assert "craft" in person and person["craft"]

    def test_response_message_is_success(self):
        resp = _get(ASTRONAUTS_URL)
        data = resp.json()
        assert data.get("message") == "success"
