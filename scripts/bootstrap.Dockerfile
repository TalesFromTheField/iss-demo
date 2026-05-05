# Bootstrap container for ISS Demo Fabric setup.
# Built on the official Azure CLI image which includes az, python3, and pip.
# Adds ms-fabric-cli (fab) and bakes in bootstrap.sh.
#
# Build context: repo root
#   docker build -f scripts/bootstrap.Dockerfile -t iss-demo-bootstrap .

FROM mcr.microsoft.com/azure-cli:2.59.0

RUN pip install --no-cache-dir --disable-pip-version-check ms-fabric-cli

COPY scripts/bootstrap.sh /bootstrap.sh
RUN chmod +x /bootstrap.sh

ENTRYPOINT ["/bootstrap.sh"]
