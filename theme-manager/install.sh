#!/usr/bin/env bash
set -e

# Installation script for 3x-ui Theme Manager

echo "Installing 3x-ui Theme Manager..."

INSTALL_DIR="/opt/3x-ui-theme-manager"
CONFIG_DIR="/etc/3x-ui-theme-manager"
REPO_URL="https://github.com/0fariid0/NeoTemplate.git"
ARCHIVE_URL="https://github.com/0fariid0/NeoTemplate/archive/refs/heads/main.tar.gz"
NO_START="${NO_START:-0}"

if [[ "${1:-}" == "--no-start" ]]; then
    NO_START="1"
fi

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root to install globally."
   exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if we are running from a local clone (either root or theme-manager directory)
if [[ -f "$SCRIPT_DIR/manager.sh" && -d "$SCRIPT_DIR/config" ]]; then
    USE_LOCAL=true
    LOCAL_SRC_DIR="$SCRIPT_DIR"
elif [[ -f "$SCRIPT_DIR/theme-manager/manager.sh" && -d "$SCRIPT_DIR/theme-manager/config" ]]; then
    USE_LOCAL=true
    LOCAL_SRC_DIR="$SCRIPT_DIR/theme-manager"
else
    USE_LOCAL=false
fi

install_deps() {
    local missing=()
    for dep in curl tar unzip jq sha256sum; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    echo "Installing dependencies: ${missing[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y curl tar unzip jq coreutils ca-certificates
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl tar unzip jq coreutils ca-certificates
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl tar unzip jq coreutils ca-certificates
    else
        echo "Could not install dependencies automatically. Please install: curl tar unzip jq coreutils"
        exit 1
    fi
}

install_deps

if [ "$USE_LOCAL" = true ]; then
    echo "Using local repository files from $LOCAL_SRC_DIR..."
else
    TMP_DIR=$(mktemp -d)
    echo "Downloading theme manager repository..."
    curl -fsSL "$ARCHIVE_URL" | tar xz -C "$TMP_DIR" --strip-components=1
fi

# Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"

# Copy theme-manager files
echo "Copying files to $INSTALL_DIR..."
if [ "$USE_LOCAL" = true ]; then
    cp -r "$LOCAL_SRC_DIR/"* "$INSTALL_DIR/"
else
    cp -r "$TMP_DIR/theme-manager/"* "$INSTALL_DIR/"
fi

# Setup default configuration
cp "$INSTALL_DIR/config/config.json" "$CONFIG_DIR/config.json"

# Make scripts executable
chmod +x "$INSTALL_DIR/manager.sh"
chmod +x "$INSTALL_DIR/install.sh"
chmod +x "$INSTALL_DIR/lib/"*.sh

# Create symlink for easy access
ln -sf "$INSTALL_DIR/manager.sh" "/usr/local/bin/neotemplate"
ln -sf "$INSTALL_DIR/manager.sh" "/usr/local/bin/3x-ui-theme"

# Clean up
if [ "$USE_LOCAL" = false ]; then
    rm -rf "$TMP_DIR"
fi

echo "Installation complete!"
if [[ "$NO_START" == "1" ]]; then
    echo "Run 'neotemplate' to open the manager."
    exit 0
fi

echo "Starting 3x-ui Theme Manager..."
echo "----------------------------------------"
if [[ -t 0 || -e /dev/tty ]]; then
    neotemplate < /dev/tty
else
    echo "No interactive terminal detected. Run 'neotemplate' manually."
fi
