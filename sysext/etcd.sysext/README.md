# etcd System Extension for Flatcar Container Linux

This directory contains the build configuration for an etcd systemd-sysext image following Flatcar's sysext-bakery patterns.

## Directory Structure

```
etcd.sysext/
├── create.sh                           # Build script (bakery-compatible)
├── files/
│   └── usr/
│       ├── local/bin/                  # Binaries (populated during build)
│       ├── lib/
│       │   ├── systemd/system/
│       │   │   ├── etcd.service        # systemd unit
│       │   │   └── multi-user.target.d/
│       │   │       └── 10-etcd.conf    # Upholds drop-in
│       │   ├── sysusers.d/
│       │   │   └── etcd.conf           # User/group creation
│       │   └── tmpfiles.d/
│       │       └── etcd.conf           # Directory creation
│       └── share/etcd/
│           ├── etcd.env.j2             # Jinja2 template for etcd configuration
│           └── etcdctl.sh.j2           # Jinja2 template for etcdctl environment
├── sysupdate/
│   ├── etcd.conf.j2                    # Jinja2 template for sysupdate config
│   └── sysupdate-etcd.service.dropin   # Drop-in for sysupdate service
├── butane/
│   └── etcd-sysext.bu.j2               # Jinja2 template for Butane configuration
└── README.md
```

## Building the Extension

### Prerequisites

- `curl` - for downloading etcd binaries
- `mksquashfs` - from squashfs-tools package
- `jq` - for parsing JSON (for listing versions)

### Standalone Build

```bash
# Build with default version (v3.5.21) for x86-64
./create.sh

# Build specific version
./create.sh --version v3.5.21 --arch x86-64

# Build for ARM64
./create.sh --version v3.5.21 --arch arm64

# Specify output directory
./create.sh --version v3.5.21 --output /path/to/output

# List available versions
./create.sh --list-versions
```

### With bakery.sh (if integrated)

```bash
# List available versions
./bakery.sh list etcd

# Build extension
./bakery.sh create etcd v3.5.21
./bakery.sh create etcd v3.5.21 --arch arm64
```

### Output

The build produces a SquashFS image named following the Flatcar convention:
```
etcd-<version>-<arch>.raw
```

Example: `etcd-3.5.21-x86-64.raw`

## Deployment

### 1. Copy artifacts to your asset server

```bash
# Copy sysext image
cp etcd-3.5.21-x86-64.raw /path/to/matchbox/assets/extensions/

# Render and copy sysupdate config (using Ansible)
ansible localhost -m template \
  -a "src=sysupdate/etcd.conf.j2 dest=/path/to/matchbox/assets/extensions/etcd.conf" \
  -e "etcd_sysext_download_url=http://matchbox:8080/assets/extensions"
```

### 2. Generate Butane/Ignition configuration with Ansible

```yaml
# playbook.yml
- hosts: etcd_nodes
  tasks:
    - name: Generate Butane configuration
      template:
        src: sysext/etcd.sysext/butane/etcd-sysext.bu.j2
        dest: "/tmp/{{ inventory_hostname }}-etcd.bu"
      delegate_to: localhost
```

### 3. Required Ansible Variables

```yaml
# Obligatorias (required)
etcd_address: "{{ ansible_default_ipv4.address }}"
etcd_initial_cluster: "etcd1=https://10.0.0.1:2380,etcd2=https://10.0.0.2:2380,etcd3=https://10.0.0.3:2380"
etcd_sysext_download_url: "http://matchbox.example.com:8080/assets/extensions"

# Opcionales (optional - have defaults)
etcd_version: "v3.5.21"
etcd_name: "{{ inventory_hostname }}"
etcd_data_dir: "/var/lib/etcd"
etcd_certs_dir: "/etc/etcd/pki"
etcd_initial_cluster_state: "new"
etcd_initial_cluster_token: "etcd-cluster"
etcd_peer_port: 2380
etcd_client_port: 2379
etcd_metrics_port: 2381
etcd_client_address: "127.0.0.1"
etcd_gomaxprocs: 4
etcd_sysext_storage_dir: "/opt/extensions/etcd"
etcd_sysext_link: "/etc/extensions/etcd.raw"
```

## Configuration

### Environment Variables (/etc/etcd/etcd.env)

The etcd service reads all configuration from `/etc/etcd/etcd.env`. Use the Jinja2 template at `files/usr/share/etcd/etcd.env.j2` to generate this file.

Key configuration groups:
- **Node Identity**: `ETCD_NAME`, `ETCD_DATA_DIR`
- **Clustering**: `ETCD_INITIAL_CLUSTER`, `ETCD_INITIAL_CLUSTER_STATE`, `ETCD_INITIAL_CLUSTER_TOKEN`
- **Peer URLs**: `ETCD_LISTEN_PEER_URLS`, `ETCD_INITIAL_ADVERTISE_PEER_URLS`
- **Client URLs**: `ETCD_LISTEN_CLIENT_URLS`, `ETCD_ADVERTISE_CLIENT_URLS`
- **Metrics**: `ETCD_LISTEN_METRICS_URLS`
- **TLS Server**: `ETCD_CERT_FILE`, `ETCD_KEY_FILE`, `ETCD_TRUSTED_CA_FILE`, `ETCD_CLIENT_CERT_AUTH`
- **TLS Peer**: `ETCD_PEER_CERT_FILE`, `ETCD_PEER_KEY_FILE`, `ETCD_PEER_TRUSTED_CA_FILE`, `ETCD_PEER_CLIENT_CERT_AUTH`
- **Security**: `ETCD_STRICT_RECONFIG_CHECK`
- **Performance**: `GOMAXPROCS`

### TLS Certificate Structure

Expected certificate paths (configurable via `etcd_certs_dir`):

```
/etc/etcd/pki/
├── ca.crt                      # CA certificate
├── server.crt                  # Server certificate
├── server.key                  # Server private key
├── peer.crt                    # Peer certificate
├── peer.key                    # Peer private key
├── apiserver-etcd-client.crt   # Client certificate (for etcdctl)
└── apiserver-etcd-client.key   # Client private key
```

## Included Components

### Binaries (in /usr/local/bin)

- `etcd` - etcd server
- `etcdctl` - etcd CLI client
- `etcdutl` - etcd utilities

### Systemd Unit (etcd.service)

- Runs as `etcd` user/group
- Reads environment from `/etc/etcd/etcd.env`
- Automatic restart on failure
- Resource limits configured (LimitNOFILE=65536)
- Process priority tuning (Nice=-10)

### Auto-Start Drop-in (multi-user.target.d/10-etcd.conf)

Ensures etcd starts automatically when the sysext is merged using `Upholds=etcd.service`.

### User/Group (sysusers.d/etcd.conf)

- Creates `etcd` user (UID 232)
- Creates `etcd` group (GID 232)
- Home directory: `/var/lib/etcd`

### Directories (tmpfiles.d/etcd.conf)

- `/var/lib/etcd` - Data directory (mode 0700)
- `/etc/etcd` - Configuration directory
- `/etc/etcd/pki` - Certificate directory
- `/run/etcd` - Runtime directory

## Automatic Updates with systemd-sysupdate

The sysupdate configuration enables automatic updates of the etcd extension:

1. Place new versions on your asset server following the naming pattern: `etcd-<version>-<arch>.raw`
2. `systemd-sysupdate` will check for updates
3. New versions are downloaded to `/opt/extensions/etcd/`
4. The symlink at `/etc/extensions/etcd.raw` is updated
5. A reboot flag is set if the extension changed

## Troubleshooting

### Check extension status
```bash
systemd-sysext status
```

### Check etcd service
```bash
systemctl status etcd
journalctl -u etcd
```

### Verify binaries are available
```bash
which etcd
etcd --version
etcdctl version
```

### Test cluster health
```bash
# Source etcdctl environment
source /etc/profile.d/etcdctl.sh

# Check health
etcdctl endpoint health

# List members
etcdctl member list
```

### Common Issues

1. **etcd.service fails to start**: Check that `/etc/etcd/etcd.env` exists and is properly configured
2. **TLS errors**: Verify certificate paths and permissions (keys should be mode 0400)
3. **Cluster issues**: Ensure `ETCD_INITIAL_CLUSTER` matches on all nodes

## Comparison with Original etcd Role

This sysext provides the same functionality as the original Ansible etcd role:

| Feature | Original Role | This Sysext |
|---------|--------------|-------------|
| Binary path | `/usr/local/bin` | `/usr/local/bin` |
| Config path | `/etc/etcd/etcd.env` | `/etc/etcd/etcd.env` |
| User/Group | etcd:etcd | etcd:etcd (UID/GID 232) |
| Metrics URL | Configurable | Via `ETCD_LISTEN_METRICS_URLS` |
| GOMAXPROCS | 4 | Configurable (default 4) |
| STRICT_RECONFIG_CHECK | true | true |

## References

- [Flatcar sysext-bakery](https://github.com/flatcar/sysext-bakery)
- [etcd documentation](https://etcd.io/docs/)
- [systemd-sysext](https://www.freedesktop.org/software/systemd/man/systemd-sysext.html)
- [systemd-sysupdate](https://www.freedesktop.org/software/systemd/man/systemd-sysupdate.html)
