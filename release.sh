#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# Release build script for multi-architecture sysext images.
# Builds extensions for x86-64 and arm64 architectures.
#
# Copyright (c) 2025 sighupio-sysext.
# Based on Flatcar sysext-bakery patterns.

set -euo pipefail

scriptroot="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${scriptroot}/lib/libbakery.sh"

# --

function usage() {
  cat <<EOF

Usage: $0 --name <extension> --version <version> [options]

Build a sysext extension for one or more architectures.

Required:
  --name <name>              Extension name (e.g., etcd, containerd)
  --version <version>        Version to build (e.g., v3.5.21, 2.2.0)

Options:
  --arch <arch>              Architecture: x86-64, arm64, or 'all' (default: all)
  --output-dir <dir>         Output directory (default: release/)
  --qemu-setup               Set up QEMU for cross-compilation (automatic for arm64)
  --skip-qemu-setup          Skip QEMU setup even for arm64
  --help                     Show this help

Examples:
  # Build etcd for all architectures
  $0 --name etcd --version v3.5.21

  # Build containerd for x86-64 only
  $0 --name containerd --version 2.2.0 --arch x86-64

  # Build kubernetes with custom output directory
  $0 --name kubernetes --version v1.32.0 --output-dir dist/

EOF
}

# --

function setup_qemu() {
  announce "Setting up QEMU for cross-compilation"

  # Check if QEMU is already set up
  if docker run --rm --privileged multiarch/qemu-user-static --reset -p yes >/dev/null 2>&1; then
    echo "✓ QEMU configured successfully"
    return 0
  else
    echo "WARNING: Failed to configure QEMU. arm64 builds may fail."
    return 1
  fi
}

# --

function build_for_arch() {
  local name="$1"
  local version="$2"
  local arch="$3"
  local output_dir="$4"

  announce "Building ${name} ${version} for ${arch}"

  # Create architecture-specific output directory
  local arch_output="${output_dir}/${arch}"
  mkdir -p "${arch_output}"

  # Build the extension
  "${scriptroot}/bakery.sh" create "$name" "$version" "$arch" "${arch_output}"

  # Verify the build succeeded
  local expected_file="${arch_output}/${name}-${version}-${arch}.raw"
  if [[ ! -f "$expected_file" ]]; then
    echo "ERROR: Expected output file not found: $expected_file" >&2
    return 1
  fi

  echo "✓ Built successfully: $expected_file"
  ls -lh "$expected_file"
}

# --

function main() {
  local name=""
  local version=""
  local arch="all"
  local output_dir="release"
  local qemu_setup="auto"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        name="$2"
        shift 2
        ;;
      --version)
        version="$2"
        shift 2
        ;;
      --arch)
        arch="$2"
        shift 2
        ;;
      --output-dir)
        output_dir="$2"
        shift 2
        ;;
      --qemu-setup)
        qemu_setup="yes"
        shift
        ;;
      --skip-qemu-setup)
        qemu_setup="no"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: Unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  # Validate required arguments
  if [[ -z "$name" ]]; then
    echo "ERROR: --name is required" >&2
    usage
    exit 1
  fi

  if [[ -z "$version" ]]; then
    echo "ERROR: --version is required" >&2
    usage
    exit 1
  fi

  # Validate extension exists
  if ! extension_name "$name" >/dev/null; then
    echo "ERROR: Extension '$name' not found" >&2
    echo "Available extensions:" >&2
    "${scriptroot}/bakery.sh" list >&2
    exit 1
  fi

  # Validate architecture
  case "$arch" in
    x86-64|arm64|all)
      ;;
    *)
      echo "ERROR: Invalid architecture: $arch" >&2
      echo "Valid architectures: x86-64, arm64, all" >&2
      exit 1
      ;;
  esac

  # Create output directory
  mkdir -p "$output_dir"

  # Determine if QEMU setup is needed
  local needs_qemu=false
  if [[ "$arch" == "arm64" ]] || [[ "$arch" == "all" ]]; then
    needs_qemu=true
  fi

  # Setup QEMU if needed
  if [[ "$needs_qemu" == "true" ]] && [[ "$qemu_setup" != "no" ]]; then
    if [[ "$qemu_setup" == "auto" ]] || [[ "$qemu_setup" == "yes" ]]; then
      setup_qemu || echo "WARNING: Continuing without QEMU setup"
    fi
  fi

  # Build for requested architectures
  local build_failed=false

  case "$arch" in
    all)
      announce "Building for all architectures: x86-64, arm64"

      if ! build_for_arch "$name" "$version" "x86-64" "$output_dir"; then
        echo "ERROR: x86-64 build failed" >&2
        build_failed=true
      fi

      if ! build_for_arch "$name" "$version" "arm64" "$output_dir"; then
        echo "ERROR: arm64 build failed" >&2
        build_failed=true
      fi
      ;;
    *)
      build_for_arch "$name" "$version" "$arch" "$output_dir" || build_failed=true
      ;;
  esac

  # Check if any builds failed
  if [[ "$build_failed" == "true" ]]; then
    echo >&2
    echo "ERROR: One or more builds failed" >&2
    exit 1
  fi

  announce "All builds completed successfully"
  echo
  echo "Output directory: $output_dir"
  echo
  echo "Built artifacts:"
  find "$output_dir" -type f \( -name "*.raw" -o -name "SHA256SUMS.*" \) -exec ls -lh {} \;
}

# --

main "$@"
