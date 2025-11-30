#!/bin/bash

###############################################################################
# generate-config-url.sh
# Generates the full configuration URLs for use with archinstall
###############################################################################

set -euo pipefail

# Configuration
GITHUB_USER="${GITHUB_USER:-your-username}"
GITHUB_REPO="${GITHUB_REPO:-archconfigs}"
BRANCH="${BRANCH:-main}"

BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/archinstall"

echo "=== Archinstall Configuration URLs ==="
echo ""
echo "User Configuration:"
echo "  ${BASE_URL}/user_configuration.json"
echo ""
echo "User Credentials:"
echo "  ${BASE_URL}/user_credentials.json"
echo ""
echo "Disk Layout:"
echo "  ${BASE_URL}/user_disk_layout.json"
echo ""
echo "=== Usage with archinstall ==="
echo ""
echo "Boot into Arch Linux ISO and run:"
echo ""
echo "  archinstall --config ${BASE_URL}/user_configuration.json \\"
echo "              --creds ${BASE_URL}/user_credentials.json \\"
echo "              --disk_layouts ${BASE_URL}/user_disk_layout.json"
echo ""
echo "Or use kernel parameters for netboot:"
echo ""
echo "  archinstall-config=${BASE_URL}/user_configuration.json"
echo "  archinstall-creds=${BASE_URL}/user_credentials.json"
echo ""
