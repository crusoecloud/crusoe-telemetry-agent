#!/bin/bash
# Helper script to build the Debian package

set -e

# Check if we're in the vm directory
if [ ! -d "debian" ]; then
    echo "Error: debian/ directory not found."
    echo "Please run this script from the vm/ directory."
    exit 1
fi

echo "Building Crusoe Telemetry Agent Debian package..."
echo ""

# Check for required tools
if ! command -v dpkg-buildpackage >/dev/null 2>&1; then
    echo "Error: dpkg-buildpackage not found."
    echo "Install it with: sudo apt-get install devscripts debhelper build-essential"
    exit 1
fi

# Clean any previous builds
echo "Cleaning previous build artifacts..."
debian/rules clean || true

# Build the package
echo "Building package..."
dpkg-buildpackage -us -uc -b

echo ""
echo "Build complete!"
echo ""
echo "Package created in parent directory:"
ls -lh ../crusoe-telemetry-agent_*.deb 2>/dev/null || echo "No .deb file found - build may have failed"
echo ""
echo "To install:"
echo "  cd .. && sudo apt install ./crusoe-telemetry-agent_*.deb"
echo ""
echo "To test:"
echo "  sudo systemctl status crusoe-telemetry-agent.service"
