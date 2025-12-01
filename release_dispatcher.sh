#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# Release dispatcher for CI/CD automation.
# Reads release_build_versions.txt and determines which extensions need to be built.
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

Usage: $0 [options]

Analyzes release_build_versions.txt and determines which extensions need builds.

Options:
  --output-format <format>  Output format: json (default), plain, github-matrix
  --check-releases          Check if GitHub releases exist (default: true)
  --no-check-releases       Skip GitHub release checks (always output all)
  --help                    Show this help

Output formats:
  plain          - One line per extension: <name> <version>
  json           - JSON array of objects: [{"name": "...", "version": "..."}]
  github-matrix  - GitHub Actions matrix JSON

Examples:
  $0
  $0 --output-format plain
  $0 --output-format github-matrix
  $0 --no-check-releases

EOF
}

# --

function parse_build_versions() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    echo "ERROR: Configuration file not found: $config_file" >&2
    exit 1
  fi

  # Read non-comment, non-empty lines
  grep -v '^#' "$config_file" | grep -v '^[[:space:]]*$'
}

# --

function check_needs_build() {
  local name="$1"
  local version="$2"
  local check_releases="${3:-true}"

  if [[ "$check_releases" != "true" ]]; then
    # Always build if not checking releases
    return 0
  fi

  # Check if release exists on GitHub
  if github_release_exists "$bakery" "releases" "${name}-${version}"; then
    # Release exists, no build needed
    return 1
  fi

  # Release doesn't exist, build needed
  return 0
}

# --

function output_plain() {
  local name="$1"
  local version="$2"

  echo "$name $version"
}

# --

function output_json_start() {
  echo "["
}

function output_json_item() {
  local name="$1"
  local version="$2"
  local is_first="${3:-false}"

  if [[ "$is_first" != "true" ]]; then
    echo ","
  fi

  cat <<EOF
  {
    "name": "$name",
    "version": "$version"
  }
EOF
}

function output_json_end() {
  echo "]"
}

# --

function output_github_matrix_start() {
  echo -n '{"extension":['
}

function output_github_matrix_item() {
  local name="$1"
  local version="$2"
  local is_first="${3:-false}"

  if [[ "$is_first" != "true" ]]; then
    echo -n ","
  fi

  echo -n "{\"name\":\"$name\",\"version\":\"$version\"}"
}

function output_github_matrix_end() {
  echo "]}"
}

# --

function main() {
  local output_format="json"
  local check_releases="true"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output-format)
        output_format="$2"
        shift 2
        ;;
      --check-releases)
        check_releases="true"
        shift
        ;;
      --no-check-releases)
        check_releases="false"
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

  # Validate output format
  case "$output_format" in
    plain|json|github-matrix)
      ;;
    *)
      echo "ERROR: Invalid output format: $output_format" >&2
      echo "Valid formats: plain, json, github-matrix" >&2
      exit 1
      ;;
  esac

  local config_file="${scriptroot}/release_build_versions.txt"
  local builds_needed=()
  local first_item="true"

  # Start output based on format
  case "$output_format" in
    json)
      output_json_start
      ;;
    github-matrix)
      output_github_matrix_start
      ;;
  esac

  # Parse configuration and check each extension
  while IFS=' ' read -r name version; do
    if check_needs_build "$name" "$version" "$check_releases"; then
      case "$output_format" in
        plain)
          output_plain "$name" "$version"
          ;;
        json)
          output_json_item "$name" "$version" "$first_item"
          first_item="false"
          ;;
        github-matrix)
          output_github_matrix_item "$name" "$version" "$first_item"
          first_item="false"
          ;;
      esac
    fi
  done < <(parse_build_versions "$config_file")

  # End output based on format
  case "$output_format" in
    json)
      output_json_end
      ;;
    github-matrix)
      output_github_matrix_end
      ;;
  esac
}

# --

main "$@"
