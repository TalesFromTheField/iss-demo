"""Tests for Fabric streaming ingestion behavior in run.py."""

import pytest
from unittest.mock import MagicMock, patch

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import run


class TestSendToFabric:
    """Tests for the send_to_fabric function."""

    def test_raises_when_ingestion_uri_not_set(self, monkeypatch):
        monkeypatch.setattr(run, "FABRIC_INGESTION_URI", "")

        with pytest.raises(RuntimeError, match="FabricIngestionUri"):
            run.send_to_fabric("ISS_Loc", {"Latitude": 1.0, "Longitude": 2.0})

    def test_uses_managed_identity(self, monkeypatch):
        monkeypatch.setattr(run, "FABRIC_INGESTION_URI", "https://trd-test.z6.kusto.data.microsoft.com")

        mock_client = MagicMock()
        mock_client_cls = MagicMock(return_value=mock_client)
        mock_kcsb = MagicMock()
        monkeypatch.setattr(run, "KustoStreamingIngestClient", mock_client_cls)
        monkeypatch.setattr(run, "KustoConnectionStringBuilder", mock_kcsb)

        run.send_to_fabric("ISS_Loc", {"Latitude": 1.0, "Longitude": 2.0})

        mock_kcsb.with_azure_token_credential.assert_called_once()
        uri_arg = mock_kcsb.with_azure_token_credential.call_args[0][0]
        assert uri_arg == "https://trd-test.z6.kusto.data.microsoft.com"
        mock_client.ingest_from_stream.assert_called_once()

    def test_ingests_to_correct_table(self, monkeypatch):
        monkeypatch.setattr(run, "FABRIC_INGESTION_URI", "https://trd-test.z6.kusto.data.microsoft.com")
        monkeypatch.setattr(run, "FABRIC_DATABASE_NAME", "test-db")

        mock_client = MagicMock()
        monkeypatch.setattr(run, "KustoStreamingIngestClient", MagicMock(return_value=mock_client))
        monkeypatch.setattr(run, "KustoConnectionStringBuilder", MagicMock())

        run.send_to_fabric("ISS_Loc", {"Latitude": 1.0})

        _, kwargs = mock_client.ingest_from_stream.call_args
        props = kwargs["ingestion_properties"]
        assert props.table == "ISS_Loc"
        assert props.database == "test-db"


