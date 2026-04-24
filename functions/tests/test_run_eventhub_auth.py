"""Tests for Event Hubs authentication behavior in run.py."""

import pytest

import run


class _FakeBatch:
    def add(self, _event):
        return None


class _FakeProducer:
    def __init__(self):
        self.sent = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def create_batch(self):
        return _FakeBatch()

    def send_batch(self, _batch):
        self.sent = True


@pytest.fixture(autouse=True)
def _restore_globals():
    original_fqdn = run.EVENT_HUB_NAMESPACE_FQDN
    original_conn = run.EVENT_HUB_CONNECTION_STRING
    yield
    run.EVENT_HUB_NAMESPACE_FQDN = original_fqdn
    run.EVENT_HUB_CONNECTION_STRING = original_conn


def test_send_to_event_hub_uses_managed_identity(monkeypatch):
    run.EVENT_HUB_NAMESPACE_FQDN = "evhnsissdemo.servicebus.windows.net"
    run.EVENT_HUB_CONNECTION_STRING = "Endpoint=sb://ignored/;SharedAccessKeyName=a;SharedAccessKey=b"

    fake_producer = _FakeProducer()

    credential_called = {"value": False}

    def fake_credential(*args, **kwargs):
        credential_called["value"] = True
        return object()

    class _FakeEventHubProducerClient:
        def __init__(self, **kwargs):
            assert kwargs["fully_qualified_namespace"] == "evhnsissdemo.servicebus.windows.net"
            assert kwargs["eventhub_name"] == "iss-location"
            assert "credential" in kwargs

        @staticmethod
        def from_connection_string(*args, **kwargs):
            pytest.fail("SAS auth should not be used when namespace is configured")

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def create_batch(self):
            return _FakeBatch()

        def send_batch(self, _batch):
            fake_producer.sent = True

    monkeypatch.setattr(run, "DefaultAzureCredential", fake_credential)
    monkeypatch.setattr(run, "EventHubProducerClient", _FakeEventHubProducerClient)

    run.send_to_event_hub("iss-location", "{}")

    assert credential_called["value"] is True
    assert fake_producer.sent is True


def test_send_to_event_hub_falls_back_to_connection_string(monkeypatch):
    run.EVENT_HUB_NAMESPACE_FQDN = ""
    run.EVENT_HUB_CONNECTION_STRING = "Endpoint=sb://evhnsissdemo.servicebus.windows.net/;SharedAccessKeyName=Root;SharedAccessKey=key"

    fake_producer = _FakeProducer()

    def fake_from_conn(conn_str, eventhub_name):
        assert conn_str.startswith("Endpoint=sb://evhnsissdemo.servicebus.windows.net")
        assert eventhub_name == "astronauts"
        return fake_producer

    monkeypatch.setattr(run.EventHubProducerClient, "from_connection_string", fake_from_conn)

    run.send_to_event_hub("astronauts", "{}")

    assert fake_producer.sent is True


def test_send_to_event_hub_raises_when_no_auth_config(monkeypatch):
    run.EVENT_HUB_NAMESPACE_FQDN = ""
    run.EVENT_HUB_CONNECTION_STRING = ""

    with pytest.raises(RuntimeError):
        run.send_to_event_hub("iss-location", "{}")
