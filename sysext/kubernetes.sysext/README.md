# Kubernetes System Extension for Flatcar Container Linux

This directory contains the build configuration for a Kubernetes systemd-sysext image following Flatcar's sysext-bakery patterns.

## Directory Structure

```
kubernetes.sysext/
├── create.sh                           # Build script (bakery-compatible)
├── files/
│   └── usr/
│       ├── bin/                        # Kubernetes binaries (populated during build)
│       │   ├── kubectl
│       │   ├── kubeadm
│       │   └── kubelet
│       ├── local/bin/cni/              # CNI plugins
│       └── lib/systemd/system/
│           ├── kubelet.service         # systemd unit
│           ├── kubelet.service.d/
│           │   └── 10-kubeadm.conf     # kubeadm drop-in
│           └── multi-user.target.d/
│               └── 10-kubelet.conf     # Upholds drop-in
├── sysupdate/
│   ├── kubernetes.conf                 # sysupdate config
│   └── sysupdate-kubernetes.service.dropin
├── butane/
│   └── kubernetes-sysext.bu            # Butane configuration example
└── README.md
```

## Building the Extension

### Prerequisites

- `curl` - for downloading Kubernetes binaries
- `mksquashfs` - from squashfs-tools package
- `jq` - for parsing JSON
- `yq` - for parsing YAML (version lists)

### Standalone Build

```bash
# Build with latest stable version for x86-64
../../../bakery.sh create kubernetes v1.32.0 x86-64

# Build for ARM64
../../../bakery.sh create kubernetes v1.32.0 arm64

# With specific CNI version
../../../bakery.sh create kubernetes v1.32.0 x86-64 --cni-version v1.6.0

# List available versions
../../../bakery.sh list kubernetes
```

### Output

The build produces a SquashFS image:
```
kubernetes-<version>-<arch>.raw
```

Example: `kubernetes-v1.32.0-x86-64.raw`

## Deployment

### 1. Manual Deployment

```bash
# Download the sysext image
wget https://github.com/smerlos/sighupio-sysext/releases/download/kubernetes-v1.32.0/kubernetes-v1.32.0-x86-64.raw

# Install to extensions directory
sudo mkdir -p /var/lib/extensions/
sudo mv kubernetes-v1.32.0-x86-64.raw /var/lib/extensions/kubernetes.raw

# Merge the extension
sudo systemd-sysext refresh

# Verify binaries are available
kubectl version --client
kubelet --version
kubeadm version
```

### 2. Butane/Ignition Configuration

See `butane/kubernetes-sysext.bu` for a complete example.

#### Basic Example

```yaml
variant: flatcar
version: 1.1.0

storage:
  directories:
    - path: /etc/kubernetes
      mode: 0755
    - path: /var/lib/kubelet
      mode: 0755
    - path: /opt/extensions/kubernetes
      mode: 0755

  files:
    # Download and install kubernetes sysext
    - path: /opt/extensions/kubernetes/kubernetes-v1.32.0-x86-64.raw
      mode: 0644
      contents:
        source: https://github.com/smerlos/sighupio-sysext/releases/download/kubernetes-v1.32.0/kubernetes-v1.32.0-x86-64.raw

    # kubelet configuration
    - path: /var/lib/kubelet/config.yaml
      mode: 0644
      contents:
        inline: |
          apiVersion: kubelet.config.k8s.io/v1beta1
          kind: KubeletConfiguration
          cgroupDriver: systemd
          containerRuntimeEndpoint: unix:///run/containerd/containerd.sock

  links:
    - path: /etc/extensions/kubernetes.raw
      target: /opt/extensions/kubernetes/kubernetes-v1.32.0-x86-64.raw
      hard: false

systemd:
  units:
    - name: kubelet.service
      enabled: true
      dropins:
        - name: 10-kubeadm.conf
          contents: |
            [Service]
            Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
            Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
            ExecStart=
            ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_EXTRA_ARGS
```

## Configuration

### kubelet Configuration (/var/lib/kubelet/config.yaml)

```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
resolvConf: /run/systemd/resolve/resolv.conf
clusterDNS:
  - 10.96.0.10
clusterDomain: cluster.local
```

### kubeadm Configuration

#### Control Plane Init

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    cgroup-driver: systemd
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.32.0
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
```

#### Worker Node Join

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    token: <token>
    apiServerEndpoint: <control-plane-ip>:6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    cgroup-driver: systemd
```

## Included Components

### Binaries (in /usr/bin)

- `kubectl` - Kubernetes CLI
- `kubeadm` - Kubernetes cluster bootstrap tool
- `kubelet` - Kubernetes node agent

### CNI Plugins (in /usr/local/bin/cni)

- `bridge` - Bridge CNI plugin
- `host-local` - IP allocation plugin
- `loopback` - Loopback plugin
- `portmap` - Port mapping plugin
- And many more...

### Systemd Unit (kubelet.service)

- Runs as root
- Automatic restart on failure
- Configured via drop-ins

### Auto-Start Drop-in (multi-user.target.d/10-kubelet.conf)

Ensures kubelet starts automatically when the sysext is merged using `Upholds=kubelet.service`.

## Cluster Bootstrap

### Initialize Control Plane

```bash
# Create kubeadm config
cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.32.0
networking:
  podSubnet: 10.244.0.0/16
EOF

# Initialize cluster
sudo kubeadm init --config kubeadm-config.yaml

# Setup kubectl for your user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install CNI (e.g., Calico)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

### Join Worker Nodes

```bash
# Get join command from control plane
kubeadm token create --print-join-command

# On worker node, run the join command
sudo kubeadm join <control-plane-ip>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket unix:///run/containerd/containerd.sock
```

## Automatic Updates with systemd-sysupdate

The sysupdate configuration enables automatic Kubernetes updates:

```ini
[Transfer]
Verify=false

[Source]
Type=url-file
Path=https://github.com/smerlos/sighupio-sysext/releases/download/
MatchPattern=kubernetes-v@v-%a.raw

[Target]
InstancesMax=3
Type=regular-file
Path=/opt/extensions/kubernetes
CurrentSymlink=/etc/extensions/kubernetes.raw
```

**Warning**: Automatic updates of Kubernetes should be carefully managed:
- Always test in non-production first
- Ensure compatibility with your cluster version
- Consider using minor version pinning

## Troubleshooting

### Check extension status
```bash
systemd-sysext status
```

### Check kubelet service
```bash
systemctl status kubelet
journalctl -u kubelet
```

### Verify binaries are available
```bash
kubectl version --client
kubelet --version
kubeadm version
```

### Check cluster status
```bash
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

### Common Issues

1. **kubelet fails to start**: Check `/var/lib/kubelet/config.yaml` exists
2. **Container runtime errors**: Ensure containerd is running and configured correctly
3. **CNI errors**: Verify CNI plugins are in `/usr/local/bin/cni`
4. **Certificate issues**: Check `/etc/kubernetes/pki/` permissions

### Debug kubelet

```bash
# Run kubelet in foreground with verbose logging
sudo /usr/bin/kubelet \
  --config=/var/lib/kubelet/config.yaml \
  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf \
  --kubeconfig=/etc/kubernetes/kubelet.conf \
  --v=4
```

## Version Compatibility

| Kubernetes | containerd | Notes |
|------------|-----------|-------|
| v1.32.x    | 2.0+      | Recommended |
| v1.31.x    | 1.7+      | Supported |
| v1.30.x    | 1.7+      | Supported |

## CNI Plugins

The extension includes the standard CNI plugins. Common CNI solutions:

- **Calico**: Network policy and security
- **Flannel**: Simple overlay network
- **Cilium**: eBPF-based networking
- **Weave Net**: Mesh networking

Install your preferred CNI after cluster initialization.

## References

- [Kubernetes documentation](https://kubernetes.io/docs/)
- [kubeadm documentation](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- [kubelet documentation](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/)
- [CNI plugins](https://www.cni.dev/)
- [Flatcar sysext-bakery](https://github.com/flatcar/sysext-bakery)
