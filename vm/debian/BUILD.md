# Building the Crusoe Telemetry Agent Debian Package

This document explains how to build and test the Debian package for the Crusoe Telemetry Agent.

## Prerequisites

Install the required Debian packaging tools:

```bash
sudo apt-get update
sudo apt-get install -y debhelper devscripts build-essential
```

## Building the Package

From the repository root:

```bash
cd vm
dpkg-buildpackage -us -uc -b
```

This will create the `.deb` package in the parent directory (`crusoe-telemetry-agent/`).

### Build Options

- `-us -uc`: Skip signing (for local testing)
- `-b`: Binary-only build (no source package)
- `-rfakeroot`: Use fakeroot for building (alternative to running as root)

For a signed release build:

```bash
dpkg-buildpackage -b
```

## Installing the Package

After building, install the package:

```bash
cd ..
sudo apt install ./crusoe-telemetry-agent_*.deb
```

Or use dpkg directly:

```bash
sudo dpkg -i crusoe-telemetry-agent_*.deb
sudo apt-get install -f  # Fix any dependency issues
```

## Testing

### Basic Installation Test

```bash
# Install
sudo apt install ./crusoe-telemetry-agent_*.deb

# Check service status
sudo systemctl status crusoe-telemetry-agent.service

# Check installed files
dpkg -L crusoe-telemetry-agent

# Check configuration
ls -la /etc/crusoe/telemetry_agent/
```

### Upgrade Test

```bash
# Modify VERSION file to bump version
echo "0.1.1" > vm/VERSION

# Rebuild package
cd vm && dpkg-buildpackage -us -uc -b && cd ..

# Install upgrade
sudo apt install ./crusoe-telemetry-agent_*.deb
```

### Removal Test

```bash
# Remove (keeps config)
sudo apt remove crusoe-telemetry-agent

# Check if configs are preserved
ls /etc/crusoe/telemetry_agent/

# Purge (removes everything)
sudo apt purge crusoe-telemetry-agent
```

## Linting

Check the package for common issues:

```bash
cd vm
lintian ../crusoe-telemetry-agent_*.deb
```

## File Structure

```
vm/
├── debian/
│   ├── control              # Package metadata and dependencies
│   ├── rules                # Build rules
│   ├── changelog            # Version history
│   ├── compat               # Debhelper compatibility level
│   ├── copyright            # License information
│   ├── install              # File installation mappings
│   ├── postinst             # Post-installation script
│   ├── prerm                # Pre-removal script
│   ├── postrm               # Post-removal script
│   ├── crusoe-telemetry-agent.dirs  # Directories to create
│   ├── source/format        # Source package format
│   ├── README.Debian        # Debian-specific documentation
│   └── BUILD.md             # This file
├── config/                  # Configuration files to package
├── docker/                  # Docker compose files to package
├── systemctl/               # Systemd unit files to package
└── VERSION                  # Version file

```

## Updating the Package

### Version Bump

1. Update `vm/VERSION` file
2. Update `vm/debian/changelog`:
   ```bash
   cd vm
   dch -i  # Opens editor for new changelog entry
   ```
3. Rebuild the package

### Adding New Files

1. Add files to appropriate directory (config/, docker/, systemctl/)
2. Update `debian/install` to include new files
3. Update `debian/postinst` if installation logic changes
4. Rebuild the package

## Troubleshooting

### Package fails to install

Check the logs:
```bash
sudo journalctl -xeu crusoe-telemetry-agent.service
```

### Services not starting

Check if Docker is installed:
```bash
docker --version
```

Verify token is set:
```bash
sudo cat /etc/crusoe/secrets/.monitoring-token
```

### Build fails

Clean and rebuild:
```bash
debian/rules clean
dpkg-buildpackage -us -uc -b
```

## Additional Resources

- [Debian New Maintainers' Guide](https://www.debian.org/doc/manuals/maint-guide/)
- [Debian Policy Manual](https://www.debian.org/doc/debian-policy/)
- [debhelper Documentation](https://manpages.debian.org/debhelper)
