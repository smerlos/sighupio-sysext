#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# Release metadata aggregation script.
# Generates extension-specific and global metadata from built releases.
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

Usage: $0 --mode <mode> [options]

Generate metadata for releases.

Modes:
  extension    - Generate metadata for a specific extension
  global       - Generate global metadata combining all extensions

Extension mode options:
  --name <name>           Extension name (required)
  --version <version>     Extension version (required)
  --release-dir <dir>     Directory containing release artifacts (default: release/)
  --output-file <file>    Output metadata file (default: <name>-<version>-metadata.json)

Global mode options:
  --release-dir <dir>     Directory containing release artifacts (default: release/)
  --output-file <file>    Output metadata file (default: global-metadata.json)

Examples:
  # Generate metadata for etcd extension
  $0 --mode extension --name etcd --version v3.5.21

  # Generate global metadata
  $0 --mode global

  # Custom output locations
  $0 --mode extension --name etcd --version v3.5.21 --output-file metadata/etcd.json
  $0 --mode global --output-file metadata/global.json

EOF
}

# --

function generate_extension_metadata() {
  local name="$1"
  local version="$2"
  local release_dir="$3"
  local output_file="$4"

  announce "Generating metadata for ${name} ${version}"

  # Collect artifacts for all architectures
  local artifacts=()
  local archs=("x86-64" "arm64")

  for arch in "${archs[@]}"; do
    local arch_dir="${release_dir}/${arch}"
    local raw_file="${arch_dir}/${name}-${version}-${arch}.raw"
    local checksum_file="${arch_dir}/SHA256SUMS.${name}"

    if [[ -f "$raw_file" ]] && [[ -f "$checksum_file" ]]; then
      local size
      size=$(stat -f%z "$raw_file" 2>/dev/null || stat -c%s "$raw_file")
      local checksum
      checksum=$(grep "${name}-${version}-${arch}.raw" "$checksum_file" | awk '{print $1}')

      artifacts+=("$arch:$size:$checksum")
    fi
  done

  if [[ ${#artifacts[@]} -eq 0 ]]; then
    echo "ERROR: No artifacts found for ${name} ${version} in ${release_dir}" >&2
    return 1
  fi

  # Generate JSON metadata
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$output_file" <<EOF
{
  "name": "${name}",
  "version": "${version}",
  "generated_at": "${timestamp}",
  "artifacts": [
EOF

  local first=true
  for artifact in "${artifacts[@]}"; do
    IFS=':' read -r arch size checksum <<< "$artifact"

    if [[ "$first" != "true" ]]; then
      echo "," >> "$output_file"
    fi
    first=false

    cat >> "$output_file" <<EOF
    {
      "architecture": "${arch}",
      "file": "${name}-${version}-${arch}.raw",
      "size_bytes": ${size},
      "sha256": "${checksum}"
    }
EOF
  done

  cat >> "$output_file" <<EOF

  ]
}
EOF

  echo "✓ Extension metadata written to: $output_file"
  cat "$output_file"
}

# --

function generate_global_metadata() {
  local release_dir="$1"
  local output_file="$2"

  announce "Generating global metadata"

  # Find all extension metadata files
  local metadata_files=()
  while IFS= read -r -d '' file; do
    metadata_files+=("$file")
  done < <(find "${release_dir}" -name "*-metadata.json" -type f -print0 2>/dev/null)

  if [[ ${#metadata_files[@]} -eq 0 ]]; then
    echo "WARNING: No extension metadata files found in ${release_dir}" >&2
    echo "Hint: Generate extension metadata first using --mode extension" >&2
  fi

  # Generate global metadata
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$output_file" <<EOF
{
  "generated_at": "${timestamp}",
  "repository": "${bakery}",
  "extensions": [
EOF

  if [[ ${#metadata_files[@]} -gt 0 ]]; then
    local first=true
    for meta_file in "${metadata_files[@]}"; do
      if [[ "$first" != "true" ]]; then
        echo "," >> "$output_file"
      fi
      first=false

      # Read and embed the extension metadata (remove first { and last })
      sed '1d;$d' "$meta_file" | sed 's/^/    /' >> "$output_file"
    done
  fi

  cat >> "$output_file" <<EOF

  ]
}
EOF

  echo "✓ Global metadata written to: $output_file"
  cat "$output_file"
}

# --

function main() {
  local mode=""
  local name=""
  local version=""
  local release_dir="release"
  local output_file=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        mode="$2"
        shift 2
        ;;
      --name)
        name="$2"
        shift 2
        ;;
      --version)
        version="$2"
        shift 2
        ;;
      --release-dir)
        release_dir="$2"
        shift 2
        ;;
      --output-file)
        output_file="$2"
        shift 2
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

  # Validate mode
  if [[ -z "$mode" ]]; then
    echo "ERROR: --mode is required" >&2
    usage
    exit 1
  fi

  case "$mode" in
    extension)
      # Validate required arguments
      if [[ -z "$name" ]]; then
        echo "ERROR: --name is required for extension mode" >&2
        exit 1
      fi

      if [[ -z "$version" ]]; then
        echo "ERROR: --version is required for extension mode" >&2
        exit 1
      fi

      # Set default output file
      if [[ -z "$output_file" ]]; then
        output_file="${release_dir}/${name}-${version}-metadata.json"
      fi

      generate_extension_metadata "$name" "$version" "$release_dir" "$output_file"
      ;;

    global)
      # Set default output file
      if [[ -z "$output_file" ]]; then
        output_file="${release_dir}/global-metadata.json"
      fi

      generate_global_metadata "$release_dir" "$output_file"
      ;;

    *)
      echo "ERROR: Invalid mode: $mode" >&2
      echo "Valid modes: extension, global" >&2
      exit 1
      ;;
  esac
}

# --

main "$@"
