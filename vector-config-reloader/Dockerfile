FROM ghcr.io/crusoecloud/crusoe-telemetry-agent/python:3.11-slim

# Install dependencies
RUN pip install --no-cache-dir pyyaml kubernetes

# Add script
WORKDIR /app
COPY ./app/vector_config_reloader_app.py /app/vector_config_reloader_app.py

# Run script by default
CMD ["python", "/app/vector_config_reloader_app.py"]
