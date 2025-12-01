# containerd System Extension for Flatcar Container Linux

This directory contains the build configuration for a containerd systemd-sysext image following Flatcar's sysext-bakery patterns.

## Directory Structure

```
containerd.sysext/
├── create.sh                           # Build script (bakery-compatible)
├── files/
│   └── usr/
│       ├── bin/                        # Binaries (populated during build)
│       │   ├── containerd
│       │   ├── containerd-shim-runc-v2
│       │   ├── ctr
│       │   └── ...
│       └── lib/
│           └── systemd/system/
│               ├── containerd.service  # systemd unit
│               └── multi-user.target.d/
│                   └── 10-containerd.conf  # Upholds drop-in
├── sysupdate/
│   ├── containerd.conf                 # sysupdate config
│   └── sysupdate-containerd.service.dropin
├── butane/
│   └── containerd-sysext.bu            # Butane configuration example
└── README.md
```

## Building the Extension

### Prerequisites

- `curl` - for downloading containerd binaries
- `mksquashfs` - from squashfs-tools package
- `tar` - for extracting tarballs

### Standalone Build

```bash
# Build with latest version for x86-64
./create.sh

# Build specific version
../../../bakery.sh create containerd 2.2.0 x86-64

# Build for ARM64
../../../bakery.sh create containerd 2.2.0 arm64

# List available versions
../../../bakery.sh list containerd
```

### Output

The build produces a SquashFS image:
```
containerd-<version>-<arch>.raw
```

Example: `containerd-2.2.0-x86-64.raw`

## Deployment

### 1. Manual Deployment

```bash
# Download the sysext image
wget https://github.com/smerlos/sighupio-sysext/releases/download/containerd-2.2.0/containerd-2.2.0-x86-64.raw

# Install to extensions directory
sudo mkdir -p /var/lib/extensions/
sudo mv containerd-2.2.0-x86-64.raw /var/lib/extensions/containerd.raw

# Merge the extension
sudo systemd-sysext refresh

# Verify containerd is available
containerd --version

# Enable and start containerd
sudo systemctl enable --now containerd
```

### 2. Butane/Ignition Configuration

See `butane/containerd-sysext.bu` for a complete example.

#### Basic Example

```yaml
variant: flatcar
version: 1.1.0

storage:
  directories:
    - path: /etc/containerd
      mode: 0755
    - path: /var/lib/containerd
      mode: 0755
    - path: /opt/extensions/containerd
      mode: 0755

  files:
    # Download and install containerd sysext
    - path: /opt/extensions/containerd/containerd-2.2.0-x86-64.raw
      mode: 0644
      contents:
        source: https://github.com/smerlos/sighupio-sysext/releases/download/containerd-2.2.0/containerd-2.2.0-x86-64.raw

    # containerd configuration
    - path: /etc/containerd/config.toml
      mode: 0644
      contents:
        inline: |
          version = 2

          [plugins."io.containerd.grpc.v1.cri"]
            sandbox_image = "registry.k8s.io/pause:3.9"

          [plugins."io.containerd.grpc.v1.cri".containerd]
            default_runtime_name = "runc"

          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
            runtime_type = "io.containerd.runc.v2"

          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true

  links:
    - path: /etc/extensions/containerd.raw
      target: /opt/extensions/containerd/containerd-2.2.0-x86-64.raw
      hard: false

systemd:
  units:
    - name: containerd.service
      enabled: true
```

## Configuration

### containerd Configuration (/etc/containerd/config.toml)

The default configuration is suitable for Kubernetes. Key settings:

```toml
version = 2

[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "registry.k8s.io/pause:3.9"

[plugins."io.containerd.grpc.v1.cri".containerd]
  default_runtime_name = "runc"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = true
```

### For Docker Compatibility

```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.docker]
  runtime_type = "io.containerd.runc.v2"
```

## Included Components

### Binaries (in /usr/bin)

- `containerd` - containerd daemon
- `containerd-shim-runc-v2` - shim for runc v2
- `ctr` - containerd CLI

### Systemd Unit (containerd.service)

- Socket activation support
- Automatic restart on failure
- Delegates control to containerd

### Auto-Start Drop-in (multi-user.target.d/10-containerd.conf)

Ensures containerd starts automatically when the sysext is merged using `Upholds=containerd.service`.

## Automatic Updates with systemd-sysupdate

The sysupdate configuration enables automatic updates:

```ini
[Transfer]
Verify=false

[Source]
Type=url-file
Path=https://github.com/smerlos/sighupio-sysext/releases/download/
MatchPattern=containerd-@v-%a.raw

[Target]
InstancesMax=3
Type=regular-file
Path=/opt/extensions/containerd
CurrentSymlink=/etc/extensions/containerd.raw
```

## Troubleshooting

### Check extension status
```bash
systemd-sysext status
```

### Check containerd service
```bash
systemctl status containerd
journalctl -u containerd
```

### Verify binaries are available
```bash
which containerd
containerd --version
ctr version
```

### Test containerd
```bash
# List namespaces
sudo ctr namespaces list

# List images
sudo ctr images list

# List containers
sudo ctr containers list
```

### Common Issues

1. **containerd.service fails to start**: Check `/etc/containerd/config.toml` syntax
2. **Permission errors**: Ensure containerd runs as root
3. **CRI plugin issues**: Verify systemd cgroup driver is configured

## Integration with Kubernetes

containerd is used as the container runtime for Kubernetes. Ensure:

1. SystemdCgroup is set to `true`
2. sandbox_image matches your Kubernetes version
3. containerd is running before kubelet starts

## References

- [containerd documentation](https://containerd.io/)
- [containerd GitHub](https://github.com/containerd/containerd)
- [systemd-sysext](https://www.freedesktop.org/software/systemd/man/systemd-sysext.html)
- [Flatcar sysext-bakery](https://github.com/flatcar/sysext-bakery)
