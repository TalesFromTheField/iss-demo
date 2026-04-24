# Stage 1: Build
FROM mcr.microsoft.com/azure-functions/python:4-python3.11 as base

ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true \
    PYTHONUNBUFFERED=1

WORKDIR /home/site/wwwroot

# Copy requirements and install dependencies
COPY functions/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy function app code
COPY functions/ .

# Run the scheduler wrapper (not the Functions runtime directly)
CMD ["python", "run.py"]
