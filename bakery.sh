#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# Simplified bakery script for building sysext images.
# Based on Flatcar sysext-bakery.
#
set -euo pipefail

rundir="$(pwd)"
scriptroot="$(dirname "$(readlink -f "$0")")"

# Source helpers
source "${scriptroot}/sysext/lib/helpers.sh"

# --

function announce() {
  echo "    ----- ===== ##### $@ ##### ===== -----"
}
# --

function check_arch() {
  local arch="$1"

  case "$arch" in
    x86-64|arm64)
        return 0;;
  esac

  echo "ERROR: unsupported architecture '$arch'."
  echo "Supported architecures are x86-64 and arm64."

  exit 1
}
# --

function extension_name() {
  local extname="${1:-}"
  extname="${extname%%.sysext/}"
  extname="${extname%%.sysext}"

  local folder="${scriptroot}/sysext/${extname}.sysext"
  if [[ -d ${folder} ]] ; then
    echo "${extname}"
  fi
}
# --

function get_optional_param() {
  local param="$1"
  local default="$2"
  shift 2

  while [[ $# -gt 0 ]] ; do
    case "$1" in
      --"$param")
          echo "$2"
          return;;
    esac
    shift
  done

  echo "$default"
}
# --

function get_positional_param() {
  local num="$1"
  shift

  local curr=1
  while [[ $# -gt 0 ]] ; do
    case "$1" in
      --*) shift;;
      *) if [[ $num -eq $curr ]] ; then
           echo "$1"
           return
         fi
         : $((curr++))
         ;;
    esac
    shift
  done
}
# --

function create_metadata() {
  local name="$1"
  local basedir="$2"
  local os="${3:-_any}"
  local arch="$4"
  local force_reload="${5:-false}"

  local metadata_file="${basedir}/usr/lib/extension-release.d/extension-release.${name}"
  announce "Generating metadata in '${metadata_file}'"

  mkdir -p "$(dirname "${metadata_file}")"
  {
    echo "ID=${os}"
    if [[ ${os} != _any ]]; then
      echo "SYSEXT_LEVEL=1.0"
    fi
    echo "ARCHITECTURE=${arch}"
    if [[ ${force_reload} == true ]]; then
      echo "EXTENSION_RELOAD_MANAGER=1"
    fi
  } | tee "${metadata_file}"
  echo
}
# --

function copy_static_files() {
  local extname="${1%%.sysext/}"
  local destdir="$2"
  local search_root="${3:-${scriptroot}}"

  local srcdir="${search_root}/${extname}.sysext/files"

  if [[ ! -d "${srcdir}" ]] ; then
    echo "No static files directory for '$extname'; continuing (no '${srcdir}')."
    return
  fi

  function _cpy() {
    local src="$1"
    local dst="$2"
    if [[ ! -d "$src" ]] ; then
      return
    fi

    mkdir -p "${dst}"
    cp -aR "${src}/"* "${dst}"
  }

  _cpy "${srcdir}/usr" "${destdir}/usr"
  _cpy "${srcdir}/opt" "${destdir}/opt"
}
# --

function generate_sysext_image() {
  local extname="$1"
  local basedir="$2"
  local arch="$3"
  local version="$4"
  local outdir="${5:-${rundir}}"
  local output_file="${6:-}"

  # Use custom output filename if provided, otherwise use default naming
  local fname
  if [[ -n "$output_file" ]]; then
    fname="${output_file}.raw"
  else
    fname="${extname}-${version}-${arch}.raw"
  fi
  local fullpath="${outdir}/${fname}"

  announce "Creating extension image '${fname}'"

  # Create squashfs image
  mksquashfs "${basedir}" "${fullpath}" -all-root -noappend

  # Generate checksum
  (cd "${outdir}" && sha256sum "${fname}" > "SHA256SUMS.${extname}")

  announce "'${fname}' is now ready"
  echo "Output: ${fullpath}"
}
# --

function create_sysext() {
  local extname="$1"
  local version="$2"
  local arch="${3:-x86-64}"
  local outdir="${4:-dist}"

  check_arch "$arch"

  local createscript="${scriptroot}/sysext/${extname}.sysext/create.sh"
  if [[ ! -f "${createscript}" ]] ; then
    echo "ERROR: Extension create implementation not found at '${createscript}'."
    return 1
  fi

  # Create output directory
  mkdir -p "${outdir}"

  # Save original scriptroot and set it to sysext/ for create.sh
  local original_scriptroot="${scriptroot}"
  scriptroot="${scriptroot}/sysext"

  # Overwritten by extension's create.sh
  RELOAD_SERVICES_ON_MERGE="false"
  function populate_sysext_root() {
      announce "Nothing to do, static files only."
  }

  source "${createscript}"

  local workdir="$(mktemp -d)"
  local sysextroot_tmp="$(mktemp -d)"
  trap "rm -rf '${workdir}' '${sysextroot_tmp}'" EXIT
  local sysextroot="${sysextroot_tmp}/${extname}"
  mkdir -p "${sysextroot}"

  announce "Building ${extname} ${version} for ${arch}"

  announce "Copying static files"
  copy_static_files "$extname" "$sysextroot" "${scriptroot}"

  announce "Populating extension root"
  # Do this in a subshell to safely change directories w/o confusing us
  # Export scriptroot so it's available in the subshell
  export scriptroot
  (
    cd "${workdir}"
    populate_sysext_root "$sysextroot" "$arch" "$version"
  )

  # Restore original scriptroot
  scriptroot="${original_scriptroot}"

  announce "Creating metadata"
  create_metadata "$extname" "$sysextroot" "_any" "$arch" "${RELOAD_SERVICES_ON_MERGE}"

  announce "Generating extension image"
  generate_sysext_image "$extname" "$sysextroot" "$arch" "$version" "$(readlink -f "${outdir}")"
}
# --

function build_all() {
  local arch="${1:-x86-64}"
  local outdir="${2:-dist}"

  announce "Building all extensions for ${arch}"

  # Build etcd
  local etcd_version="v3.5.21"
  echo "Building etcd ${etcd_version}..."
  create_sysext "etcd" "${etcd_version}" "${arch}" "${outdir}"

  # Build containerd - get latest version
  echo "Building containerd (latest)..."
  local containerd_version
  containerd_version=$(list_github_releases "containerd" "containerd" | grep -vE '^api/' | sed 's/^v//' | head -n1)
  create_sysext "containerd" "${containerd_version}" "${arch}" "${outdir}"

  # Build kubernetes - get latest version
  echo "Building kubernetes (latest)..."
  local k8s_version
  k8s_version=$(list_github_tags "kubernetes" "kubernetes" | grep -E '^v1\.[0-9]+\.[0-9]+$' | head -n1)
  create_sysext "kubernetes" "${k8s_version}" "${arch}" "${outdir}"

  # Build keepalived - get latest version
  echo "Building keepalived (latest)..."
  local keepalived_version
  keepalived_version=$(list_github_tags "acassen" "keepalived" | head -n1)
  create_sysext "keepalived" "${keepalived_version}" "${arch}" "${outdir}"

  announce "All extensions built successfully in ${outdir}/"
}
# --

function usage() {
  echo
  echo "Usage: $0 <command> [options]"
  echo
  echo "Commands:"
  echo "  create <name> <version> [arch] [outdir]  - Build a specific extension"
  echo "  build-all [arch] [outdir]                - Build all extensions (default: x86-64, dist/)"
  echo "  list [extension] [--plain]               - List all extensions or versions for a specific one"
  echo "  list-bakery [--plain]                    - List versions from release_build_versions.txt"
  echo "  help                                     - Show this help"
  echo
  echo "Examples:"
  echo "  $0 create etcd v3.5.21"
  echo "  $0 create etcd v3.5.21 x86-64 dist/"
  echo "  $0 build-all"
  echo "  $0 build-all x86-64 dist/"
  echo "  $0 list"
  echo "  $0 list etcd"
  echo "  $0 list-bakery"
  echo
}
# --

case "${1:-help}" in
  create)
    shift
    if [[ $# -lt 2 ]]; then
      echo "ERROR: create requires <name> and <version>"
      usage
      exit 1
    fi
    create_sysext "$@"
    ;;
  build-all)
    shift
    build_all "$@"
    ;;
  list)
    shift
    plain=$(get_optional_param "plain" "false" "$@")

    if [[ $# -eq 0 ]] || [[ "${1:-}" == "--plain" ]]; then
      # List all extensions
      for dir in "${scriptroot}"/sysext/*.sysext; do
        extname=$(basename "$dir" .sysext)
        if [[ "$plain" == "true" ]]; then
          echo "$extname"
        else
          echo "- $extname"
        fi
      done
    else
      # List versions for specific extension
      extname=$(extension_name "$1")
      if [[ -z "$extname" ]]; then
        echo "ERROR: Extension '$1' not found"
        exit 1
      fi

      createscript="${scriptroot}/sysext/${extname}.sysext/create.sh"
      if [[ ! -f "$createscript" ]]; then
        echo "ERROR: No create.sh found for extension '$extname'"
        exit 1
      fi

      # Source the create script to get list_available_versions function
      scriptroot="${scriptroot}/sysext"
      source "$createscript"

      if [[ "$plain" == "true" ]]; then
        list_available_versions
      else
        echo "Available versions for $extname:"
        list_available_versions | sed 's/^/  - /'
      fi
    fi
    ;;
  list-bakery)
    shift
    # List versions from release_build_versions.txt
    config_file="${scriptroot}/release_build_versions.txt"

    if [[ ! -f "$config_file" ]]; then
      echo "ERROR: $config_file not found"
      exit 1
    fi

    plain=$(get_optional_param "plain" "false" "$@")

    if [[ "$plain" == "true" ]]; then
      grep -v '^#' "$config_file" | grep -v '^[[:space:]]*$'
    else
      echo "Configured bakery versions (from release_build_versions.txt):"
      grep -v '^#' "$config_file" | grep -v '^[[:space:]]*$' | sed 's/^/  - /'
    fi
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "ERROR: Unknown command '${1:-}'"
    usage
    exit 1
    ;;
esac
