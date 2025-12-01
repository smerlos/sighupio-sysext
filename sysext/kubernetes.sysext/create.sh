#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# Kubernetes system extension.
#

RELOAD_SERVICES_ON_MERGE="true"

# We overwrite this library function and return a list of all latest patch levels
# of all supported release branches.
function list_latest_release() {
  curl -fsSL --retry-delay 1 --retry 60 --retry-connrefused \
       --retry-max-time 60 --connect-timeout 20 \
       https://raw.githubusercontent.com/kubernetes/website/main/data/releases/schedule.yaml \
       | yq -r '.schedules[] | .previousPatches[0] // (.release = .release + ".0") | .release' \
       | sed 's/^/v/'
}
# --

function list_available_versions() {
  curl -fsSL --retry-delay 1 --retry 60 --retry-connrefused \
       --retry-max-time 60 --connect-timeout 20 \
       https://raw.githubusercontent.com/kubernetes/website/main/data/releases/schedule.yaml \
       | yq -r '.schedules[] | .previousPatches[] // (.release = .release + ".0") | .release' \
       | sed 's/^/v/'
}
# --

function populate_sysext_root_options() {
  echo "  --cni-version <version> : Include CNI plugin <version> instead of latest."
  echo "                            For a list of versions please refer to:"
  echo "                    https://github.com/containernetworking/plugins/releases"
}
# --

function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local cni_version="$(get_optional_param "cni-version" "" "$@")"
  local rel_arch="$(arch_transform "x86-64" "amd64" "$arch")"

  if [[ -z ${cni_version} ]] ; then
    cni_version="$(curl_api_wrapper https://api.github.com/repos/containernetworking/plugins/releases/latest \
                   | jq -r .tag_name)"
  fi

  announce "Using CNI version '${version}'"

  mkdir -p "${sysextroot}/usr/bin"

  # Download Kubernetes binaries
  local k8s_base_url="https://dl.k8s.io/${version}/bin/linux/${rel_arch}"
  local binaries=("kubectl" "kubeadm" "kubelet")

  for binary in "${binaries[@]}"; do
    echo "Downloading ${binary}..."
    curl -fsSL "${k8s_base_url}/${binary}" -o "${sysextroot}/usr/bin/${binary}"

    # Download and verify SHA256 checksum
    echo "Verifying ${binary} SHA256 checksum..."
    local checksum_url="${k8s_base_url}/${binary}.sha256"
    local expected_checksum
    expected_checksum=$(curl -fsSL "${checksum_url}")

    if [[ -z "$expected_checksum" ]]; then
      echo "ERROR: Could not download checksum for ${binary}" >&2
      return 1
    fi

    # Compute actual checksum
    local actual_checksum
    actual_checksum=$(sha256sum "${sysextroot}/usr/bin/${binary}" | awk '{print $1}')

    # Verify checksums match
    if [[ "$expected_checksum" != "$actual_checksum" ]]; then
      echo "ERROR: SHA256 checksum mismatch for ${binary}" >&2
      echo "  Expected: $expected_checksum" >&2
      echo "  Actual:   $actual_checksum" >&2
      return 1
    fi

    echo "✓ ${binary} SHA256 checksum verified"
  done

  # Download CNI plugins
  echo "Downloading CNI plugins ${cni_version}..."
  local cni_tarball="cni-plugins-linux-${rel_arch}-${cni_version}.tgz"
  local cni_url="https://github.com/containernetworking/plugins/releases/download/${cni_version}/${cni_tarball}"
  local cni_checksum_url="https://github.com/containernetworking/plugins/releases/download/${cni_version}/${cni_tarball}.sha256"

  curl -fsSL "${cni_url}" -o cni.tgz

  # Download and verify CNI plugins checksum
  echo "Verifying CNI plugins SHA256 checksum..."
  local cni_expected_checksum
  # Extract only the hash (first field) from the checksum file
  cni_expected_checksum=$(curl -fsSL "${cni_checksum_url}" | awk '{print $1}')

  if [[ -z "$cni_expected_checksum" ]]; then
    echo "ERROR: Could not download checksum for CNI plugins" >&2
    return 1
  fi

  # Compute actual checksum
  local cni_actual_checksum
  cni_actual_checksum=$(sha256sum cni.tgz | awk '{print $1}')

  # Verify checksums match
  if [[ "$cni_expected_checksum" != "$cni_actual_checksum" ]]; then
    echo "ERROR: SHA256 checksum mismatch for CNI plugins" >&2
    echo "  Expected: $cni_expected_checksum" >&2
    echo "  Actual:   $cni_actual_checksum" >&2
    return 1
  fi

  echo "✓ CNI plugins SHA256 checksum verified"

  chmod +x "${sysextroot}/usr/bin/"*

  mkdir -p "${sysextroot}/usr/local/bin/cni"
  tar --force-local -xf "cni.tgz" -C "${sysextroot}/usr/local/bin/cni"

  mkdir -p "${sysextroot}/usr/local/share/"
  echo "${version}" > "${sysextroot}/usr/local/share/kubernetes-version"
  echo "${cni_version}" > "${sysextroot}/usr/local/share/kubernetes-cni-version"

  mkdir -p "${sysextroot}/usr/libexec/kubernetes/kubelet-plugins/volume/"
  # /var/kubernetes/... will be created at runtime by the kubelet unit.
  ln -sf "/var/kubernetes/kubelet-plugins/volume/exec" "${sysextroot}/usr/libexec/kubernetes/kubelet-plugins/volume/exec"

  # Generate 2nd sysupdate config for only patchlevel upgrades.
  local sysupdate="$(get_optional_param "sysupdate" "false" "${@}")"
  if [[ ${sysupdate} == true ]] ; then
    local majorver="$(echo "${version}" | sed 's/^\(v[0-9]\+\.[0-9]\+\).*/\1/')"
    _create_sysupdate "${extname}" "${extname}-${majorver}.@v-%a.raw" "${extname}" "${extname}" "${extname}-${majorver}.conf"
    mv "${extname}-${majorver}.conf" "${rundir}"
  fi
}
# --
