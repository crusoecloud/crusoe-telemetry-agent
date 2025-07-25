#!/bin/bash

# This script refreshes the Crusoe authentication token stored in the .env file
# for the Crusoe Telemetry Agent. It prompts the user for a new token and updates
# the CRUSOE_AUTH_TOKEN variable in the .env file.

# --- Constants (re-used from setup_crusoe_telemetry_agent.sh) ---
# Directory where the telemetry agent is installed and the .env file resides
CRUSOE_TELEMETRY_AGENT_DIR="/etc/crusoe/telemetry_agent"
# Expected length of the Crusoe authentication token
CRUSOE_AUTH_TOKEN_LENGTH=82
# Full path to the .env file
ENV_FILE="$CRUSOE_TELEMETRY_AGENT_DIR/.env"

# --- Helper Functions ---

# Function to print error messages and exit
error_exit() {
  echo "Error: $1" >&2
  exit 1
}

# Function to print status messages in bold
status() {
  echo -e "\n\033[1m$1\033[0m"
}

# Function to check if the script is run as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
      error_exit "This script must be run as root to update the .env file."
  fi
}

# Function to check if a file exists
file_exists() {
  [ -f "$1" ]
}

# --- Main Script ---
check_root # Ensure the script is run as root

status "Refreshing Crusoe Auth Token."

# Check if the .env file exists before attempting to modify it
if ! file_exists "$ENV_FILE"; then
  error_exit "The .env file not found at $ENV_FILE. Please run the 'setup_crusoe_telemetry_agent.sh' script first to set up the agent."
fi

# Prompt the user to enter the new Crusoe monitoring token
echo "Command: crusoe monitoring tokens create"
echo "Please enter the new Crusoe monitoring token:"
read -s NEW_CRUSOE_AUTH_TOKEN # -s for silent input (no echo)
echo "" # Add a newline after the silent input for better readability

# Validate the length of the entered token
if [ "${#NEW_CRUSOE_AUTH_TOKEN}" -ne $CRUSOE_AUTH_TOKEN_LENGTH ]; then
  echo "NEW_CRUSOE_AUTH_TOKEN should be $CRUSOE_AUTH_TOKEN_LENGTH characters long."
  echo "Use Crusoe CLI to generate a new token:"
  echo "Command: crusoe monitoring tokens create"
  error_exit "NEW_CRUSOE_AUTH_TOKEN is invalid. Please provide a valid token."
fi

# Update the CRUSOE_AUTH_TOKEN line in the .env file
# 'sed -i.bak' edits the file in place and creates a backup file (.bak)
# '^CRUSOE_AUTH_TOKEN=.*$' matches the line starting with CRUSOE_AUTH_TOKEN
# 's/.../.../' performs the substitution
status "Updating CRUSOE_AUTH_TOKEN in $ENV_FILE..."
sed -i.bak "s/^CRUSOE_AUTH_TOKEN=.*$/CRUSOE_AUTH_TOKEN='${NEW_CRUSOE_AUTH_TOKEN}'/" "$ENV_FILE"
rm "$ENV_FILE.bak" # Remove the backup file created by sed

status "Token refresh complete."
echo "CRUSOE_AUTH_TOKEN has been successfully updated in $ENV_FILE."
echo "For the changes to take effect, you may need to restart the crusoe-telemetry-agent service:"
echo "  sudo systemctl restart crusoe-telemetry-agent"
