#!/bin/bash

# --- Constants ---
SYSTEMCTL_DIR="/etc/systemd/system"
CRUSOE_TELEMETRY_AGENT_DIR="/etc/crusoe/telemetry_agent"
CRUSOE_AUTH_TOKEN_REFRESH_ALIAS_PATH="/usr/bin/crusoe_auth_token_refresh"

# Service name constant
DCGM_EXPORTER_SERVICE_NAME="crusoe-dcgm-exporter.service"

# --- Helper Functions ---
error_exit() {
  echo "Error: $1" >&2
  exit 1
}

status() {
  echo -e "\n\033[1m$1\033[0m"
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
      error_exit "This script must be run as root."
  fi
}

service_exists() {
  systemctl cat "$1" >/dev/null 2>&1
}

# CLI args parsing
usage() {
  echo "Usage: $0 [--help]"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        usage; exit 0;;
      *)
        echo "Unknown option: $1"; usage; exit 1;;
    esac
  done
}

# --- Main Script ---

# Parse command line arguments
parse_args "$@"

# Ensure the script is run as root
check_root

status "Starting Crusoe Telemetry Agent uninstallation..."

# Stop and disable crusoe-telemetry-agent service
if service_exists crusoe-telemetry-agent.service; then
  status "Stopping and disabling crusoe-telemetry-agent service."
  systemctl stop crusoe-telemetry-agent.service
  systemctl disable crusoe-telemetry-agent.service
  echo "crusoe-telemetry-agent service stopped and disabled."
else
  echo "crusoe-telemetry-agent service not found. Skipping."
fi

# Stop and disable DCGM exporter service (if exists)
if service_exists "$DCGM_EXPORTER_SERVICE_NAME"; then
  status "Stopping and disabling $DCGM_EXPORTER_SERVICE_NAME."
  systemctl stop "$DCGM_EXPORTER_SERVICE_NAME"
  systemctl disable "$DCGM_EXPORTER_SERVICE_NAME"
  echo "$DCGM_EXPORTER_SERVICE_NAME stopped and disabled."
else
  echo "$DCGM_EXPORTER_SERVICE_NAME not found. Skipping."
fi

# Remove systemd service files
status "Removing systemd service files."
if [ -f "$SYSTEMCTL_DIR/crusoe-telemetry-agent.service" ]; then
  rm -f "$SYSTEMCTL_DIR/crusoe-telemetry-agent.service"
  echo "Removed $SYSTEMCTL_DIR/crusoe-telemetry-agent.service"
fi

if [ -f "$SYSTEMCTL_DIR/$DCGM_EXPORTER_SERVICE_NAME" ]; then
  rm -f "$SYSTEMCTL_DIR/$DCGM_EXPORTER_SERVICE_NAME"
  echo "Removed $SYSTEMCTL_DIR/$DCGM_EXPORTER_SERVICE_NAME"
fi

# Reload systemd daemon
status "Reloading systemd daemon."
systemctl daemon-reload
echo "Systemd daemon reloaded."

# Remove telemetry agent directory
if [ -d "$CRUSOE_TELEMETRY_AGENT_DIR" ]; then
  status "Removing telemetry agent directory."
  rm -rf "$CRUSOE_TELEMETRY_AGENT_DIR"
  echo "Removed $CRUSOE_TELEMETRY_AGENT_DIR"
else
  echo "Telemetry agent directory not found. Skipping."
fi

# Remove symbolic link
if [ -L "$CRUSOE_AUTH_TOKEN_REFRESH_ALIAS_PATH" ]; then
  status "Removing crusoe_auth_token_refresh symbolic link."
  rm -f "$CRUSOE_AUTH_TOKEN_REFRESH_ALIAS_PATH"
  echo "Removed $CRUSOE_AUTH_TOKEN_REFRESH_ALIAS_PATH"
else
  echo "crusoe_auth_token_refresh symbolic link not found. Skipping."
fi

status "Uninstallation Complete!"
echo "Crusoe Telemetry Agent has been successfully uninstalled."
echo ""
echo "Note: Docker and NVIDIA dependencies were not removed as they may be used by other applications."
