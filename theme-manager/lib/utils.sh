#!/usr/bin/env bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    local deps=("curl" "unzip" "jq" "sha256sum")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log_error "Required dependency '$dep' is not installed."
            exit 1
        fi
    done
}

# Read config value using jq
get_config_val() {
    local key="$1"
    local config_file="$2"
    if [[ ! -f "$config_file" ]]; then
        log_error "Config file $config_file not found."
        exit 1
    fi
    jq -r ".$key" "$config_file"
}
