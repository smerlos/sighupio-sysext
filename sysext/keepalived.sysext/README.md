# keepalived System Extension for Flatcar Container Linux

This directory contains the build configuration for a keepalived systemd-sysext image following Flatcar's sysext-bakery patterns.

## Directory Structure

```
keepalived.sysext/
├── create.sh                           # Build script (bakery-compatible)
├── build.sh                            # Compilation script (Alpine-based)
├── files/
│   └── usr/
│       ├── sbin/                       # keepalived binary (populated during build)
│       │   └── keepalived
│       └── lib/systemd/system/
│           ├── keepalived.service      # systemd unit
│           └── multi-user.target.d/
│               └── 10-keepalived.conf  # Upholds drop-in
├── sysupdate/
│   ├── keepalived.conf                 # sysupdate config
│   └── sysupdate-keepalived.service.dropin
├── butane/
│   └── keepalived-sysext.bu            # Butane configuration example
└── README.md
```

## Building the Extension

### Prerequisites

- `docker` - for Alpine-based compilation
- `mksquashfs` - from squashfs-tools package

### Build Process

keepalived is compiled from source using Alpine Linux in a Docker container to produce a static binary.

```bash
# Build with latest version for x86-64
../../../bakery.sh create keepalived v2.3.4 x86-64

# Build for ARM64 (requires QEMU)
../../../bakery.sh create keepalived v2.3.4 arm64

# List available versions
../../../bakery.sh list keepalived
```

### Output

The build produces a SquashFS image:
```
keepalived-<version>-<arch>.raw
```

Example: `keepalived-v2.3.4-x86-64.raw`

## Deployment

### 1. Manual Deployment

```bash
# Download the sysext image
wget https://github.com/smerlos/sighupio-sysext/releases/download/keepalived-v2.3.4/keepalived-v2.3.4-x86-64.raw

# Install to extensions directory
sudo mkdir -p /var/lib/extensions/
sudo mv keepalived-v2.3.4-x86-64.raw /var/lib/extensions/keepalived.raw

# Merge the extension
sudo systemd-sysext refresh

# Verify keepalived is available
keepalived --version

# Enable and start keepalived
sudo systemctl enable --now keepalived
```

### 2. Butane/Ignition Configuration

See `butane/keepalived-sysext.bu` for a complete example.

#### Basic Example

```yaml
variant: flatcar
version: 1.1.0

storage:
  directories:
    - path: /etc/keepalived
      mode: 0755
    - path: /opt/extensions/keepalived
      mode: 0755

  files:
    # Download and install keepalived sysext
    - path: /opt/extensions/keepalived/keepalived-v2.3.4-x86-64.raw
      mode: 0644
      contents:
        source: https://github.com/smerlos/sighupio-sysext/releases/download/keepalived-v2.3.4/keepalived-v2.3.4-x86-64.raw

    # keepalived configuration
    - path: /etc/keepalived/keepalived.conf
      mode: 0644
      contents:
        inline: |
          global_defs {
            router_id KUBERNETES_MASTER
          }

          vrrp_instance VI_1 {
            state MASTER
            interface eth0
            virtual_router_id 51
            priority 100
            advert_int 1

            authentication {
              auth_type PASS
              auth_pass secret
            }

            virtual_ipaddress {
              192.168.1.100/24
            }
          }

  links:
    - path: /etc/extensions/keepalived.raw
      target: /opt/extensions/keepalived/keepalived-v2.3.4-x86-64.raw
      hard: false

systemd:
  units:
    - name: keepalived.service
      enabled: true
```

## Configuration

### keepalived Configuration (/etc/keepalived/keepalived.conf)

#### Basic VRRP Configuration

```conf
global_defs {
  router_id KUBERNETES_MASTER
  enable_script_security
}

vrrp_script check_apiserver {
  script "/usr/local/bin/check-apiserver.sh"
  interval 3
  weight -2
  fall 2
  rise 2
}

vrrp_instance VI_1 {
  state MASTER
  interface eth0
  virtual_router_id 51
  priority 100
  advert_int 1

  authentication {
    auth_type PASS
    auth_pass your_secret_password
  }

  virtual_ipaddress {
    192.168.1.100/24
  }

  track_script {
    check_apiserver
  }
}
```

#### Kubernetes API Server HA Configuration

```conf
global_defs {
  router_id K8S_API_LB
  vrrp_skip_check_adv_addr
  vrrp_strict
  vrrp_garp_interval 0
  vrrp_gna_interval 0
}

vrrp_script check_apiserver {
  script "/usr/local/bin/check-apiserver.sh"
  interval 3
  timeout 10
  fall 2
  rise 2
  weight -2
}

vrrp_instance kube_api_server {
  state MASTER
  interface eth0
  virtual_router_id 51
  priority 100
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass k8s_api_secret
  }
  virtual_ipaddress {
    192.168.1.100/24 dev eth0
  }
  track_script {
    check_apiserver
  }
}
```

### Health Check Script

Create `/usr/local/bin/check-apiserver.sh`:

```bash
#!/bin/bash
# Check if kube-apiserver is responding

APISERVER_VIP=192.168.1.100
APISERVER_PORT=6443

curl -sfk https://${APISERVER_VIP}:${APISERVER_PORT}/healthz > /dev/null 2>&1
if [ $? -eq 0 ]; then
    exit 0
else
    exit 1
fi
```

Make it executable:
```bash
chmod +x /usr/local/bin/check-apiserver.sh
```

## Use Cases

### 1. Kubernetes Control Plane HA

keepalived provides a virtual IP for the Kubernetes API server:

```
┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│ Master 1    │   │ Master 2    │   │ Master 3    │
│ 192.168.1.1 │   │ 192.168.1.2 │   │ 192.168.1.3 │
└─────────────┘   └─────────────┘   └─────────────┘
       │                 │                 │
       └─────────────────┴─────────────────┘
                         │
                  Virtual IP
                 192.168.1.100
```

### 2. Load Balancer Failover

Provide high availability for load balancers or proxies.

### 3. Database Failover

Automatic failover for database master nodes.

## Included Components

### Binary (in /usr/sbin)

- `keepalived` - VRRP daemon (statically compiled)

### Systemd Unit (keepalived.service)

- Runs as root (required for network configuration)
- Reads configuration from `/etc/keepalived/keepalived.conf`
- Automatic restart on failure
- Supports reload via `SIGHUP`

### Auto-Start Drop-in (multi-user.target.d/10-keepalived.conf)

Ensures keepalived starts automatically when the sysext is merged using `Upholds=keepalived.service`.

## Automatic Updates with systemd-sysupdate

The sysupdate configuration enables automatic updates:

```ini
[Transfer]
Verify=false

[Source]
Type=url-file
Path=https://github.com/smerlos/sighupio-sysext/releases/download/
MatchPattern=keepalived-v@v-%a.raw

[Target]
InstancesMax=3
Type=regular-file
Path=/opt/extensions/keepalived
CurrentSymlink=/etc/extensions/keepalived.raw
```

## Troubleshooting

### Check extension status
```bash
systemd-sysext status
```

### Check keepalived service
```bash
systemctl status keepalived
journalctl -u keepalived
```

### Verify binary is available
```bash
which keepalived
keepalived --version
```

### Check VRRP Status

```bash
# Check if virtual IP is assigned
ip addr show

# Monitor keepalived logs
journalctl -u keepalived -f

# Check VRRP packets
tcpdump -i eth0 vrrp
```

### Common Issues

1. **Virtual IP not assigned**:
   - Check interface name in config matches actual interface
   - Verify VRRP packets aren't blocked by firewall
   - Check priority settings on all nodes

2. **Split-brain**:
   - Multiple nodes have MASTER state
   - Check network connectivity between nodes
   - Verify authentication settings match

3. **Service fails to start**:
   - Validate `/etc/keepalived/keepalived.conf` syntax: `keepalived -t -f /etc/keepalived/keepalived.conf`
   - Check for required kernel modules: `modprobe ip_vs`

### Validate Configuration

```bash
# Check configuration syntax
keepalived -t -f /etc/keepalived/keepalived.conf

# Run in foreground for debugging
keepalived -n -l -D
```

## Security Considerations

1. **Authentication**: Always use authentication in production
2. **Firewall**: Allow VRRP (protocol 112) between nodes
3. **Script Security**: Enable `enable_script_security` in global_defs
4. **Permissions**: Protect `/etc/keepalived/keepalived.conf` (mode 0600)

## Kubernetes Integration

### High Availability Setup

1. Deploy keepalived on all control plane nodes
2. Configure same VIP on all nodes with different priorities
3. Point kubeconfig to the VIP
4. Workers join using the VIP

### Example Priority Configuration

- Node 1 (Primary): `priority 100`
- Node 2 (Secondary): `priority 99`
- Node 3 (Tertiary): `priority 98`

The node with the highest priority becomes MASTER.

## References

- [keepalived documentation](https://www.keepalived.org/)
- [keepalived GitHub](https://github.com/acassen/keepalived)
- [VRRP RFC 5798](https://tools.ietf.org/html/rfc5798)
- [Flatcar sysext-bakery](https://github.com/flatcar/sysext-bakery)
