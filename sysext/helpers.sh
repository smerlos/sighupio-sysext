#!/usr/bin/env bash
#
# Common helper functions for sysext build scripts
# Based on Flatcar sysext-bakery patterns
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print error message and exit
error() {
    echo -e "${RED}ERROR: $*${NC}" >&2
    exit 1
}

# Print warning message
warn() {
    echo -e "${YELLOW}WARNING: $*${NC}" >&2
}

# Print info message
info() {
    echo -e "${GREEN}INFO: $*${NC}"
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Verify required tools are available
verify_requirements() {
    local tools=("curl" "mksquashfs" "tar")
    local missing=()
    
    for tool in "${tools[@]}"; do
        if ! command_exists "$tool"; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
    fi
}

# Get the Flatcar architecture name
get_flatcar_arch() {
    local arch="${1:-$(uname -m)}"
    case "${arch}" in
        x86_64|amd64)
            echo "x86-64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            error "Unsupported architecture: ${arch}"
            ;;
    esac
}

# Create extension-release file
create_extension_release() {
    local sysextroot="$1"
    local name="$2"
    local version="${3:-}"
    
    mkdir -p "${sysextroot}/usr/lib/extension-release.d"
    
    cat > "${sysextroot}/usr/lib/extension-release.d/extension-release.${name}" <<EOF
ID=flatcar
SYSEXT_LEVEL=1.0
EXTENSION_RELOAD_MANAGER=1
EOF

    if [[ -n "${version}" ]]; then
        echo "VERSION=${version}" >> "${sysextroot}/usr/lib/extension-release.d/extension-release.${name}"
    fi
}

# Create squashfs image with standard options
create_squashfs() {
    local source_dir="$1"
    local output_file="$2"
    
    if ! command_exists mksquashfs; then
        error "mksquashfs not found. Install squashfs-tools."
    fi
    
    mksquashfs "${source_dir}" "${output_file}" \
        -noappend \
        -comp zstd \
        -Xcompression-level 19 \
        -quiet
    
    info "Created: ${output_file}"
}

# Download file with retry
download_with_retry() {
    local url="$1"
    local output="$2"
    local retries="${3:-3}"
    
    for ((i=1; i<=retries; i++)); do
        if curl -fsSL "${url}" -o "${output}"; then
            return 0
        fi
        warn "Download attempt ${i}/${retries} failed, retrying..."
        sleep 2
    done
    
    error "Failed to download: ${url}"
}

# Verify checksum of a file
verify_checksum() {
    local file="$1"
    local expected="$2"
    local algorithm="${3:-sha256}"
    
    local actual
    case "${algorithm}" in
        sha256)
            actual=$(sha256sum "${file}" | cut -d' ' -f1)
            ;;
        sha512)
            actual=$(sha512sum "${file}" | cut -d' ' -f1)
            ;;
        md5)
            actual=$(md5sum "${file}" | cut -d' ' -f1)
            ;;
        *)
            error "Unsupported checksum algorithm: ${algorithm}"
            ;;
    esac
    
    if [[ "${actual}" != "${expected}" ]]; then
        error "Checksum verification failed for ${file}"
    fi
    
    info "Checksum verified: ${file}"
}

# Parse semantic version
parse_version() {
    local version="$1"
    # Remove leading 'v' if present
    version="${version#v}"
    echo "${version}"
}

# Compare semantic versions
# Returns: 0 if equal, 1 if first > second, 2 if first < second
compare_versions() {
    local v1="$1"
    local v2="$2"
    
    v1=$(parse_version "$v1")
    v2=$(parse_version "$v2")
    
    if [[ "$v1" == "$v2" ]]; then
        return 0
    fi
    
    local IFS=.
    local i ver1=($v1) ver2=($v2)
    
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]:-} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    
    return 0
}
