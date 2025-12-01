# System Extensions (sysext) for Flatcar Container Linux

This directory contains build configurations for systemd-sysext images following Flatcar's sysext-bakery patterns.

## What are System Extensions?

System extensions (sysext) are a way to extend Flatcar's immutable `/usr` filesystem using an overlay mechanism provided by `systemd-sysext`. Extensions are packaged as SquashFS images with a `.raw` extension.

## Directory Structure

```
sysext/
├── helpers.sh          # Common helper functions for build scripts
├── README.md           # This file
└── <extension>/        # Extension-specific directory
    ├── create.sh       # Build script
    ├── files/          # Static files to include
    │   └── usr/
    │       └── lib/
    │           ├── systemd/system/   # systemd units
    │           ├── sysusers.d/       # User/group definitions
    │           └── tmpfiles.d/       # Directory definitions
    ├── sysupdate/      # Sysupdate configuration files
    └── butane/         # Example Butane configurations
```

## Available Extensions

| Extension | Description | Version |
|-----------|-------------|---------|
| [etcd](etcd/) | Distributed key-value store for Kubernetes | v3.5.21 |

## Building Extensions

### Prerequisites

- `curl` - for downloading binaries
- `mksquashfs` - from squashfs-tools package
- `tar` - for extracting archives
- `jq` - for parsing JSON (optional)

### Build Commands

Each extension has its own `create.sh` script:

```bash
# Build specific extension
cd <extension>
./create.sh --version <version> --arch <arch>

# Example: Build etcd
cd etcd
./create.sh --version v3.5.21 --arch x86-64
```

### Common Options

| Option | Description |
|--------|-------------|
| `-v, --version` | Software version to build |
| `-a, --arch` | Target architecture (x86-64, arm64) |
| `-o, --output` | Output directory |
| `-h, --help` | Show help message |

## Deployment with Butane/Ignition

### Basic Deployment

```yaml
variant: flatcar
version: 1.1.0

storage:
  files:
    # Extension image
    - path: /opt/extensions/<name>/<name>-<version>-<arch>.raw
      contents:
        source: http://your-server/assets/extensions/<name>-<version>-<arch>.raw
  
  links:
    # Activate extension
    - path: /etc/extensions/<name>.raw
      target: /opt/extensions/<name>/<name>-<version>-<arch>.raw
```

### With Automatic Updates (sysupdate)

```yaml
storage:
  files:
    # Sysupdate configuration
    - path: /etc/sysupdate.<name>.d/<name>.conf
      contents:
        source: http://your-server/assets/extensions/<name>.conf

systemd:
  units:
    - name: systemd-sysupdate.service
      dropins:
        - name: <name>.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/<name>.raw > /tmp/<name>"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C <name> update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/<name>.raw > /tmp/<name>-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /tmp/<name> /tmp/<name>-new; then touch /run/reboot-required; fi"
```

## Extension Anatomy

### Required Files

1. **extension-release** (`/usr/lib/extension-release.d/extension-release.<name>`)
   ```
   ID=flatcar
   SYSEXT_LEVEL=1.0
   EXTENSION_RELOAD_MANAGER=1
   ```

2. **Binaries** (`/usr/bin/` or `/usr/sbin/`)

### Optional Files

- **systemd units** (`/usr/lib/systemd/system/`)
- **sysusers.d** (`/usr/lib/sysusers.d/`) - for creating users/groups
- **tmpfiles.d** (`/usr/lib/tmpfiles.d/`) - for creating directories

## Managing Extensions

### View active extensions
```bash
systemd-sysext status
```

### Refresh extensions
```bash
systemd-sysext refresh
```

### List available images
```bash
ls -la /etc/extensions/
ls -la /opt/extensions/
```

## References

- [Flatcar sysext-bakery](https://github.com/flatcar/sysext-bakery)
- [systemd-sysext documentation](https://www.freedesktop.org/software/systemd/man/systemd-sysext.html)
- [systemd-sysupdate documentation](https://www.freedesktop.org/software/systemd/man/systemd-sysupdate.html)
- [Flatcar Container Linux docs](https://www.flatcar.org/docs/latest/)
