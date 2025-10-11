# Debian Packaging for Crusoe Telemetry Agent

## Overview

The Crusoe Telemetry Agent has been packaged for Debian/Ubuntu using standard Debian packaging practices. The original `cta_manager.sh` script has been split into proper Debian maintainer scripts that handle installation, upgrade, and removal lifecycle events.

## Directory Structure

```
vm/
├── debian/                              # Debian packaging directory
│   ├── control                          # Package metadata and dependencies
│   ├── rules                            # Build instructions (Makefile)
│   ├── changelog                        # Version history
│   ├── compat                           # Debhelper compatibility level (13)
│   ├── copyright                        # License information
│   ├── install                          # File installation mappings
│   ├── postinst                         # Post-installation script
│   ├── prerm                            # Pre-removal script
│   ├── postrm                           # Post-removal script
│   ├── crusoe-telemetry-agent.dirs      # Directories to create
│   ├── source/format                    # Source package format (3.0 native)
│   ├── README.Debian                    # User-facing documentation
│   └── BUILD.md                         # Build instructions
├── build-deb.sh                         # Helper script to build package
├── config/                              # Config files (packaged)
├── docker/                              # Docker compose files (packaged)
├── systemctl/                           # Systemd units (packaged)
└── VERSION                              # Version file (packaged)
```

## Script Migration

### Original cta_manager.sh Functions → Debian Scripts

| Original Function | Debian Script | Description |
|-------------------|---------------|-------------|
| `do_install()` | `debian/postinst` | Post-installation configuration |
| `do_uninstall()` (stop services) | `debian/prerm` | Stop services before removal |
| `do_uninstall()` (cleanup) | `debian/postrm` | Remove configs and systemd units |
| `do_upgrade()` | Handled by dpkg | Package manager handles upgrades |
| `do_refresh_token()` | Manual process | User updates token file directly |

### Key Changes from Original Script

1. **No wget downloads**: Files are packaged and installed to `/usr/share/crusoe-telemetry-agent/`
2. **No GitHub branch selection**: Version is controlled by package version
3. **Debhelper handles file installation**: `debian/install` maps source → destination
4. **Token handling**: Prompts user if not found, preserves existing token
5. **Idempotent operations**: Scripts handle upgrade scenarios properly

## File Locations

### Package Data (Read-only)
- `/usr/share/crusoe-telemetry-agent/` - Package-provided files
  - `config/` - Vector and DCGM configs
  - `docker/` - Docker compose files
  - `systemctl/` - Systemd unit files
  - `VERSION` - Package version

### Runtime Configuration
- `/etc/crusoe/telemetry_agent/` - Runtime configuration
  - `vector.yaml` - Active Vector config (copied from package)
  - `docker-compose-vector.yaml` - Vector compose file
  - `docker-compose-dcgm-exporter.yaml` - DCGM compose file (GPU VMs)
  - `dcp-metrics-included.csv` - DCGM metrics config (GPU VMs)
  - `.env` - Environment variables (VM_ID, ports, etc.)
  - `VERSION` - Installed version

### Secrets
- `/etc/crusoe/secrets/` - Sensitive data
  - `.monitoring-token` - Crusoe monitoring token (preserved across reinstalls)

### Systemd
- `/etc/systemd/system/` - Systemd unit files
  - `crusoe-telemetry-agent.service` - Vector service
  - `crusoe-dcgm-exporter.service` - DCGM Exporter service (GPU VMs)

## Building the Package

### Prerequisites

```bash
sudo apt-get install -y debhelper devscripts build-essential
```

### Build

```bash
cd vm
./build-deb.sh
```

Or manually:

```bash
cd vm
dpkg-buildpackage -us -uc -b
```

The `.deb` package will be created in the parent directory.

## Installation

### Basic Installation

```bash
sudo apt install ./crusoe-telemetry-agent_*.deb
```

### With Token Pre-configured

```bash
export CRUSOE_AUTH_TOKEN="your-82-character-token"
sudo -E apt install ./crusoe-telemetry-agent_*.deb
```

### With Custom Environment

```bash
export CRUSOE_ENVIRONMENT="staging"
sudo -E apt install ./crusoe-telemetry-agent_*.deb
```

## Post-Installation

### Set Token (if not provided during install)

```bash
echo 'CRUSOE_AUTH_TOKEN=your-token-here' | sudo tee /etc/crusoe/secrets/.monitoring-token
sudo chmod 600 /etc/crusoe/secrets/.monitoring-token
sudo systemctl restart crusoe-telemetry-agent.service
```

### Verify Services

```bash
# Vector service (all VMs)
sudo systemctl status crusoe-telemetry-agent.service

# DCGM Exporter (GPU VMs only)
sudo systemctl status crusoe-dcgm-exporter.service
```

## Upgrade Process

The package upgrade process:

1. **Download new package**: `apt install ./crusoe-telemetry-agent_*.deb`
2. **prerm (old version)**: Stops services
3. **File replacement**: Package manager replaces files in `/usr/share/`
4. **postinst (new version)**: Copies new configs, restarts services
5. **Preserves**: `/etc/crusoe/secrets/.monitoring-token` is never touched

## Removal

### Remove (keep configuration)

```bash
sudo apt remove crusoe-telemetry-agent
```

This will:
- Stop and disable services
- Remove systemd unit files
- Keep `/etc/crusoe/telemetry_agent/` and secrets

### Purge (complete removal)

```bash
sudo apt purge crusoe-telemetry-agent
```

This will:
- Remove all configuration in `/etc/crusoe/telemetry_agent/`
- Preserve `/etc/crusoe/secrets/.monitoring-token` (intentionally)
- User can manually delete secrets if desired

## Maintainer Scripts Detail

### debian/postinst

**Triggered**: After package files are installed

**Actions**:
1. Detect GPU presence (nvidia-smi)
2. For GPU VMs:
   - Check/upgrade DCGM (v3 → v4)
   - Copy GPU configs
   - Install DCGM Exporter service
3. For CPU VMs:
   - Copy CPU configs
4. Handle auth token (check env, existing file, or prompt)
5. Create `.env` file with VM_ID and endpoints
6. Install systemd services
7. Enable and start services

### debian/prerm

**Triggered**: Before package removal/upgrade

**Actions**:
1. Stop `crusoe-telemetry-agent.service`
2. Stop `crusoe-dcgm-exporter.service` (if exists)

### debian/postrm

**Triggered**: After package removal

**Actions for remove**:
1. Disable services
2. Remove systemd unit files
3. Reload systemd daemon
4. Keep configs (for potential reinstall)

**Actions for purge**:
1. All of the above, plus:
2. Remove `/etc/crusoe/telemetry_agent/`
3. Preserve `/etc/crusoe/secrets/` (user can delete manually)

## Environment Variables

The package respects these environment variables during installation:

- `CRUSOE_AUTH_TOKEN` - Monitoring token (82 chars)
- `CRUSOE_ENVIRONMENT` - Environment: prod (default), staging, dev
- `DCGM_EXPORTER_SERVICE_NAME` - Custom DCGM service name (default: crusoe-dcgm-exporter.service)
- `DCGM_EXPORTER_SERVICE_PORT` - Custom DCGM port (default: 9400)

## Package Dependencies

### Required
- `docker.io` or `docker-ce` - Container runtime
- `wget` - For potential future downloads
- `dmidecode` - To get VM UUID
- `lsb-release` - To detect Ubuntu version

### Recommended (for GPU VMs)
- `nvidia-utils` - nvidia-smi command
- `datacenter-gpu-manager` - DCGM tools

## Testing Checklist

- [ ] Build package successfully
- [ ] Install on CPU VM
- [ ] Install on GPU VM with DCGM v3 (test upgrade)
- [ ] Install on GPU VM with DCGM v4 (no upgrade)
- [ ] Verify services start correctly
- [ ] Test token setup (env var)
- [ ] Test token setup (manual)
- [ ] Test package upgrade (preserve token)
- [ ] Test package removal (preserve config)
- [ ] Test package purge (clean removal)
- [ ] Run lintian for package quality

## Linting

```bash
cd vm
lintian ../crusoe-telemetry-agent_*.deb
```

Common warnings can be ignored if they're related to:
- Native package version
- Init script handling (we use systemd)

## Future Enhancements

1. **Debconf integration**: Interactive prompts for token during install
2. **Repository hosting**: Set up APT repository for easy `apt install crusoe-telemetry-agent`
3. **Automatic updates**: Enable unattended-upgrades support
4. **Multi-architecture**: Support arm64 if needed
5. **Systemd hardening**: Add security restrictions to unit files
6. **Config file handling**: Use debconf for managing config updates

## Comparison: Script vs Package

| Feature | cta_manager.sh | Debian Package |
|---------|----------------|----------------|
| Distribution | Download and execute | APT install |
| Updates | Manual script re-run | apt upgrade |
| Removal | Script with args | apt remove/purge |
| Dependencies | Manual checks | APT resolves |
| Version tracking | Manual VERSION file | Package version |
| Config management | Script-based | Debian standard |
| Token refresh | `cta_manager.sh refresh-token` | Manual file edit |
| Rollback | Manual | dpkg/apt handles |

## Notes

- The original `cta_manager.sh` script can remain for backward compatibility
- Package and script can coexist but shouldn't both manage the same installation
- For production deployments, prefer the Debian package
- For development/testing, the script may be more flexible

## Support

For issues related to Debian packaging:
- Check `/var/log/dpkg.log` for installation logs
- Check `journalctl -xeu crusoe-telemetry-agent.service` for service logs
- Review `debian/BUILD.md` for build troubleshooting

---

Last updated: 2025-10-10
