FROM ghcr.io/crusoecloud/crusoe-telemetry-agent/python:3.11-slim

# Add app
WORKDIR /app
COPY app /app
COPY requirements.txt /app/

# Install dependencies
RUN pip install -r /app/requirements.txt

# Run script by default
CMD ["python", "/app/vector_config_reloader_app.py"]
