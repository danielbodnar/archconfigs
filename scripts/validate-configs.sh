#!/bin/bash

###############################################################################
# validate-configs.sh
# Validates the archinstall JSON configuration files
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../archinstall"

echo "Validating archinstall configuration files..."

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "Install with: pacman -S jq"
    exit 1
fi

# Validate JSON syntax
validate_json() {
    local file="$1"
    if jq empty "$file" 2>/dev/null; then
        echo "✓ $file - Valid JSON syntax"
        return 0
    else
        echo "✗ $file - Invalid JSON syntax"
        return 1
    fi
}

# Check required files exist
check_files() {
    local status=0
    
    for file in user_configuration.json user_credentials.json; do
        if [[ -f "$CONFIG_DIR/$file" ]]; then
            echo "✓ $file exists"
        else
            echo "✗ $file missing"
            status=1
        fi
    done
    
    return $status
}

echo ""
echo "=== Checking required files ==="
check_files

echo ""
echo "=== Validating JSON syntax ==="
validation_status=0

set +e
for config_file in "$CONFIG_DIR"/*.json; do
    if ! validate_json "$config_file"; then
        validation_status=1
    fi
done
set -e

echo ""
if [[ $validation_status -eq 0 ]]; then
    echo "All configurations are valid!"
else
    echo "Some configurations have errors. Please fix them before use."
    exit 1
fi
