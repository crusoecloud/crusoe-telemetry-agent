#!/bin/bash

# --- Constants ---
UBUNTU_OS_VERSION=$(lsb_release -r -s)
CRUSOE_VM_ID=$(dmidecode -s system-uuid)

# GitHub branch (optional override via CLI, defaults to main)
GITHUB_BRANCH="main"

# Define paths for config files within the GitHub repository
REMOTE_VECTOR_CONFIG_GPU_VM="config/vector_gpu_vm.yaml"
REMOTE_VECTOR_CONFIG_CPU_VM="config/vector_cpu_vm.yaml"
REMOTE_DCGM_EXPORTER_METRICS_CONFIG="config/dcp-metrics-included.csv"
REMOTE_DOCKER_COMPOSE_DCGM_EXPORTER_UBUNTU_22="docker/docker-compose-dcgm-exporter-ubuntu22.04.yaml"
REMOTE_DOCKER_COMPOSE_VECTOR="docker/docker-compose-vector.yaml"
REMOTE_CRUSOE_TELEMETRY_SERVICE="systemctl/crusoe-telemetry-agent.service"
REMOTE_CRUSOE_DCGM_EXPORTER_SERVICE="systemctl/crusoe-dcgm-exporter.service"
SYSTEMCTL_DIR="/etc/systemd/system"
CRUSOE_TELEMETRY_AGENT_DIR="/etc/crusoe/telemetry_agent"
CRUSOE_AUTH_TOKEN_LENGTH=82
ENV_FILE="$CRUSOE_TELEMETRY_AGENT_DIR/.env" # Define the .env file path
CRUSOE_AUTH_TOKEN_REFRESH_ALIAS_PATH="/usr/bin/crusoe_auth_token_refresh"

# Optional parameters with defaults
DCGM_EXPORTER_SERVICE_NAME="crusoe-dcgm-exporter.service"
DCGM_EXPORTER_SERVICE_PORT="9400"

# CLI args parsing
usage() {
  echo "Usage: $0 [--dcgm-exporter-service-name NAME] [--dcgm-exporter-service-port PORT] [--branch BRANCH]"
  echo "Defaults: NAME=crusoe-dcgm-exporter.service, PORT=9400, BRANCH=main"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dcgm-exporter-service-name|-n)
        if [[ -n "$2" ]]; then
          DCGM_EXPORTER_SERVICE_NAME="$2"; shift 2
        else
          error_exit "Missing value for $1"
        fi
        ;;
      --dcgm-exporter-service-port|-p)
        if [[ -n "$2" ]]; then
          DCGM_EXPORTER_SERVICE_PORT="$2"; shift 2
        else
          error_exit "Missing value for $1"
        fi
        ;;
      --branch|-b)
        if [[ -n "$2" ]]; then
          GITHUB_BRANCH="$2"; shift 2
        else
          error_exit "Missing value for $1"
        fi
        ;;
      --help|-h)
        usage; exit 0;;
      *)
        echo "Unknown option: $1"; usage; exit 1;;
    esac
  done
}

# Check if a systemd unit exists (anywhere on the systemd path)
service_exists() {
  systemctl cat "$1" >/dev/null 2>&1
}

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
  if [[ $UBUNTU_OS_VERSION != "22.04" && $UBUNTU_OS_VERSION != "24.04" ]]; then
    error_exit "Ubuntu version $UBUNTU_OS_VERSION is not supported."
  fi
}

install_docker() {
  curl -fsSL https://get.docker.com | sh
}

# Function to check and upgrade DCGM version
upgrade_dcgm() {
  status "Checking DCGM version for upgrade."

  local dcgm_version_raw=$(dcgmi --version | grep 'DCGM Version:' | awk '{print $3}' | cut -d'.' -f1)
  local dcgm_version_major=${dcgm_version_raw:0:1}

  if [[ "$dcgm_version_major" -lt 4 ]]; then
    status "Current DCGM version ($dcgm_version_major.x.x) is older than 4.x.x. Upgrading DCGM."

    # Stop DCGM service
    systemctl --now disable nvidia-dcgm || error_exit "Failed to disable and stop nvidia-dcgm service."

    # Purge old packages
    dpkg --list datacenter-gpu-manager &> /dev/null && apt purge --yes datacenter-gpu-manager
    dpkg --list datacenter-gpu-manager-config &> /dev/null && apt purge --yes datacenter-gpu-manager-config

    # Update package lists
    apt-get update || error_exit "Failed to update package lists."

    # Get CUDA version
    if ! command_exists nvidia-smi; then
      error_exit "nvidia-smi not found. Cannot determine CUDA version for DCGM upgrade."
    fi
    local CUDA_VERSION=$(nvidia-smi -q | sed -E -n 's/CUDA Version[ :]+([0-9]+)[.].*/\1/p')

    if [[ -z "$CUDA_VERSION" ]]; then
      error_exit "Could not determine CUDA version. DCGM upgrade aborted."
    fi
    echo "Found CUDA Version: $CUDA_VERSION"

    # Install new DCGM package
    apt-get install --yes --install-recommends "datacenter-gpu-manager-4-cuda${CUDA_VERSION}" || error_exit "Failed to install datacenter-gpu-manager-4-cuda${CUDA_VERSION}."

    # Enable and start the new service
    systemctl --now enable nvidia-dcgm || error_exit "Failed to enable and start nvidia-dcgm service."

    status "DCGM upgrade complete."
  else
    echo "DCGM version is already 4.x.x or newer. No upgrade needed."
  fi
}

# Parse command line arguments
parse_args "$@"

# Update base URL to reflect chosen branch
GITHUB_RAW_BASE_URL="https://raw.githubusercontent.com/crusoecloud/crusoe-telemetry-agent/${GITHUB_BRANCH}"

# --- Main Script ---

# Ensure the script is run as root.
check_root

status "Ensure docker installation."
if command_exists docker; then
  echo "Docker is already installed."
else
  echo "Installing Docker."
  install_docker
fi

# Ensure wget is installed
status "Ensuring wget is installed."
if ! command_exists wget; then
  apt-get update && apt-get install -y wget || error_exit "Failed to install wget."
fi

status "Create telemetry agent target directory."
if ! dir_exists "$CRUSOE_TELEMETRY_AGENT_DIR"; then
  mkdir -p "$CRUSOE_TELEMETRY_AGENT_DIR"
fi

# Download required config files
# if VM has NVIDIA GPUs
HAS_NVIDIA_GPUS=false
if command_exists nvidia-smi && nvidia-smi -L >/dev/null 2>&1; then
  HAS_NVIDIA_GPUS=true
fi

if $HAS_NVIDIA_GPUS; then
  status "Ensure NVIDIA dependencies exist."
  if command_exists dcgmi && command_exists nvidia-ctk; then
    echo "Required NVIDIA dependencies are already installed."
    # Check and upgrade DCGM here
    upgrade_dcgm
  else
    error_exit "Please make sure NVIDIA dependencies (dcgm & nvidia-ctk) are installed and try again."
  fi

  check_os_support

  status "Download DCGM exporter metrics config."
  wget -q -O "$CRUSOE_TELEMETRY_AGENT_DIR/dcp-metrics-included.csv" "$GITHUB_RAW_BASE_URL/$REMOTE_DCGM_EXPORTER_METRICS_CONFIG" || error_exit "Failed to download $REMOTE_DCGM_EXPORTER_METRICS_CONFIG"

  status "Download GPU Vector config."
  wget -q -O "$CRUSOE_TELEMETRY_AGENT_DIR/vector.yaml" "$GITHUB_RAW_BASE_URL/$REMOTE_VECTOR_CONFIG_GPU_VM" || error_exit "Failed to download $REMOTE_VECTOR_CONFIG_GPU_VM"

  # Only download DCGM Exporter artifacts if the specified service does not already exist
  if service_exists "$DCGM_EXPORTER_SERVICE_NAME"; then
    echo "$DCGM_EXPORTER_SERVICE_NAME already exists. Skipping DCGM Exporter compose and service download."
  else
    status "Download DCGM Exporter docker-compose file."
    wget -q -O "$CRUSOE_TELEMETRY_AGENT_DIR/docker-compose-dcgm-exporter.yaml" "$GITHUB_RAW_BASE_URL/$REMOTE_DOCKER_COMPOSE_DCGM_EXPORTER_UBUNTU_22" || error_exit "Failed to download $REMOTE_DOCKER_COMPOSE_DCGM_EXPORTER_UBUNTU_22"

    status "Download $DCGM_EXPORTER_SERVICE_NAME systemd unit."
    wget -q -O "$SYSTEMCTL_DIR/$DCGM_EXPORTER_SERVICE_NAME" "$GITHUB_RAW_BASE_URL/$REMOTE_CRUSOE_DCGM_EXPORTER_SERVICE" || error_exit "Failed to download $REMOTE_CRUSOE_DCGM_EXPORTER_SERVICE"
  fi

  status "Enable and start systemd services for $DCGM_EXPORTER_SERVICE_NAME."
  echo "systemctl daemon-reload"
  systemctl daemon-reload
  echo "systemctl enable $DCGM_EXPORTER_SERVICE_NAME"
  systemctl enable "$DCGM_EXPORTER_SERVICE_NAME"
  echo "systemctl start $DCGM_EXPORTER_SERVICE_NAME"
  systemctl start "$DCGM_EXPORTER_SERVICE_NAME"
else
   status "Copy CPU Vector config."
   wget -q -O "$CRUSOE_TELEMETRY_AGENT_DIR/vector.yaml" "$GITHUB_RAW_BASE_URL/$REMOTE_VECTOR_CONFIG_CPU_VM" || error_exit "Failed to download $REMOTE_VECTOR_CONFIG_CPU_VM"
fi

status "Download Vector docker-compose file."
wget -q -O "$CRUSOE_TELEMETRY_AGENT_DIR/docker-compose-vector.yaml" "$GITHUB_RAW_BASE_URL/$REMOTE_DOCKER_COMPOSE_VECTOR" || error_exit "Failed to download $REMOTE_DOCKER_COMPOSE_VECTOR"

status "Fetching crusoe auth token."
if [[ -z "$CRUSOE_AUTH_TOKEN" ]]; then
  echo "Command: crusoe monitoring tokens create"
  echo "Please enter the crusoe monitoring token:"
  read -s CRUSOE_AUTH_TOKEN # -s for silent input (no echo)
  echo "" # Add a newline after the silent input for better readability

  if [ "${#CRUSOE_AUTH_TOKEN}" -ne $CRUSOE_AUTH_TOKEN_LENGTH ]; then
    echo "CRUSOE_AUTH_TOKEN should be $CRUSOE_AUTH_TOKEN_LENGTH characters long."
    echo "Use Crusoe CLI to generate a new token:"
    echo "Command: crusoe monitoring tokens create"
    error_exit "CRUSOE_AUTH_TOKEN is invalid. "
  fi
fi

status "Creating .env file with CRUSOE_AUTH_TOKEN and VM_ID."
cat <<EOF > "$ENV_FILE"
CRUSOE_AUTH_TOKEN='${CRUSOE_AUTH_TOKEN}'
VM_ID='${CRUSOE_VM_ID}'
DCGM_EXPORTER_PORT='${DCGM_EXPORTER_SERVICE_PORT}'
EOF
echo ".env file created at $ENV_FILE"

status "Download crusoe-telemetry-agent.service."
wget -q -O "$SYSTEMCTL_DIR/crusoe-telemetry-agent.service" "$GITHUB_RAW_BASE_URL/$REMOTE_CRUSOE_TELEMETRY_SERVICE" || error_exit "Failed to download $REMOTE_CRUSOE_TELEMETRY_SERVICE"

status "Download crusoe_auth_token_refresh.sh and make it executable command."
wget -q -O "$CRUSOE_TELEMETRY_AGENT_DIR/crusoe_auth_token_refresh.sh" "$GITHUB_RAW_BASE_URL/crusoe_auth_token_refresh.sh" || error_exit "Failed to download crusoe_auth_token_refresh.sh"
chmod +x "$CRUSOE_TELEMETRY_AGENT_DIR/crusoe_auth_token_refresh.sh"
# Create a symbolic link from /usr/bin to the actual script location.
ln -sf "$CRUSOE_TELEMETRY_AGENT_DIR/crusoe_auth_token_refresh.sh" "$CRUSOE_AUTH_TOKEN_REFRESH_ALIAS_PATH"

status "Enable and start systemd services for crusoe-telemetry-agent."
echo "systemctl daemon-reload"
systemctl daemon-reload
echo "systemctl enable crusoe-telemetry-agent.service"
systemctl enable crusoe-telemetry-agent.service
echo "systemctl start crusoe-telemetry-agent.service"
systemctl start crusoe-telemetry-agent

status "Setup Complete!"
if $HAS_NVIDIA_GPUS; then
  echo "Check status of $DCGM_EXPORTER_SERVICE_NAME: 'sudo systemctl status $DCGM_EXPORTER_SERVICE_NAME'"
fi
echo "Check status of crusoe-telemetry-agent service: 'sudo systemctl status crusoe-telemetry-agent.service'"
echo "Setup finished successfully!"