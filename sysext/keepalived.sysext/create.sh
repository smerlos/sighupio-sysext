#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# Keepalived system extension.
#

RELOAD_SERVICES_ON_MERGE="true"

function list_available_versions() {
    list_github_tags "acassen" "keepalived"
}
# --

function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  # Transform architecture for Alpine APK
  local apk_arch
  case "${arch}" in
    x86-64) apk_arch="x86_64" ;;
    arm64) apk_arch="aarch64" ;;
    *) echo "ERROR: Unsupported architecture: ${arch}" >&2; return 1 ;;
  esac

  # Extract version number (v2.3.4 -> 2.3.4)
  local version_no_v="${version#v}"

  # Alpine edge repository URL
  local alpine_repo="https://dl-cdn.alpinelinux.org/alpine/edge/community/${apk_arch}"
  local apk_package="keepalived-${version_no_v}-r1.apk"

  announce "Downloading keepalived ${version} from Alpine edge for ${arch}"

  # Download the APK package
  curl -fsSL "${alpine_repo}/${apk_package}" -o "${apk_package}"

  # Extract the APK (it's a tar.gz archive)
  tar -xzf "${apk_package}"

  # Alpine installs keepalived to /usr/sbin
  mkdir -p "${sysextroot}/usr/bin"
  cp usr/sbin/keepalived "${sysextroot}/usr/bin/"
  chmod 755 "${sysextroot}/usr/bin/keepalived"

  # Verify binary
  echo "Binary information:"
  file "${sysextroot}/usr/bin/keepalived"

  echo "✓ keepalived binary installed to ${sysextroot}/usr/bin/"
}
# --
