#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# etcd System Extension Build Script
# Following Flatcar sysext-bakery patterns
#

set -euo pipefail

# Extension metadata - used by bakery.sh when sourcing this script
# shellcheck disable=SC2034
RELOAD_SERVICES_ON_MERGE="true"

# ==================== REQUIRED FUNCTIONS ====================

# Fetch and print a list of available versions (one per line, newest first)
function list_available_versions() {
  curl -fsSL "https://api.github.com/repos/etcd-io/etcd/releases" 2>/dev/null | \
    jq -r '.[].tag_name' 2>/dev/null | \
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | \
    sort -Vr
}

# Populate the sysext root with binaries and files
function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  # Transform architecture names for etcd download
  local dl_arch
  case "${arch}" in
    x86-64)
      dl_arch="amd64"
      ;;
    arm64)
      dl_arch="arm64"
      ;;
    *)
      echo "ERROR: Unsupported architecture: ${arch}" >&2
      return 1
      ;;
  esac

  echo "Downloading etcd ${version} for ${dl_arch}..."

  # Download etcd tarball
  local tarball="etcd-${version}-linux-${dl_arch}.tar.gz"
  local download_url="https://storage.googleapis.com/etcd/${version}/${tarball}"
  local checksum_url="https://storage.googleapis.com/etcd/${version}/SHA256SUMS"

  curl -fsSL "${download_url}" -o "${tarball}"

  # Download and verify SHA256 checksum
  echo "Verifying SHA256 checksum..."
  curl -fsSL "${checksum_url}" -o SHA256SUMS

  # Extract the checksum for our specific tarball
  local expected_checksum
  expected_checksum=$(grep "${tarball}" SHA256SUMS | awk '{print $1}')

  if [[ -z "$expected_checksum" ]]; then
    echo "ERROR: Could not find checksum for ${tarball} in SHA256SUMS" >&2
    return 1
  fi

  # Compute actual checksum
  local actual_checksum
  actual_checksum=$(sha256sum "${tarball}" | awk '{print $1}')

  # Verify checksums match
  if [[ "$expected_checksum" != "$actual_checksum" ]]; then
    echo "ERROR: SHA256 checksum mismatch for ${tarball}" >&2
    echo "  Expected: $expected_checksum" >&2
    echo "  Actual:   $actual_checksum" >&2
    return 1
  fi

  echo "✓ SHA256 checksum verified: $expected_checksum"

  tar --force-local -xzf "${tarball}"

  # Copy binaries to /usr/bin
  # Following Flatcar sysext standard location
  mkdir -p "${sysextroot}/usr/bin"
  cp "etcd-${version}-linux-${dl_arch}/etcd" "${sysextroot}/usr/bin/"
  cp "etcd-${version}-linux-${dl_arch}/etcdctl" "${sysextroot}/usr/bin/"
  cp "etcd-${version}-linux-${dl_arch}/etcdutl" "${sysextroot}/usr/bin/"
  chmod 755 "${sysextroot}/usr/bin/"*

  echo "etcd binaries installed to ${sysextroot}/usr/bin/"
}
