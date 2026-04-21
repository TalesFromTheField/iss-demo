"""Pytest configuration for ISS Demo function tests."""


def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "integration: marks tests that call external APIs (deselect with '-m \"not integration\"')")
