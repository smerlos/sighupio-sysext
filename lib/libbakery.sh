#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# Bakery library functions for release management.
#
# Copyright (c) 2025 sighupio-sysext.
# Based on Flatcar sysext-bakery patterns.

bakery="smerlos/sighupio-sysext"
scriptroot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source existing helpers
source "${scriptroot}/sysext/lib/helpers.sh"

# --

function github_release_exists() {
  local org="$1"
  local repo="$2"
  local tag="$3"

  curl -fsSL -I "https://api.github.com/repos/${org}/${repo}/releases/tags/${tag}" \
    -H "Authorization: Bearer ${GH_TOKEN:-}" \
    2>/dev/null | grep -q "HTTP/2 200"
}
# --
