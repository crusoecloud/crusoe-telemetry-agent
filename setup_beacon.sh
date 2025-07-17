#!/bin/bash

# --- Constants ---
UBUNTU_OS_VERSION=$(lsb_release -r -s)
CRUSOE_VM_ID=$(dmidecode -s system-uuid)

# GitHub raw content base URL
GITHUB_RAW_BASE_URL="https://raw.githubusercontent.com/crusoecloud/beacon/main"

# Define paths for config files within the GitHub repository
REMOTE_VECTOR_CONFIG_GPU_VM="config/vector_gpu_vm.yaml"
REMOTE_DCGM_EXPORTER_METRICS_CONFIG="config/dcp-metrics-included.csv"
REMOTE_DOCKER_COMPOSE_GPU_VM_UBUNTU_22="docker/docker-compose-gpu-vm-ubuntu22.04.yaml"
REMOTE_CRUSOE_BEACON_SERVICE="systemctl/crusoe-beacon.service"

SYSTEMCTL_DIR="/etc/systemd/system"
CRUSOE_BEACON_DIR="/etc/crusoe/beacon"

BEACON_TOKEN_FILE="$CRUSOE_BEACON_DIR/.beacon_token"
BEACON_TOKEN_LENGTH=82
BEACON_TOKEN=""

# Temporary directory for downloading and processing files
TEMP_CONFIG_DIR=$(mktemp -d -t beacon_config_XXXXXX)

# --- Helper Functions ---

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

file_exists() {
  [ -f "$1" ]
}

dir_exists() {
  [ -d "$1" ]
}

error_exit() {
  echo "Error: $1" >&2
  # Clean up temporary directory before exiting on error
  if [[ -d "$TEMP_CONFIG_DIR" ]]; then
    rm -rf "$TEMP_CONFIG_DIR"
  fi
  exit 1
}

status() {
  # Bold text for status messages
  echo -e "\n\033[1m$1\033[0m"
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
      error_exit "This script must be run as root."
  fi
}

check_os_support() {
  if [[ $UBUNTU_OS_VERSION != "22.04" ]]; then
    error_exit "Ubuntu version $UBUNTU_OS_VERSION is not supported."
  fi
}

install_docker() {
  curl -fsSL https://get.docker.com | sh
}

# --- Main Script ---

# Ensure the script is run as root.
check_root

# Ensure temporary directory is cleaned up on script exit
trap "rm -rf '$TEMP_CONFIG_DIR'" EXIT

check_os_support

status "Fetching Beacon secret."
# 1. Try to fetch the token from the BEACON_TOKEN_FILE
echo "Checking for token in: $BEACON_TOKEN_FILE..."
if [[ -f "$BEACON_TOKEN_FILE" && -r "$BEACON_TOKEN_FILE" ]]; then
    BEACON_TOKEN=$(cat "$BEACON_TOKEN_FILE")
    if [ "${#BEACON_TOKEN}" -ne $BEACON_TOKEN_LENGTH ]; then
      echo "BEACON_TOKEN should be $BEACON_TOKEN_LENGTH characters long."
      BEACON_TOKEN=""
    else
      echo "Token successfully read from $BEACON_TOKEN_FILE."
    fi
else
  echo "File $BEACON_TOKEN_FILE not found or not readable." >&2
fi

# 2. If token is not found, prompt the user
if [[ -z "$BEACON_TOKEN" ]]; then
  echo "Token not found from file. Prompting user for input..."
  echo "Please enter your authentication token:"
  read -s BEACON_TOKEN # -s for silent input (no echo)
  echo "" # Add a newline after the silent input for better readability

  if [ "${#BEACON_TOKEN}" -ne $BEACON_TOKEN_LENGTH ]; then
    echo "BEACON_TOKEN should be $BEACON_TOKEN_LENGTH characters long."
    echo "User Crusoe CLI to get a new token:"
    echo "Command: crusoe monitoring tokens create"
    error_exit "BEACON_TOKEN is invalid. "
  fi
fi

status "Create Beacon target directory."
if ! dir_exists "$CRUSOE_BEACON_DIR"; then
  mkdir -p "$CRUSOE_BEACON_DIR"
fi

status "Ensure docker installation."
if command_exists docker; then
  echo "Docker is already installed."
else
  echo "Installing Docker."
  install_docker
fi

status "Check if VM has NVIDIA GPUs."
if lspci | grep -q "NVIDIA Corporation"; then
  IS_GPU_VM=true
  echo "NVIDIA GPUs detected."
else
  IS_GPU_VM=false
  echo "NVIDIA GPU not detected."
fi

# Ensure wget is installed
status "Ensuring wget is installed."
if ! command_exists wget; then
  apt-get update && apt-get install -y wget || error_exit "Failed to install wget."
fi

# Download required files into the temporary directory
status "Downloading Beacon configuration files from GitHub."

# Download DCGM Exporter Metrics Config
LOCAL_DCGM_EXPORTER_METRICS_CONFIG="$TEMP_CONFIG_DIR/$(basename $REMOTE_DCGM_EXPORTER_METRICS_CONFIG)"
wget -q -O "$LOCAL_DCGM_EXPORTER_METRICS_CONFIG" "$GITHUB_RAW_BASE_URL/$REMOTE_DCGM_EXPORTER_METRICS_CONFIG" || error_exit "Failed to download $REMOTE_DCGM_EXPORTER_METRICS_CONFIG"

# Download Vector Config for GPU VM
LOCAL_VECTOR_CONFIG_GPU_VM="$TEMP_CONFIG_DIR/$(basename $REMOTE_VECTOR_CONFIG_GPU_VM)"
wget -q -O "$LOCAL_VECTOR_CONFIG_GPU_VM" "$GITHUB_RAW_BASE_URL/$REMOTE_VECTOR_CONFIG_GPU_VM" || error_exit "Failed to download $REMOTE_VECTOR_CONFIG_GPU_VM"

# Download Docker Compose file for GPU VM Ubuntu 22.04
LOCAL_DOCKER_COMPOSE_GPU_VM_UBUNTU_22="$TEMP_CONFIG_DIR/$(basename $REMOTE_DOCKER_COMPOSE_GPU_VM_UBUNTU_22)"
wget -q -O "$LOCAL_DOCKER_COMPOSE_GPU_VM_UBUNTU_22" "$GITHUB_RAW_BASE_URL/$REMOTE_DOCKER_COMPOSE_GPU_VM_UBUNTU_22" || error_exit "Failed to download $REMOTE_DOCKER_COMPOSE_GPU_VM_UBUNTU_22"

# Download Crusoe Beacon Service file
LOCAL_CRUSOE_BEACON_SERVICE="$TEMP_CONFIG_DIR/$(basename $REMOTE_CRUSOE_BEACON_SERVICE)"
wget -q -O "$LOCAL_CRUSOE_BEACON_SERVICE" "$GITHUB_RAW_BASE_URL/$REMOTE_CRUSOE_BEACON_SERVICE" || error_exit "Failed to download $REMOTE_CRUSOE_BEACON_SERVICE"


# install GPU VM dependencies
if $IS_GPU_VM; then
  status "Ensure NVIDIA dependencies exist."
  if command_exists dcgmi && command_exists nvidia-ctk; then
    echo "Required NVIDIA dependencies are already installed."
  else
    error_exit "Cannot find required NVIDIA dependencies. Please install them and try again."
  fi

  status "Copy DCGM exporter metrics config."
  if ! file_exists "$LOCAL_DCGM_EXPORTER_METRICS_CONFIG"; then
    error_exit "DCGM exporter metrics config not found in temporary directory: $LOCAL_DCGM_EXPORTER_METRICS_CONFIG"
  fi
  echo "cp $LOCAL_DCGM_EXPORTER_METRICS_CONFIG $CRUSOE_BEACON_DIR/dcp-metrics-included.csv"
  cp "$LOCAL_DCGM_EXPORTER_METRICS_CONFIG" "$CRUSOE_BEACON_DIR/dcp-metrics-included.csv"

  status "Copy Vector config."
  if ! file_exists "$LOCAL_VECTOR_CONFIG_GPU_VM"; then
    error_exit "Vector config not found in temporary directory: $LOCAL_VECTOR_CONFIG_GPU_VM"
  fi
  echo "cp $LOCAL_VECTOR_CONFIG_GPU_VM $CRUSOE_BEACON_DIR/vector.yaml"
  cp "$LOCAL_VECTOR_CONFIG_GPU_VM" "$CRUSOE_BEACON_DIR/vector.yaml"

  status "Copy docker-compose file."
  if [[ $UBUNTU_OS_VERSION == "22.04" ]]; then
    if ! file_exists "$LOCAL_DOCKER_COMPOSE_GPU_VM_UBUNTU_22"; then
      error_exit "Docker compose file not found in temporary directory: $LOCAL_DOCKER_COMPOSE_GPU_VM_UBUNTU_22"
    fi
    echo "cp $LOCAL_DOCKER_COMPOSE_GPU_VM_UBUNTU_22 $CRUSOE_BEACON_DIR/docker-compose.yaml"
    cp "$LOCAL_DOCKER_COMPOSE_GPU_VM_UBUNTU_22" "$CRUSOE_BEACON_DIR/docker-compose.yaml"
  else
      error_exit "Ubuntu version $UBUNTU_OS_VERSION is not supported."
  fi
else
  error_exit "Non-GPU VMs are not supported."
fi

status "Update docker-compose.yaml with BEACON_TOKEN."
sed -i.bak "s|BEACON_TOKEN_PLACEHOLDER|${BEACON_TOKEN}|g" "$CRUSOE_BEACON_DIR/docker-compose.yaml"
status "Update docker-compose.yaml with CRUSOE_VM_ID."
sed -i.bak "s|VM_ID_PLACEHOLDER|${CRUSOE_VM_ID}|g" "$CRUSOE_BEACON_DIR/docker-compose.yaml"

status "Enable systemctl service for crusoe-beacon."
if ! file_exists "$LOCAL_CRUSOE_BEACON_SERVICE"; then
  error_exit "Crusoe Beacon service file not found in temporary directory: $LOCAL_CRUSOE_BEACON_SERVICE"
fi
echo "cp $LOCAL_CRUSOE_BEACON_SERVICE $SYSTEMCTL_DIR/crusoe-beacon.service"
cp "$LOCAL_CRUSOE_BEACON_SERVICE" "$SYSTEMCTL_DIR/crusoe-beacon.service"
echo "systemctl daemon-reload"
systemctl daemon-reload
echo "systemctl enable crusoe-beacon.service"
systemctl enable crusoe-beacon.service

status "Setup Complete!"
echo "Setup script finished successfully!"
